// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if VORSSAINT_DEVELOPMENT
import AppKit
import Darwin
import SwiftUI

/// Local Developer build for validating the MTP helper on real devices.
final class AndroidTransferWindow: NSObject, NSWindowDelegate {
    static let shared = AndroidTransferWindow()
    static var available: Bool { helper.map { FileManager.default.isExecutableFile(atPath: $0.path) } == true }

    private static var helper: URL? { Bundle.main.url(forAuxiliaryExecutable: "vorssaint-mtp") }
    private var window: NSWindow?
    private var browser: AndroidTransferBrowser?

    func show() {
        guard let helper = Self.helper, Self.available else { return }
        if window == nil {
            let browser = AndroidTransferBrowser(helper: helper)
            let host = NSHostingController(rootView: AndroidTransferView(browser: browser))
            let window = NSWindow(contentViewController: host)
            window.title = "Android File Transfer"
            window.setContentSize(NSSize(width: 620, height: 440))
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.browser = browser
            self.window = window
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { browser?.cancel() }
}

private struct AndroidTransferEntry: Identifiable {
    let id: String
    let name: String
    var folder = false
    var size: UInt64?

    init?(_ line: Substring) {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count == 3 || fields.count == 5,
              ["device", "storage", "item"].contains(fields[0]) else { return nil }
        id = String(fields[1])
        var bytes: [UInt8] = []
        var hex = fields.last!
        guard hex.count.isMultiple(of: 2), hex.count <= 8_192 else { return nil }
        while !hex.isEmpty {
            guard let byte = UInt8(hex.prefix(2), radix: 16) else { return nil }
            bytes.append(byte)
            hex = hex.dropFirst(2)
        }
        let title = String(decoding: bytes, as: UTF8.self)
        name = title.isEmpty ? id : title
        if fields.count == 5 {
            folder = fields[2] == "folder"
            size = UInt64(fields[3])
        } else { folder = true }
    }

    var safeFilename: Bool {
        !name.isEmpty && name != "." && name != ".."
            && name.rangeOfCharacter(from: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)) == nil
    }
}

private final class AndroidTransferBrowser: ObservableObject {
    @Published private(set) var entries: [AndroidTransferEntry] = []
    @Published private(set) var folders: [AndroidTransferEntry] = []
    @Published private(set) var storage: AndroidTransferEntry?
    @Published private(set) var device: AndroidTransferEntry?
    @Published private(set) var busy = false
    @Published private(set) var message = ""
    @Published private(set) var progress: Double?
    private let helper: URL
    private var process: Process?
    private var cancelled = false

    init(helper: URL) { self.helper = helper }

