#!/usr/bin/env bash
# test_governance_gates.sh — negative tests for governance gates
#
# Creates temp copies with deliberate breakage and verifies that each
# gate script detects the problem (non-zero exit).
#
# Usage: bash scripts/test_governance_gates.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

tmpdir=$(mktemp -d)
trap 'rm -r "$tmpdir"' EXIT

PASS=0
FAIL=0
TOTAL=0

run_test() {
  local name="$1" expect_exit="$2"
  shift 2
  ((TOTAL++)) || true
  local actual_exit=0
  "$@" > "$tmpdir/stdout_${TOTAL}.log" 2>&1 || actual_exit=$?
  if [[ "$actual_exit" -eq "$expect_exit" ]]; then
    ((PASS++)) || true
    printf '  [PASS] %s (exit=%d)\n' "$name" "$actual_exit"
  else
    ((FAIL++)) || true
    printf '  [FAIL] %s (expected exit=%d, got=%d)\n' "$name" "$expect_exit" "$actual_exit"
  fi
}

printf '=== governance gate negative tests ===\n\n'

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
# T4: doc-contract-drift — remove ExtInfo from PROPOSAL → fail
# ---------------------------------------------------------------------------
t4_dir="$tmpdir/t4"
mkdir -p "$t4_dir"
for f in COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md PLAN_TO_PORT_SSH_TO_RUST.md PROPOSED_ARCHITECTURE.md FRANKENSSH_PROPOSAL.md; do
  cp "$REPO_DIR/$f" "$t4_dir/"
done
sed -i 's/ExtInfo/REDACTED/g' "$t4_dir/FRANKENSSH_PROPOSAL.md"

run_test "doc-contract-drift: broken ExtInfo" 1 \
  bash -c "cd '$t4_dir' && bash '$REPO_DIR/scripts/check_doc_contract_drift.sh'"

# ---------------------------------------------------------------------------
# T5: doc-contract-drift — clean main → pass
# ---------------------------------------------------------------------------
t5_dir="$tmpdir/t5"
mkdir -p "$t5_dir"
for f in COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md PLAN_TO_PORT_SSH_TO_RUST.md PROPOSED_ARCHITECTURE.md FRANKENSSH_PROPOSAL.md; do
  cp "$REPO_DIR/$f" "$t5_dir/"
done

run_test "doc-contract-drift: clean main" 0 \
  bash -c "cd '$t5_dir' && bash '$REPO_DIR/scripts/check_doc_contract_drift.sh'"

# ---------------------------------------------------------------------------
# T6: anchor-check — shift line in SPEC → mismatched anchors → fail
# ---------------------------------------------------------------------------
t6_dir="$tmpdir/t6"
mkdir -p "$t6_dir/scripts"
for f in COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md PLAN_TO_PORT_SSH_TO_RUST.md FRANKENSSH_PROPOSAL.md PROPOSED_ARCHITECTURE.md FEATURE_PARITY.md PHASE2_REVIEW_CHECKLIST_FOR_CLAUDE.md; do
  cp "$REPO_DIR/$f" "$t6_dir/"
done
cp "$REPO_DIR/scripts/anchor_expectations.tsv" "$t6_dir/scripts/"
sed -i '232 a\\' "$t6_dir/COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md"

run_test "anchor-check: shifted line" 1 \
  bash -c "cd '$t6_dir' && bash '$REPO_DIR/scripts/check_review_anchors.sh'"

# ---------------------------------------------------------------------------
# T7: anchor-check — clean main → pass
# ---------------------------------------------------------------------------
t7_dir="$tmpdir/t7"
mkdir -p "$t7_dir/scripts"
for f in COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md PLAN_TO_PORT_SSH_TO_RUST.md FRANKENSSH_PROPOSAL.md PROPOSED_ARCHITECTURE.md FEATURE_PARITY.md PHASE2_REVIEW_CHECKLIST_FOR_CLAUDE.md; do
  cp "$REPO_DIR/$f" "$t7_dir/"
done
cp "$REPO_DIR/scripts/anchor_expectations.tsv" "$t7_dir/scripts/"

run_test "anchor-check: clean main" 0 \
  bash -c "cd '$t7_dir' && bash '$REPO_DIR/scripts/check_review_anchors.sh'"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n=== results: %d/%d passed ===\n' "$PASS" "$TOTAL"
if [[ $FAIL -gt 0 ]]; then
  printf 'FAIL: %d test(s) failed\n' "$FAIL"
  exit 1
else
  printf 'PASS: all governance gate tests passed\n'
  exit 0
fi
