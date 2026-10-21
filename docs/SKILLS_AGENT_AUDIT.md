# 12 Circle Fitness — Skills / Agent Ecosystem Forensic Audit

**Mode:** read-only discovery. **Mutations:** none. No skill, agent, config or repo file was
created, modified, renamed, activated or deleted. This report is the only file written.

**Date:** 2026-09-23 · **Repo:** `12circle-fitness` · **Branch:** `chore/qa-environments-secure-ai-backend`
**Method:** nine parallel investigations (discovery, configuration, QA, development/architecture,
design, delegation, invocation forensics, dormancy, conflict), reconciled against the working tree.

Every claim below is marked **VERIFIED** (a definition, config or log was read), **INFERRED**
(reasoned from verified facts), or **REFERENCED-BUT-NOT-FOUND**. Nothing is carried on the
authority of conversation history, documentation, a README, a prior QA report, or a filename.

---

## 1. Executive Summary

**There are two agent systems for this project. They have never been connected, and neither is
governing the work.**

| | System 1 — Cowork Agent Registry | System 2 — Claude Skills |
|---|---|---|
| Location | `docs/COWORK_AGENT_REGISTRY.md` (in repo) | `~/.claude/skills/synced/<bucket>/` (global) |
| Roles | AG-00 … AG-13 (14 roles) | 36 skills, 21 of them `12circle-*` |
| Product fit | **Correct** — workouts, women's health, PAR-Q, Stripe, Supabase, `apps/mobile` | **Wrong** — residents, providers, bookings, Portal, public website |
| Executable? | **No.** Prose role charters; no runtime binding | **Yes.** Invocable via the Skill tool |
| Actually used? | **No.** `AG-xx` appears in **1 file — itself** | **No, not here.** 0 invocations for fitness |

**The three findings that matter:**

1. **The dedicated QA Skill Agent exists, works, and has never once run on this project.**
   `10-12circle-qa-engineer` shows **0 invocations and 0 attributed tool calls across 37
   12circle-fitness sessions**. The same skill shows **3 invocations and 147 attributed tool
   calls in the sibling repo `12circle-communities`**. It is installed correctly and is driving a
   different product. Bypass rate on this project: **100%**. (VERIFIED — §4, §14)

2. **The skills describe a different product, and six of them actively prohibit this one.**
   `01-development-standards` forbids agents from *"turn[ing] 12Circle into a fitness app."*
   `12circle-source-of-truth` states *"Fitness/wellness is a category… not the product identity."*
   `03-product-design-gatekeeper` lists **"fitness-first framing"** as a reportable defect and
   `12circle-visual-critic` lists **"fitness-only framing"** as grounds for REJECT. Against a repo
   named `12circle-fitness` whose `pubspec.yaml` reads *"Complete Fitness & Wellness Platform"*.
   Had these skills been invoked as designed, they would have blocked the product. (VERIFIED — §7, §11)

3. **No skill declares a single tool permission, and no configuration gates anything.**
   All 36 skills carry two-field frontmatter (`name`, `description`). Zero `allowed-tools`. Every
   skill therefore **inherits the full toolset of the calling session**. There is no `deny` or
   `ask` rule in any settings file on this machine, `defaultMode` is `auto`, and the untracked
   `settings.local.json` grants `Bash(git push:*)`. Every constraint in every skill is prose an
   agent may ignore. (VERIFIED — §9)

**The net effect:** all 12Circle Fitness QA, security and design work in the audit window was
produced by **ungoverned general Claude reasoning** — assisted by 11 stock `Explore` subagents
that carry no 12Circle contract, definition of done, or escalation rule.

**Mitigating fact, stated fairly:** the ungoverned work was not low quality. The repo's own
`docs/QA_CLOSURE_STANDARD.md` five-state evidence ladder is markedly more rigorous than anything
in the skill set. The governance this project actually runs on lives in `docs/`, was written in
prose, and is enforced by discipline rather than by tooling.

---

## 2. Verified Agent / Skill Inventory

**Reachable definitions: 37.** 36 in the synced bucket + `frontend-design`. (VERIFIED)

> 227 `SKILL.md` files exist on disk machine-wide, but only these 37 plus the vercel plugin are
> reachable. The remaining ~190 are **inert marketplace catalog clones** from an uninstalled
> marketplace — they carry rich `tools:`/`model:` grants but are not installed and cannot run.
> Only one plugin is installed: `vercel@0.49.2`.

**Bucket:** `~/.claude/skills/synced/51c8f154-f2bf-482e-9c2b-fb4d165ce48f_ccd8df34-6806-41c0-8bd0-89548ca9f524/`

| # | Skill | Bytes | Family | Status |
|---|---|---|---|---|
| 1 | `01-12circle-development-standards` | 2496 | 12C governance | CONFLICTS WITH PRODUCT |
| 2 | `02-12circle-engineering-lead` | 1785 | 12C orchestration | DORMANT |
| 3 | `03-12circle-product-design-gatekeeper` | 1320 | 12C design | CONFLICTS WITH PRODUCT |
| 4 | `04-12circle-web-engineer` | 1292 | 12C dev | **ORPHANED** |
| 5 | `05-12circle-portal-engineer` | 1283 | 12C dev | **ORPHANED** |
| — | **`06-*` — MISSING** | — | — | **REFERENCED-BUT-NOT-FOUND** |
| 6 | `07-12circle-design-system-engineer` | 1175 | 12C design | ORPHANED |
| 7 | `08-12circle-backend-engineer` | 1240 | 12C dev | PARTIALLY APPLICABLE |
| 8 | `09-12circle-database-engineer` | 1118 | 12C data | APPLICABLE / **HIGHEST RISK** |
| 9 | `10-12circle-qa-engineer` | 1074 | 12C QA | **DORMANT — never invoked here** |
| 10 | `11-12circle-visual-fidelity-engineer` | 1118 | 12C QA | ORPHANED |
| 11 | `12-12circle-security-engineer` | 1069 | 12C security | DORMANT |
| 12 | `13-12circle-devops-release-engineer` | 950 | 12C release | DORMANT |
| 13 | `14-12circle-performance-engineer` | 1151 | 12C perf | DORMANT |
| 14 | `12circle-agent-handoff` | 959 | 12C process | DORMANT (1 use ever, global) |
| 15 | `12circle-source-of-truth` | 1482 | 12C governance | CONFLICTS WITH PRODUCT |
| 16 | `12circle-creative-director` | 2819 | 12C design | ORPHANED + CONFLICTS |
| 17 | `12circle-design-orchestrator` | 3251 | 12C design | ORPHANED + CONFLICTS |
| 18 | `12circle-design-to-code` | **34051** | 12C design | ORPHANED + WRONG STACK |
| 19 | `12circle-figma-product-design` | 2206 | 12C design | ORPHANED + CONFLICTS |
| 20 | `12circle-motion-interaction` | 2341 | 12C design | ORPHANED |
| 21 | `12circle-visual-critic` | 1904 | 12C design | ORPHANED + CONFLICTS |
| 22–27 | `aiwos-*` (6 skills) | 6086–9617 | AIWOS | **OBSOLETE HERE** (different product) |
| 28–36 | `docs`, `docx`, `xlsx`, `pptx`, `pdf`, `morning`, `import-memory`, `skill-creator`, `tax-preparation` | — | Anthropic stock | ACTIVE (general purpose) |
| 37 | `frontend-design` (outside bucket) | — | Anthropic stock | DORMANT + CONTRADICTS 01 |

