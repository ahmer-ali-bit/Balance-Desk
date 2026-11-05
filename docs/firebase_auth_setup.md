# Linked Devices — Cloud Setup And Security

This document describes what the linked-devices feature actually does. It
replaces the earlier notes that described a Firebase Auth based design; the app
has never used it.

## 1. How the cloud layer works today

Cross-device sync talks to **Cloud Firestore through the REST API**
(`lib/features/linked_devices/firestore_rest_client.dart`). There is no
`firebase_*` plugin, no generated platform config, and **no sign-in step**: every
request carries a Firebase API key, and access is decided by
`firestore.rules`.

The ledger itself stays local (SQLite). Cloud sync is only used for pairing and
for exchanging records between devices that were deliberately linked.

## 2. Setup

1. Create a Firebase project (or reuse the existing one).
2. Create a Firestore database.
3. Publish `firestore.rules` to it (`firebase deploy --only firestore:rules`).
4. Point the build at your project:

```sh
flutter run \
  --dart-define=FIREBASE_PROJECT_ID=your_project_id \
  --dart-define=FIREBASE_API_KEY=your_web_api_key
```

Both values have defaults baked in for the current project, so a plain
`flutter run` works. Anonymous Authentication does **not** need to be enabled —
nothing in the app signs in.

## 3. Security model (and what it does not cover)

Access is **capability based**:

- A workspace lives at `linked_workspaces/{workspaceId}` where `workspaceId` is a
  128-bit random id. It only ever leaves the device inside an invite link / QR
  code.
- An invite lives at `linked_invites/{token}` where `token` is 12 characters
  from a 32 character alphabet (~60 bits) and is valid for 10 minutes.
- `list` is **denied** on `linked_invites` and on `linked_workspaces`, so the
  collections cannot be enumerated. Only `get` by a known id is allowed.
- The sub-collections (`customers`, `entries`, `summary_snapshots`,
  `ledger_years`, `app_settings`) must allow `list` because the sync engine pages
  through them with `runQuery`.

**Residual risk:** a Firebase API key is not a secret, and rules cannot tell one
shop's build from another's. Anyone who obtains a workspace id can read and
write that workspace. The invite token is the only thing standing between a
stranger and a workspace id, which is why it is long, random, single use, and
short lived.

Closing this properly means giving up on "no sign-in" and either:

- enabling Firebase Auth (Anonymous at minimum) and rewriting the rules to check
  `request.auth.uid` against the roster in the workspace document, or
- putting a small server-side proxy in front of Firestore that holds a service
  account and verifies the caller.

Until then, do not widen the rules back to `allow read` on `linked_invites` /
`linked_workspaces`, and do not treat a workspace id as a secret worth less than
the data it protects.

## 4. What a workspace stores in the cloud

```
linked_workspaces/{workspaceId}          control document
  workspaceName, hostDeviceId, dataChangedAt, invite, devices{...}
  customers/{syncId}
  entries/{syncId}
  summary_snapshots/{syncId}
  ledger_years/y{year}
  app_settings/{sha1(wireKey)}
```

"Stop sharing" deletes the control document **and** purges those sub-collections;
Firestore does not cascade a document delete into its sub-collections, so the
purge has to walk them explicitly (up to 25 pages of 200 per collection, best
effort).

## 5. Sync behaviour worth knowing

- **Timestamps come from each device's clock.** The pull cursor is a plain
  `startAt` on `updatedAt`, so a device whose clock runs fast would otherwise
  hand every other device a cursor that skips their later writes. The cursor is
  therefore never allowed to advance past this device's own clock (15 minutes of
  tolerance), and a future-stamped remote record never overwrites a local record
  that has not been uploaded yet.
- **Deletes travel as tombstones** (`sync_tombstones`) so a delete on one device
  is not resurrected by a stale upload from another.
- **The first share uploads the whole ledger** in batches of up to 400 records
  per cycle; the linked-devices screen shows the queue ("N waiting to upload").
- **Disconnecting keeps the data.** A joined workspace is opened as its own
  local workspace (its own database file), so leaving a shared workspace never
  touches the user's own books, and what was downloaded stays as an ordinary
  local workspace.
- **A guest is returned to its own workspace** after disconnecting, when it had
  one before joining.

## 6. Desktop notes

- **QR scanning is mobile only.** The camera scanner (`mobile_scanner`) is not
  part of the desktop build, so an invite is shared as a code or a link.
- **Windows invite links need the URL scheme registered.** `app_links` reads the
  link from the command line, and Windows only launches the app that way if the
  `balancedesk` scheme is registered. `tool/installer/balance-desk.iss` does
  that; installs produced with `msix:create` do **not**, because MSIX needs a
  protocol extension in the app manifest instead. On an MSIX install, invite
  links will not open the app — copy the code and paste it into "Join Workspace".
