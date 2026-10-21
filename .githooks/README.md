# Repository git hooks

Enable them once per clone:

```bash
git config core.hooksPath .githooks
```

`core.hooksPath` is local configuration and is **not** carried by a clone, so this
is a per-checkout step. There is no way to make a hook mandatory from inside the
repository — a hook is a convenience that fires before a mistake, not a control.
Anything that must not be bypassable belongs in CI, where `ci.yml` runs regardless
of what a working copy is configured to do.

## `pre-push` — refuses a push while a governed CI run is in flight

Pushing over a run cancels it, and a cancelled process never runs a `finally`.
V5 §137: that left a fixture row in `admin_role_assignments`; the next run's arrange
hit 409 on a primary key, and because its cleanup was guarded by `if (arranged)` the
failure perpetuated itself. One impatient push produced a red CI that had nothing to
do with the code and would not have cleared on its own.

V5 §96.2 already made this a rule. It was then broken in §98.4 and again in §137 —
three times by the same operator, which is evidence that the mechanism was wrong,
not that the operator needed reminding.

The hook **fails closed** when a run is in flight and **fails open** when it cannot
tell (no `gh`, offline, unauthenticated), saying which. To supersede a run on
purpose:

```bash
ALLOW_PUSH_OVER_CI=1 git push
```
