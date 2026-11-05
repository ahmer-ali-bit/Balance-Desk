# Linked Devices — Two Device Smoke Test

Manual test plan for cross-device sync. Every other part of the feature is
covered by `test/linked_devices_test.dart`; the parts that need a live Firestore
project and two real installations are checked here.

**Setup**

- Two devices, ideally a **macOS/Windows desktop as the host** and an
  **Android/iOS phone as the guest** (the phone is the only one that can scan the
  invite QR).
- Run both from source so `debugPrint` output is visible:
  `flutter run -d macos` on the desktop (logs in the terminal) and
  `flutter run -d <phone>` (or `adb logcat | grep -i -E "Sync|Linked|Join"`).
- Open the Firebase console side by side: **Firestore → Data** (to inspect the
  `devices` map) and **Usage** (to watch reads/writes).
- Use a **scratch workspace** for step 12 ("Stop sharing"), so the purge test
  cannot touch the workspace you actually use.

## 1. Host starts sharing

1. Host: Linked Devices → *Share This Workspace* → give it a name.
2. Expect the sync card to go *Syncing…* → *Up to date*, and a queue line
   such as `12 waiting to upload` that counts down as records go up.
3. Log to expect: `Sync: <table> row could not be uploaded (key …)` must **not**
   appear. If it does, a record is un-uploadable — capture which table and key.

## 2. Invite is generated

1. Host: *Generate Invite Code*.
2. Expect a 12 character code (not 8), the QR, and *Expires in 10 minutes*.
3. Copy the code — it is what the guest types if it cannot scan.

## 3. Guest joins

1. Guest: Linked Devices → *Join Workspace* → scan the QR (or paste the code).
2. Log order to expect:
   ```
   Join Step 1: Claiming invite token...
   Join Step 1 done: Workspace <name>
   Join Step 2: Creating local workspace linked_<workspaceId>...
   Join Step 3: Switching to new workspace...
   Join Step 4: Downloading admin data...
   Initial download complete: N records applied
   Join Step 4 done: Data downloaded and notified
   ```
3. The guest now shows the host's customers/entries, and the host's roster lists
   the guest as **EDITABLE**.

## 4. Both directions sync automatically

1. Guest adds an entry → it must appear on the host within ~2 seconds, **without**
   pressing *Sync now* (that is the `:listen` watch).
2. Host adds an entry → it must appear on the guest within ~2 seconds.
3. Host log must **not** repeat `Sync: document stamped … is ahead of this device`
   — that line means one device's clock is genuinely off (see step 8).

## 5. Permission change does not damage the roster (field masks)

This is the check for the riskiest change: roster updates now write a single
nested field (`devices.<id>.permission`) instead of the whole `devices` map.

1. Host: set the guest to **read only**.
2. Guest: within ~2 seconds, notice *The main device switched this device to read
   only.* and every edit affordance disappears. Trying to add an entry must be
   refused.
3. Firebase console → `linked_workspaces/<id>` → open `devices.<guestId>`:
   it must **still contain** `name`, `platform`, `role`, `joinedAt`,
   `lastSeenAt` — only `permission` changed. The other devices' entries must be
   byte-identical to before.
4. Any log like `Firestore updateDocument … failed [400]` here means the dot-path
   update mask is not accepted; fall back to rewriting the whole `devices` map
   with a fresh read (and re-report).
5. Host: set the guest back to **edit** → guest regains editing.

## 6. Offline edit is queued and then pushed on its own

1. Guest: turn off Wi-Fi/mobile data → add an entry.
2. Guest sync card: *Offline — changes are queued* with a pending count.
3. Guest: turn the network back on and **do not touch the app**.
4. Within ~20 seconds the entry must reach the host. (Before the fix this could
   wait for the 30 minute safety poll, or forever while the app sat idle.)

## 7. Delete propagates and stays deleted

1. Host deletes an entry → it disappears on the guest within ~2 seconds.
2. Guest: disconnect the network, reconnect (or *Sync now*) → the deleted entry
   must **not** come back.

## 8. Clock skew must not stop the sync (regression test for the cursor fix)

1. Guest: set the system clock **2 hours ahead**, add an entry, wait until it
   appears on the host.
2. Host log will contain, at most once per cycle for that collection:
   `Sync: document stamped … is ahead of this device; holding the sync cursor at …`
   — expected, and it must not repeat endlessly.
3. Host: add a new entry **now**. It must still reach the guest. (Before the fix
   the host's cursor could run ahead of its own clock and silently skip
   everything written afterwards — permanent divergence.)
4. Guest: set the clock back to automatic/correct, add another entry → it must
   reach the host normally.

## 9. Unlinking keeps the data (no silent wipe)

1. Host: roster → *Unlink* the guest.
2. Guest: within ~2 seconds, notice *This device was unlinked by the main device.
   The shared ledger stays here as a read-only local workspace.*
3. Guest: the previously downloaded customers/entries must **still be there**
   (this is the fix — the old build deleted the whole database here).
4. Guest: its own earlier workspace must still be listed in the workspace menu.

## 10. Disconnecting returns the user to their own books

1. Re-join the guest to the shared workspace (new invite).
2. Guest: *Disconnect* → confirm.
3. Expect: the guest switches back to the workspace it was using before it
   joined — its own customers are on screen again.
4. The shared workspace must still exist in the workspace menu, containing the
   host's data (disconnect keeps a local copy, it does not delete).
5. Log to expect: `Could not reopen the previous workspace: …` must **not**
   appear.

## 11. Heartbeat keeps the roster honest

1. Heartbeats only fire every 6 hours, so instead of waiting: on the host open
   *Firestore → Data* and confirm the guest entry still has a `lastSeenAt` after
   steps 5 and 9 (permission changes must not have removed it).

## 12. Stop sharing purges the cloud copy

**Use a scratch workspace for this step.**

1. Host: create/switch to a scratch workspace, share it, add two customers and an
   entry, let it finish uploading.
2. Host: *Stop Sharing*.
3. Log to expect: `Purged N workspace records so far (customers)` and similar —
   the purge runs in the background, so the UI returns immediately.
4. Firebase console: `linked_workspaces/<id>` is gone, and after a minute the
   `customers`, `entries`, `summary_snapshots`, `ledger_years` and `app_settings`
   sub-collections are empty. Nothing of that shop's ledger is left in the cloud.
5. Local data on the host must be untouched.

## 13. Rules (already verified, quick re-check)

With the deployed rules:

| Request | Expected |
| --- | --- |
| `list linked_invites` | 403 |
| `list linked_workspaces` | 403 |
| `get` an invite by token | 404/200, never 403 |
| `runQuery` a sub-collection | 200 |

If `get`/`runQuery` ever answer 403, joining or syncing will fail with
*The cloud rejected the request* — that means the rules were widened or
replaced.

## Failure triage

| Symptom | Most likely cause | Where to look |
| --- | --- | --- |
| Join fails immediately | invite expired/used, or rules denied `get` | `Join failed (LinkedDevicesException): …` |
| Guest joins but sees nothing | watch blocked, pull failed | `LinkedSessionProvider watch stopped: …`, `Sync: could not apply …` |
| Changes never leave a device | pending queue stuck | `LinkedSessionProvider local push failed: …`, pending count on the sync card |
| Record missing on one side only | row could not be built into a write | `Sync: <table> row could not be uploaded (key …)` |
| Permission toggle has no effect | roster field update rejected | `Firestore updateDocument … failed [4xx]` |
| Repeated `is ahead of this device` | a device clock is really wrong | fix that device's clock/NTP |
