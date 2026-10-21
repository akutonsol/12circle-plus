# Schema contract guard

`npm run test:contract`

Offline. **Contacts no environment** — neither QA nor production. It derives the
`public` schema by replaying `supabase/migrations` and asserts that every
relation and column the application names actually exists.

## What it checks

| Check | Source |
|---|---|
| `.from('<relation>')` resolves to a table or a view | `schema.mjs` + `VIEWS` |
| every name in `.select('a, b, c')` is a real column | derived DDL |
| every top-level key of `.insert/.update/.upsert({…})` is a real column | derived DDL |

Embedded resources (`.select('*, user_profiles(first_name)')`), storage buckets
(`.from('avatars')`), and keys nested inside a `jsonb` value are not columns and
are excluded.

## Why it exists

PostgREST rejects an unknown column with **HTTP 400 / `42703` before it checks
authorization** — verified live against QA:

```
GET /rest/v1/nutrition_logs?select=calories,protein_g
→ 400 {"code":"42703","message":"column nutrition_logs.protein_g does not exist"}
```

Every client call site wraps that in a `catch` that returns `[]`, `false` or
`null`. A misspelled column therefore ships as a **silently dead feature**, not
as a crash, and no amount of widget or unit testing sees it. Nine such defects
were open when this guard was written — see
[`docs/QA_WORKSTREAM_I_DATA_CONTRACT_REPORT.md`](../../../docs/QA_WORKSTREAM_I_DATA_CONTRACT_REPORT.md).

## The allowlist

`known-violations.json` records the violations that are open today, each tagged
with its finding ID. It is checked in **both** directions:

* a violation that is **not** listed fails the guard — a new defect;
* a listed entry that **no longer reproduces** also fails the guard — so a fix
  cannot leave a stale excuse behind.

The list can therefore only shrink. Removing an entry is the last step of fixing
its finding; nothing may be added without a finding ID.

## Known blind spot

A payload key assigned dynamically (`row['metadata'] = value`) rather than
written as an object literal is invisible to this guard. **I-NOT-01**
(`messages.metadata`) is exactly that shape and is deliberately *not* in the
allowlist, because the guard cannot prove it either way.

## Fidelity

`schema.mjs` was verified byte-exact against `supabase db dump --linked` of QA
(`eyqtldjqpgpljlqvpowh`) on 2026-08-24: **91 tables, 0 column drift**. If a
future migration uses a DDL form the replayer does not understand, that check
must be repeated.
