# Android USB transfer Developer preview

This is an opt-in preview for a locally built Vorssaint Developer app. Enable **Android USB Transfer** in the feature menu, then go to **Settings → Shelf → Nearby Transfer**. The option uses the bundled MTP helper. While enabled, it watches for USB attachment and removal without opening a separate window.

A local Mac with Homebrew's `libmtp` and `libusb` libraries can assemble the preview with `VORSSAINT_DEV_MTP=1 ./build.sh --dev`. The local libraries determine the helper's OS compatibility. Building or distributing an official app requires a reproducible, macOS 14-compatible backend and its corresponding LGPL notices and source availability.

1. Unlock the Android device and select File Transfer in its USB options.
2. In Shelf settings, expand Android USB Transfer.
3. Choose the device and storage, then open folders with **Open**.
4. Select files with the usual macOS selection keys, then use **Save Copies** to copy them to a Mac folder. Use **Copy to Android** to select one or more Mac files.
5. Under **Manage Files**, rename one selected file, mark a selection for a move, or confirm permanent deletion. For a move, open the destination within the same Android storage and choose **Move Here**. Move requires device support for the MTP operation.

A separate, signed helper opens one MTP operation at a time using libmtp. It stages downloads on the selected local volume, checks the byte count, and publishes the complete copy only at a free destination. The helper checks remote name collisions before upload and attempts to remove the object it created if a transfer fails. Disconnects may prevent the phone from cleaning up its own incomplete copy. Files and transfer metadata stay between the Mac and the connected device.

A successful export opens Finder at the selected destination. The Android storage is browsed from Vorssaint. Direct Finder mounting would require a separate File Provider extension and a session-safe device bridge. Finder can replay operations after reconnection, so a provider needs durable device identity, item versions, and stale-operation rejection before using it for writes.

Physical-device transfers, reconnect handling, localization, and release packaging remain unverified. The GitHub preview links against the recipient’s Apple Silicon Homebrew installation of `libmtp`. The preview ZIP requires that library on the test Mac.