**Size signal (INFERRED):** the 13 numbered role skills average **~1.2 KB / ~30 lines**. They are
one-page role charters, not operational playbooks. The single substantial skill,
`12circle-design-to-code` at 34 KB / 1,644 lines, is 28× the size of the QA skill.

### 2.1 In-repo role definitions — `docs/COWORK_AGENT_REGISTRY.md` (VERIFIED)

14 roles, 5 authority levels (L0 Observer → L4 Human Product Owner), a pairing/review matrix, a
startup protocol and a completion protocol. **Product-correct**: scopes cite real paths
(`supabase/migrations/**`, `apps/mobile/lib/features/workout/**`, `apps/mobile/lib/features/womens_health/**`).

AG-00 Lead Architect · AG-01 Security · AG-02 Database · AG-03 Error Contract · AG-04 AI ·
AG-05 Billing · AG-06 Product Journey · AG-07 Release · AG-08 QA · AG-09 Workout Domain ·
AG-10 Women's Health · AG-11 UI (marked *"NOT ACTIVE for implementation"*) · AG-12 Wearables
(roadmap) · AG-13 Specialist Training Agents (roadmap).

**These are role charters, not executable agents.** The registry itself says *"Cowork agents may
be instantiated as separate sessions/workers."* There is no runtime binding, no `.claude/agents/`
entry, and no hook. Committed once (`9319c67`, 2026-08-24) and never referenced again.

---

## 3. Complete Agent Registry

### 3.1 What does NOT exist (VERIFIED by exhaustive search)

| Searched for | Result |
|---|---|
| Project `.claude/skills/` | **DOES NOT EXIST** |
| Project `.claude/agents/` | **DOES NOT EXIST** |
| Project `.claude/commands/` | **DOES NOT EXIST** |
| Project `.claude/hooks/` | **DOES NOT EXIST** |
| Project `CLAUDE.md` (any depth) | **DOES NOT EXIST** — zero results |
| `AGENTS.md` | DOES NOT EXIST |
| Global `~/.claude/agents/` or `commands/` | DOES NOT EXIST |
| Agent/skill definitions committed in repo | **ZERO** — no repo `.md` has frontmatter |
| Claude automation in CI (`.github/`) | **NONE** — only `ci.yml` + `supabase-keepalive.yml` |
| MCP servers for this project | `mcpServers: {}` — none |
| Any skill slug referenced anywhere in repo | **ZERO hits** |
| `06-*` skill, any location | **DOES NOT EXIST** |
| Mobile / Flutter / Android skill | **DOES NOT EXIST** |
| Dormant definitions in `.staging` / `.trash` | **BOTH EMPTY** (full resync 2026-09-19 22:05) |

The project `.claude/` directory contains exactly two files: `settings.json` and `settings.local.json`.

### 3.2 The manifest is not a capability registry (VERIFIED)

`$BUCKET/manifest.json` is in perfect sync — 36 entries ↔ 36 directories, empty set-difference
both ways. Its schema is exhaustively `skillId | name | description | source | updatedAt |
backingPluginId`. **There is no `enabled`, `required`, `mandatory`, `trigger`, `hook` or
dependency field — the manifest physically cannot express gating or delegation.**

### 3.3 Hooks — the only executing ones (VERIFIED)

None come from user or project config. All five ship with the vercel plugin:

- `SessionStart` → `session-start-seen-skills.mjs`, `session-start-profiler.mjs`, `inject-claude-md.mjs`
- `PostToolUse` matcher `"Skill"` → `posttooluse-skill-telemetry.mjs` — **observes only; blocks nothing**
- `SessionEnd` → `session-end-cleanup.mjs`

**No `PreToolUse`, `UserPromptSubmit` or `Stop` hook exists anywhere on this machine.** Nothing can
block, force or redirect a tool call in this project.

> ⚠️ The plugin ships **24 hook scripts but registers only 5**. The 19 unregistered include
> `pretooluse-skill-inject.mjs` and `user-prompt-submit-skill-inject.mjs` — dormant skill-injection
> paths, one JSON edit away from firing. Not currently active. (VERIFIED)

---

## 4. QA Agent Deep Audit — the special investigation

### 4.1 Does it exist? Yes — as a 27-line advisory document

`10-12circle-qa-engineer/SKILL.md`, **1,074 bytes, 27 lines**, two frontmatter keys, **zero
supporting files** (no `references/`, `scripts/`, `agents/`, checklists or templates). Exactly one
copy on disk. No richer definition is hiding anywhere. (VERIFIED)

### 4.2 The twelve questions, answered from the definition

