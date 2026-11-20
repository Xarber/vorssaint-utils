# Developer preview builds

The fork's **Developer preview** GitHub workflow builds the isolated Developer app. A `vorssaint-preview-*` tag selects the commit to build. The workflow also supports manual dispatch once it is on the default branch. It checks the bundle signature, runs the selftest and focused suites, then uploads an app ZIP, SHA-256 checksum and full Git commit identifier as Actions artifacts. These builds are for testing.

The workflow includes the LocalSend helper and an Android USB helper that uses the existing Homebrew libmtp runtime on the destination Mac. The preview uses ad-hoc signing. A release or notarized installer requires the existing separate release process.

A local build can use `VORSSAINT_DEV_MTP=1 VORSSAINT_DEV_LOCALSEND=1 ./build.sh --dev` with libmtp and Rust 1.97.1 already installed. The source-preparation script verifies the pinned LocalSend archive before extracting it.
