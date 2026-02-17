#!/usr/bin/env bash
# test_governance_gates.sh — negative tests for governance gates
#
# Creates temp copies with deliberate breakage and verifies that each
# gate script detects the problem (non-zero exit).
#
# Usage: bash scripts/test_governance_gates.sh
# Env:
#   GOVERNANCE_TEST_MODE=full|ci  (default: full)
#     full — run complete suite
#     ci   — skip clean-path checks already executed directly by workflow
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MODE="${GOVERNANCE_TEST_MODE:-full}"

case "$MODE" in
  full|ci) ;;
  *)
    printf 'ERROR: invalid GOVERNANCE_TEST_MODE "%s" (must be full|ci)\n' "$MODE" >&2
    exit 2
    ;;
esac

tmpdir=$(mktemp -d)
trap 'rm -r "$tmpdir"' EXIT

PASS=0
FAIL=0
TOTAL=0
SKIP=0

run_test() {
  local name="$1" expect_exit="$2"
  shift 2
  ((TOTAL++)) || true
  local logfile="$tmpdir/stdout_${TOTAL}.log"
  local actual_exit=0
  "$@" > "$logfile" 2>&1 || actual_exit=$?
  if [[ "$actual_exit" -eq "$expect_exit" ]]; then
    ((PASS++)) || true
    printf '  [PASS] %s (exit=%d)\n' "$name" "$actual_exit"
  else
    ((FAIL++)) || true
    printf '  [FAIL] %s (expected exit=%d, got=%d)\n' "$name" "$expect_exit" "$actual_exit"
    printf '         last 5 lines of output:\n'
    tail -5 "$logfile" | sed 's/^/         | /'
  fi
}

skip_test() {
  local name="$1" reason="$2"
  ((SKIP++)) || true
  printf '  [SKIP] %s (%s)\n' "$name" "$reason"
}

printf '=== governance gate tests ===\n\n'

# ---------------------------------------------------------------------------
# T0: selfdoc-lint — real beads golden-path → pass
# ---------------------------------------------------------------------------
t0_dir="$tmpdir/t0"
mkdir -p "$t0_dir"
run_test "selfdoc-lint: real beads pass" 0 \
  bash -c "cd '$t0_dir' && SELFDOC_ISSUES_FILE='$REPO_DIR/.beads/issues.jsonl' bash '$REPO_DIR/scripts/check_bead_self_documentation.sh'"

# ---------------------------------------------------------------------------
# T1: selfdoc-lint — bead with no sections → fail
# ---------------------------------------------------------------------------
t1_dir="$tmpdir/t1"
mkdir -p "$t1_dir"
printf '{"id":"bad-001","title":"Bad","description":"nothing","status":"open","priority":2,"issue_type":"task","created_at":"2026-01-01T00:00:00Z","created_by":"test","updated_at":"2026-01-01T00:00:00Z","source_repo":".","compaction_level":0,"original_size":0}\n' \
  > "$t1_dir/issues.jsonl"

run_test "selfdoc-lint: missing sections" 1 \
  env SELFDOC_ISSUES_FILE="$t1_dir/issues.jsonl" bash "$REPO_DIR/scripts/check_bead_self_documentation.sh"

# ---------------------------------------------------------------------------
# T2: selfdoc-lint — epic is skipped (not checked) → pass
# ---------------------------------------------------------------------------
t2_dir="$tmpdir/t2"
mkdir -p "$t2_dir"
printf '{"id":"epic-001","title":"Epic","description":"no sections","status":"open","priority":2,"issue_type":"epic","created_at":"2026-01-01T00:00:00Z","created_by":"test","updated_at":"2026-01-01T00:00:00Z","source_repo":".","compaction_level":0,"original_size":0}\n' \
  > "$t2_dir/issues.jsonl"

run_test "selfdoc-lint: epic skipped" 0 \
  env SELFDOC_ISSUES_FILE="$t2_dir/issues.jsonl" bash "$REPO_DIR/scripts/check_bead_self_documentation.sh"