| # | Question | Answer |
|---|---|---|
| 1 | What QA work does it own? | Mission *"Prove that implemented functionality works and remains stable."* Five test layers; 12 critical journeys — *onboarding, authentication, **community discovery**, **experience discovery**, **booking**, confirmation, **upcoming bookings**, **guest participation**, messaging, notifications, profile, **connected communities***. **Every domain-specific journey belongs to the Communities product.** |
| 2 | Autonomous? Delegates? | **No.** "sub-agent", "delegate", "spawn", "dispatch" appear **zero times**. One role hand-off with no mechanism: *"Hand visual findings to the Visual Fidelity Engineer."* |
| 3 | Phases governed? | **NOT SPECIFIED.** The word "phase" is absent. The five layers are a menu, not a lifecycle. No entry/exit criteria. |
| 4 | Evidence required? | A 7-field bug schema — but *"**should** include"*, not must, and `evidence` is an undefined field name. **No closure criteria.** |
| 5 | Gates controlled? | **NONE.** "gate", "block", "merge", "approve", "sign-off", "veto" appear **zero times** in the body. |
| 6 | Can it modify code? | **NOT SPECIFIED.** Only a negative, and it sits in the description not the body: *"Do not redesign UI or approve visual deviations."* |
| 7 | Can it verify fixes? | **NOT SPECIFIED — the word "verify" does not appear.** Conspicuous: all three sibling skills have one (visual-fidelity *"Re-render and verify"*; performance *"Record before/after measurements"*; devops *"Do not declare success because deployment completed. Verify the running application."*). The skill whose mission is proof is the only one without a verification clause. |
| 8 | Android emulator workflow? | **ABSENT — definitively.** `emulator\|android\|adb\|xcode\|simulator\|device` across **all 36 bucket skills** returns **zero hits**. It claims E2E coverage of mobile journeys with no mechanism to run anything. |
| 9 | Controls final QA closure? | **NO.** No sign-off, no verdict owner. |
| 10 | `allowed-tools`? | **ABSENT** → inherits **ALL** session tools. Nothing technically stops it editing production code, running migrations, or pushing. |
| 11 | References other skills? | Exactly one, by role title not slug: *"the Visual Fidelity Engineer."* Not Security, Performance, DevOps, Engineering Lead, or the handoff skill. |
| 12 | Anchored to source-of-truth / standards? | **NO, neither.** Zero occurrences of "source of truth" or "standards". Fully unanchored. The dependency runs one way only: `01-standards` requires tests in its definition of done; QA neither knows nor enforces that. |

### 4.3 Is current QA work invoking it? — No. With numbers.

| Metric | 12circle-**fitness** | 12circle-**communities** |
|---|---|---|
| Sessions | **37** (2026-08-24 → 2026-09-23) | 11 |
| Total Skill invocations | **5** | 47 raw / 22 anchored |
| Any `*-12circle-*` skill | **0** | 22 |
| **`10-12circle-qa-engineer` invocations** | **0** | **3** |
| Tool calls with `attributionSkill` | 273 (`claude-api` 243, `artifact-design` 30) | 1,141 |
| …attributed to the QA skill | **0** | **147** |

The 5 fitness skill calls were `artifact-design` ×3 and `claude-api` ×2, all on 2026-08-24 — none
in the September working session.

**Method note (why these numbers are trustworthy):** two decoys were stripped. `"name":"Skill"`
also appears in every request's *tool-schema block*, and `anthropic-skills:<name>` also appears in
the system prompt's *available-skills listing* — each 12circle skill occurs exactly 9× in the
fitness corpus, matching 9 system-prompt copies, zero uses. Counting used anchored
`"name":"Skill","input":{"skill":"X"` plus `attributionSkill`.

### 4.4 What was doing the QA instead (VERIFIED)

Plain Claude reasoning in one long session (`d1740817`, Sep 9 → Sep 23, 28.7 MB), assisted by
**11 Agent calls, 100% stock `subagent_type:"Explore"`** — the generic read-only search agent,
which carries no 12Circle QA contract, no definition of done, no escalation rule. Slash commands
used: `/model` ×4, `/compact` ×1. **No `/code-review`, no `/security-review`.**

### 4.5 The sharpest fact

The skills were synced to disk **2026-09-19 22:05**. Only two fitness sessions ever had them
listed in the system prompt: this audit, and `d1740817` — which carried the listing **six separate
times** across Sep 19–23 resumes **and never called one**. The August sessions' zero is innocent
(the skills did not exist yet). `d1740817`'s zero is not.

### 4.6 No false provenance

`grep -rin 'qa-engineer' docs/` → **0 hits**. No fitness document claims a skill produced it.
`QA_EVIDENCE.md` cites *"per brief §19"* — a brief, not a skill. Nothing is falsely claiming skill
provenance; nothing establishes it either.

---

## 5. Development Agent Deep Audit

| Skill | Repo correspondence | Verdict |
|---|---|---|
| `04-web-engineer` | No website app. No `next.config`/`vite.config`/`astro.config` at any depth ≤4. The only "web" is `flutter build web` — the same Flutter app, not a site. | **ORPHANED** |
| `05-portal-engineer` | No Portal app. **"Resident Core" — its named central artifact — has zero hits in `apps/mobile/lib`.** `resident` appears repo-wide only in one registry doc and one test script. | **ORPHANED** |
| `08-backend-engineer` | Claims "communities, providers, offerings/experiences". `apps/api/src` is `ai`/`auth`/`config`/`users`. **Never mentions Supabase** — the actual backend (132 migrations, edge functions, three test suites). | PARTIALLY APPLICABLE |
| `09-database-engineer` | Applies. Sole migration authority. | APPLICABLE / **HIGHEST RISK** |
| `01-development-standards` | Claims to cover *"any 12Circle implementation work"*; **has no publication rule at all**. | CONFLICTS |
| `02-engineering-lead` | Assigns 11 ownership lanes mapping 1:1 onto bucket skills — **except "Mobile"**, which has no skill (`06` is missing). | DORMANT |

**The structural hole:** the repo is ~100% mobile. **Flutter/Dart/Android/emulator work is entirely
unowned** by any skill. "Flutter", "Dart", "pubspec", "Riverpod", "workout", "coach", "exercise",
"nutrition" appear **zero times across all 36 skills**. (VERIFIED)

**Commit/push silence:** the words commit, push, PR, branch and merge appear nowhere in skills 01,
04, 05, 08, 09 or `source-of-truth`. `02`'s "Merge discipline" section is about code-conflict
resolution, not version control. Combined with zero `allowed-tools`: **12Circle skills have
unbounded, unstated git authority.**

---

## 6. Security / Architecture Agent Audit

**`12-12circle-security-engineer`** authorizes offensive testing in prose — *"Attempt unauthorized
cross-community access, object ID manipulation, privilege escalation, replay/stale-session
behavior, malformed input, and excessive request patterns"* — with **no environment restriction and
no approval gate**. Given that `supabase db dump --linked` reaches live QA, this is the sharpest
risk surface in the skill set. (VERIFIED)