    func refresh() {
        let arguments: [String]
        if let storage, let device {
            arguments = ["list", device.id, storage.id, folders.last?.id ?? String(UInt32.max)]
        } else if let device {
            arguments = ["storages", device.id]
        } else { arguments = ["devices"] }
        run(arguments) { [weak self] data in
            self?.entries = String(decoding: data, as: UTF8.self).split(separator: "\n")
                .compactMap(AndroidTransferEntry.init)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    func open(_ entry: AndroidTransferEntry) {
        guard !busy, entry.folder else { return }
        if device == nil { device = entry }
        else if storage == nil { storage = entry }
        else { folders.append(entry) }
        entries = []
        refresh()
    }

    func back() {
        guard !busy else { return }
        if !folders.isEmpty { folders.removeLast() }
        else if storage != nil { storage = nil }
        else { device = nil }
        entries = []
        refresh()
    }

    func download(_ entry: AndroidTransferEntry) {
        guard let device, entry.safeFilename else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = entry.name
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        // Stage on the destination volume and publish exclusively. A file
        // that appeared while the transfer was running keeps its contents.
        let directory = destination.deletingLastPathComponent()
            .appendingPathComponent(".vorssaint-\(UUID().uuidString)", isDirectory: true)
        guard PrivateFileStore.createDirectory(at: directory, container: directory) else {
            message = "Couldn’t prepare the destination."
            return
        }
        let temporary = directory.appendingPathComponent("download")
        run(["get", device.id, entry.id, temporary.path], cleanup: {
            try? FileManager.default.removeItem(at: directory)
        }) { [weak self] _ in
            let result = temporary.withUnsafeFileSystemRepresentation { source in
                destination.withUnsafeFileSystemRepresentation { target in
                    renamex_np(source, target, UInt32(RENAME_EXCL))
                }
            }
            self?.message = result == 0 ? "File copied." : "Couldn’t save the file. Choose an unused filename."
        }
    }

    func upload() {
        guard let device, let storage else { return }
        let panel = NSOpenPanel()
        guard panel.runModal() == .OK, let file = panel.url else { return }
        run(["put", device.id, storage.id, folders.last?.id ?? String(UInt32.max),
             file.path, file.lastPathComponent]) { [weak self] _ in
            self?.refresh()
        }
    }

    func cancel() {
        guard let process, busy else { return }
        cancelled = true
        if process.isRunning { process.interrupt() }
    }

    private func run(_ arguments: [String], cleanup: (() -> Void)? = nil, completion: @escaping (Data) -> Void) {
        guard !busy else { cleanup?(); return }
        let process = Process()
        process.executableURL = helper
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        let progressOutput = Pipe()
        process.standardError = progressOutput
        let progressHandle = progressOutput.fileHandleForReading
        progressHandle.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            guard let line = String(decoding: data, as: UTF8.self).split(separator: "\n").last else { return }
            let columns = line.split(separator: "\t")
            guard columns.count == 3, columns[0] == "progress",
                  let completed = UInt64(columns[1]), let total = UInt64(columns[2]), total > 0 else { return }
            DispatchQueue.main.async { [weak self, weak process] in
                guard let self, let process, self.process === process else { return }
                self.progress = min(1, Double(completed) / Double(total))
            }
        }
        do { try process.run() }
        catch {
            progressHandle.readabilityHandler = nil
            message = "Couldn’t start Android File Transfer."
            cleanup?()
            return
        }
        self.process = process
        cancelled = false
        busy = true
        message = ""
        progress = nil
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let status = process.terminationStatus
            progressHandle.readabilityHandler = nil
            DispatchQueue.main.async { [weak self] in
                defer { cleanup?() }
                guard let self else { return }
                self.busy = false
                self.process = nil
                if self.cancelled { self.message = "Cancelled."; return }
                guard status == 0 else {
                    self.message = "Android File Transfer couldn’t complete. Check USB File Transfer mode and try again."
                    return
                }
                completion(data)
            }
        }
    }
}

private struct AndroidTransferView: View {
    @ObservedObject var browser: AndroidTransferBrowser

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: browser.back) { Label("Back", systemImage: "chevron.left") }
                    .disabled(browser.device == nil)
                Button(action: browser.refresh) { Label("Refresh", systemImage: "arrow.clockwise") }
                Spacer()
                if browser.storage != nil {
                    Button(action: browser.upload) { Label("Copy to Android", systemImage: "arrow.up") }
                }
            }
            .disabled(browser.busy)
            if browser.entries.isEmpty {
                Text(browser.device == nil
                     ? "Connect an unlocked Android device and choose File Transfer in its USB options."
                     : "This location is empty or unavailable.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(browser.entries) { entry in
                    HStack {
                        Label(entry.name, systemImage: entry.folder ? "folder" : "doc")
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if entry.folder {
                            Button("Open") { browser.open(entry) }
                        } else {
                            Button("Save a Copy") { browser.download(entry) }
                                .disabled(!entry.safeFilename)
                        }
                    }
                }
                .disabled(browser.busy)
            }
            if browser.busy {
                HStack {
                    if let progress = browser.progress {
                        ProgressView(value: progress).frame(maxWidth: 180)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text("Working…")
                    Spacer()
                    Button("Cancel", action: browser.cancel)
                }
            } else if !browser.message.isEmpty {
                Text(browser.message).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(minWidth: 500, minHeight: 340)
        .onAppear(perform: browser.refresh)
    }
}
#endif