# ---------------------------------------------------------------------------
# T3: selfdoc-lint — audit mode reports but passes
# ---------------------------------------------------------------------------
run_test "selfdoc-lint: audit mode pass" 0 \
  env SELFDOC_ISSUES_FILE="$t1_dir/issues.jsonl" SELFDOC_LINT_PHASE=audit \
  bash "$REPO_DIR/scripts/check_bead_self_documentation.sh"

# ---------------------------------------------------------------------------
# T4: selfdoc-lint — closed task is skipped → pass
# ---------------------------------------------------------------------------
t4a_dir="$tmpdir/t4a"
mkdir -p "$t4a_dir"
printf '{"id":"closed-001","title":"Old","description":"nothing","status":"closed","priority":2,"issue_type":"task","created_at":"2026-01-01T00:00:00Z","created_by":"test","updated_at":"2026-01-01T00:00:00Z","source_repo":".","compaction_level":0,"original_size":0}\n' \
  > "$t4a_dir/issues.jsonl"

run_test "selfdoc-lint: closed task skipped" 0 \
  env SELFDOC_ISSUES_FILE="$t4a_dir/issues.jsonl" bash "$REPO_DIR/scripts/check_bead_self_documentation.sh"

# ---------------------------------------------------------------------------
# T4b: selfdoc-lint — blocked task remains actionable → fail
# ---------------------------------------------------------------------------
t4b_dir="$tmpdir/t4b"
mkdir -p "$t4b_dir"
printf '{"id":"blocked-001","title":"Blocked","description":"nothing","status":"blocked","priority":2,"issue_type":"task","created_at":"2026-01-01T00:00:00Z","created_by":"test","updated_at":"2026-01-01T00:00:00Z","source_repo":".","compaction_level":0,"original_size":0}\n' \
  > "$t4b_dir/issues.jsonl"

run_test "selfdoc-lint: blocked task linted" 1 \
  env SELFDOC_ISSUES_FILE="$t4b_dir/issues.jsonl" bash "$REPO_DIR/scripts/check_bead_self_documentation.sh"

# ---------------------------------------------------------------------------
# T5: selfdoc-lint — bare N/A in E2E → warning (strict fails)
# ---------------------------------------------------------------------------
t5a_dir="$tmpdir/t5a"
mkdir -p "$t5a_dir"
printf '{"id":"na-001","title":"Bare NA","description":"## Acceptance Criteria\\nok\\n## Unit Tests\\nok\\n## E2E\\nN/A\\n## Structured Logging\\nN/A\\n## Evidence\\nok\\n## Traceability\\n- PLAN: §0.3.1 item 1.\\n- FEATURE_PARITY: row 1.","status":"open","priority":2,"issue_type":"task","created_at":"2026-01-01T00:00:00Z","created_by":"test","updated_at":"2026-01-01T00:00:00Z","source_repo":".","compaction_level":0,"original_size":0}\n' \
  > "$t5a_dir/issues.jsonl"

run_test "selfdoc-lint: bare N/A strict fail" 1 \
  env SELFDOC_ISSUES_FILE="$t5a_dir/issues.jsonl" SELFDOC_LINT_PHASE=strict \
  bash "$REPO_DIR/scripts/check_bead_self_documentation.sh"

# ---------------------------------------------------------------------------
# T6: selfdoc-lint — unstructured traceability → error
# ---------------------------------------------------------------------------
t6a_dir="$tmpdir/t6a"
mkdir -p "$t6a_dir"
printf '{"id":"trace-001","title":"Weak","description":"## Acceptance Criteria\\nok\\n## Unit Tests\\nok\\n## E2E\\nN/A + justification: pure-function.\\n## Structured Logging\\nN/A + justification: pure-function.\\n## Evidence\\nok\\n## Traceability\\nSee PLAN and FEATURE_PARITY somewhere.","status":"open","priority":2,"issue_type":"task","created_at":"2026-01-01T00:00:00Z","created_by":"test","updated_at":"2026-01-01T00:00:00Z","source_repo":".","compaction_level":0,"original_size":0}\n' \
  > "$t6a_dir/issues.jsonl"

