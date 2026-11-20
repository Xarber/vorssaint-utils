# Android USB transfer Developer preview

This is an opt-in preview for a locally built Vorssaint Developer app. It opens from Connected Devices when the optional helper is bundled.

A local Mac with Homebrew's `libmtp` and `libusb` libraries can assemble the preview with `VORSSAINT_DEV_MTP=1 ./build.sh --dev`. The local libraries determine the helper's OS compatibility. Building or distributing an official app requires a reproducible, macOS 14-compatible backend and its corresponding LGPL notices and source availability.

1. Unlock the Android device and select File Transfer in its USB options.
2. In the Connected Devices detail, open Android File Transfer.
3. Choose the device and storage, then open folders with **Open**.
4. Use **Save a Copy** for an Android file or **Copy to Android** while a destination folder is open.

A separate, signed helper opens one MTP operation at a time using libmtp. It stages downloads on the selected local volume, checks the byte count, and publishes the complete copy only at a free destination. The helper checks remote name collisions before upload and attempts to remove the object it created if a transfer fails. Disconnects may prevent the phone from cleaning up its own incomplete copy. Files and transfer metadata stay between the Mac and the connected device.

The preview supports individual files. Multi-selection, reconnect handling on representative phones, localization, and release packaging remain open. Setup and transfers have not been verified on a physical Android device.
