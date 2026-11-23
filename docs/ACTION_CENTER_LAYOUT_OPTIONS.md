# Coach Action Center — layout options at normal text size (owner decision)

**Status:** options only. **No layout change is made for this question.** The 44px touch targets stay.
**Prepared:** cycle 10 (2026-11-23). **Code read at:** `integration/p0-flutter-stack-c9` @ `1b94044`
(`apps/mobile/lib/features/dashboard/presentation/client_detail_screen.dart`, `_row` ~1803–1823 and
`_miniBtn`). **Decision owner:** Julia.

## What changed and why

P0-FL-48 (cycle 9, PR #203) made two changes to each Action Center item.

**Before:** the item text and its three actions (Approve / Edit / Dismiss) shared one row. The buttons
were sized to their text (about 11px tall). Two problems followed:
- at large text, and on a 360dp phone even at normal size, the row ran past the card;
- the buttons were far below the 44px minimum touch target.

**Now:**
- the text gets the full width and wraps;
- the three buttons sit under it, right-aligned, each at least 44px, and wrap if needed;
- each button's screen-reader name says which item it is for (e.g. "Approve: Schedule a deload week").

**The cost:** at normal text size each item is about one 44px button row taller, so fewer items fit
on screen. The cycle 9 UX and QA reviews recorded this as an owner question, not a defect. No option
below shrinks a target under 44px.

## Options

| Option | Normal text size (1×) | Large text (≥1.3×) | Targets | Effort | Notes |
|---|---|---|---|---|---|
| **A · Keep today's layout** | Text, then the buttons underneath | Same; buttons wrap | 44px | none | No overflow at any size (pinned by tests). The cost is height. **Recommended.** |
| B · Side by side when it fits | Text and buttons on one row only when the measured width allows all three 44px buttons and the text keeps a minimum width; otherwise today's layout | Today's layout | 44px | small to medium | Denser on wide phones. The switch point must be measured, not guessed: at 1× on a 360dp phone the old single row already overflowed. Needs no-overflow tests at 320/360/390/430dp for 1.0/1.3/2.0. |
| C · One "Act" button per item | Text plus one 44px button that opens a sheet with Approve / Edit / Dismiss | Same | 44px | medium | Most compact, but every action takes an extra tap, and this changes how coaches work the list. A redesign, not a fix. |
| D · Icon-only buttons inline | Text plus three 44px icon buttons (✓ / ✎ / ✕) | Today's layout | 44px | small | Compact, but the visible words go. Voice-control users say "Approve" while the control shows only an icon, so the label must still contain the word. Icons are less clear to coaches. |
| E · Swipe to approve/dismiss | Text only; swipe actions | — | n/a | medium | Hidden gestures are not accessible on their own and still need visible controls, so the height isn't saved. **Not recommended.** |

Not offered: making the buttons smaller than 44px. That would trade accessibility for density, which
this cycle's direction rules out.

## What Julia is asked to choose

1. Keep **A** (no work), or
2. pick **B / C / D**, which becomes a cycle package with UX, QA and accessibility reviews, 1× and 2×
   tests at 320–430dp, and its own PR, or
3. ask for a mock-up of B and D first.

Until then the Action Center stays as P0-FL-48 left it.
