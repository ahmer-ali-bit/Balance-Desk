# Balance Desk — Design System
**"Modern Professional Ledger"** · v1.0 · 2026-11-13

This document is the single source of truth for the Balance Desk visual
redesign. It records the direction, the tokens, and the reasoning — so future
screens are built from decisions, not guesses.

## 1. Product & audience

Balance Desk is a **shop ledger / udhaar accounting** app: customer accounts,
a ledger-year register, daily snapshots, summary reports, stock ledgers,
PDF/CSV backups. Users are shop owners and their bookkeepers — often
non-technical, often working in bright shop light, sometimes on dim evenings.
Figures must be readable at a glance; mistakes cost money.

## 2. Direction (chosen by the product owner)

| Decision | Choice |
|---|---|
| Direction | **Modern Professional Light** (paper, ink, deep emerald) |
| Theme modes | **Light + Dark + System** — user toggle, persisted |
| Density | **Adaptive**: comfortable on mobile, compact on desktop (tabular figures everywhere) |
| Scope | Splash → PIN gate → shell → every screen, both platforms |
| Brand | Existing hexagon emblem kept; new "BALANCE DESK" lockup, ivory/mint on emerald rail |

References that shaped the system: Mercury/Ramp (calm fintech), Stripe
Dashboard (paper data-dense tables), classic khata book (warm paper, brass,
ink) — not "premium dark glass" (the previous look), not neon.

## 3. Identity

The emblem (deep-green hexagon, mint line-art ledger) is the brand. It sits on
**deep emerald** (`#12402E → #0B241B`) — the same hue family on both themes.
The splash and PIN gate are full ceremony moments on this panel; the desktop
navigation rail and the mobile drawer carry it permanently. Content areas are
paper; the brand panel is the only place darkness is permanent.

Logo usage: `assets/logo.png` (RGBA, transparent). On emerald it always sits
on an **obsidian disc** (`#08150F @ ~72%`) with a hairline mint ring so the
transparent emblem never drowns in the panel. Never recolor the emblem.

## 4. Color tokens

### 4.1 Light — "Paper Ledger" (default)

| Role | Value | Notes |
|---|---|---|
| Canvas (scaffold) | `#F4F5F0` | warm paper, faint green-gray |
| Surface (cards) | `#FFFFFF` | |
| Surface low | `#FAFAF7` | table header tint |
| Surface high / highest | `#EBEDE7` / `#DFE2D8` | inputs, chips |
| Ink (onSurface) | `#182420` | green-charcoal, never pure black |
| Ink variant | `#55645A` | secondary text |
| Outline / variant | `#D9DCD1` / `#E7E9E0` | hairlines |
| **Primary** | `#0E5F3D` | emerald — actions, focus |
| Primary container | `#E0EFE5` | selected pills, chips |
| Tertiary (brass) | `#8A6D1D` | eyebrows, premium accents |
| Debit (in) | `#0E7A5F` | |
| Credit (out) | `#C72B4A` | |

### 4.2 Dark — "Night Ledger"

| Role | Value |
|---|---|
| Canvas | `#0E1511` (green-ink, never blue-black) |
| Surface | `#151F19` |
| Surface low / high | `#1A2620` / `#223028` |
| Ink | `#E9EFEA` · variant `#A5B6AB` |
| Outline / variant | `#33463B` / `#223128` |
| **Primary** | `#5BE0A4` (brand mint) |
| Primary container | `#173B29` |
| Tertiary (brass) | `#E3B95B` |
| Debit | `#47D8A0` · Credit `#FB7A95` |

Debit/credit/brass soft containers exist in both modes as `BalanceColors`
(`lib/theme/finance_colors.dart`, a `ThemeExtension`). Prefer
`BalanceColors.of(context)` over raw constants; `AppColors` remains as a
context-free shim with dual-theme-safe values.

### 4.3 Semantics (never swap)

Debit = money **in / receivable** (deep teal family). Credit = money **out /
payable** (rose family). Brass = premium metadata (FY, workspace, upsell).
Error ≠ credit — errors are `#C72B4A` only where destructive actions are
concerned.

## 5. Typography

Bundled OFL faces (declared in `pubspec.yaml`):

- **Lato** — UI & display. Weights 400–900. Headlines: `w900`, tight tracking
  (−0.3 … −0.8), height 1.15–1.3. Labels/micro: `w800/w900`, caps, +0.7…+2.6
  letterspacing.
- **IBM Plex Mono** — **all monetary figures, IDs, file names**. Tabular,
  letterspacing −0.2…−0.4. Never used for prose.