**`09-12circle-database-engineer`** is the highest-risk skill overall: the only one granted
migration execution and DB access, with full inherited tools, and a sole safety clause qualified
three ways — *"Never run **destructive production** migrations without an **explicit release
gate**."* Non-destructive production changes, all QA/staging work, and a "gate" with no named human
are each left unguarded. It never says Supabase, RLS, policy or Postgres.

**`13-devops-release-engineer`** holds the strongest gate language of the six QA-family skills
(owns the CI gate set) but specifies **no human approval step before production**.

**The AIWOS irony (VERIFIED).** The six `aiwos-*` skills belong to a third product — `grep -ri aiwos`
over the repo returns **NONE**, and all 23 paths they cite are missing, including
`.claude/hooks/aiwos-guard.mjs`, which they repeatedly describe as *"the deterministic one"* that
actually enforces their rules. Yet AIWOS is the **only** family in the entire bucket that defines
publication authority: `commit ─╳→ push ─╳→ open draft PR ─╳→ merge (NOT DELEGABLE IN v1)`, with
commit and push gated on explicit packet booleans and merge refused unconditionally — *"The owner
merges, personally."* Every AIWOS skill ends *"This skill grants no authority."*

**That rigor is pointed at the wrong repository, while 12Circle Fitness's real governance corpus
has no skill representing it at all.**

---

## 7. Design / Product Agent Audit

Nine design skills. **None declares `allowed-tools`.** Only `12circle-design-to-code` executes.

**Product-framing drift — CONFIRMED AND SEVERE.** All nine frame the product as a
neighbourhood/communities platform; **six affirmatively prohibit fitness framing**:

- `01-development-standards`: agents *"MUST NOT… turn 12Circle into a fitness app"*
- `12circle-source-of-truth`: *"12Circle is a community platform. Fitness/wellness is a category within the ecosystem, not the product identity."*
- `12circle-creative-director`: *"Fitness is only one configuration. **Never let fitness define the platform.**"*
- `12circle-design-orchestrator`: *"No fitness-only product framing"*
- `12circle-figma-product-design`: *"Fitness terminology is allowed only as configured example content."*
- `03-gatekeeper` lists *"fitness-first framing"* as a defect; `12circle-visual-critic` lists *"fitness-only framing"* as grounds for REJECT.

**Consequence (INFERRED, and testable):** if an agent built the fitness UI that `~/.claude/CLAUDE.md`
mandates, `03-gatekeeper` would return **RED → "stop and escalate"**, `visual-critic` would
**REJECT**, and the orchestrator's stage-12 gate could **never close** — it requires sector
neutrality demonstrated across apartment / workplace / university / hotel / park.

**Aesthetic inversions, all pointing the same way:**

| `~/.claude/CLAUDE.md` mandate | Design skills prescribe |
|---|---|
| "Energetic/springy motion" | *"calm / architectural / restrained"*; avoid motion on **"numerical readouts"** |
| "Big legible metric readouts" | *"Do not replace this with a generic analytics dashboard"*; *"No excessive card usage"* |
| Apple Fitness+ / WHOOP / Oura / Strava feel | **Zero references** to any of these. Orchestrator: *"- No neon green."* |

**Stack drift — CONFIRMED.** `12circle-design-to-code` mandates the wrong stack twice — *"The future
mobile client is: **React Native + Expo**"* (§7) and *"When mobile work begins: use React Native +
Expo"* (§42) — into a Flutter repo. Compounding: §42 defers all mobile work *"until the web visual
system stabilizes"* — in a repo whose only client **is** the mobile app.

**Helix verdict.** Referenced in 2 of 10 design skills, substantively in 1. `design-to-code` §8
encodes the three-tier model correctly, but `helix-core`, `@helix/design-system`, the repo path,
the literal phrase "three-tier", and the five-dimension theme-bundle concept are all **ABSENT**.
The orchestrator **inverts the direction**: *"Figma → Helix → Product UI"*. Eight skills would
generate design work with no awareness Helix exists. Separately, `docs/MOBILE_QA_SWEEP_2026-09-22.md`
records that this app has **no Helix dependency at all** — `apps/mobile/lib/core/helix/` is an
unrelated in-repo Dart token system.

**Design authority in this repo is none of the above.** `docs/DESIGN_INTAKE_REPORT.md` establishes
it as an external ZIP handoff package with `FIT-001…FIT-110` identifiers and a `manifest.json` —
**not Figma**, and not any design skill.

---

## 8. Delegation Graph

**The slug graph is empty.** Across 21 12Circle skills there is **not one machine-resolvable
cross-skill reference**. All 16 slug-pattern matches are each skill's own `name:` frontmatter line.
(VERIFIED)

### Evidenced edges (the complete set)

```
12circle-design-orchestrator --[DELEGATES-TO]--> 12circle-creative-director       (:8, :31)
12circle-design-orchestrator --[DELEGATES-TO]--> 12circle-figma-product-design    (:8, :49)
12circle-design-orchestrator --[DELEGATES-TO]--> 12circle-motion-interaction      (:8, :60)
12circle-design-orchestrator --[DELEGATES-TO]--> 12circle-visual-critic           (:8, :70)
12circle-design-orchestrator --[REQUIRES-FIRST]-> 12circle-visual-critic          (:124)
10-12circle-qa-engineer      --[DELEGATES-TO]--> 11-visual-fidelity-engineer      (10-…:26)
12-12circle-security-engineer --[peer]--------->  08-backend, 09-database          (12-…:29)
12circle-source-of-truth     --[DEFERS-TO]----->  03-product-design-gatekeeper     (:29)
aiwos-pr-handoff             --[REQUIRES-FIRST]-> aiwos-evidence-run               (:32)
```

All four orchestrator edges are **by prose role name, not by skill slug** — no Skill-tool
invocation, no path. The one slug-form edge in the entire bucket is in the orphaned AIWOS cluster.

### Hierarchy as actually supported by evidence

