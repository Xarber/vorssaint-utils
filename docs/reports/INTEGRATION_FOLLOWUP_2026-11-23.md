# Integration follow-up verification

Work on `test/vorssaint-integrations` extends the original Developer preview. The test host is Apple Silicon running macOS 27.3 with the macOS 26 Command Line Tools SDK.

| Check | Result |
| --- | --- |
| Shelf, Notch, Pointer Input, Linear Scroll, Metrics and Feature Catalog harnesses | 71,720 assertions passed after updating the catalog tests and adding profile override coverage. |
| Focused rerun after USB identity assertions and Developer feature availability changes | 2,061 assertions passed across Metrics, Linear Scroll and Feature Catalog. |
| Isolated comparison with pre-change commit `067671c7` | The unchanged Notch suite passed 67,933 assertions. The changed Notch suite passed 67,934 assertions on rerun. An earlier run saw transient duplicate slider callbacks, with no slider source changes. |
| Original Developer build | GitHub run [44720837848](https://github.com/Xarber/vorssaint-utils/actions/runs/44720837848) passed for `ac3ff11b`. The original artifact predates this follow-up. |
| Follow-up runtime | Native interactions, accessibility, physical USB devices, Nearby transfers, and account flows are pending verification. |

The drop-router test checks the geometry shared with SwiftUI and AppKit. The mouse tests exercise portable records, override precedence, and the production raw wheel handler. USB tests validate USB-PD identity decoding against constructed registry records. These checks do not establish the behavior of actual hardware, external providers, or the system share picker.

The LocalSend helper stays within the existing transfer boundary. Accept and decline stay explicit, the Mac-specific receive folder bookmark remains local, and the incoming notification contains neither filenames nor sender details. NearDrop is an external companion. Its selection and consent stay within macOS Share and NearDrop itself. Android write operations continue to run through the serialized helper with existing collision and confirmation controls. A durable external-device identity and write-replay verification are prerequisites for exposing Finder operations on a connected phone.

The declared hosted settings data is limited to a validated mouse-profile category. X-Center's discovery endpoint was available and the developer portal required authentication. No account was connected, storage provisioned or settings uploaded. The Developer preview and production sign-in paths must be verified against an owned callback and approved app scope before enabling this adapter.

Scoped UADS evidence covers feature planning, conflict-safe Git, source-level tests, data boundaries and docs under §§2–4, 7–8, 21–23, 43 and 51–52. Repository-wide compliance, device validation, screenshot capture and release checks remain pending. The hardware signing key was unavailable and commits use the unsigned fallback in §36.
