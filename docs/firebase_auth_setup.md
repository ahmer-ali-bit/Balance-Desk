# Firebase Setup For Linked Devices

Linked Devices uses Firebase Auth (anonymous) + Cloud Firestore. The ledger
itself stays a local SQLite database and keeps working fully offline — Firebase
is only used to pair devices and replicate changes between them.

> **If you build without the Firebase dart-defines, nothing breaks.** The app
> starts as a local-only ledger and the Linked Devices screen explains that
> syncing is unavailable.

---

## 1. What is actually implemented

| Piece | Where |
| --- | --- |
| Pairing (QR + paste-a-link) | `lib/screens/linked_devices_screen.dart` |
| Invites, roster, roles | `lib/services/sync/link_service.dart` |
| Replication engine (delta journal + per-row LWW) | `lib/services/sync/sync_engine.dart` |
| Local capture tables & triggers | `lib/database/sync_tables.dart` |
| Deep links (`balancedesk://link-device?w=…&t=…`) | `lib/services/app_deep_link_service.dart` |
| Build-time Firebase config | `lib/services/firebase/firebase_options.dart` |
| Security rules | `firestore.rules` |

Data model in Firestore:

```
workspaces/{workspaceId}                  {name, ownerUid, revision, createdAt, updatedAt}
workspaces/{workspaceId}/members/{uid}    {uid, deviceId, displayName, platform, role, inviteToken, joinedAt, lastSeenAt}
workspaces/{workspaceId}/invites/{token}  {token, createdByUid, role, createdAt, expiresAt, maxUses, uses, joinedUids, revoked}
workspaces/{workspaceId}/ops/{opId}       {opId, originDeviceId, table, rowId, action, updatedAt, payload, createdAt}
```

Roles: `owner` → `editor` → `viewer`. New devices join with the role the invite
granted (view-only by default); the owner can upgrade them afterwards from the
Linked Devices screen.

How sync works:

1. Every local INSERT/UPDATE/DELETE on `customers`, `entries`,
   `summary_snapshots`, `ledger_years` and `app_settings` is captured by a
   SQLite trigger into a local `sync_outbox` table. No business-logic code
   path is involved, so calculations are untouched.
2. Outbox rows are collapsed per row and pushed as immutable ops.
3. Remote ops are replayed in id order and applied only when newer than what
   the device already holds; equal timestamps are broken deterministically by
   origin device id. Every device converges to the same state.
4. `activeYear` and `sidebar.notes` are per-device and deliberately **not**
   replicated.

---

## 2. Firebase Console

1. Create one project, then add the platforms you need (Android, iOS, macOS,
   Windows).
2. **Authentication → Sign-in method → enable Anonymous.**
3. **Firestore Database → create a database** (production mode is fine; the
   rules below are not permissive).
4. Deploy the rules:

   ```bash
   firebase deploy --only firestore:rules
   ```

   The rules enforce:
   - anonymous sign-in is required for everything;
   - only the owner can create/rotate/revoke invites and change roles;
   - a joiner can only take the role its invite granted;
   - viewers can read but never write ledger ops;
   - ops are immutable; only the owner prunes them.

---

## 3. Credentials — never committed

Real credentials are **git-ignored**. Copy the templates and fill them in:

| Platform | File | Template |
| --- | --- | --- |
| Android | `android/app/google-services.json` | `android/app/google-services.json.example` |
| iOS | `ios/Runner/GoogleService-Info.plist` | from the Firebase Console |
| macOS | `macos/Runner/GoogleService-Info.plist` | from the Firebase Console |
| Windows / CI | env vars via `firebase.local.ps1` | `firebase.local.example.ps1` |

The Android Gradle plugin is applied **only when** `google-services.json`
exists, so a fresh clone still builds.

> If a real key was ever committed, rotating it in the Firebase Console is the
> only real fix — removing it from Git does not remove it from history.

---

## 4. Passing the configuration at build time

```powershell
Copy-Item firebase.local.example.ps1 firebase.local.ps1   # then edit it
.\windows_firebase.ps1 run            # or: build release
.\windows_firebase.cmd build release  # same thing through cmd
```

Required variables:

- `BD_FIREBASE_API_KEY`
- `BD_FIREBASE_PROJECT_ID`
- `BD_FIREBASE_MESSAGING_SENDER_ID`
- `BD_FIREBASE_APP_ID_WINDOWS` (or `_ANDROID` / `_IOS` / `_MACOS` / `_WEB`, or a
  generic `BD_FIREBASE_APP_ID`)

Optional: `BD_FIREBASE_STORAGE_BUCKET`, `BD_FIREBASE_AUTH_DOMAIN`,
`BD_FIREBASE_MEASUREMENT_ID`.

Mobile/desktop builds can pass the same values directly:

```bash
flutter run \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_PROJECT_ID=... \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=FIREBASE_APP_ID_ANDROID=...
```

`lib/services/firebase/firebase_options.dart` maps those defines to
`FirebaseOptions` for the running platform. If you prefer generated options,
run `flutterfire configure` and replace that file.

CI: add `FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`,
`FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_APP_ID_WINDOWS` (and optionally
`FIREBASE_STORAGE_BUCKET`) as repository secrets;
`.github/workflows/build_windows.yml` forwards them automatically.

---

## 5. Pairing behaviour

- The invite link is `balancedesk://link-device?w=<workspaceId>&t=<token>` and
  the **same string** is encoded into the QR code.
- It contains pairing tokens only — **no ledger data**.
- Tokens are 128-bit random, expire (15 minutes by default, 24 h maximum) and
  have a use cap (5 by default, 25 maximum).
- The scheme is registered on Android (intent filter), iOS/macOS
  (`CFBundleURLSchemes`) and Windows (registry entry written by
  `tool/installer/balance-desk.iss`).
- QR *scanning* is offered only where a camera exists (Android/iOS). On
  Windows/macOS/Linux, paste the link instead.
- Firebase Dynamic Links are not used.

---

## 6. Known limits

- **Owner handover is not implemented.** If the owner leaves the workspace,
  the remaining devices keep their local copies but nobody can invite new
  devices or change roles.
- Deletes are replicated as tombstones; a device that is offline when a row is
  deleted will apply the tombstone on its next sync.
- Concurrent edits to the *same* row resolve by last-writer-wins, not by merge.
  Editing different rows never conflicts.
- `app_settings` replicates except for the two per-device keys listed above.
- The Firestore journal grows until the owner prunes it (rules allow only the
  owner to delete ops).
