# ADMIN COMPONENT SPECIFICATIONS — `DESIGN-02`

> **PROVENANCE — where the cited design artifacts actually are.** The approved
> 12Circle+ design authority was published by commit **`931218b`** on the branch
> **`design/12circle-plus-admin-dashboard`**, which is **not an ancestor of
> `reconcile/12circle-integrated`**. So `admin.tokens.css`, `admin.tokens.json`,
> `admin.contrast.md`, `admin-icon-inventory.md`, `RESPONSIVE.md`, `SCREEN-INVENTORY.md`,
> `COMPONENTS.md` and the `screens/` sources named below are **not in this branch's
> working tree**. Read any of them with:
>
> ```
> git show 931218b:docs/design/brand/tokens/admin.tokens.css
> ```
>
> Every citation in this document was made against that commit. `check-design-citations.mjs`
> enforces this note's presence — see V5 §165.


**Produced 2026-10-06 to close the gap `COMPONENTS.md` records in its own words:**
*"A separate per-component specification sheet (anatomy, variants, spacing annotations) has **not** been
produced. Listed as missing."*

## Provenance — derived, not designed

Every value below is **extracted from the published design authority**, never chosen here:

| input | branch path | what it supplies |
|---|---|---|
| six approved pages | `docs/design/admin-dashboard/screens/*.dc.html` | anatomy, spacing, radii, colours, states — as **inline styles**, which are the only source: the referenced `_ds/nocturne-…` bundle is **absent from the package** (0 files) |
| `admin.tokens.css` / `.json` | `docs/design/brand/tokens/` | **126 `--adm-*` tokens** across breakpoint · color · font · motion · radius · shadow · size · space · type · z |
| `admin.contrast.md` | `docs/design/brand/tokens/` | measured WCAG ratios and the rule that `text.disabled` and `brand.violet` are **never** used for text |
| `admin-icon-inventory.md` | `docs/design/brand/icons/` | Phosphor Icons **v2.1.1**, `regular` default, `fill` for selected/active, **107 icons** with usage counts |
| `RESPONSIVE.md` | `docs/design/admin-dashboard/` | five breakpoints and the layout rules |
| `SCREEN-INVENTORY.md` | `docs/design/admin-dashboard/` | the ten designed state patterns |

**Nothing was invented.** Where the package does not define a behaviour it is recorded as a gap in §G rather
than filled in.

**What the `token` column claims, precisely.** It is filled only when the observed literal matches a declared
`--adm-*` token **and** that token's family matches the CSS property — `--adm-radius-*` for `border-radius`,
`--adm-color-*` for colours, `--adm-size-*` for dimensions, and so on. The family constraint matters: an
earlier draft of this file mapped `border: 0` to `--adm-type-caption-tracking`, because several tokens share
the value `0`. **That was nonsense and was corrected.** Trivial values (`0`, `none`, `auto`) are deliberately
left unmapped.

**A match is by VALUE, not by designed intent.** `width: 52px` on the Switch resolves to
`--adm-size-row-list` because both are 52px; the package does not say the switch was drawn *from* that token.
Read the column as *"this literal equals this token"*, which is what a implementer needs, and not as a claim
about the designer's reasoning. `—` means the page uses a literal the 126-token set does not name — recorded
as gap **G-6**.

## Typography and identity — consistent with the shipped implementation

`--adm-font-family: "Schibsted Grotesk", system-ui, sans-serif`, weights 400 / 500 / 600. The shipped
application declares the same family (`twelve_circle_theme.dart`: `fontDisplay`, `fontBody`, `fontNumeric` all
`Schibsted Grotesk`), and `admin.tokens.css` ships the identical palette — `#0a0a0b`, `#121215`, `#f4f3f6`,
`#9b96a3`, violet `#7c3aed`, amber `#e0a030`, green `#2fbf87`. **`CONF-D6-B`'s locked token authority and this
package are the same token set**, which is why `BOUNDARIES G` needed no resolution.

## Global rules every component inherits

**Accessibility.** Body text ≥ 4.5:1. `text.disabled` (3.8) and `brand.violet` (3.5) are **never** text —
disabled icons, logo mark and fills only. Interactive controls carry their ARIA role (`switch`, `tab`,
`tablist`, `menu`, `menuitem`, `dialog`, `status`, `region`, `list`, `listitem`) as the pages already declare.

