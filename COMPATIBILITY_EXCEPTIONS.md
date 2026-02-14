# COMPATIBILITY_EXCEPTIONS

Ledger of approved compatibility deviations from canonical FrankenSSH
specification behavior.

Rules:

1. This file is append-only for approved exceptions (do not rewrite history).
2. Every exception must reference a specific spec section and include evidence.
3. Exceptions are valid only for declared scope and mode (`strict`/`hardened`).
4. Temporary exceptions must carry an explicit sunset condition.

## Template

| Exception ID | Spec Section | Scope (Mode/Phase) | OpenSSH Observable Behavior | FrankenSSH Deviation | Rationale | Evidence Links | Approved By | Approved Date (UTC) | Sunset Condition | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| EXC-TBD-001 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | proposed |

## Notes

- `proposed`: documented candidate, not yet normative.
- `approved`: permitted deviation under declared scope.
- `expired`: no longer valid; implementation/spec must be re-aligned.
