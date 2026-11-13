# Linked devices and shared workspaces

## Product behavior

- A normal workspace remains local-only until its owner chooses **Linked Devices → Share this workspace**.
- The first installation that shares a workspace becomes its owner device. Other installations join through a single-use invite QR/code.
- Each installation stores a random device capability in the operating system secure store; the cloud stores only its SHA-256 hash.
- Invites expire after five minutes and can be claimed once. The owner can review devices, switch a linked device between edit/read-only, transfer ownership to an active linked device, revoke a device, or stop sharing.
- Local SQLite remains the working copy. Changes sync automatically while the app is active and on resume; offline edits remain queued. Sync polls at an 8-second interval because the free setup does not depend on a paid realtime service.
- Records use stable cross-device IDs and optimistic revisions. Concurrent changes to the same record are shown in the conflict review instead of silently overwritten.
- A linked device that disconnects or is revoked keeps its local copy. Stopping sharing removes the cloud workspace and its records but preserves the owner’s local books.

## Security model

- Supabase project: `balance-desk-linked-devices` in `ap-south-1` (Mumbai), Free plan.
- The app embeds only the Supabase publishable key. A service-role/secret key is never put in the client.
- Ledger/device/invite tables have RLS enabled and no direct client table grants. Narrow Postgres RPCs are the only public entry points; each data operation validates a 256-bit per-install capability and active device row.
- Capability values are random, stored in Android Keystore / Apple Keychain / supported OS credential storage, and never written to SQLite or SharedPreferences. The database stores only SHA-256 hashes.
- Network traffic uses HTTPS. This is server-side access control and transport protection, not end-to-end encryption: the Supabase project owner/database administrators can access data in the managed database. Treat the Supabase account and project dashboard as trusted administrative access.
- Free cloud plans have usage and availability limits. A paused/unavailable cloud does not erase the local workspace; sync resumes after service is available.

## Local setup and build

1. Run `flutter pub get` after pulling this feature. It adds secure-storage and QR scanner packages; do not reuse an old build/hot reload for the first install.
2. Rebuild the native app. macOS secure storage requires the keychain access-group entitlement already added under `macos/Runner`.
3. On Android/iOS, grant camera access to scan invites. Code copy/paste remains available if scanning is unavailable.
4. For desktop-to-phone linking, create/show the invite QR on desktop and scan it from the phone. For phone-to-desktop, copy the invite string and paste it into the desktop app.
5. Keep backups before enabling sharing across real workspaces. Verify add/edit/delete, customer-linked opening-balance settings, ledger years, summary snapshots, read-only, revoke, offline catch-up, conflict review, disconnect, and stop-sharing on two installations.

## Cloud schema

The migrations `supabase/migrations/202611130001_linked_devices.sql`, `supabase/migrations/202611130002_owner_transfer_and_sync_status.sql`, and `supabase/migrations/202611130003_preserve_readonly_edits.sql` are applied to the connected Supabase project. The app URL and publishable key are in `lib/core/config/supabase_config.dart`; those are public client values. Never replace them with a `sb_secret_*` or `service_role` key. A privileged project key was exposed during development; rotate it in the Supabase dashboard before production use.