```
    ??? "Lead Architect" — named 7x, NO SKILL FILE — ROOT ABSENT ???
          : (dangling)                        : (dangling)
 12circle-design-orchestrator          12circle-design-to-code (1,644 lines)
   |-- creative-director                 |-- absorbs creative / Figma / motion
   |-- figma-product-design              |-- STEP 5 = critique  (dup of visual-critic)
   |-- motion-interaction                |-- STEP 9 = visual QA (dup of 11-*)
   `-- visual-critic --REJECT--> loop    `-- references NO other skill
   `-- :109 "Production visual QA" --+
                                     +-- SAME ACTIVITY, 3 OWNERS, MUTUALLY UNAWARE
 11-visual-fidelity-engineer  -------+

 02-12circle-engineering-lead          [SEPARATE, UNCONNECTED TREE]
   `-- 11 lanes as BARE NOUNS, names zero skills; "Mobile" lane has no skill (06 missing)
   `-- 10-qa --> 11-visual-fidelity   [the only real edge in this tree]
   `-- ":56 Product/design ambiguity is escalated." --> TARGET NEVER NAMED

 source-of-truth / 01-development-standards / 12circle-agent-handoff   [FLOATING — 0 inbound]
```

**The dangling root is the bridge that was never built.** "Lead Architect" is referenced 7 times by
the skills and has no skill file — but it **is** defined, as **AG-00 Lead Architect / Orchestrator**
in `docs/COWORK_AGENT_REGISTRY.md`. The two systems share vocabulary and have zero linkage.

### Orphan nodes (VERIFIED)

- **Zero inbound (13 of 21):** 01, 02, 04, 05, 07, 10, 12, 13, 14, agent-handoff, source-of-truth, design-orchestrator, design-to-code
- **Zero outbound (17 of 21):** all but design-orchestrator, 10-qa, 12-security, source-of-truth
- **Fully isolated (11):** 01, 02, 04, 05, 07, 13, 14, agent-handoff, design-to-code, aiwos-worktree-guard, aiwos-governance-change, aiwos-architecture-response

The three skills written as *universal* contracts — `source-of-truth`, `01-development-standards`,
`12circle-agent-handoff` — have **0, 0 and 0 inbound references**, by slug or by prose.

---

## 9. Authority Matrix

**The critical column is the last one.** No skill declares any tool restriction, so *declared*
authority is prose and *effective* authority is total.

| Agent / Skill | Inspect | Modify | Test | Delegate | Commit | Push | Owner approval | **EFFECTIVE (enforced)** |
|---|---|---|---|---|---|---|---|---|
| `01-development-standards` | ✓ | unstated | requires | ✗ | **silent** | **silent** | none | **ALL TOOLS** |
| `02-engineering-lead` | ✓ | unstated | gate lang. | prose only | **silent** | **silent** | none | **ALL TOOLS** |
| `03-design-gatekeeper` | ✓ | ✗ (review only) | ✗ | escalates | ✗ | ✗ | RED→escalate | **ALL TOOLS** |
| `04-web-engineer` | ✓ | implied | unstated | ✗ | **silent** | **silent** | none | **ALL TOOLS** |
| `05-portal-engineer` | ✓ | implied | unstated | ✗ | **silent** | **silent** | none | **ALL TOOLS** |
| `07-design-system-eng` | ✓ | implied | unstated | ✗ | **silent** | **silent** | none | **ALL TOOLS** |
| `08-backend-engineer` | ✓ | implied | unstated | ✗ | **silent** | **silent** | none | **ALL TOOLS** |
| `09-database-engineer` | ✓ | ✓ **migrations** | unstated | ✗ | **silent** | **silent** | qualified 3× | **ALL TOOLS** ⚠️ |
| `10-qa-engineer` | ✓ | **unspecified** | ✓ 5 layers | role handoff | **silent** | **silent** | **none** | **ALL TOOLS** |
| `11-visual-fidelity` | ✓ | "smallest correction" | re-render | ✗ | **silent** | **silent** | escalate | **ALL TOOLS** |
| `12-security-engineer` | ✓ | implied | ✓ **offensive** | peer coord. | **silent** | **silent** | **none** ⚠️ | **ALL TOOLS** ⚠️ |
| `13-devops-release` | ✓ | CI/infra | ✓ owns gates | ✗ | "no secrets" | deploy implied | **none before prod** ⚠️ | **ALL TOOLS** |
| `14-performance` | ✓ | implied | measurement | ✗ | **silent** | **silent** | none | **ALL TOOLS** |
| `12circle-agent-handoff` | n/a | n/a | asks "Tests:" | ✗ | ✗ | ✗ | RED self-declared | **ALL TOOLS** |
| `source-of-truth` | ✓ | unstated | ✗ | defers | ✗ | ✗ | gatekeeper | **ALL TOOLS** |
| `creative-director` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | none | **ALL TOOLS** |
| `design-orchestrator` | ✓ | unstated | ✗ | ✓ 4 roles (prose) | ✗ | ✗ | Lead Architect ✗ | **ALL TOOLS** |
| `design-to-code` | ✓ | ✓ STEP 8 | ✓ STEP 10 | ✗ | ✓ **self-negating** | ✗ | Lead Architect ✗ | **ALL TOOLS** |
| `figma-product-design` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | none | **ALL TOOLS** |
| `motion-interaction` | ✓ | ✗ spec only | ✗ | ✗ | ✗ | ✗ | none | **ALL TOOLS** |
| `visual-critic` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | REJECT veto | **ALL TOOLS** |
| `aiwos-*` (6) | ✓ | packet-bounded | ✓ | packet | **✓ gated bool** | **✓ gated bool** | **✓ explicit** | **ALL TOOLS** |
| **COWORK AG-00…AG-13** | ✓ | by level | by level | ✓ L3 | doc'd | doc'd | ✓ L4 owner | **NOT EXECUTABLE** |

### Session-level authority (VERIFIED — this is what actually governs)

| Control | Value | Effect |
|---|---|---|
| `defaultMode` (global) | `auto` | Tools run without prompting |
| `deny` rules | **NONE on this machine** | Nothing is forbidden |
| `ask` rules | **NONE on this machine** | Nothing requires confirmation |
| Project `settings.json` git | `Bash(git diff *)` only | Read-only — *appears* safe |
| `settings.local.json` (untracked) | **`Bash(git push:*)`** | **Unrestricted push authority** |
| `additionalDirectories` | `["/Users/dmac/.claude"]` | Project session can reach — **and write** — the global skill bucket |
| Hooks that can block | **NONE** | No enforcement point exists |

---

## 10. Active vs Dormant vs Orphaned

**ACTIVE (evidence of current use):** `claude-api` (243 attributed calls), `artifact-design` (30),
plus Anthropic stock document skills. **No `12circle-*` skill is ACTIVE on this project.**