**Responsive.** 1439 content relaxes · 1400 wide grids drop a column · 1199/1180 two-column collapses,
side panels stack · 1100 dense tables scroll **inside their card** · 900 nav collapses, single column,
**44px touch targets**. Tables never scroll the page; no horizontal page scroll at any width;
`prefers-reduced-motion` removes animation.

**Icons.** Phosphor v2.1.1 only. `ph` regular by default, `ph-fill` for selected/active.

## Shell

### Environment strip

**Purpose.** The staging/production banner pinned above the header.

**Observed in.** Control_Center ×1 · Ecosystem ×1 · Operations ×3 · People ×1 · Settings ×1 · Trust ×2

| property | value | token |
|---|---|---|
| `gap` | `10px` | `--adm-space-5` |
| `min-height` | `34px` | `--adm-size-env-strip` |
| `padding` | `0 16px` | — |
| `background` | `#e0a030` | `--adm-color-status-warning` |
| `color` | `#0a0a0b` | `--adm-color-bg-canvas` |
| `font-size` | `13px` | — |
| `font-weight` | `500` | `--adm-font-weight-medium` |
| `border-radius` | `16px` | `--adm-radius-xl` |
| `background` | `#121215` | `--adm-color-bg-surface` |
| `box-shadow` | `inset 0 0 0 1px rgba(255,255,255,0.08)` | `--adm-shadow-edge` |
| `padding` | `18px 20px` | — |
| `gap` | `14px` | `--adm-space-7` |

### Header + six-item nav

**Purpose.** Dashboard · People · Ecosystem · Trust · Operations · Settings.

**Observed in.** Control_Center ×1 · Ecosystem ×1 · Operations ×1 · People ×1 · Settings ×1 · Trust ×1

| property | value | token |
|---|---|---|
| `z-index` | `10` | `--adm-z-header` |
| `background` | `rgba(10,10,11,0.9)` | — |
| `box-shadow` | `inset 0 -1px 0 rgba(255,255,255,0.07)` | `--adm-shadow-header` |

### User menu

**Purpose.** Identity control opening a menu.

**Observed in.** Control_Center ×4 · Ecosystem ×4 · Operations ×4 · People ×4 · Settings ×4 · Trust ×4

| property | value | token |
|---|---|---|
| `z-index` | `20` | `--adm-z-menu` |
| `padding` | `6px` | `--adm-space-3` |
| `border-radius` | `14px` | — |
| `background` | `#16161a` | `--adm-color-bg-raised` |
| `box-shadow` | `inset 0 0 0 1px rgba(255,255,255,0.1), 0 20px 50px rgba(0,0,0,0.6)` | `--adm-shadow-menu` |

### Search

**Purpose.** Global search control in the header.

**Observed in.** Control_Center ×1 · Ecosystem ×8 · Operations ×9 · People ×5 · Settings ×3 · Trust ×10

| property | value | token |
|---|---|---|
| `width` | `100%` | — |
| `border` | `0` | — |
| `color` | `#f4f3f6` | `--adm-color-text-primary` |
| `min-height` | `44px` | `--adm-size-control` |
| `border-radius` | `10px` | `--adm-radius-md` |
| `background` | `#1b1b20` | `--adm-color-bg-hover` |
| `font-size` | `14px` | `--adm-type-body-size` |
| `box-shadow` | `inset 0 0 0 1px rgba(255,255,255,0.1)` | — |
| `padding` | `0 14px 0 40px` | — |
| `font-size` | `13.5px` | `--adm-type-small-size` |
| `padding` | `0 12px 0 36px` | — |
| `padding` | `0 64px 0 40px` | — |


## Containers

### Card

**Purpose.** Primary surface container.

**Observed in.** Control_Center ×13 · Ecosystem ×7 · Operations ×85 · People ×4 · Settings ×52 · Trust ×89

| property | value | token |
|---|---|---|
| `background` | `#121215` | `--adm-color-bg-surface` |
| `border-radius` | `16px` | `--adm-radius-xl` |
| `box-shadow` | `inset 0 0 0 1px rgba(255,255,255,0.08)` | `--adm-shadow-edge` |
| `padding` | `18px 20px` | — |
| `padding` | `16px 18px` | — |
| `box-shadow` | `inset 0 0 0 1px rgba(255,255,255,0.07)` | — |
| `padding` | `22px 20px` | — |
| `padding` | `18px` | — |
| `border-radius` | `18px` | — |
| `gap` | `8px` | `--adm-space-4` |
| `padding` | `14px` | `--adm-space-7` |
| `border-radius` | `16px 16px 0 0` | — |

