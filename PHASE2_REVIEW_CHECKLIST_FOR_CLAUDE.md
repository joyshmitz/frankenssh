# PHASE2_REVIEW_CHECKLIST_FOR_CLAUDE

Purpose: one-pass review checklist for the Phase 2 normative docs package.

## 1. Phase Boundary Hygiene

- [ ] `fsh-types` Phase 2 scope excludes SFTP-specific typing and crypto-key enums (`COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:240`, `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:242`, `PLAN_TO_PORT_SSH_TO_RUST.md:84`, `PLAN_TO_PORT_SSH_TO_RUST.md:86`)
- [ ] Phase 2 helper list includes read/write name-list and bool helpers (`COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:233`, `PLAN_TO_PORT_SSH_TO_RUST.md:68`, `FRANKENSSH_PROPOSAL.md:982`)
- [ ] Proposal architecture table matches Phase 2 baseline (`FRANKENSSH_PROPOSAL.md:479`)
- [ ] Context-dependent type strategy (30-49, 60-79) is explicit in spec+plan+proposal (`COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:274`, `PLAN_TO_PORT_SSH_TO_RUST.md:71`, `FRANKENSSH_PROPOSAL.md:992`)

## 2. API Contract Completeness

- [ ] Phase 2 entry contract remains canonical in spec sections 11.2-11.4 (`COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:227`, `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:245`, `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:257`)
- [ ] `ExtInfo` (SSH_MSG_EXT_INFO type 7) is in Phase 2 baseline and dispatch requirements (`COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:267`, `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:678`, `FRANKENSSH_PROPOSAL.md:984`)
- [ ] Disconnect mapping includes required service-gate code 7 plus version/connection/rate/auth-cancel cases (`COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:385`, `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:386`, `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:388`, `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:391`, `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:392`)
- [ ] New Appendix defines minimum API shapes for `fsh-types`/`fsh-error`/`fsh-wire` (`COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:602`, `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:607`, `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:646`, `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:662`)

## 3. Evidence and Milestone Gates

- [ ] PLAN Phase 2 checklist and acceptance tests are aligned (`PLAN_TO_PORT_SSH_TO_RUST.md:67`, `PLAN_TO_PORT_SSH_TO_RUST.md:77`)
- [ ] Exit evidence package is explicit and reviewable (`PLAN_TO_PORT_SSH_TO_RUST.md:117`)
- [ ] New deterministic artifact format is present (`PLAN_TO_PORT_SSH_TO_RUST.md:127`)
- [ ] Milestones cleanly separate Phase 2 baseline from Phase 3 crypto (`COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:511`, `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:518`)
- [ ] Strict-mode rekey defaults are explicit and OpenSSH-aligned (`COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:106`)

## 4. Parity Ledger Discipline

- [ ] Phase 2 readiness rows stay non-parity-gating (`FEATURE_PARITY.md:38`)
- [ ] Row-to-PLAN mapping is explicit (`FEATURE_PARITY.md:44`)
- [ ] Transition rules for `not_started/in_progress/parity_green/parity_gap` are defined (`FEATURE_PARITY.md:56`)

## 5. Reviewer Exit Criteria

- [ ] No contradictions across `SPEC`, `PLAN`, `PARITY`, `PROPOSAL` on Phase 2 type/helper lists
- [ ] No stale wording implying Phase 2 completion without required evidence
- [ ] Package is ready for implementation handoff if all boxes above pass
