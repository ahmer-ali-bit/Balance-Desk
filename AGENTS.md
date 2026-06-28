# Project Constraints

## Scope Restriction
- **ONLY** work on **mobile app UI design**.
- **DO NOT** touch any **desktop UI** code.
- **DO NOT** touch any **business logic** code.

## Performance Session (2026-06-01)

### Completed
- `ledger_screen.dart` (compact entries): Replaced `Column(children: [for ...])` with `ListView.builder` + `_EntryBalance` class; debounced `setState` in opening balance fields via `_debounceOpeningBalanceUpdate()` (80ms timer) to avoid rebuild-per-keystroke.
- `customer_list_screen.dart` (mobile premium cards): `_buildPremiumMobileCustomerCards` → `ListView.builder`.
- `summary_screen.dart` (mobile premium cards): `_buildPremiumMobileSummaryCards` → `ListView.builder`.
- `snapshot_entries_screen.dart` (premium mobile timeline): Replaced `Column+for` with `ListView.builder` + `_TimelineNode` descriptor list; hoisted `canEdit` out of per-item `context.watch` into `_buildPremiumMobileTimeline` and passed as parameter; added `_obDebounceTimer` for opening balance field `setState`.
- `_syncOpeningBalanceControllers` already guarded by `_lastOpeningBalanceSignature` hash — no additional revision counter needed.

### Key Patterns Used
- `ListView.builder(shrinkWrap: true, physics: NeverScrollableScrollPhysics())` for lazy loading in nested scroll contexts.
- Pre-computed descriptor lists (`_TimelineNode`, `_EntryBalance`) to avoid building widgets during iteration — `itemBuilder` creates them on demand.
- Hoisted `context.watch` from per-item builders to parent to prevent unnecessary rebuilds; passed via parameter.
- Debounced `setState((){})` in `onChanged` with 80ms `Timer` to batch rebuilds during rapid keystrokes.

### Items Skipped (Out of Scope / Not a Problem)
- `Canvas.saveLayer` in timeline entries — leaf widget, single clip, no perf impact.
- `_buildCompactTimeline` / `_buildSummaryCardList` — used by both mobile and narrow desktop; desktop per the constraint is off-limits.
- `_buildOpeningBalanceSection` — shared by mobile and desktop.
- DataTable row builders with `context.watch` — desktop code.