run_test "selfdoc-lint: unstructured traceability" 1 \
  env SELFDOC_ISSUES_FILE="$t6a_dir/issues.jsonl" bash "$REPO_DIR/scripts/check_bead_self_documentation.sh"

# ---------------------------------------------------------------------------
# T7: doc-contract-drift — remove ExtInfo from PROPOSAL → fail
# ---------------------------------------------------------------------------
t7b_dir="$tmpdir/t7b"
mkdir -p "$t7b_dir"
for f in COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md PLAN_TO_PORT_SSH_TO_RUST.md \
         PROPOSED_ARCHITECTURE.md FRANKENSSH_PROPOSAL.md \
         AGENTIC_ENV_SETUP.md AGENTS.md; do
  cp "$REPO_DIR/$f" "$t7b_dir/"
done
sed -i 's/ExtInfo/REDACTED/g' "$t7b_dir/FRANKENSSH_PROPOSAL.md"

run_test "doc-contract-drift: broken ExtInfo" 1 \
  bash -c "cd '$t7b_dir' && bash '$REPO_DIR/scripts/check_doc_contract_drift.sh'"

# ---------------------------------------------------------------------------
# T8: doc-contract-drift — clean main → pass
# ---------------------------------------------------------------------------
t8_dir="$tmpdir/t8"
mkdir -p "$t8_dir"
for f in COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md PLAN_TO_PORT_SSH_TO_RUST.md \
         PROPOSED_ARCHITECTURE.md FRANKENSSH_PROPOSAL.md \
         AGENTIC_ENV_SETUP.md AGENTS.md; do
  cp "$REPO_DIR/$f" "$t8_dir/"
done

if [[ "$MODE" == "ci" ]]; then
  skip_test "doc-contract-drift: clean main" "mode=ci (already checked by workflow step)"
else
  run_test "doc-contract-drift: clean main" 0 \
    bash -c "cd '$t8_dir' && bash '$REPO_DIR/scripts/check_doc_contract_drift.sh'"
fi

# ---------------------------------------------------------------------------
# T9: anchor-check — shift line in SPEC → mismatched anchors → fail
# ---------------------------------------------------------------------------
t9_dir="$tmpdir/t9"
mkdir -p "$t9_dir/scripts"
for f in COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md PLAN_TO_PORT_SSH_TO_RUST.md FRANKENSSH_PROPOSAL.md PROPOSED_ARCHITECTURE.md FEATURE_PARITY.md PHASE2_REVIEW_CHECKLIST_FOR_CLAUDE.md; do
  cp "$REPO_DIR/$f" "$t9_dir/"
done
cp "$REPO_DIR/scripts/anchor_expectations.tsv" "$t9_dir/scripts/"
sed -i '232 a\\' "$t9_dir/COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md"

run_test "anchor-check: shifted line" 1 \
  bash -c "cd '$t9_dir' && bash '$REPO_DIR/scripts/check_review_anchors.sh'"

# ---------------------------------------------------------------------------
# T10: anchor-check — clean main → pass
# ---------------------------------------------------------------------------
t10_dir="$tmpdir/t10"
mkdir -p "$t10_dir/scripts"
for f in COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md PLAN_TO_PORT_SSH_TO_RUST.md FRANKENSSH_PROPOSAL.md PROPOSED_ARCHITECTURE.md FEATURE_PARITY.md PHASE2_REVIEW_CHECKLIST_FOR_CLAUDE.md; do
  cp "$REPO_DIR/$f" "$t10_dir/"
done
cp "$REPO_DIR/scripts/anchor_expectations.tsv" "$t10_dir/scripts/"

if [[ "$MODE" == "ci" ]]; then
  skip_test "anchor-check: clean main" "mode=ci (already checked by workflow step)"
else
  run_test "anchor-check: clean main" 0 \
    bash -c "cd '$t10_dir' && bash '$REPO_DIR/scripts/check_review_anchors.sh'"
fi

