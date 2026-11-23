# X-Center settings sync

This change adds a portable mouse-profile snapshot and a private app-storage API adapter. The app currently runs entirely from local settings. Sign-in, consent, upload, merge, and deletion are pending a verified X-Center ID registration and the end-to-end account flow.

## Data and boundaries

The versioned snapshot explicitly allows up to 256 application bundle identifiers and validated mouse override values. Local file paths, folder bookmarks, clipboard contents, hardware IDs and credentials stay outside it. The adapter targets the official HTTPS issuer, rejects redirects, uses a user-scoped access token and sends private records with revision preconditions. Live API responses remain unverified for this app.

## Activation

Vorssaint needs its own client registration, a verified redirect that matches the native signing and distribution path, and administrator verification for private app records. The developer portal currently requires an authenticated session. No callback ownership, registration identifier or app-data permission has been verified for this fork.

Before enabling the account UI, implement browser-based passkey sign-in with state and PKCE validation, add a persistent opt-in per data category, and verify the end-to-end flow with two Macs. Resolve conflicts against the user's current revision, keep the cache isolated per account, and let users turn sync off and remove the uploaded records. The Developer preview is ad-hoc signed, so a supported HTTPS pickup flow is required for that distribution if verified app links are unavailable.
