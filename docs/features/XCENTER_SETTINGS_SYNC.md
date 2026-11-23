# X-Center settings sync

Vorssaint can save and import per-app mouse profiles through X-Center ID. Setup requires the activated Vorssaint registration, administrator approval for private app storage, and a configured HTTPS relay.

In **Settings → Mouse & Trackpad → Global → Mouse Profile Sync**, sign in through the system browser. **Save Current Profiles** replaces the private cloud record after confirmation. **Import Saved Profiles** updates matching apps on this Mac and keeps additional local profiles. **Remove Cloud Profiles** deletes the record after confirmation. Sign-out clears the short-lived session and keeps local profiles. Transfers are user-initiated.

## Data and boundaries

The versioned record contains up to 256 application bundle identifiers and canonical per-app preference values. Local file paths, folder bookmarks, clipboard contents, device identifiers, and credentials are outside the record. The record is private and uses X-Center revisions for writes and deletions.

The relay owns the OAuth client secret and binds issuer authorization to a cookie, state, nonce, and S256 PKCE. It validates the signed ID token and the issuer's UserInfo subject. The Mac uses a random verifier to redeem a successful login once. Only the relay receives issuer tokens. The Mac holds an opaque, short-lived relay session in memory. Closing the app or restarting the relay requires signing in again. The relay retains no mouse profiles or long-lived tokens.

## Deployment and operations

- Issuer: `https://id.xcenter.it`
- Callback: `https://vorssaint.xcenter.it/auth/xcenter/callback`
- Client ID: `xid-e5d5cf89-b811-418f-8499-391a1826b38e`
- App storage record: `preferences/mouse-profiles`
- Root-only configuration: `/srv/xcenter/secrets/vorssaint/relay.env`

Run `npm ci --ignore-scripts` and `npm test` in `server/`. The relay container listens only on the appliance's host loopback. Provide `VORSSAINT_XCENTER_CLIENT_ID` and `VORSSAINT_XCENTER_CLIENT_SECRET` in the protected environment file. Then attach `server/relay.nginx.conf` to the dedicated TLS host, validate Nginx, and reload it. Access logs are disabled for the authentication endpoints because browser callbacks include short-lived codes. Use `GET /auth/xcenter/status` for readiness and a real sign-in to test the issuer exchange. Restarting or rolling back the relay expires in-memory sessions and leaves remote records intact.

DNS ownership is publicly verified and the developer portal shows an active registration. The approved existing client credential is configured on the appliance. The public relay is enabled. Administrator verification for private storage and user consent remain separate checks. End-to-end verification must exercise sign-in, consent denial, save, import, conditional conflict, deletion and sign-out on the normal Mac UI.

## Verification so far

Relay release `6cd04044` is healthy on the appliance. Public HTTPS reports sync enabled. A test of the issuer token endpoint returned `invalid_grant` for a deliberately invalid code using the configured client authentication. Public sign-in initiation, exact callback, S256 challenge, secure cookie, pending pickup, cancellation and rejection of anonymous profile requests passed. The Vorssaint host uses its dedicated TLS route. The pre-existing home page response body retained the same SHA-256 digest. Four tests passed using a signed test issuer and simulated private app storage. They cover wrong pickup proof, single-use browser and pickup, cancellation, revision checks, record deletion and sign-out. The macOS Developer source type check and 2,839 focused assertions passed. The [Developer preview workflow](https://github.com/Xarber/vorssaint-utils/actions/runs/45227552157) was cancelled before any job steps ran. No artifact was produced by that run. The local Developer build at `2114dc17` passed bundle signature verification and its self-test. It used the build script’s local signing identity and the standard icon fallback because the Command Line Tools installation lacks actool. The Mac settings screen reached the issuer’s passkey page through Safari. Authenticated profile storage remains pending.

To disable the public relay route, disable `/etc/nginx/sites-enabled/vorssaint.xcenter.it.conf` and validate before reloading. The generic site then handles the host again. Restarting the separate Compose project clears active sessions. Cloud records remain with X-Center ID.
