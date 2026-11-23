# X-Center app data sync

Open **Settings → Advanced → App Data Sync**, next to the existing Export All Data and Import All Data controls. Sign in through the system browser and approve private app storage. **Back Up Now** saves the portable data covered by Export All Data. **Restore Cloud Backup** downloads the backup, validates it, and opens the existing Import All Data confirmation. Confirming restores that data and relaunches the app. Sign out or delete the cloud backup from the same section. Each backup or restore is user-initiated.

## Data and boundaries

Cloud and file backups use the same exporter, allowlist and import rules in `SettingsBackup` and `SettingsBackupSupport`. This includes the exportable settings and content maintained by those tools, including per-app mouse profiles. Local credentials, security-scoped bookmarks and other machine-specific data excluded by the exporter stay out of the backup.

The relay stores a binary property list as private, account-scoped chunks in X-Center ID. Replacing a backup publishes its new manifest only after all chunks are written. Revision checks prevent concurrent updates from silently overwriting each other, and the downloader verifies the archive digest. Removing a backup invalidates its manifest and deletes its chunks. A transport interruption during cleanup can leave unreferenced private chunks. Backups are limited to 6 MiB and to available account storage, including temporary space for a replacement while the prior copy remains accessible. Local file export remains available for larger backups.

The relay owns the OAuth client credential and binds issuer authorization to a secure browser cookie, state, nonce and S256 PKCE. The Mac exchanges a single-use proof for a short-lived session. Closing the app or restarting the relay requires a new sign-in. The relay keeps no backup files on its own disk.

## Deployment and operations

- Issuer `https://id.xcenter.it`
- Callback `https://vorssaint.xcenter.it/auth/xcenter/callback`
- Public app client ID `xid-e5d5cf89-b811-418f-8499-391a1826b38e`
- Private manifest record `preferences/advanced-backup`
- Protected deployment configuration `/srv/xcenter/secrets/vorssaint/relay.env`

Run `npm ci --ignore-scripts` and `npm test` in `server/`. The Compose project serves a loopback port. The dedicated Vorssaint TLS site forwards the app routes to that port, with access logging disabled so short-lived codes stay out of logs. Check public `/auth/xcenter/status` for readiness. Rolling the relay back to the preceding image expires in-memory sessions. It leaves the X-Center ID records intact.

## Verification

The Mac successfully completed passkey sign-in through the earlier Developer build. The corrected Advanced flow uses that same verified registration and browser protocol. Relay tests exercise signed test-issuer login, permission boundaries, private multi-record backups, cancelled and replayed requests, revision conflicts, failed chunk writes, successful restore and deletion. Relay release `135a2d77` is deployed. Public readiness reports sync enabled and the backup endpoints reject anonymous reads. The prior image and proxy configuration are retained on the appliance. The corrected Developer build and settings parity checks were started locally. Real-account cloud writes and restores require testing after the corrected Mac build completes.