**DORMANT (valid, applicable, not invoked here):** `10-qa-engineer`, `12-security-engineer`,
`13-devops-release`, `14-performance`, `02-engineering-lead`, `12circle-agent-handoff`,
`frontend-design`. Also **the entire COWORK AG-00…AG-13 registry** — approved, product-correct,
never operationalized.

**ORPHANED (no corresponding code or artifact):** `04-web-engineer`, `05-portal-engineer`,
`07-design-system-engineer`, `11-visual-fidelity`, `figma-product-design`, `motion-interaction`,
`creative-director`, `design-orchestrator`, `design-to-code`, `visual-critic`.

**OBSOLETE FOR THIS PROJECT:** all six `aiwos-*` — different product, all 23 cited paths missing,
including the `PreToolUse` guard they depend on for enforcement.

**CONFLICTS WITH THE PRODUCT:** `01`, `03`, `source-of-truth`, `creative-director`, `visual-critic`,
`design-orchestrator`, `figma-product-design`.

**REFERENCED-BUT-NOT-FOUND:** `06-*` (mobile engineer — the one the repo most needs);
"Lead Architect" as a skill; `.claude/hooks/aiwos-guard.mjs`; `packages/helix`; `apps/web`;
commit `7ccbd77`; Hanken Grotesk.

**BLOCKED:** vercel MCP server (`https://mcp.vercel.com`) — configured but unauthorized in
non-interactive sessions.

### Dormancy analysis for the applicable skills

| Skill | Why dormant | Still relevant? | What prevents use |
|---|---|---|---|
| `10-qa-engineer` | Nothing requires it; Communities vocabulary makes it feel wrong for fitness | **Yes, in principle** | No gate, no emulator capability, wrong journey list |
| `12-security-engineer` | Same | Yes — repo has live RLS regressions | Wrong domain vocabulary; no approval gate |
| `13-devops-release` | Same | Yes — owns CI gates | Never mentions Supabase/Flutter |
| `14-performance` | Same | Partly | No mobile profiling mechanism |
| `COWORK AG-00…AG-13` | **Never had a runtime** | **Yes — it is the correct model** | Not executable; no skill implements it |

**No dormant agent was activated. Activation requires owner authorization (§16).**

---

## 11. Duplicate / Conflict Analysis

### Cluster verdicts

| Cluster | Verdict |
|---|---|
| **A. Design authority** | **OVERLAPPING — 5 claims, no precedence.** `source-of-truth` (constitutional), `03-gatekeeper` (enforcement veto), `creative-director` (*"You own the visual identity"* — the only ownership claim), `visual-critic` (*"You are the independent quality gate"*), `figma-product-design` (*"Figma is the visual source of truth"*). `11-fidelity` declines authority. **03 and 11 are functional duplicates in different vocabularies.** |
| **B. Design implementation** | **OVERLAPPING → effectively DUPLICATE.** `design-to-code` (1,644 lines) is a superset absorbing 04, 05, 07, 11 and the whole creative/motion cluster, and references **none** of the six skills it duplicates. |
| **C. Orchestration** | **OVERLAPPING at the release seam.** Both `02` and the orchestrator claim the visual release gate. The orchestrator inserts "Lead Architect" above `02`, which `02` never acknowledges. |
| **D. Process/governance** | **DUPLICATE IN PURPOSE, CONTRADICTORY IN RULES — the major finding.** Two complete, mutually unaware frameworks with **three incompatible status vocabularies for the same event**: `GREEN/YELLOW/RED` (agent-handoff), `PASS/REVISE/BLOCKED` (design-to-code §43), `SUCCEEDED/FAILED/REFUSED/NOT_AUTHORIZED/NOT_ATTEMPTED` (aiwos). AIWOS forbids exactly the collapse the others require: *"`NOT_AUTHORIZED` and `NOT_ATTEMPTED` are different facts and are never collapsed into 'didn't happen'."* |
| **E. `frontend-design`** | **CONTRADICTORY.** *"take one real aesthetic risk"* vs `01`'s *"MUST NOT redesign approved screens."* Its own calibration list names the 12Circle house style as generic-AI-default #1 — *"a warm cream background (near #F4F1EA) with a high-contrast serif display"* — which `design-to-code` §4.1/§5 prescribe. |
| **F. Web vs Portal** | DISTINCT from each other; **BOTH ORPHANED.** |

### Highest-value conflicts

- **C-1 Commit authority — absolute gate vs none.** AIWOS: *"Merge — never, in v1."* Across all 13 numbered skills the only commit statements are `13-devops` *"Never commit secrets"* and `design-to-code` *"Only commit after the Lead Architect has approved the batch **when the workflow requires explicit review**"* — self-negating, and deferring to a nonexistent actor.
- **C-4 QA gating — work CAN ship without QA sign-off.** `10-qa` has no gate; `agent-handoff` permits self-certification: *"GREEN: implementation is complete… and verification passed"* — declared by the agent that did the work. **The only framework forbidding self-certification is AIWOS, the orphaned one.**
- **C-5 Design freeze — four incompatible rules.** `source-of-truth` *"Figma is frozen"* + `01` *"MUST NOT redesign approved screens"* vs `creative-director` *"produce 3–5 substantially different directions"* and `design-to-code` §2.4 *"**Never let current code limitations dictate the final design**"* / §40 *"Phase 16 is the major visual transformation."* No reconciliation clause anywhere.
- **C-6 Flat contradiction on a testable UI decision.** `05-portal`: *"**Do not reintroduce the removed desktop sidebar without approval.**"* `design-to-code` §6/§31: the North Star is a *"**dark architectural sidebar**… Do not replace this."*
- **C-7 Figma page collision — real data-loss risk.** `source-of-truth`: authoritative mobile page is `05 — Mobile App — NEW`, adjacent `05 — Mobile App` is *"do not edit."* `design-to-code` §12 assigns page `05` to `Public Website` and puts mobile at `11`. If Figma tooling were pointed at the file on the wrong skill's map, it would write to a protected page.
- **C-11 Terminology — six skills prohibit the product this repo is.** `workout`/`coach`/`exercise`/`nutrition`/`Flutter` = **0 occurrences across all 36 skills**. In `apps/mobile/lib`: **90 files match `workout`, 155 match `coach`**. Conversely `resident` = 16 hits in skills, **0 in repo source**.
- **C-9 / C-10 Concrete falsifications.** `design-to-code` §9 *"No Google Fonts dependency"* vs `pubspec.yaml:32 google_fonts: ^8.1.0`. The Helix semantic-token rule *"Do not write `color: #123456;`"* is CSS aimed at a Dart codebase with **68 raw `0xFF…` literals in `lib/core`**.
- **C-12 Stale pinned state.** `design-to-code` §40 asserts *"Phase 14 is complete at `7ccbd77`"* — `git cat-file` reports that is not a valid object in this repo.