# ---------------------------------------------------------------------------
# T11: anchor-check — missing expectations file → hard fail
# ---------------------------------------------------------------------------
run_test "anchor-check: missing expectations hard fail" 1 \
  bash -c "cd '$t10_dir' && ANCHOR_EXPECTATIONS=/tmp/nonexistent.tsv bash '$REPO_DIR/scripts/check_review_anchors.sh'"

# ---------------------------------------------------------------------------
# T12: doc-contract-drift — remove preflight.sh from AGENTIC → C10 fail
# ---------------------------------------------------------------------------
t12_dir="$tmpdir/t12"
mkdir -p "$t12_dir"
for f in COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md PLAN_TO_PORT_SSH_TO_RUST.md \
         PROPOSED_ARCHITECTURE.md FRANKENSSH_PROPOSAL.md \
         AGENTIC_ENV_SETUP.md AGENTS.md; do
  cp "$REPO_DIR/$f" "$t12_dir/"
done
sed -i 's/preflight\.sh/REDACTED/g' "$t12_dir/AGENTIC_ENV_SETUP.md"

run_test "doc-contract-drift: broken C10 preflight ref" 1 \
  bash -c "cd '$t12_dir' && bash '$REPO_DIR/scripts/check_doc_contract_drift.sh'"

# ---------------------------------------------------------------------------
# T13: doc-contract-drift — inject auto_register=true → C9b fail
# ---------------------------------------------------------------------------
t13_dir="$tmpdir/t13"
mkdir -p "$t13_dir"
for f in COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md PLAN_TO_PORT_SSH_TO_RUST.md \
         PROPOSED_ARCHITECTURE.md FRANKENSSH_PROPOSAL.md \
         AGENTIC_ENV_SETUP.md AGENTS.md; do
  cp "$REPO_DIR/$f" "$t13_dir/"
done
printf '\nauto_register = true\n' >> "$t13_dir/AGENTIC_ENV_SETUP.md"

run_test "doc-contract-drift: C9b auto_register=true detected" 1 \
  bash -c "cd '$t13_dir' && bash '$REPO_DIR/scripts/check_doc_contract_drift.sh'"

# ---------------------------------------------------------------------------
# T14: doc-contract-drift — remove Agent Mail Identity ref → C8 fail
# ---------------------------------------------------------------------------
t14_dir="$tmpdir/t14"
mkdir -p "$t14_dir"
for f in COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md PLAN_TO_PORT_SSH_TO_RUST.md \
         PROPOSED_ARCHITECTURE.md FRANKENSSH_PROPOSAL.md \
         AGENTIC_ENV_SETUP.md AGENTS.md; do
  cp "$REPO_DIR/$f" "$t14_dir/"
done
sed -i 's/Agent Mail Identity/REDACTED/g' "$t14_dir/AGENTIC_ENV_SETUP.md"

run_test "doc-contract-drift: broken C8 agents ref" 1 \
  bash -c "cd '$t14_dir' && bash '$REPO_DIR/scripts/check_doc_contract_drift.sh'"

# ---------------------------------------------------------------------------
# T15: doc-contract-drift — remove auto_register=false → C9 fail
# ---------------------------------------------------------------------------
t15_dir="$tmpdir/t15"
mkdir -p "$t15_dir"
for f in COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md PLAN_TO_PORT_SSH_TO_RUST.md \
         PROPOSED_ARCHITECTURE.md FRANKENSSH_PROPOSAL.md \
         AGENTIC_ENV_SETUP.md AGENTS.md; do
  cp "$REPO_DIR/$f" "$t15_dir/"
done
sed -i 's/auto_register *= *false/auto_register_disabled/g' "$t15_dir/AGENTIC_ENV_SETUP.md"

run_test "doc-contract-drift: broken C9 auto_register=false" 1 \
  bash -c "cd '$t15_dir' && bash '$REPO_DIR/scripts/check_doc_contract_drift.sh'"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n=== results: %d/%d passed (%d skipped) ===\n' "$PASS" "$TOTAL" "$SKIP"
if [[ $FAIL -gt 0 ]]; then
  printf 'FAIL: %d test(s) failed\n' "$FAIL"
  exit 1
else
  printf 'PASS: all governance gate tests passed\n'
  exit 0
fi