### Panel

**Purpose.** Sectioned region inside a page.

**Observed in.** Control_Center ×15 · Ecosystem ×7 · Operations ×6 · People ×6 · Settings ×12 · Trust ×6

| property | value | token |
|---|---|---|
| `box-shadow` | `inset 0 1px 0 rgba(255,255,255,0.08)` | — |
| `background` | `#121215` | `--adm-color-bg-surface` |
| `box-shadow` | `inset 0 0 0 1px rgba(255,255,255,0.07)` | — |
| `padding` | `28px 0 8px` | — |
| `border-radius` | `20px` | `--adm-radius-2xl` |
| `padding` | `20px` | `--adm-space-10` |
| `border-radius` | `26px` | — |
| `padding` | `26px` | — |
| `grid-template-columns` | `auto minmax(0, 1fr)` | — |
| `gap` | `0` | — |
| `box-shadow` | `inset 0 0 0 1px rgba(224,160,48,0.35)` | — |
| `grid-template-columns` | `repeat(auto-fit, minmax(210px, 1fr))` | — |

### Drawer

**Purpose.** Right-hand overlay; "Needs your attention".

**Observed in.** Control_Center ×1

| property | value | token |
|---|---|---|
| `z-index` | `90` | — |
| `width` | `min(600px, calc(100vw - 56px))` | — |
| `transition` | `transform 320ms cubic-bezier(0.2, 0.8, 0.2, 1)` | — |

### Dialog

**Purpose.** Modal, aria-modal="true".

**Observed in.** People ×1 · Settings ×2 · Trust ×1

| property | value | token |
|---|---|---|
| `border-radius` | `16px` | `--adm-radius-xl` |
| `background` | `#121215` | `--adm-color-bg-surface` |
| `box-shadow` | `inset 0 0 0 1px rgba(255,255,255,0.08)` | `--adm-shadow-edge` |
| `padding` | `22px` | — |
| `box-shadow` | `inset 0 0 0 1px rgba(232,85,109,0.35), 0 24px 60px rgba(0,0,0,0.5)` | — |
| `padding` | `24px` | `--adm-space-12` |
| `border-radius` | `20px` | `--adm-radius-2xl` |
| `background` | `#16161a` | `--adm-color-bg-raised` |
| `box-shadow` | `inset 0 0 0 1px rgba(232,85,109,0.35), 0 30px 70px rgba(0,0,0,0.6)` | — |
| `box-shadow` | `inset 0 0 0 1px rgba(224,160,48,0.4), 0 24px 60px rgba(0,0,0,0.5)` | — |

### Menu item

**Purpose.** Row inside a menu.

**Observed in.** Control_Center ×17 · Ecosystem ×17 · Operations ×17 · People ×17 · Settings ×17 · Trust ×17

| property | value | token |
|---|---|---|
| `gap` | `11px` | — |
| `min-height` | `44px` | `--adm-size-control` |
| `padding` | `0 12px` | — |
| `border-radius` | `10px` | `--adm-radius-md` |
| `color` | `#d0ccd6` | `--adm-color-text-secondary` |
| `font-size` | `14px` | `--adm-type-body-size` |

### Region

**Purpose.** Labelled landmark region.

**Observed in.** Settings ×3

| property | value | token |
|---|---|---|
| `border-radius` | `16px` | `--adm-radius-xl` |
| `background` | `#121215` | `--adm-color-bg-surface` |
| `box-shadow` | `inset 0 0 0 1px rgba(255,255,255,0.08)` | `--adm-shadow-edge` |
| `padding` | `12px 16px` | — |
| `gap` | `12px` | `--adm-space-6` |
| `box-shadow` | `inset 0 0 0 1px rgba(224,160,48,0.4)` | — |


## Data

### Table

**Purpose.** Sticky header, row actions.

**Observed in.** Ecosystem ×9 · Operations ×9 · People ×4 · Settings ×12 · Trust ×11

| property | value | token |
|---|---|---|
| `width` | `100%` | — |
| `font-size` | `13.5px` | `--adm-type-small-size` |
| `font-size` | `14px` | `--adm-type-body-size` |

### Stat tile

**Purpose.** Metric readout tile.

**Observed in.** Control_Center ×5

