# ADMIN CAPABILITY MATRIX — DESIGN-AUTHORITY INPUT REQUEST

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


**This is a request for data, not a design question.** Engineering has implemented the mechanism and
cannot proceed without the values. **Nothing here proposes, defaults or suggests a value.**

Companion to `ADMIN-CAPABILITY-MATRIX.json`, which records the recovery evidence and is **not** modified
by this request. Governing records: V5 §113 (specification) · §115 (vocabulary) · §116 (recovery proof).

---

## 1 · Why engineering cannot derive this

The approved Settings design establishes three **role-level labels**:

> **`Trust lead → Full`** · **`Support → Limited`** · **`Viewer → Read-only`**
> *(`Operations lead` and `Content editor` carry no level in the artifact.)*

**Those labels establish a role's LEVEL. They do not establish its area × verb grant set.**

- *"Full"* does not say **which** of the 17 areas.
- *"Limited"* does not say **which** of the 5 verbs, nor in which areas.
- *"Read-only"* does not say which areas are readable, nor whether "read" means `View` alone.

**Expanding three adjectives into 425 grant decisions is not implementation logic — it is authorization
policy.** Engineering inventing it would be inventing permissions. **This is design-authority data.**

---

## 2 · What was recovered, and what is genuinely absent

**The grid exists in the approved artifact. Its cells are empty — and they were never authored.**
Proven, not assumed (V5 §116):

| check | result |
|---|---|
| Static cells, re-parsed with a real **HTML parser** | **all 85 empty** |
| The page's only inline script | **`renderVals() { return {}; }`** — supplies no values by construction |
| Same empty `renderVals` | in **all five** `Pages - *.dc.html` |
| `ph-check` / `ph-minus-circle` / `ph-dot-outline` | present, but bound to **status pills elsewhere**, not to cells |
| `support.js` | **zero** hits for any role, verb or capability term |
| **Nocturne `_ds_bundle.js`** — recovered and read in full | **`"components":[]`** — declares nothing, holds no data |
| Repository-wide search | nothing beyond the V5 records of this question |

**The Nocturne bundle was obtained and inspected. It would not have helped.**

---

## 3 · Known vs unknown

**KNOWN — do not re-supply:**

- the **17 areas** in 4 groups and the **5 verbs** (§115, recovered from the approved page);
- the **five Admin roles** (`Trust lead`, `Operations lead`, `Support`, `Content editor`, `Viewer`);
- the three role-level labels above;
- the existing **seven database roles**, unchanged;
- the graded architecture — migration **153**, `admin_role_assignments` → `is_admin_member()` →
  `admin_can(area, verb)` → Admin RLS — **deny-by-default, 0 capability rows seeded**;
- **no Admin-surface policy** consumes `admin_can()` yet; **`CONF-D8` is open.**

**UNKNOWN — this request:** the grant for **every role × area × verb** combination.

---

## 4 · One model question that must be answered with the data

The approved artifact uses **three** state icons — `check`, `minus-circle`, `dot-outline`. Migration 153
currently models a grant as **binary**: a row in `admin_role_capabilities` means granted; its absence
means denied.

> **Is the vocabulary BINARY (granted / not granted), or TRI-STATE (e.g. granted / denied / conditional)?**

**If tri-state, say what the third state means.** A conditional grant is not expressible as a row's
presence and would require a schema change before seeding. **Engineering will not guess which.**

---

## 5 · The matrix to return

**85 rows (17 areas × 5 verbs). Each row needs a value for each of the five roles — 425 values.**
Use `Y` for granted and `N` for not granted, or the tri-state vocabulary from §4 if that is the answer.

