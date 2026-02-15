#!/usr/bin/env bash
# check_doc_contract_drift.sh — cross-file contract consistency gate
#
# Verifies key governance contracts are consistently expressed across
# the normative document set (SPEC, PLAN, PROPOSAL, ARCH).
#
# Output: doc-contract-drift-report.json
set -euo pipefail

REPORT_FILE="doc-contract-drift-report.json"

command -v jq >/dev/null 2>&1 || { printf 'ERROR: jq not found\n' >&2; exit 2; }

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

checks_file="$tmpdir/checks.jsonl"
: > "$checks_file"
ERRORS=0

# --- helper ----------------------------------------------------------------

# check_contract RULE_ID PATTERN FILE [FILE...]
# Verifies PATTERN (grep -iE) appears in every listed FILE.
# Flattens line breaks before matching so contracts that span two
# lines (e.g. "ParseError … \n … re-exported") are detected.
check_contract() {
  local rule="$1" pattern="$2"
  shift 2
  local files=("$@")
  local missing=()

  for f in "${files[@]}"; do
    if [[ ! -f "$f" ]]; then
      missing+=("$f (not found)")
    elif ! tr '\n' ' ' < "$f" | grep -qiE "$pattern"; then
      missing+=("$f")
    fi
  done

  local status="pass" detail=""
  if [[ ${#missing[@]} -gt 0 ]]; then
    status="fail"
    detail="Pattern not found in: $(IFS=', '; echo "${missing[*]}")"
    ((ERRORS++)) || true
  fi

  local files_json
  files_json=$(printf '%s\n' "${files[@]}" | jq -R . | jq -s .)

  jq -n \
    --arg rule "$rule" \
    --arg status "$status" \
    --argjson files "$files_json" \
    --arg detail "$detail" \
    '{rule:$rule, status:$status, files:$files, detail:$detail}' \
    >> "$checks_file"
}

# --- document aliases ------------------------------------------------------

SPEC="COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md"
PLAN="PLAN_TO_PORT_SSH_TO_RUST.md"
PROP="FRANKENSSH_PROPOSAL.md"
ARCH="PROPOSED_ARCHITECTURE.md"

# --- contract definitions --------------------------------------------------

# C1: ParseError mentioned across all normative docs
check_contract "parseerror-mention" \
  "ParseError" \
  "$SPEC" "$ARCH" "$PLAN" "$PROP"

# C2: ParseError re-export provenance (fsh-types -> fsh-error)
check_contract "parseerror-reexport" \
  "re-export.*ParseError|ParseError.*re-export" \
  "$SPEC" "$ARCH" "$PLAN" "$PROP"

# C3: read_bool in helper baseline
check_contract "helper-read-bool" \
  "read_bool" \
  "$SPEC" "$PLAN" "$PROP"

# C4: read_name_list in helper baseline
check_contract "helper-read-name-list" \
  "read_name_list" \
  "$SPEC" "$PLAN" "$PROP"

# C5: read_mpint in helper baseline
check_contract "helper-read-mpint" \
  "read_mpint" \
  "$SPEC" "$PLAN" "$PROP"

# C6: ExtInfo in Phase 2 baseline
check_contract "extinfo-baseline" \
  "ExtInfo" \
  "$SPEC" "$PROP"

# C7: wire fail-closed through ParseError (SPEC + PLAN)
check_contract "wire-fail-closed" \
  "fail.closed.*ParseError|ParseError.*fail.closed|fail closed.*deterministic" \
  "$SPEC" "$PLAN"

# --- report ----------------------------------------------------------------

checks_json=$(jq -s '.' "$checks_file")

pass=true
if [[ $ERRORS -gt 0 ]]; then
  pass=false
fi

jq -n \
  --argjson pass "$pass" \
  --argjson checks "$checks_json" \
  '{pass:$pass, checks:$checks}' \
  > "$REPORT_FILE"

# --- summary ---------------------------------------------------------------

printf '\n=== doc-contract-drift ===\n'
jq -r '.checks[] | "  [\(.status)] \(.rule)"' "$REPORT_FILE"

if [[ "$pass" == "false" ]]; then
  printf '\nFailed contracts:\n'
  jq -r '.checks[] | select(.status=="fail") | "  \(.rule): \(.detail)"' "$REPORT_FILE"
  printf '\nFAIL: doc-contract-drift gate failed\n'
  exit 1
else
  printf '\nPASS: doc-contract-drift gate passed\n'
  exit 0
fi