| property | value | token |
|---|---|---|
| `grid-template-columns` | `4px 1fr auto` | — |
| `gap` | `14px` | `--adm-space-7` |
| `padding` | `14px 0` | — |
| `box-shadow` | `inset 0 -1px 0 rgba(255,255,255,0.05)` | — |

### Chart

**Purpose.** Sparkline / bar / line.

**Observed in.** Control_Center ×1 · Ecosystem ×3

| property | value | token |
|---|---|---|
| `width` | `100%` | — |
| `height` | `160px` | — |
| `height` | `290px` | — |

### Severity badge

**Purpose.** Critical / High / Warning / Informational.

**Observed in.** Control_Center ×3 · Ecosystem ×4

| property | value | token |
|---|---|---|
| `font-weight` | `600` | `--adm-font-weight-semibold` |
| `letter-spacing` | `0.08em` | — |
| `font-size` | `11.5px` | — |
| `color` | `#f08a9b` | — |
| `color` | `#f0c060` | `--adm-color-status-warning-text` |
| `color` | `#b8b3c0` | — |

### Status pill

**Purpose.** Pill-shaped state label.

**Observed in.** Control_Center ×27 · Ecosystem ×68 · Operations ×94 · People ×36 · Settings ×113 · Trust ×113

| property | value | token |
|---|---|---|
| `border-radius` | `999px` | `--adm-radius-pill` |
| `font-weight` | `500` | `--adm-font-weight-medium` |
| `padding` | `4px 10px` | — |
| `font-size` | `12px` | `--adm-type-caption-size` |
| `gap` | `5px` | — |
| `background` | `rgba(47,191,135,0.14)` | `--adm-color-status-success-tint` |
| `color` | `#2fbf87` | `--adm-color-status-success` |
| `font-size` | `12.5px` | — |
| `gap` | `6px` | `--adm-space-3` |
| `color` | `#9b96a3` | `--adm-color-text-muted` |
| `background` | `rgba(224,160,48,0.14)` | `--adm-color-status-warning-tint` |
| `color` | `#e0a030` | `--adm-color-status-warning` |

### Progress bar

**Purpose.** Proportional fill.

**Observed in.** Control_Center ×1

| property | value | token |
|---|---|---|
| `width` | `390px` | — |
| `height` | `380px` | — |

### Tab

**Purpose.** Segmented/tab control button.

**Observed in.** Control_Center ×8 · People ×47

| property | value | token |
|---|---|---|
| `border` | `0` | — |
| `background` | `none` | — |
| `min-height` | `44px` | `--adm-size-control` |
| `color` | `#9b96a3` | `--adm-color-text-muted` |
| `padding` | `0 14px` | — |
| `font-size` | `13.5px` | `--adm-type-small-size` |
| `box-shadow` | `none` | — |
| `border-radius` | `999px` | `--adm-radius-pill` |
| `padding` | `0 18px` | — |
| `font-size` | `14.5px` | `--adm-type-nav-size` |
| `min-height` | `52px` | `--adm-size-row-list` |
| `padding` | `0 24px` | — |


## Inputs

### Text input

**Purpose.** Single-line text.

**Observed in.** Settings ×10

| property | value | token |
|---|---|---|
| `width` | `100%` | — |
| `min-height` | `44px` | `--adm-size-control` |
| `padding` | `0 14px` | — |
| `border` | `0` | — |
| `border-radius` | `10px` | `--adm-radius-md` |
| `background` | `#1b1b20` | `--adm-color-bg-hover` |
| `box-shadow` | `inset 0 0 0 1px rgba(255,255,255,0.1)` | — |
| `color` | `#f4f3f6` | `--adm-color-text-primary` |
| `font-size` | `14px` | `--adm-type-body-size` |
| `box-shadow` | `inset 0 0 0 1px rgba(224,160,48,0.55)` | — |

### Select

**Purpose.** Native select.

**Observed in.** Settings ×27

| property | value | token |
|---|---|---|
| `width` | `100%` | — |
| `min-height` | `44px` | `--adm-size-control` |
| `padding` | `0 14px` | — |
| `border` | `0` | — |
| `border-radius` | `10px` | `--adm-radius-md` |
| `background` | `#1b1b20` | `--adm-color-bg-hover` |
| `box-shadow` | `inset 0 0 0 1px rgba(255,255,255,0.1)` | — |
| `color` | `#f4f3f6` | `--adm-color-text-primary` |
| `font-size` | `14px` | `--adm-type-body-size` |

