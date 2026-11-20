// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <libmtp.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static volatile sig_atomic_t cancelled;
static uint64_t last_reported;

static void stop_transfer(int signal_number) {
    (void)signal_number;
    cancelled = 1;
}

static int output_progress(uint64_t completed, uint64_t total, const void *context) {
    (void)context;
    if (cancelled) return 1;
    if (completed == total || (completed >= last_reported && completed - last_reported >= 1024 * 1024)) {
        last_reported = completed;
        fprintf(stderr, "progress\t%" PRIu64 "\t%" PRIu64 "\n", completed, total);
    }
    return 0;
}

static void write_text(const char *text) {
    // Hex carries UTF-8 names without letting the device inject records.
    if (text) {
        const unsigned char *bytes = (const unsigned char *)text;
        for (size_t index = 0; index < 4096 && bytes[index]; ++index) printf("%02x", bytes[index]);
    }
    putchar('\n');
}

static int parse_id(const char *text, uint32_t *value) {
    if (!text[0] || strspn(text, "0123456789") != strlen(text)) return 0;
    errno = 0;
    unsigned long parsed = strtoul(text, NULL, 10);
    if (errno || parsed > UINT32_MAX) return 0;
    *value = (uint32_t)parsed;
    return 1;
}

static void device_key(const LIBMTP_raw_device_t *device, char buffer[64]) {
    snprintf(buffer, 64, "%" PRIu32 "-%u-%04x-%04x", device->bus_location, (unsigned)device->devnum,
             (unsigned)device->device_entry.vendor_id, (unsigned)device->device_entry.product_id);
}

static void list_devices(LIBMTP_raw_device_t *devices, int count) {
    for (int index = 0; index < count; index++) {
        LIBMTP_raw_device_t *device = &devices[index];
        char key[64];
        device_key(device, key);
        printf("device\t%s\t", key);
        write_text(device->device_entry.product);
    }
}

static int list_storage(LIBMTP_mtpdevice_t *device) {
    if (LIBMTP_Get_Storage(device, LIBMTP_STORAGE_SORTBY_NOTSORTED) < 0) return 1;
    for (LIBMTP_devicestorage_t *storage = device->storage; storage; storage = storage->next) {
        printf("storage\t%" PRIu32 "\t", storage->id);
        write_text(storage->StorageDescription);
    }
    return 0;
}

static int list_folder(LIBMTP_mtpdevice_t *device, uint32_t storage, uint32_t folder) {
    LIBMTP_Clear_Errorstack(device);
    LIBMTP_file_t *item = LIBMTP_Get_Files_And_Folders(device, storage, folder);
    int failure = item == NULL && LIBMTP_Get_Errorstack(device) != NULL;
    size_t count = 0;
    while (item) {
        LIBMTP_file_t *next = item->next;
        if (++count <= 10000) {
            printf("item\t%" PRIu32 "\t%s\t%" PRIu64 "\t", item->item_id,
               item->filetype == LIBMTP_FILETYPE_FOLDER ? "folder" : "file", item->filesize);
            write_text(item->filename);
        } else {
            failure = 1;
        }
        LIBMTP_destroy_file_t(item);
        item = next;
    }
    return failure;
}

static int download_file(LIBMTP_mtpdevice_t *device, uint32_t object, const char *staged_path) {
    LIBMTP_file_t *metadata = LIBMTP_Get_Filemetadata(device, object);
    if (!metadata || metadata->filetype == LIBMTP_FILETYPE_FOLDER) {
        if (metadata) LIBMTP_destroy_file_t(metadata);
        return 1;
    }
    uint64_t expected = metadata->filesize;
    LIBMTP_destroy_file_t(metadata);
    int fd = open(staged_path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, S_IRUSR | S_IWUSR);
    if (fd < 0) return 1;
    int result = LIBMTP_Get_File_To_File_Descriptor(device, object, fd, output_progress, NULL);
    struct stat received;
    int valid = result == 0 && !cancelled && fstat(fd, &received) == 0 && (uint64_t)received.st_size == expected;
    if (valid) valid = fsync(fd) == 0;
    if (close(fd) != 0) valid = 0;
    if (!valid) unlink(staged_path);
    return !valid;
}

static int upload_file(LIBMTP_mtpdevice_t *device, uint32_t storage, uint32_t folder,
                       const char *source, const char *name) {
    if (!*name || strlen(name) > 255 || strpbrk(name, "/\\\r\n") || !strcmp(name, ".") || !strcmp(name, "..")) return 1;
    int fd = open(source, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) return 1;
    struct stat info;
    if (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode)) {
        close(fd);
        return 1;
    }
    LIBMTP_Clear_Errorstack(device);
    int collision = 0;
    for (LIBMTP_file_t *item = LIBMTP_Get_Files_And_Folders(device, storage, folder); item;) {
        LIBMTP_file_t *next = item->next;
        if (item->filename && strcasecmp(item->filename, name) == 0) collision = 1;
        LIBMTP_destroy_file_t(item);
        item = next;
    }
    if (collision || LIBMTP_Get_Errorstack(device) || cancelled) {
        close(fd);
        return 1;
    }
    LIBMTP_file_t *metadata = LIBMTP_new_file_t();
    if (!metadata) { close(fd); return 1; }
    metadata->filename = strdup(name);
    if (!metadata->filename) { LIBMTP_destroy_file_t(metadata); close(fd); return 1; }
    metadata->storage_id = storage;
    metadata->parent_id = folder == LIBMTP_FILES_AND_FOLDERS_ROOT ? 0 : folder;
    metadata->filesize = (uint64_t)info.st_size;
    metadata->modificationdate = info.st_mtime;
    metadata->filetype = LIBMTP_FILETYPE_UNKNOWN;
    int result = LIBMTP_Send_File_From_File_Descriptor(device, fd, metadata, output_progress, NULL);
    close(fd);
    if ((result != 0 || cancelled) && metadata->item_id) {
        // Roll back only the handle allocated by this upload.
        LIBMTP_Delete_Object(device, metadata->item_id);
    }
    LIBMTP_destroy_file_t(metadata);
    return result != 0 || cancelled;
}