| # | Group | Area | Verb | Trust lead | Operations lead | Support | Content editor | Viewer |
|---|---|---|---|---|---|---|---|---|
|  1 | Ecosystem | Community | View | | | | | |
|  2 | Ecosystem | Community | Create | | | | | |
|  3 | Ecosystem | Community | Update | | | | | |
|  4 | Ecosystem | Community | Manage | | | | | |
|  5 | Ecosystem | Community | Approve | | | | | |
|  6 | Ecosystem | Events | View | | | | | |
|  7 | Ecosystem | Events | Create | | | | | |
|  8 | Ecosystem | Events | Update | | | | | |
|  9 | Ecosystem | Events | Manage | | | | | |
| 10 | Ecosystem | Events | Approve | | | | | |
| 11 | Ecosystem | Training | View | | | | | |
| 12 | Ecosystem | Training | Create | | | | | |
| 13 | Ecosystem | Training | Update | | | | | |
| 14 | Ecosystem | Training | Manage | | | | | |
| 15 | Ecosystem | Training | Approve | | | | | |
| 16 | Ecosystem | Monetization | View | | | | | |
| 17 | Ecosystem | Monetization | Create | | | | | |
| 18 | Ecosystem | Monetization | Update | | | | | |
| 19 | Ecosystem | Monetization | Manage | | | | | |
| 20 | Ecosystem | Monetization | Approve | | | | | |
| 21 | Ecosystem | Wearable intelligence | View | | | | | |
| 22 | Ecosystem | Wearable intelligence | Create | | | | | |
| 23 | Ecosystem | Wearable intelligence | Update | | | | | |
| 24 | Ecosystem | Wearable intelligence | Manage | | | | | |
| 25 | Ecosystem | Wearable intelligence | Approve | | | | | |
| 26 | Trust | AI Guardian | View | | | | | |
| 27 | Trust | AI Guardian | Create | | | | | |
| 28 | Trust | AI Guardian | Update | | | | | |
| 29 | Trust | AI Guardian | Manage | | | | | |
| 30 | Trust | AI Guardian | Approve | | | | | |
| 31 | Trust | Security | View | | | | | |
| 32 | Trust | Security | Create | | | | | |
| 33 | Trust | Security | Update | | | | | |
| 34 | Trust | Security | Manage | | | | | |
| 35 | Trust | Security | Approve | | | | | |
| 36 | Trust | Incidents | View | | | | | |
| 37 | Trust | Incidents | Create | | | | | |
| 38 | Trust | Incidents | Update | | | | | |
| 39 | Trust | Incidents | Manage | | | | | |
| 40 | Trust | Incidents | Approve | | | | | |
| 41 | Trust | Audit logs | View | | | | | |
| 42 | Trust | Audit logs | Create | | | | | |
| 43 | Trust | Audit logs | Update | | | | | |
| 44 | Trust | Audit logs | Manage | | | | | |
| 45 | Trust | Audit logs | Approve | | | | | |
| 46 | Operations | QA | View | | | | | |
| 47 | Operations | QA | Create | | | | | |
| 48 | Operations | QA | Update | | | | | |
| 49 | Operations | QA | Manage | | | | | |
| 50 | Operations | QA | Approve | | | | | |
| 51 | Operations | Releases | View | | | | | |
| 52 | Operations | Releases | Create | | | | | |
| 53 | Operations | Releases | Update | | | | | |
| 54 | Operations | Releases | Manage | | | | | |
| 55 | Operations | Releases | Approve | | | | | |
| 56 | Operations | Integrations | View | | | | | |
| 57 | Operations | Integrations | Create | | | | | |
| 58 | Operations | Integrations | Update | | | | | |
| 59 | Operations | Integrations | Manage | | | | | |
| 60 | Operations | Integrations | Approve | | | | | |
| 61 | Operations | System | View | | | | | |
| 62 | Operations | System | Create | | | | | |
| 63 | Operations | System | Update | | | | | |
| 64 | Operations | System | Manage | | | | | |
| 65 | Operations | System | Approve | | | | | |
| 66 | Settings | Organization | View | | | | | |
| 67 | Settings | Organization | Create | | | | | |
| 68 | Settings | Organization | Update | | | | | |
| 69 | Settings | Organization | Manage | | | | | |
| 70 | Settings | Organization | Approve | | | | | |
| 71 | Settings | Users | View | | | | | |
| 72 | Settings | Users | Create | | | | | |
| 73 | Settings | Users | Update | | | | | |
| 74 | Settings | Users | Manage | | | | | |
| 75 | Settings | Users | Approve | | | | | |
| 76 | Settings | Roles | View | | | | | |
| 77 | Settings | Roles | Create | | | | | |
| 78 | Settings | Roles | Update | | | | | |
| 79 | Settings | Roles | Manage | | | | | |
| 80 | Settings | Roles | Approve | | | | | |
| 81 | Settings | Configuration | View | | | | | |
| 82 | Settings | Configuration | Create | | | | | |
| 83 | Settings | Configuration | Update | | | | | |
| 84 | Settings | Configuration | Manage | | | | | |
| 85 | Settings | Configuration | Approve | | | | | |

---

## 6 · Returning it — schema, and the validator that will check it

**Return `docs/design/admin-dashboard/ADMIN-CAPABILITY-MATRIX.json` in this shape** (the owner-specified
schema; it replaces the flat shape an earlier draft of this request proposed):

```json
{ "version": "1.0",
  "authority": "<who designated this as the authoritative Admin authorization model>",
  "areas": [
    { "group": "Ecosystem", "area": "Community",
      "verbs": [
        { "verb": "View",
          "grants": { "trust_lead": true, "operations_lead": false, "support": true,
                      "content_editor": true, "viewer": true } }
      ] }
  ] }
```

**17 areas × 5 verbs = 85 cells, each with all five roles = 425 explicit values.** Area, verb and role
names exactly as in §3; a name outside that vocabulary is reported, never interpreted.

**A cell may be left undecided rather than guessed.** Use
`{ "unresolved": true, "reason": "…" }` in place of `true`/`false`. **An unresolved grant is NOT seeded**
— absent a capability row `admin_can()` denies, which is the safe reading of "undecided", and the reason
is carried into the record.

**The response is checked mechanically before anything is seeded:**

```
node supabase/scripts/validate-admin-capability-matrix.mjs [path]
```

It verifies the 17 areas and their groups, the 5 verbs, 85 unique cells with none missing or duplicated,
all five roles per cell, strictly binary grants (or a reasoned unresolved marker), no unknown
area/verb/role, and that an `authority` is named. **It reports every defect with its exact cell and
exits non-zero; nothing is seeded until it passes.** Validated against 12 cases including a well-formed
85×5 matrix, each defect class, and both unresolved forms.

---

## 7 · What this unblocks

Seeding `admin_role_capabilities` · every Admin-surface RLS policy consuming `admin_can()` ·
**`CONF-D8`** (`Full`/`Limited`/`Read-only` enforceable at the data layer rather than in the UI) ·
the Admin screens of **P5** · the Settings feature registry's authorization · `CAP-1`'s moderation
authorization.

**Until it is supplied, `admin_can()` returns false for every caller — which is the safe state, not a
broken one.**
