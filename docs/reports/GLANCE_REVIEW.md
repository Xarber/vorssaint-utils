# Glance Mac unlock review

Reviewed source revision [b97f521](https://github.com/jonnyoo/glance/tree/b97f521397ec1197ba17768ba797cae1e628848d). The requested behavior is unlocking an existing macOS session. The security review covered app startup, lock and wake observations, enrollment and inference, liveness decisions, Keychain access, in-memory authorization, password delivery, settings, private overlay APIs and the model conversion recipe. It was a source review. No login password was supplied, and the upstream app was neither built nor run.

## Trust boundary

Glance protects its stored password and face data with AES-GCM and gates access to the decryption key through local user presence in Keychain. It checks the session server for lock state instead of treating distributed notifications as authentication. The app keeps the unlocked decryption key in memory across Mac lock and wake. Its default 30-day idle timer starts over after successful password reads, and settings offer a session with no idle expiry. Screen lock is the trigger to use that existing authorization.

Camera recognition and optional liveness checks control whether the app uses the actual login password. macOS sees a password entry. It does not attest the camera match through its own biometric sign-in path. The lock-screen overlay is implemented with undocumented SkyLight interfaces. The combination would bring the device's reusable login credential into the trust boundary of Vorssaint, which also handles shareable files, event taps and network-facing features.

Relevant source areas include [credential and session state](https://github.com/jonnyoo/glance/blob/b97f521397ec1197ba17768ba797cae1e628848d/glance/SecureCredentialManager.swift), [default settings](https://github.com/jonnyoo/glance/blob/b97f521397ec1197ba17768ba797cae1e628848d/glance/Settings/GlanceSettings.swift), and [platform authorization documentation](https://developer.apple.com/documentation/localauthentication).

## Model redistribution

The [conversion recipe](https://github.com/jonnyoo/glance/blob/b97f521397ec1197ba17768ba797cae1e628848d/tools/README.md) identifies InsightFace's `buffalo_s` recognition weights. [InsightFace's model terms](https://github.com/deepinsight/insightface#license) limit its pretrained model packs to non-commercial research. Glance's MIT source license does not establish broader rights for those weights.

VOR-01 remains blocked. The reviewed design does not meet Vorssaint's credential boundary, and the reviewed model has no verified general redistribution grant.