### Segmented control

**Purpose.** Tablist wrapper (Today / 7 / 30 / 90 days).

**Observed in.** Control_Center ×2 · People ×4

| property | value | token |
|---|---|---|
| `gap` | `2px` | `--adm-space-1` |
| `box-shadow` | `inset 0 -1px 0 rgba(255,255,255,0.07)` | `--adm-shadow-header` |
| `padding` | `4px` | `--adm-space-2` |
| `border-radius` | `999px` | `--adm-radius-pill` |
| `box-shadow` | `inset 0 0 0 1px rgba(255,255,255,0.1)` | — |

### Switch

**Purpose.** role="switch", aria-checked.

**Observed in.** Settings ×20

| property | value | token |
|---|---|---|
| `width` | `52px` | `--adm-size-row-list` |
| `height` | `44px` | `--adm-size-control` |
| `border` | `0` | — |
| `background` | `none` | — |
| `padding` | `0` | — |

### Checkbox

**Purpose.** Native checkbox.

**Observed in.** Settings ×86

| property | value | token |
|---|---|---|
| `width` | `20px` | — |
| `height` | `20px` | — |


## Feedback

### Degraded banner

**Purpose.** Amber system-state banner.

**Observed in.** Control_Center ×1 · Ecosystem ×1 · Operations ×1 · People ×1 · Settings ×1 · Trust ×1

| property | value | token |
|---|---|---|
| `gap` | `10px` | `--adm-space-5` |
| `min-height` | `34px` | `--adm-size-env-strip` |
| `padding` | `0 16px` | — |
| `background` | `#e0a030` | `--adm-color-status-warning` |
| `color` | `#0a0a0b` | `--adm-color-bg-canvas` |
| `font-size` | `13px` | — |
| `font-weight` | `500` | `--adm-font-weight-medium` |

### Empty state

**Purpose.** No-content state.

**Observed in.** Control_Center ×3 · Ecosystem ×3 · Operations ×3 · People ×2 · Settings ×1 · Trust ×7

| property | value | token |
|---|---|---|
| `color` | `#9b96a3` | `--adm-color-text-muted` |
| `font-size` | `13px` | — |
| `line-height` | `1.5` | `--adm-type-body-line` |
| `color` | `#8b8595` | `--adm-color-text-subtle` |
| `font-size` | `13.5px` | `--adm-type-small-size` |
| `font-size` | `15px` | — |
| `color` | `#d0ccd6` | `--adm-color-text-secondary` |
| `font-size` | `12.5px` | — |
| `font-weight` | `500` | `--adm-font-weight-medium` |
| `color` | `#f4f3f6` | `--adm-color-text-primary` |
| `font-size` | `12px` | `--adm-type-caption-size` |
| `padding` | `12px 14px` | — |

---

## G · GAPS — recorded, not filled

These are **design decisions still owed**, not omissions in this document. Each is a thing the approved
package does not establish, and inventing any of them would be creating product behaviour.

| # | gap | evidence |
|---|---|---|
| G-1 | **Radio** — named in `COMPONENTS.md`, appears in **no** approved page | probed for `type="radio"` and `role="radio"`: zero occurrences across all six pages |
| G-2 | **Toast** — named in `COMPONENTS.md`, appears in **no** approved page | probed for `role="alert"` and `toast`: zero occurrences. A static page export may simply not capture a transient control; the gap is recorded rather than assumed either way |
| G-3 | **Timeline** — present as activity lists, but no distinct timeline component is separable from the generic list markup | `role="list"` carries no timeline-specific styling |
| G-4 | **Per-component variant matrices** — the pages show each component in the states they happen to use. A component's *full* variant set (every size, every emphasis) is not enumerated anywhere | the package specifies "interactive behaviour is in the page files"; observed ≠ exhaustive |
| G-5 | **Phone layout below 480px** | `RESPONSIVE.md` states it "has **not** been separately designed for Admin (Admin is an operator tool); recorded as a gap" — the package's own words |
| G-6 | **Literal values with no token** | every `—` in the token column above. The pages use values the 126-token set does not name; whether those become tokens is a design-system decision |

## H · WHAT THIS DOCUMENT DOES NOT DO

It does not redesign the Admin system, replace the shipped token system, introduce a competing component
library, or define any product behaviour. It records what the approved package already specifies, in the
per-component form `COMPONENTS.md` asked for and did not contain.