static uint32_t normalize_parent(uint32_t parent) {
    return parent == 0 ? LIBMTP_FILES_AND_FOLDERS_ROOT : parent;
}

static int valid_name(const char *name) {
    if (!*name || strlen(name) > 255 || !strcmp(name, ".") || !strcmp(name, "..")) return 0;
    for (const unsigned char *p = (const unsigned char *)name; *p; ++p) {
        if (*p < 32 || *p == 127 || *p == '/' || *p == '\\' || *p == ':') return 0;
    }
    return 1;
}

static int destination_available(LIBMTP_mtpdevice_t *device, uint32_t storage,
                                 uint32_t folder, uint32_t object, const char *name) {
    LIBMTP_Clear_Errorstack(device);
    int free_name = 1;
    for (LIBMTP_file_t *item = LIBMTP_Get_Files_And_Folders(device, storage, folder); item;) {
        LIBMTP_file_t *next = item->next;
        if (item->item_id != object && item->filename && !strcasecmp(item->filename, name)) free_name = 0;
        LIBMTP_destroy_file_t(item);
        item = next;
    }
    return free_name && !LIBMTP_Get_Errorstack(device);
}

// Revalidate selected items because each operation opens a fresh USB session.
static int mutate_file(LIBMTP_mtpdevice_t *device, const char *action, uint32_t object,
                       uint32_t storage, uint32_t parent, const char *expected_name,
                       const char *destination) {
    LIBMTP_file_t *file = LIBMTP_Get_Filemetadata(device, object);
    if (!file) return 1;
    int result = 1;
    if (!cancelled && file->filetype != LIBMTP_FILETYPE_FOLDER && file->storage_id == storage
        && normalize_parent(file->parent_id) == parent && file->filename
        && !strcmp(file->filename, expected_name)) {
        uint32_t folder;
        if (!strcmp(action, "delete")) {
            result = LIBMTP_Delete_Object(device, object);
        } else if (!strcmp(action, "rename") && destination && valid_name(destination)
                   && destination_available(device, storage, parent, object, destination)) {
            if (!cancelled) result = LIBMTP_Set_File_Name(device, file, destination);
        } else if (!strcmp(action, "move") && destination && parse_id(destination, &folder)
                   && LIBMTP_Check_Capability(device, LIBMTP_DEVICECAP_MoveObject)
                   && destination_available(device, storage, folder, object, file->filename)) {
            if (!cancelled) result = folder == parent ? 0 : LIBMTP_Move_Object(
                device, object, storage, folder == LIBMTP_FILES_AND_FOLDERS_ROOT ? 0 : folder);
        }
    }
    LIBMTP_destroy_file_t(file);
    return result == 0 ? 0 : 1;
}

static int run_command(LIBMTP_mtpdevice_t *device, int argc, char **argv) {
    uint32_t storage, folder, object;
    if (((argc == 7 && !strcmp(argv[1], "delete"))
         || (argc == 8 && (!strcmp(argv[1], "rename") || !strcmp(argv[1], "move"))))
        && parse_id(argv[3], &object) && parse_id(argv[4], &storage) && parse_id(argv[5], &folder))
        return mutate_file(device, argv[1], object, storage, folder, argv[6], argc == 8 ? argv[7] : NULL);
    if (argc == 3 && !strcmp(argv[1], "storages")) return list_storage(device);
    if (argc == 5 && !strcmp(argv[1], "list") && parse_id(argv[3], &storage) && parse_id(argv[4], &folder))
        return list_folder(device, storage, folder);
    if (argc == 5 && !strcmp(argv[1], "get") && parse_id(argv[3], &object))
        return download_file(device, object, argv[4]);
    if (argc == 7 && !strcmp(argv[1], "put") && parse_id(argv[3], &storage) && parse_id(argv[4], &folder))
        return upload_file(device, storage, folder, argv[5], argv[6]);
    return 64;
}

int main(int argc, char **argv) {
    if (argc < 2) return 64;
    signal(SIGTERM, stop_transfer);
    signal(SIGINT, stop_transfer);
    LIBMTP_Init();
    LIBMTP_raw_device_t *devices = NULL;
    int count = 0;
    LIBMTP_error_number_t result = LIBMTP_Detect_Raw_Devices(&devices, &count);
    if (result != LIBMTP_ERROR_NONE && result != LIBMTP_ERROR_NO_DEVICE_ATTACHED) {
        free(devices);
        return 1;
    }
    if (argc == 2 && !strcmp(argv[1], "devices")) {
        list_devices(devices, count);
        free(devices);
        return 0;
    }
    if (argc < 3) { free(devices); return 64; }
    LIBMTP_mtpdevice_t *device = NULL;
    for (int index = 0; index < count && !cancelled; index++) {
        char key[64];
        device_key(&devices[index], key);
        if (!strcmp(key, argv[2])) {
            device = LIBMTP_Open_Raw_Device_Uncached(&devices[index]);
            break;
        }
    }
    free(devices);
    if (!device) return 2;
    int status = run_command(device, argc, argv);
    LIBMTP_Release_Device(device);
    return cancelled ? 130 : status;
}
