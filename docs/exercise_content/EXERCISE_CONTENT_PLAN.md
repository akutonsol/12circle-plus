# Exercise content readiness plan

Measured on QA, read-only, 2026-11-16. **Correction:** earlier reports said the built-in
library had images for all 46 entries; it has **6**. **No content in this folder is authored;** it is an
inventory and a plan. Nothing here writes to QA.

## Where content stands

| | Database library (`custom_exercises`, global) | Built-in library (in the app) |
|---|---|---|
| Entries | 621 | 46 |
| With description + instructions + cues + mistakes | 20 | 46 |
| With alternatives / beginner / advanced variants | 0 | 46 |
| With an image | 0 | **6** image assets |
| With a video | 0 | 0 (links are YouTube *searches*) |
| Human-reviewed (`human_reviewed`) | 0 | n/a (shipped in code) |
| Duplicate names | 0 | 0 |

Classification is complete in the database: all 621 have category, muscle group,
equipment, difficulty and movement pattern.

## Priority: what programs actually use

`exercise_name_mapping.csv` lists every movement name used in a program or a logged set on
QA (26 names), with use counts:

| Status | Names |
|---|---|
| exact match in both libraries | 8 |
| exact match in the database only | 5 |
| **needs human mapping** | 13 |

"Exact" means equal after normalising case, spaces and punctuation ("Push Up" = "Push-Up").
`candidates_UNREVIEWED` lists database entries containing the name's words. **These are
suggestions for a reviewer, not mappings**: "Bench Press" could be barbell or dumbbell; that
choice changes the form shown to a client, so a person makes it.

`priority_missing_fields.csv` is the field inventory for the 46 database entries that are
exact matches or candidates: 32 lack description/instructions/cues/mistakes; all 46 lack
alternatives, beginner and advanced variants, image and video; none is human-reviewed.

## Normalisation rule

`normalizeExerciseName(s) = lowercase(s) with every non-alphanumeric character removed`
(the app's `library_match.dart`, PR #166). Exact equality only. No stemming, no plural folding,
no fuzzy matching in code — a plural or variant name ("Calf Raises", "Face Pulls") is mapped by
a reviewer, once, in the mapping table.

## Content-quality criteria (an entry is "complete" for the beta when)

1. **Description**: what the movement trains and who it suits; no medical claims.
2. **Instructions**: 4–8 ordered steps, set-up to finish.
3. **Coaching cues**: 3–5 short external cues.
4. **Common mistakes**: 3–5, each with the correction.
5. **Beginner modification** and **advanced progression**: one each, naming real movements.
6. **Alternatives**: 2–4 library entries (by exact name) for equipment swaps.
7. **Classification** consistent with the library (already true).
8. **Media**: see below.
9. **Review**: `human_reviewed = true`, `last_reviewed_by` set — only after a person checks it.

Contraindications and injury guidance stay out unless written or approved by a qualified
professional (no medical claims are generated).

## Media requirements

| Asset | Minimum for beta | Source (decision for Julia) |
|---|---|---|
| Image | one clear start or mid-rep frame per priority entry | coach demo > licensed library > none |
| Video | optional for beta; one form demo per priority entry before public launch | coach upload or licensed; YouTube search links are not media |

No automated media source is wired. The 6 built-in image assets can be
reused for the matching database entries once a reviewer confirms the match.

## Human-review workflow (uses what exists)

1. Draft: text for an entry is drafted (coach-written, or AI-drafted by `enrich-exercise-content`
   once deployed) into the entry with `content_status = 'draft'`.
2. Submit: the existing review queue (`content-review` / `knowledge-review` screens) moves it to
   `under_review`.
3. Review: a coach or admin checks it against the criteria above and either approves
   (`human_reviewed = true`, `published`) or returns it.
4. Only `published` + `human_reviewed` entries count toward readiness.

## Batch plan

| Batch | Entries | Prerequisites |
|---|---|---|
| 0 | Review the 13 "needs human mapping" names; record one library entry per name | none (a document decision) |
| 1 | The 13 exact + 13 mapped entries (~26): complete text, reuse the built-in text (46) and images (6) where a reviewer confirms the match | QA write approval for content updates |
| 2 | Remaining entries used by the engine's beta programs | enrichment functions deployed; review capacity |
| 3 | Media for batches 1–2 | media source decision |
| 4 | The rest of the 621, by category | after beta feedback |

Batches are content-only updates (no schema change) but are **QA writes** — each needs approval.
