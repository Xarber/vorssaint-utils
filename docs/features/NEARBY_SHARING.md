# Nearby sharing

In a Developer build with the LocalSend helper bundled, select a file in Shelf and choose **Share → LocalSend**. Choose **Find Nearby Devices** and select a recipient. To receive, open **Connected Devices → Receive with LocalSend** and select a destination. An incoming offer displays the sender and filenames for approval.

The helper uses a checksum-pinned LocalSend v2.2 source tree and TLS peer-certificate fingerprints from discovery. Transfers start when you choose a recipient or approve an incoming offer. Incoming files are bounded, staged privately on the destination volume and published only if their names are free. Closing the window stops the session. The app uses the local network when the session is active.

For Quick Share, an installed NearDrop companion supplies **NearDrop** in the native file Share menu. **Connected Devices → Open Quick Share Receiver** opens that app. Its own QR, visibility, and receive controls manage the transfer. See the [NearDrop usage guide](https://github.com/grishka/NearDrop).

LocalSend’s helper tests exercise a pinned HTTPS loopback transfer and file-name validation. Physical peer tests, helper permission attribution, and NearDrop’s registered Share service still require testing on a Mac and Android device.
