#!/usr/bin/env bash
# check_review_anchors.sh — two-layer anchor validation
#
# Layer A (all anchors): file exists + line reachable.
# Layer B (critical contracts): line matches expected regex from
#   scripts/anchor_expectations.tsv.
#
# Output: anchor-check-report.json
set -euo pipefail

CHECKLIST="${ANCHOR_CHECKLIST:-PHASE2_REVIEW_CHECKLIST_FOR_CLAUDE.md}"
EXPECTATIONS="${ANCHOR_EXPECTATIONS:-scripts/anchor_expectations.tsv}"
REPORT_FILE="anchor-check-report.json"

command -v jq >/dev/null 2>&1 || { printf 'ERROR: jq not found\n' >&2; exit 2; }

if [[ ! -f "$CHECKLIST" ]]; then
  printf 'ERROR: %s not found\n' "$CHECKLIST" >&2
  exit 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

missing_file="$tmpdir/missing.jsonl"
mismatched_file="$tmpdir/mismatched.jsonl"
: > "$missing_file"
: > "$mismatched_file"

TOTAL=0
MISSING=0
MISMATCHED=0

# --- Layer A: extract all anchors and check existence ----------------------

# Anchors look like FILENAME.md:NNN (may contain digits/underscores in name)
grep -oE '[A-Za-z_0-9]+\.md:[0-9]+' "$CHECKLIST" | sort -u > "$tmpdir/anchors.txt"

while IFS= read -r anchor; do
  file="${anchor%%:*}"
  line="${anchor##*:}"
  ((TOTAL++)) || true

  if [[ ! -f "$file" ]]; then
    ((MISSING++)) || true
    jq -n --arg a "$anchor" --arg r "file not found" \
      '{anchor:$a, reason:$r}' >> "$missing_file"
  else
    total_lines=$(wc -l < "$file")
    if [[ "$line" -gt "$total_lines" ]]; then
      ((MISSING++)) || true
      jq -n --arg a "$anchor" \
        --arg r "line $line exceeds file length ($total_lines)" \
        '{anchor:$a, reason:$r}' >> "$missing_file"
    fi
  fi
done < "$tmpdir/anchors.txt"

# --- Layer B: semantic regex check -----------------------------------------

if [[ -f "$EXPECTATIONS" ]]; then
  while IFS=$'\t' read -r anchor regex rule_id; do
    # Skip comments and empty lines
    [[ "$anchor" =~ ^#.*$ || -z "$anchor" ]] && continue

    file="${anchor%%:*}"
    line="${anchor##*:}"

    # Skip if file missing or line unreachable (already in Layer A)
    [[ ! -f "$file" ]] && continue
    total_lines=$(wc -l < "$file")
    [[ "$line" -gt "$total_lines" ]] && continue

    actual=$(sed -n "${line}p" "$file")
    if ! printf '%s' "$actual" | grep -qE "$regex"; then
      ((MISMATCHED++)) || true
      jq -n \
        --arg a "$anchor" --arg rule "$rule_id" \
        --arg expected "$regex" --arg actual "$actual" \
        '{anchor:$a, rule:$rule, expected_regex:$expected, actual_content:$actual}' \
        >> "$mismatched_file"
    fi
  done < "$EXPECTATIONS"
fi

# --- report ----------------------------------------------------------------

missing_json=$(jq -s '.' "$missing_file")
mismatched_json=$(jq -s '.' "$mismatched_file")

pass=true
if [[ $MISSING -gt 0 || $MISMATCHED -gt 0 ]]; then
  pass=false
fi

jq -n \
  --argjson pass "$pass" \
  --argjson total "$TOTAL" \
  --argjson missing_count "$MISSING" \
  --argjson mismatched_count "$MISMATCHED" \
  --argjson missing "$missing_json" \
  --argjson mismatched "$mismatched_json" \
  '{pass:$pass, total:$total, missing_count:$missing_count,
    mismatched_count:$mismatched_count, missing:$missing, mismatched:$mismatched}' \
  > "$REPORT_FILE"

# --- summary ---------------------------------------------------------------

printf '\n=== anchor-check ===\n'
printf 'Anchors:    %d\n' "$TOTAL"
printf 'Missing:    %d\n' "$MISSING"
printf 'Mismatched: %d\n' "$MISMATCHED"

if [[ $MISSING -gt 0 ]]; then
  printf '\nMissing anchors:\n'
  jq -r '.[] | "  \(.anchor): \(.reason)"' <<< "$missing_json"
fi

if [[ $MISMATCHED -gt 0 ]]; then
  printf '\nMismatched anchors:\n'
  jq -r '.[] | "  \(.anchor) [\(.rule)]: expected /\(.expected_regex)/"' <<< "$mismatched_json"
fi

if [[ "$pass" == "false" ]]; then
  printf '\nFAIL: anchor-check gate failed\n'
  exit 1
else
  printf '\nPASS: anchor-check gate passed\n'
  exit 0
fi
