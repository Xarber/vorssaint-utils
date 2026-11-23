# Nearby sharing

Enable **LocalSend** or **Quick Share** separately under **Clipboard & Files** in the feature menu. In a Developer build, both use the **Nearby** drop target under **AirDrop**, next to the Files Tray. AirDrop keeps its own system recipient chooser. Shelf's Share menu is also available for stored files.

LocalSend starts its bundled helper when enabled and retries if the process exits. Drop files on **Nearby** to see discovered LocalSend recipients, then choose a device. To receive, choose a folder in **Settings → Shelf → Nearby Transfer**. Incoming offers show the sender and files for explicit approval. If notifications are allowed, the app announces incoming requests without revealing filenames or sender names. Clearing the receive folder stops incoming transfers while leaving outgoing discovery enabled. Disabling LocalSend shuts down its helper. Switching the receive folder waits for the current process to exit before starting a new session.

The helper uses a checksum-pinned LocalSend v2.2 source tree and TLS peer-certificate fingerprints from discovery. Incoming files are bounded, staged privately on the destination volume and published only if their names are free.

Quick Share uses an installed NearDrop companion. Vorssaint starts NearDrop in the background when enabled and leaves a manually started copy under the user's control. In **Nearby**, **Quick Share** opens the system Share menu for the staged files. NearDrop owns Quick Share device discovery, transfer prompts and receipt. A single cross-provider recipient list is pending. [NearDrop usage](https://github.com/grishka/NearDrop)

Physical peer transfers, local-network prompts, incoming offer usability when the island is closed and NearDrop's Share service still need testing. See the [transfer trust boundaries](../reports/TRANSFER_TRUST_BOUNDARIES.md).