### The inverse finding

**The repo's real governance corpus is cited by zero skills** — `COWORK_ENGINEERING_GOVERNANCE.md`,
`COWORK_AGENT_REGISTRY.md`, `COWORK_FILE_OWNERSHIP.md`, `QA_CLOSURE_STANDARD.md`,
`RELEASE_GATES.md`, `MASTER_PRODUCT_DECISIONS.md`, `WORKING_TREE_CUSTODY_MANIFEST.md`. The
relationship is null in **both** directions.

---

## 12. 12Circle Phase → Agent Mapping

| Phase | Skill candidate | Cowork role | Verdict |
|---|---|---|---|
| **TECHNICAL QA** | `10-qa-engineer` | AG-08 | Skill applicable but **unanchored, no gate, wrong journeys**. AG-08 is product-correct. **Use AG-08's contract; skill needs rewrite.** |
| **INTEGRATION QA** | `10-qa` (layer 2) | AG-08 + domain owner | Thin. `QA_CLOSURE_STANDARD.md` "VERIFIED END-TO-END" is far stronger. **Doc wins.** |
| **DESIGN INTEGRATION** | 9 design skills | AG-11 (*"NOT ACTIVE"*) | **Actively harmful** — would RED/REJECT the fitness product. **Do not invoke.** |
| **ANDROID RUNTIME QA** | **none** | none | **MISSING CAPABILITY** — zero emulator/device references in all 36 skills. Runbooks exist only in session memory. |
| **ACCESSIBILITY** | **none owns it** | none | **MISSING CAPABILITY** — absent from QA, security, perf, devops and the handoff template. `01` asks only that *"accessibility is considered."* |
| **SECURITY** | `12-security-engineer` | AG-01 | Skill is offensive-capable with **no approval gate**. AG-01 has review requirements. **Use AG-01 boundaries.** |
| **PERFORMANCE** | `14-performance` | none | Applicable in principle; **no mobile profiling mechanism**. Partial. |
| **ERROR / EMPTY / LOADING** | **none** | **AG-03 Error Integrity** | **MISSING from skills; AG-03 covers it exactly** (*"eliminating swallowed exceptions… preventing fabricated success"*) — and the repo has live defects of this class. |
| **VISUAL QA** | `11` + orchestrator :109 + `design-to-code` STEP 9 | AG-11 | **TRIPLICATED, mutually unaware.** Needs one owner. |
| **PREMIUM PRODUCT QUALITY** | `visual-critic` | AG-11 | Skill would **REJECT** fitness framing. **Conflicts with owner's stated brand direction.** |
| **REGRESSION** | `10-qa` (layer 5) | AG-08 | Underspecified. The repo's *"would `flutter test` go red?"* framing is better. |
| **CI/CD** | `13-devops-release` | AG-07 | Closest fit. Skill never mentions Supabase/Flutter; AG-07 does, and adds *"may never contact production unless explicitly authorized."* |
| **RELEASE** | `13-devops` + `02` gate | AG-07 + AG-00 + **L4 owner** | Only the Cowork model puts a **human** at the release gate. **Use it.** |

**Five MISSING CAPABILITIES:** Android/device runtime QA · accessibility ownership ·
error-contract QA (in skills) · mobile/Flutter engineering (`06-*`) · a single visual-QA owner.

**Per instruction, none was created.**

---

## 13. Missing Capabilities

1. **Mobile / Flutter engineering skill (`06-*`)** — the gap in the numbered series. The repo is
   ~100% Flutter; `02-engineering-lead` assigns a "Mobile" lane to a skill that does not exist.
2. **Android emulator / device runtime QA** — zero references machine-wide. Two hard-won emulator
   runbooks exist only in session memory (SDK provisioning, the 7.4 GB disk constraint); the skill
   layer has no idea they exist.
3. **Accessibility ownership** — no skill owns it.
4. **Error-contract QA** — AG-03's domain; no skill equivalent. The repo has live defects here.
5. **A single visual-QA owner** — currently triplicated.
6. **An executable binding for the COWORK registry** — the correct model with no runtime.
7. **Any enforcement point** — no `PreToolUse` hook, no `deny`/`ask` rule, no `allowed-tools`.

---

## 14. Agents Currently Being Bypassed

| Agent | Bypassed by | Evidence |
|---|---|---|
| **`10-12circle-qa-engineer`** | General Claude reasoning + 11 stock `Explore` subagents | **0 invocations / 0 attributed calls across 37 sessions**, while the same skill logged 3 invocations and 147 attributed calls in `12circle-communities`. Listed in the system prompt 6× in the working session and never called. |
| `12-security-engineer` | General reasoning | 0 fitness invocations |
| `13-devops`, `14-performance`, `02-engineering-lead` | General reasoning | 0 fitness invocations |
| **COWORK AG-00…AG-13 (all 14)** | General reasoning | `AG-xx` appears in **exactly one file — the registry itself**. Zero citations in ~60 QA/evidence documents. |
| `12circle-agent-handoff` | Ad-hoc report formats | 1 use ever, globally |

**What replaced them:** the `QA_WORKSTREAM_A…N` lettered taxonomy and the `WAVE_*` sequence — a
third, undocumented organizing scheme that matches neither `AG-xx` nor the skill set.

**Is the bypass harmful?** Partly. The work is good — `QA_CLOSURE_STANDARD.md`'s five-state ladder
is more rigorous than any skill. But it is **unenforced**: nothing prevents a future session from
skipping it, because it lives in prose that no mechanism reads.

---

## 15. Recommended Activation Model

Presented as options for decision. **Nothing was activated.**

**The core problem is not a shortage of agents — it is that the two systems are inverted.** The
product-correct model (COWORK) cannot execute. The executable model (skills) targets the wrong
product.

**Recommended: make COWORK executable; quarantine the Communities skills.**

1. **Quarantine, don't delete.** The 21 `12circle-*` skills are correct and in active use for
   `12circle-communities`. They are only wrong *here*. Since the bucket is global and shared, the
   fix is scoping, not removal. **Owner decision required** (§16).