Type scale: display 34/28 · headline 24/20/18 · title 17/15/13 · body 15/13.5
· label 13/12/10.5.

## 6. Geometry & elevation

- Radius: **10** (inputs/buttons) · **12–14** (cards, tiles) · **16** (page) ·
  **999** (pills).
- Borders over shadows. Light cards: 1px `#E7E9E0` + `0 4–14px` black @ 4–6%.
  Dark cards: 1px `#223128` + black @ 34–38%.
- Interactive states: hover = 4% ink fill; selected = mint-tinted gradient +
  1px mint border (rail), or `primaryContainer` (content).
- Focus ring: 1.6px emerald, always visible (keyboard-first desktop).

## 7. Surfaces & components

- **Emerald rail** (desktop sidebar + mobile drawer): always-deep gradient,
  ivory text, mint accents, micro-caps section labels (`MENU / LEDGER YEAR /
  WORKSPACE / TOOLS`), engraved dark insets for FY + workspace selectors,
  appearance switch (Light/Auto/Dark) pinned above the footer hairline.
- **Content masthead** (desktop): brass eyebrow = screen description (caps),
  Lato Black page title, brass/mint FY + workspace pills on the right. No
  redundant app bar — the rail owns brand; the masthead owns the page.
- **Content sheet** (desktop): white/elevated panel, 14px radius, hairline.
- **Cards/panels** (mobile): white, hairline, soft shadow; header panel =
  icon tile in `primaryContainer` + accent bar; section headers = emerald
  caps micro type + count pill.
- **Tables** (desktop): header row `surfaceContainerLow`, caps 10–11px
  labels, rows 46px, mono figures right-aligned on `numeric` columns,
  hairline dividers, no zebra (hairlines are calmer).
- **Amounts**: always IBM Plex Mono; debit/credit color reinforces sign,
  never sole carrier (icons/labels duplicate meaning).
- **Buttons**: primary = emerald fill (dark: mint fill, ink text), radius 10,
  min height 44 (touch) · secondary = white + outline · destructive = rose.
- **Empty states**: single icon in tinted circle, one clear sentence, one
  action.

## 8. Motion

160–220ms, `easeOutCubic`. Page transitions: fade (shell) / 220ms switch.
Splash & gate: one 1.4s entrance (fade + 18px lift). No spring physics, no
confetti — ledgers are serious software.

## 9. Density rules (adaptive)

- Mobile (< 720dp): 15px body, ≥48px touch targets, cards, comfortable
  padding (16px gutters), mono figures ≥12px.
- Desktop (≥ 980px): 13–13.5px body, 46px table rows, 44px buttons,
  16–20px gutters, keyboard shortcuts preserved (`Ctrl/Cmd+F/N/R`, arrows).
- Narrow desktop (980–1100px): same as desktop, reduced column spacing.

## 10. What was deliberately NOT changed

Business logic, calculations, services, database, models — untouched. The
redesign is pure presentation + one new dependency-free state holder
(`ThemeProvider`, persisted via `shared_preferences` which was already a
dependency) and two bundled OFL fonts.

## 11. Screen inventory & intent

| Screen | Intent |
|---|---|
| Splash | Brand ceremony. Desktop: split rail + paper welcome; mobile: full-bleed emerald. Company logo → obsidian disc emblem; fallback = bundled emblem. |
| PIN Gate | Same ceremony, gate card. Desktop: rail + paper panel; mobile: full-bleed. PIN = OTP field (mono, wide tracking). |
| Shell | Emerald rail (nav/FY/workspace/appearance) + masthead + content sheet (desktop); paper app bar + drawer + bottom nav (mobile). |
| Customers | Directory table (desktop, mono IDs, initial tiles) / card feed (mobile). Search, refresh, add — same shortcuts. |
| Ledger | Hero balance slab (semantic debit/credit), dense entry table (mono figures) — not rewritten, restyled in place. |
| Summary | Stat cards: tinted icon tile + mono ink figures (label color = accent, figure = ink). |
| Daily Logs / Snapshots | Same card & table rules as ledger; timeline accent dots keep semantic colors. |
| Backup & Restore | Same panel system; mono file names; lazy `ListView.builder`. |

## 12. Known trade-offs / follow-ups

- `ledger_screen.dart` (6k+ lines) was restyled via theme, not restructured;
  a structural split is a separate, riskier project.
- Splash/gate artwork is the emblem on disc — no new illustration budget.
- Lato/IBM Plex Mono chosen because they're OFL, static, and bundle safely;
  a future licensed pairing (e.g. Söhne/IBM Plex Sans) can swap via pubspec.
