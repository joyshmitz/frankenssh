#!/usr/bin/env bash
# check_bead_self_documentation.sh — selfdoc-lint for frankenssh beads
#
# Validates implementation beads (issue_type=task) have required
# self-documentation sections per governance contract.
#
# Environment:
#   SELFDOC_LINT_PHASE  audit|default|strict  (default: default)
#     audit   — report only, always exit 0
#     default — fail on errors, report warnings
#     strict  — fail on errors AND warnings (min_fail_severity=warning)
#
# Output: selfdoc-lint-report.json
set -euo pipefail

ISSUES_FILE="${SELFDOC_ISSUES_FILE:-.beads/issues.jsonl}"
REPORT_FILE="selfdoc-lint-report.json"
PHASE="${SELFDOC_LINT_PHASE:-default}"

# --- preflight -----------------------------------------------------------

command -v jq >/dev/null 2>&1 || { printf 'ERROR: jq not found\n' >&2; exit 2; }

case "$PHASE" in
  audit|default|strict) ;;
  *) printf 'ERROR: invalid phase "%s" (must be audit|default|strict)\n' "$PHASE" >&2; exit 2 ;;
esac

if [[ ! -f "$ISSUES_FILE" ]]; then
  jq -n --arg p "$PHASE" --arg f "$ISSUES_FILE" '{
    pass:false, phase:$p, total:0, errors:1, warnings:0,
    violations:[{id:"V1", severity:"error", bead_id:"",
      rule:"FILE_EXISTS", message:($f+" not found"),
      fix_hint:"Run br sync --flush-only"}]
  }' > "$REPORT_FILE"
  printf 'FAIL: %s not found\n' "$ISSUES_FILE" >&2
  exit 1
fi

# --- workspace ------------------------------------------------------------

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

violations_file="$tmpdir/violations.jsonl"
: > "$violations_file"

TOTAL=0
ERRORS=0
WARNINGS=0
VSEQ=0

# --- helpers ---------------------------------------------------------------

add_violation() {
  local severity="$1" bead_id="$2" rule="$3" message="$4" fix_hint="$5"
  ((VSEQ++)) || true
  jq -n \
    --arg id "V${VSEQ}" --arg s "$severity" --arg b "$bead_id" \
    --arg r "$rule" --arg m "$message" --arg f "$fix_hint" \
    '{id:$id, severity:$s, bead_id:$b, rule:$r, message:$m, fix_hint:$f}' \
    >> "$violations_file"
  case "$severity" in
    error)   ((ERRORS++))   || true ;;
    warning) ((WARNINGS++)) || true ;;
  esac
}

# Extract text between "## $header" and the next "## " (or EOF).
extract_section() {
  local file="$1" header="$2"
  awk -v h="## $header" '
    $0 == h { found=1; next }
    found && /^## / { exit }
    found { print }
  ' "$file"
}

# --- rules -----------------------------------------------------------------

REQUIRED_SECTIONS=(
  "Acceptance Criteria"
  "Unit Tests"
  "E2E"
  "Structured Logging"
  "Evidence"
  "Traceability"
)

# --- main loop -------------------------------------------------------------