2. **Author the missing `06` mobile/Flutter skill** — the single highest-value gap.
3. **Bind COWORK AG-01/03/07/08/09 to real skills**, carrying their scope paths and the L0–L4
   authority levels, which already match the repo.
4. **Make `QA_CLOSURE_STANDARD.md` the QA skill's body** rather than the Communities journey list.
5. **Add the one thing nothing has: an enforcement point.** A `PreToolUse` hook, or at minimum
   `deny`/`ask` rules, so production and migration boundaries are mechanical rather than advisory.
6. **Adopt AIWOS's publication gate** (`commit → push → draft PR → merge`, merge non-delegable),
   which is the best authority model present and is currently pointed at the wrong repo.
7. **Resolve `settings.local.json`** — unrestricted `git push` in an untracked personal file
   contradicts the shared `settings.json`'s read-only git posture.

**Sequencing note:** step 5 is worth more than steps 2–4 combined. Governance that no mechanism
reads is exactly what this audit found three times over.

---

## 16. Owner Decisions Required

1. **Scope of the Communities skills.** They are live for the sibling repo. Disable for fitness,
   rename to `12circle-communities-*`, or leave and rely on judgment? *(Affects both projects.)*
2. **Product identity.** Six skills prohibit fitness framing; `CLAUDE.md` mandates WHOOP/Oura.
   Which governs? Until ruled, any design skill invocation here produces a contradiction.
3. **Does the COWORK registry remain authoritative?** Approved 2026-08-24, never operationalized.
   Activate, retire, or leave as documentation?
4. **Should `06-12circle-mobile-engineer` be authored?** *(Creation requires authorization.)*
5. **Enforcement.** Introduce hooks / `deny` rules, or continue with advisory governance?
6. **`Bash(git push:*)` in `settings.local.json`** — intended, or accreted?
7. **AIWOS skills** — retire from this machine's bucket, or leave for their own project?
8. **Which taxonomy is canonical** — `AG-xx`, `QA_WORKSTREAM_A…N`, or `WAVE_*`? Three coexist.

**Out of scope but surfaced (pre-existing, not introduced by this audit):** two Phase-1 security
fixes were regressed by later migrations and **production remains unpatched**; `npm run test:security`
has not run since Phase 1 and there is no CI for it; free-tier Supabase means no PITR. Tracked in
existing memory — noted here only because §6 bears on who should own it.

---

## 17. Evidence Index

| Source | What it established |
|---|---|
| `~/.claude/skills/synced/<bucket>/` — 36 `SKILL.md` read | Inventory, sizes, frontmatter, zero `allowed-tools` |
| `<bucket>/manifest.json` | 36↔36 sync; schema cannot express gating |
| `<bucket>/.staging`, `~/.claude/skills/.trash/` | Both empty — no dormant definitions survive |
| Project `.claude/settings.json`, `settings.local.json` | Permissions; `additionalDirectories`; `git push:*` |
| `~/.claude/settings.json` | `defaultMode: auto`; one plugin; no hooks |
| `~/.claude/CLAUDE.md` | Helix doctrine; fitness brand mandate |
| Project `CLAUDE.md` | **Does not exist** (zero results at any depth) |
| `~/.claude.json` → `skillUsage` | Backward-looking counters; sparse, uneven |
| `~/.claude/projects/*/*.jsonl` — 37 fitness + 11 communities sessions | Invocation counts; `attributionSkill`; subagent types |
| `vercel/0.49.2/hooks/hooks.json` | The only executing hooks; 19 unregistered scripts |
| `docs/COWORK_AGENT_REGISTRY.md` + governance + ownership | The in-repo role system |
| `docs/QA_CLOSURE_STANDARD.md`, `RELEASE_GATES.md` | The real QA authority |
| `docs/DESIGN_INTAKE_REPORT.md` | Design SoT is a ZIP handoff, not Figma |
| `docs/MOBILE_QA_SWEEP_2026-09-22.md` | Explicit disclaimer of the Communities/Helix workstream |
| `apps/`, `packages/`, `pubspec.yaml`, `.github/` | Repo shape; orphan determination; no CI agents |
| `git log` on COWORK docs | Single commit `9319c67`, 2026-08-24 |

**Machine-readable registry:** the project's existing registries (`COWORK_AGENT_REGISTRY.md`,
`MASTER_REMEDIATION_REGISTRY.md`) are **Markdown prose, not a machine-readable format**. Per the
audit instruction, **no new persistent registry file was invented.**

---

## 18. Final Findings

1. **The dedicated QA Skill Agent exists, is installed, is provably functional — and has never run
   on 12 Circle Fitness.** 0 of 37 sessions. It has only ever driven `12circle-communities`.
   Bypass rate here: **100%**. (VERIFIED)
2. **It is not, in its current form, an agent.** 27 lines, no gates, no closure criteria, no
   verification clause, no emulator capability, no anchor to any standard.
3. **The skill set targets the wrong product**, and six skills would actively block this one.
4. **No skill declares any tool permission.** All 36 inherit the full session toolset. With no
   `deny`/`ask` rules, `defaultMode: auto`, and `git push:*` granted, **every prohibition in every
   skill is advisory**.
5. **The delegation graph is empty** — zero machine-resolvable cross-skill references; three
   competing orchestrators; a shared root ("Lead Architect") that has no skill file but **is**
   defined as AG-00 in the repo.
6. **The correct model already exists and cannot execute.** COWORK AG-00…AG-13 is product-accurate,
   authority-layered, human-terminated — and referenced in exactly one file: itself.
7. **Five capabilities are missing**, most critically **mobile/Flutter engineering (`06`)** and
   **Android runtime QA** — in a repo that is ~100% mobile.
8. **The work being done is better than the system governing it.** `QA_CLOSURE_STANDARD.md`
   outclasses every QA skill on disk. The risk is not quality; it is that **nothing enforces it**.

**Bottom line:** this project has 36 reachable skills, 14 documented agent roles, and zero
governed agents. Every line of QA, security and design work in the audit window was produced by
ungoverned general Claude reasoning. The remedy is not more agents — it is to make the one correct
model executable, and to give it an enforcement point.

---

*Read-only audit. No skill, agent, configuration or repository file was created, modified,
renamed, activated, installed, committed or pushed. This report is the only artifact produced.*
