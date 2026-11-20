# Vorssaint engineering guide

Vorssaint is a SwiftUI and AppKit utility for Apple Silicon Macs running macOS 14 or later. Its menu-bar panel and Dynamic Island host tools for input, window management, audio, capture, files, and system metrics.

- [Contributor guide](../CONTRIBUTING.md) for development, verification, signing, and release workflows.
- [Active task queue](ACTIVE_TASKS.md) for feature scope, dependencies, and verification status.
- [Permissions](PERMISSIONS.md), [privacy](PRIVACY.md), and [security reporting](../SECURITY.md).
- [Troubleshooting](TROUBLESHOOTING.md) and [verification reports](reports/INTEGRATION_CHECKS.md).

## Source map

- `Sources/Vorssaint/App` owns startup, the status item, and optional feature lifecycle.
- `Sources/Vorssaint/Core` contains preferences, backup settings, feature catalog, and localized strings.
- `Sources/Vorssaint/Services` owns feature behavior. Shelf stores files and coordinates promised-file delivery. Notch owns presentation and dispatches file drops to Shelf, AirDrop or media optimization. System Monitor samples USB peripherals and reads optional USB-C details on its sampling queue.
- `Sources/Vorssaint/UI` contains the native settings and feature screens. The AirDrop presenter hands file URLs to AppKit. Cable details and the [Developer Android transfer preview](features/ANDROID_USB_TRANSFER.md) live in Connected Devices.
- `Resources` contains the app bundle configuration and localized permission prompts.

## Verification

`./build.sh --test-suite=notch`, `--test-suite=shelf` and `--test-suite=metrics` run focused checks through the repository's standalone harness. `./build.sh --dev` builds the separate Developer app. Follow the contributor guide for app selftests, packaging and compatibility CI.

Baseline reviewed at `89d26260`. This map covers the integration entry points and related build configuration. Broader first-party source, operations and compliance inventory is tracked in the active queue.
