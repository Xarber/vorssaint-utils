# Transfer trust boundaries

## LocalSend

The Developer helper processes requests from untrusted LAN peers. Opening a window alone shows setup. Starting discovery or choosing a receive folder starts a temporary session. Sending requires the selected peer and its TLS fingerprint. Receiving requires the user to accept the displayed offer, a session match, and a TLS client certificate. The helper bounds the number and declared total size of files, rejects invalid names and writes to a private temporary directory on the destination volume. Completed files are published without replacing an existing destination. The peer's displayed name is self-reported.

Actual checks cover filename validation and a TLS-pinned upload to an approving loopback peer. Remaining verification covers physical mobile peer discovery and agreement, declined transfers, macOS local-network permission attribution, locks and sleep, and disconnect recovery. The Developer preview remains an opt-in build variant.

## USB and Finder

The MTP helper treats object names and identifiers as device-provided data. Developer browser operations recheck the selected object, expected name, storage and parent before mutation. Deletes require explicit confirmation. Staged downloads are published without replacing an existing destination. Moves require a supported device operation within the selected storage.

A future Finder provider would need a persistent, verified device identity, generation-tagged item identifiers, and a per-device operation queue. It must map a disconnected phone to a transient provider error and reject delayed writes that refer to a prior device session. The macOS File Provider framework can show a domain in Finder and manage local copies. The current browser transfers files through MTP while connected. [Apple File Provider documentation](https://developer.apple.com/documentation/fileprovider/replicated-file-provider-extension)
