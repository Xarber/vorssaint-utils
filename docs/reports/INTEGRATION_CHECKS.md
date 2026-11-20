# Vorssaint integration checks

Testing took place on the local Apple Silicon Mac using the macOS 26 SDK and the repository's test harness. Scope covered notch file-drop routing, Shelf behavior, and USB-C data decoding.

| Check | Result | Evidence |
| --- | --- | --- |
| Notch suite | Passed | 67,894 assertions. Existing notch behavior and geometry checks. |
| Shelf suite | Passed | 482 assertions. Shelf and Optimize Media routing, AirDrop routing and busy state, three destinations and hover transitions. Native delivery uses a test adapter here. |
| Metrics suite | Passed | 573 assertions. Cable rating decoding, ambiguous speeds, restricted power and invalid data, plus existing metrics and devices. |
| AirDrop presenter AppKit API type check | Passed | Checked the native sharing API against the macOS 26 SDK for the macOS 14 target. |
| USB cable sampler type check | Passed | Checked the IOKit wrapper against the macOS 26 SDK for the macOS 14 target. |
| GUI and hardware | Pending | Verify AirDrop with an Apple peer, Finder and Mail file promises, picker cancellation and recovery. Verify USB-C readings with a known cable, a charger and a dock. |

The initial Notch check overlapped a source edit and Swift rejected the changed input. It passed when rerun with stable source files. The Shelf runner emitted macOS sandbox-extension messages and still passed all assertions. No full application build or release has been run.
