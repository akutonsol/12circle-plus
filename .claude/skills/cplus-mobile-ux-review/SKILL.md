---
name: cplus-mobile-ux-review
description: Reviewing a 12circle-plus Flutter screen or flow for usability, state completeness, accessibility, consistency and honest feedback — preserving the existing 12circle-plus design direction rather than redesigning. Use when a mobile screen or journey is added or changed.
---

# Mobile UX review in 12circle-plus

12circle-plus is a coaching app (client and coach). Review against **its own** screens and the
controlled-beta journeys (`docs/CONTROLLED_BETA_SCOPE.md`, `docs/WEEK1_ACCEPTANCE_WALKTHROUGH.md`).
Do not import another product's design rules; do not propose a redesign unless a concrete defect
requires it.

## For each screen in the flow

- **States:** loading (no infinite spinner), empty (says what to do next), error (says what failed
  and offers retry), success (only after the server confirmed). A failed read must never look like
  "nothing here" or zeros.
- **Truthful copy:** no fabricated or sample data presented as the user's; numbers in the member's
  unit; dates in the member's local day.
- **Navigation:** every entry has a way back; no dead ends; deep links (`?invite=`, recovery)
  land somewhere sensible when signed out.
- **Gating:** paywalled or role-limited actions are hidden or explained, never offered then refused.
- **Accessibility:** tappable controls have semantic labels and actions (`Semantics`), adequate hit
  size, readable contrast, keyboard not covering inputs.
- **Consistency:** terminology and components match neighbouring screens.

Report findings as: screen · problem · evidence (file:line or screenshot) · user impact ·
suggested minimal fix · whether it needs a product decision.
