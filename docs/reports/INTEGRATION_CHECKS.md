# Vorssaint integration checks

Testing took place on the local Apple Silicon Mac using the macOS 26 SDK and the repository's test harness. Scope covered notch file-drop routing, Shelf behavior, USB-C data decoding, Android USB development helper checks, and wheel direction profiles.

| Check | Result | Evidence |
| --- | --- | --- |
| Notch suite | Passed | 67,894 assertions. Existing notch behavior and geometry checks. |
| Shelf suite | Passed | 482 assertions. Shelf and Optimize Media routing, AirDrop routing and busy state, three destinations and hover transitions. Native delivery uses a test adapter here. |
| Metrics suite | Passed | 573 assertions. Cable rating decoding, ambiguous speeds, restricted power and invalid data, plus existing metrics and devices. |
| AirDrop presenter AppKit API type check | Passed | Checked the native sharing API against the macOS 26 SDK for the macOS 14 target. |
| USB cable sampler type check | Passed | Checked the IOKit wrapper against the macOS 26 SDK for the macOS 14 target. |
| App source type check | Passed | All app Swift sources including the Android Developer preview and scroll profiles, targeting macOS 14 with the macOS 26 SDK. |
| Pointer Input and Linear Scroll suites | Passed | 1,299 assertions. New checks cover per-app reversal, macOS direction, exception precedence, uninstall behavior, and profile storage. Hardware event delivery remains pending. |
| Android USB Developer preview | Partial | Native Swift type check and standalone helper compilation passed. Enumeration returned no attached device, and storage selection returned the expected disconnected exit status. The preview has no physical Android copy evidence. |
| LocalSend dependency | Passed | LocalSend core at `e05d12a9c0fd` passed `cargo check --locked -p localsend --features discovery` and three targeted peer-discovery tests in an isolated checkout. The tests included certificate fingerprint extraction. This does not verify Vorssaint integration or peer interoperability. |
| GUI and hardware | Pending | Verify AirDrop with an Apple peer, Finder and Mail file promises, picker cancellation and recovery. Verify USB-C readings with a known cable, a charger and a dock. |

The initial Notch check overlapped a source edit and Swift rejected the changed input. It passed when rerun with stable source files. The Shelf runner emitted macOS sandbox-extension messages and still passed all assertions. A direct cable-sampler invocation completed with zero reportable USB-C records on the connected setup. No full application build or release has been run.

For Android helper validation, Homebrew installed `libmtp` 1.1.23 alongside the existing `libusb`. Running the initial Cargo check under the upstream LocalSend checkout also caused Rustup to install the toolchain version specified there, 1.97.1. The Cargo check and targeted tests used that installed toolchain.