while IFS= read -r line; do
  issue_type=$(printf '%s' "$line" | jq -r '.issue_type // ""')
  [[ "$issue_type" == "task" ]] || continue

  ((TOTAL++)) || true
  bead_id=$(printf '%s' "$line" | jq -r '.id')
  title=$(printf '%s' "$line" | jq -r '.title')
  has_deps=$(printf '%s' "$line" | jq -r \
    'if (.dependencies // []) | length > 0 then "yes" else "no" end')

  desc_file="$tmpdir/desc_${bead_id}"
  printf '%s' "$line" | jq -r '.description // ""' > "$desc_file"

  # R1 — required sections exist
  for section in "${REQUIRED_SECTIONS[@]}"; do
    if ! grep -q "^## ${section}$" "$desc_file" 2>/dev/null; then
      add_violation "error" "$bead_id" "SECT_MISSING" \
        "Missing required section: ## ${section}" \
        "Add '## ${section}' section to bead ${bead_id} (${title})"
    fi
  done

  # R2 — ## Traceability must reference PLAN and FEATURE_PARITY
  if grep -q "^## Traceability$" "$desc_file" 2>/dev/null; then
    trace=$(extract_section "$desc_file" "Traceability")
    if ! printf '%s' "$trace" | grep -qi "PLAN"; then
      add_violation "error" "$bead_id" "TRACE_PLAN" \
        "## Traceability missing PLAN reference" \
        "Add 'PLAN: §...' to ## Traceability in ${bead_id}"
    fi
    if ! printf '%s' "$trace" | grep -qi "FEATURE_PARITY"; then
      add_violation "error" "$bead_id" "TRACE_PARITY" \
        "## Traceability missing FEATURE_PARITY reference" \
        "Add 'FEATURE_PARITY: row ...' to ## Traceability in ${bead_id}"
    fi
  fi

  # R3 — ## E2E must have content (command/expected or N/A + justification)
  if grep -q "^## E2E$" "$desc_file" 2>/dev/null; then
    e2e=$(extract_section "$desc_file" "E2E" | sed '/^[[:space:]]*$/d')
    if [[ -z "$e2e" ]]; then
      add_violation "warning" "$bead_id" "E2E_EMPTY" \
        "## E2E section has no content" \
        "Add command/expected or 'N/A + justification' in ${bead_id}"
    fi
  fi

  # R4 — ## Structured Logging must have content
  if grep -q "^## Structured Logging$" "$desc_file" 2>/dev/null; then
    sl=$(extract_section "$desc_file" "Structured Logging" | sed '/^[[:space:]]*$/d')
    if [[ -z "$sl" ]]; then
      add_violation "warning" "$bead_id" "LOGGING_EMPTY" \
        "## Structured Logging section has no content" \
        "Add requirements or 'N/A + justification' in ${bead_id}"
    fi
  fi

  # R5 — beads with dependencies must have ## Dependency Justification
  if [[ "$has_deps" == "yes" ]]; then
    if ! grep -q "^## Dependency Justification$" "$desc_file" 2>/dev/null; then
      add_violation "error" "$bead_id" "SECT_DEP_JUST" \
        "Bead has dependencies but missing ## Dependency Justification" \
        "Add '## Dependency Justification' to ${bead_id} (${title})"
    fi
  fi

done < "$ISSUES_FILE"

# --- report ----------------------------------------------------------------

violations_json=$(jq -s '.' "$violations_file")

case "$PHASE" in
  audit)   pass_val=true ;;
  default) [[ $ERRORS -eq 0 ]] && pass_val=true || pass_val=false ;;
  strict)  [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]] && pass_val=true || pass_val=false ;;
esac

jq -n \
  --argjson pass "$pass_val" \
  --arg     phase "$PHASE" \
  --argjson total "$TOTAL" \
  --argjson errors "$ERRORS" \
  --argjson warnings "$WARNINGS" \
  --argjson violations "$violations_json" \
  '{pass:$pass, phase:$phase, total:$total, errors:$errors,
    warnings:$warnings, violations:$violations}' \
  > "$REPORT_FILE"

# --- summary ---------------------------------------------------------------

printf '\n=== selfdoc-lint ===\n'
printf 'Phase:    %s\n' "$PHASE"
printf 'Beads:    %d\n' "$TOTAL"
printf 'Errors:   %d\n' "$ERRORS"
printf 'Warnings: %d\n' "$WARNINGS"

if [[ $(jq 'length' <<< "$violations_json") -gt 0 ]]; then
  printf '\nViolations:\n'
  jq -r '.[] | "  [\(.severity)] \(.bead_id): \(.rule) — \(.message)"' \
    <<< "$violations_json"
fi

if [[ "$pass_val" == "false" ]]; then
  printf '\nFAIL: selfdoc-lint gate failed\n'
  exit 1
else
  printf '\nPASS: selfdoc-lint gate passed\n'
  exit 0
fi
