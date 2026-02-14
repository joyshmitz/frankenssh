# PHASE2_REVIEW_CHECKLIST_FOR_CLAUDE

Purpose: one-pass review checklist for the Phase 2 normative docs package.

## 1. Phase Boundary Hygiene

- [ ] `fsh-types` Phase 2 scope excludes SFTP-specific typing and crypto-key enums (`COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:238`, `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:240`, `PLAN_TO_PORT_SSH_TO_RUST.md:83`, `PLAN_TO_PORT_SSH_TO_RUST.md:85`)
- [ ] Phase 2 helper list includes both read/write name-list support (`COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:231`, `PLAN_TO_PORT_SSH_TO_RUST.md:68`, `FRANKENSSH_PROPOSAL.md:973`)
- [ ] Proposal architecture table matches Phase 2 baseline (`FRANKENSSH_PROPOSAL.md:479`)

## 2. API Contract Completeness

- [ ] Phase 2 entry contract remains canonical in spec sections 11.2-11.4 (`COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:225`, `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:243`, `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:255`)
- [ ] Disconnect mapping includes required service-gate code 7 (`COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:377`)
- [ ] New Appendix defines minimum API shapes for `fsh-types`/`fsh-error`/`fsh-wire` (`COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:590`, `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:595`, `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:630`, `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:646`)

## 3. Evidence and Milestone Gates

- [ ] PLAN Phase 2 checklist and acceptance tests are aligned (`PLAN_TO_PORT_SSH_TO_RUST.md:67`, `PLAN_TO_PORT_SSH_TO_RUST.md:76`)
- [ ] Exit evidence package is explicit and reviewable (`PLAN_TO_PORT_SSH_TO_RUST.md:113`)
- [ ] New deterministic artifact format is present (`PLAN_TO_PORT_SSH_TO_RUST.md:123`)
- [ ] Milestones cleanly separate Phase 2 baseline from Phase 3 crypto (`COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:499`, `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md:506`)

## 4. Parity Ledger Discipline

- [ ] Phase 2 readiness rows stay non-parity-gating (`FEATURE_PARITY.md:38`)
- [ ] Row-to-PLAN mapping is explicit (`FEATURE_PARITY.md:44`)
- [ ] Transition rules for `not_started/in_progress/parity_green/parity_gap` are defined (`FEATURE_PARITY.md:56`)

## 5. Reviewer Exit Criteria

- [ ] No contradictions across `SPEC`, `PLAN`, `PARITY`, `PROPOSAL` on Phase 2 type/helper lists
- [ ] No stale wording implying Phase 2 completion without required evidence
- [ ] Package is ready for implementation handoff if all boxes above pass
