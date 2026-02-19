#!/usr/bin/env bash
# preflight.sh — automated environment health and session readiness checks
#
# Replaces the manual smoke-check procedure from AGENTIC_ENV_SETUP.md §6.
# NOT added to CI (ntm/cass/acfs unavailable on GitHub runners).
#
# Usage:
#   bash scripts/preflight.sh --pre                          # infra health (6 checks)
#   bash scripts/preflight.sh --post                         # session readiness (16 checks)
#   bash scripts/preflight.sh --post --cargo                 # + build gate (20 checks)
#   bash scripts/preflight.sh --check cass-health,am-daemon  # specific checks
#   bash scripts/preflight.sh --list-checks                  # print all check IDs
#
# Exit codes: 0=clean/warn, 1=fail, 2=usage error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_MD="$REPO_DIR/AGENTS.md"
REPORT_FILE="$REPO_DIR/preflight-report.json"
PREFLIGHT_VERSION="1.0"

# Agent Mail defaults
AM_HOST="${AM_HOST:-127.0.0.1}"
AM_PORT="${AM_PORT:-8765}"

# ntm session name
NTM_SESSION="${NTM_SESSION:-frankenssh}"

# ---------------------------------------------------------------------------
# Canonical Check Registry — single source of truth (v19-F2)
# ---------------------------------------------------------------------------

CHECK_REGISTRY=(
  "pre:acfs-doctor"
  "pre:ntm-doctor"
  "pre:am-daemon"
  "pre:cass-health"
  "pre:cm-context"
  "pre:ms-doctor"
  "post:ntm-session"
  "post:mcp-claude-am"
  "post:mcp-claude-ms"
  "post:mcp-codex-am"
  "post:mcp-codex-ms"
  "post:agents-registered"
  "post:agents-no-extra"
  "post:governance-contracts"
  "post:governance-anchors"
  "post:governance-tests"
  "cargo:cargo-fmt"
  "cargo:cargo-check"
  "cargo:cargo-clippy"
  "cargo:cargo-test"
)

ALL_CHECK_IDS=$(printf '%s\n' "${CHECK_REGISTRY[@]}" | cut -d: -f2 | paste -sd,)

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------

MODE=""
CARGO=false
CHECK_FILTER=""
PASS=0 FAIL=0 WARN=0 FIX=0 SKIP=0 TOTAL=0

_script_start=0
_check_start=0

tmpdir=""
checks_file=""

# AM state shared between pre and post checks
am_daemon_ok=false
actual_agents=""

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
  cat >&2 <<'EOF'
Usage: bash scripts/preflight.sh [OPTIONS]

Options:
  --pre              Infrastructure health checks (6 checks)
  --post             Session readiness checks (includes --pre, 16 checks)
  --cargo            Build gate (requires --post, +4 = 20 checks)
  --check ID[,ID]    Run specific check(s) by ID
  --list-checks      Print all check IDs and exit

Exit codes: 0=clean/warn, 1=fail, 2=usage error
EOF
}

# ---------------------------------------------------------------------------
# Timing (R1) — $EPOCHREALTIME (bash 5.0+, verified bash 5.2)
# ---------------------------------------------------------------------------

start_timer() { _check_start=$EPOCHREALTIME; }

elapsed_ms() {
  local now=$EPOCHREALTIME
  local start_us=${_check_start/./} now_us=${now/./}
  echo $(( (now_us - start_us) / 1000 ))
}

# ---------------------------------------------------------------------------
# Check filter (v19-F3, v20-F1, v20-F2)
# ---------------------------------------------------------------------------

should_run() {
  [[ -z "$CHECK_FILTER" ]] && return 0
  [[ ",$CHECK_FILTER," == *",$1,"* ]]
}

normalize_check_filter() {
  local normalized="" seen=""
  IFS=',' read -ra ids <<< "$CHECK_FILTER"
  for id in "${ids[@]}"; do
    id=$(printf '%s' "$id" | xargs)
    [[ -n "$id" ]] || continue
    [[ ",$seen," == *",$id,"* ]] && continue
    seen="${seen:+$seen,}$id"
    normalized="${normalized:+$normalized,}$id"
  done
  CHECK_FILTER="$normalized"

  if [[ -z "$CHECK_FILTER" ]]; then
    printf 'ERROR: --check requires at least one valid check ID\n' >&2
    exit 2
  fi
}

validate_check_ids() {
  IFS=',' read -ra ids <<< "$CHECK_FILTER"
  for id in "${ids[@]}"; do
    if [[ ",$ALL_CHECK_IDS," != *",$id,"* ]]; then
      printf 'ERROR: unknown check ID: %s\n' "$id" >&2
      printf 'Valid IDs:\n' >&2
      printf '%s\n' "${CHECK_REGISTRY[@]}" | cut -d: -f2 | sed 's/^/  /' >&2
      exit 2
    fi
  done
}

check_category_for_id() {
  local id="$1" entry
  for entry in "${CHECK_REGISTRY[@]}"; do
    if [[ "${entry#*:}" == "$id" ]]; then
      printf '%s\n' "${entry%%:*}"
      return 0
    fi
  done
  return 1
}

category_enabled_for_mode() {
  local category="$1"
  case "$MODE" in
    all)
      return 0
      ;;
    pre)
      [[ "$category" == "pre" ]]
      ;;
    post)
      if [[ "$category" == "pre" || "$category" == "post" ]]; then
        return 0
      fi
      if [[ "$category" == "cargo" && "$CARGO" == "true" ]]; then
        return 0
      fi
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

validate_check_ids_for_mode() {
  local invalid=() id category
  IFS=',' read -ra ids <<< "$CHECK_FILTER"
  for id in "${ids[@]}"; do
    category=$(check_category_for_id "$id") || continue
    if ! category_enabled_for_mode "$category"; then
      invalid+=("$id($category)")
    fi
  done

  if [[ ${#invalid[@]} -gt 0 ]]; then
    printf 'ERROR: --check contains IDs incompatible with mode "%s": %s\n' \
      "$MODE" "$(IFS=', '; echo "${invalid[*]}")" >&2
    case "$MODE" in
      pre)
        printf 'Allowed categories for this run: pre\n' >&2
        ;;
      post)
        if [[ "$CARGO" == "true" ]]; then
          printf 'Allowed categories for this run: pre, post, cargo\n' >&2
        else
          printf 'Allowed categories for this run: pre, post\n' >&2
        fi
        ;;
      all)
        printf 'Allowed categories for this run: pre, post, cargo\n' >&2
        ;;
    esac
    exit 2
  fi
}

list_checks() {
  for entry in "${CHECK_REGISTRY[@]}"; do
    printf '%-6s %s\n' "${entry%%:*}" "${entry#*:}"
  done
  exit 0
}

# ---------------------------------------------------------------------------
# Core deps — fail-fast (exit 2)
# ---------------------------------------------------------------------------

check_core_deps() {
  local missing=()
  for cmd in jq curl; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'ERROR: missing core tools: %s\n' "${missing[*]}" >&2
    exit 2
  fi
}

# ---------------------------------------------------------------------------
# Tool dep guard for single-check functions
# ---------------------------------------------------------------------------

require_tool() {
  local cmd="$1" check_id="$2" category="$3"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    record_check "$check_id" "$category" "fail" "$cmd not installed"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Record check result — JSONL + counters + live output (F1)
# ---------------------------------------------------------------------------

record_check() {
  local id="$1" cat="$2" status="$3" detail="$4" fix="${5:-}"
  local ms
  ms=$(elapsed_ms)

  # Append JSONL
  jq -n \
    --arg id "$id" --arg cat "$cat" --arg status "$status" \
    --arg detail "$detail" --arg fix "$fix" --argjson ms "$ms" \
    '{id:$id, category:$cat, status:$status, detail:$detail,
      fix_applied:(if $fix == "" then null else $fix end), duration_ms:$ms}' \
    >> "$checks_file"

  # Increment counters
  case "$status" in
    pass) ((PASS++)) || true ;;
    fail) ((FAIL++)) || true ;;
    warn) ((WARN++)) || true ;;
    fix)  ((FIX++))  || true ;;
    skip) ((SKIP++)) || true ;;
  esac

  # Live colored output
  local color
  case "$status" in
    pass) color="\033[32m";; fail) color="\033[31m";;
    warn) color="\033[33m";; fix)  color="\033[36m";;
    skip) color="\033[90m";;
  esac
  printf '  %b[%s]%b %s — %s (%dms)\n' "$color" "$status" "\033[0m" "$id" "$detail" "$ms"
}

# ---------------------------------------------------------------------------
# Parse args
# ---------------------------------------------------------------------------

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pre)    MODE="pre" ;;
      --post)   MODE="post" ;;
      --cargo)  CARGO=true ;;
      --check)
        shift
        [[ $# -gt 0 ]] || { printf 'ERROR: --check requires an argument\n' >&2; exit 2; }
        CHECK_FILTER="$1"
        ;;
      --list-checks) list_checks ;;
      -h|--help) usage; exit 0 ;;
      *)
        printf 'ERROR: unknown option: %s\n' "$1" >&2
        usage; exit 2
        ;;
    esac
    shift
  done

  # --cargo requires explicit --post
  if [[ "$CARGO" == "true" && "$MODE" != "post" ]]; then
    printf 'ERROR: --cargo requires --post\n' >&2
    exit 2
  fi

  if [[ -n "$CHECK_FILTER" ]]; then
    normalize_check_filter
    validate_check_ids
    if [[ -z "$MODE" ]]; then
      MODE="all"
    fi
    validate_check_ids_for_mode
  fi

  if [[ -z "$CHECK_FILTER" && -z "$MODE" ]]; then
    usage; exit 2
  fi
}

# ---------------------------------------------------------------------------
# Workspace setup
# ---------------------------------------------------------------------------

setup_workspace() {
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  checks_file="$tmpdir/checks.jsonl"
  : > "$checks_file"
  _script_start=$EPOCHREALTIME
}

# ---------------------------------------------------------------------------
# Pre checks (infrastructure, 6 checks)
# ---------------------------------------------------------------------------

check_acfs_doctor() {
  should_run "acfs-doctor" || return 0
  start_timer
  require_tool acfs "acfs-doctor" "pre" || return 0
  local out rc=0
  out=$(timeout 15 acfs doctor 2>&1) || rc=$?
  if [[ $rc -eq 0 ]]; then
    record_check "acfs-doctor" "pre" "pass" "exit 0"
  else
    record_check "acfs-doctor" "pre" "fail" "exit $rc"
  fi
  return 0
}

check_ntm_doctor() {
  should_run "ntm-doctor" || return 0
  start_timer
  require_tool ntm "ntm-doctor" "pre" || return 0
  local out
  out=$(timeout 15 ntm doctor 2>&1) || true
  if printf '%s\n' "$out" | grep -qi "HEALTHY"; then
    if printf '%s\n' "$out" | grep -qi "warning"; then
      record_check "ntm-doctor" "pre" "warn" "HEALTHY with warnings"
    else
      record_check "ntm-doctor" "pre" "pass" "HEALTHY"
    fi
  else
    record_check "ntm-doctor" "pre" "fail" "not HEALTHY"
  fi
  return 0
}

check_am_daemon() {
  should_run "am-daemon" || return 0
  start_timer
  local slug
  slug=$(printf '%s' "$REPO_DIR" | sed 's|^/||; s|/|-|g')
  local am_url="http://${AM_HOST}:${AM_PORT}/mail/api/projects/${slug}/agents"
  local http_code
  http_code=$(curl -s -o "$tmpdir/am_resp.json" -w '%{http_code}' --max-time 5 "$am_url" 2>/dev/null) || http_code="000"

  if [[ "$http_code" != "200" ]]; then
    record_check "am-daemon" "pre" "fail" "HTTP $http_code from $am_url"
  else
    if jq -e '.agents | type == "array"' "$tmpdir/am_resp.json" >/dev/null 2>&1; then
      record_check "am-daemon" "pre" "pass" "HTTP 200, .agents is array"
      am_daemon_ok=true
      actual_agents=$(jq -r '.agents[]' "$tmpdir/am_resp.json")
    else
      record_check "am-daemon" "pre" "fail" ".agents missing or not array"
    fi
  fi
  return 0
}

check_cass_health() {
  should_run "cass-health" || return 0
  start_timer
  require_tool cass "cass-health" "pre" || return 0
  local out rc=0
  out=$(timeout 15 cass status 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && ! printf '%s\n' "$out" | grep -qi "stale"; then
    record_check "cass-health" "pre" "pass" "healthy"
  else
    # Auto-fix: reindex
    local fix_out fix_rc=0
    fix_out=$(timeout 60 cass index 2>&1) || fix_rc=$?
    # Re-verify
    local out2 rc2=0
    out2=$(timeout 15 cass status 2>&1) || rc2=$?
    if [[ $rc2 -eq 0 ]] && ! printf '%s\n' "$out2" | grep -qi "stale"; then
      record_check "cass-health" "pre" "fix" "stale → auto-reindexed" "cass index"
    else
      record_check "cass-health" "pre" "fail" "still stale after cass index"
    fi
  fi
  return 0
}

check_cm_context() {
  should_run "cm-context" || return 0
  start_timer
  require_tool cm "cm-context" "pre" || return 0
  local out rc=0
  out=$(timeout 15 cm context "preflight" --json 2>&1) || rc=$?
  if [[ $rc -eq 0 ]]; then
    record_check "cm-context" "pre" "pass" "success"
  else
    record_check "cm-context" "pre" "fail" "exit $rc"
  fi
  return 0
}

check_ms_doctor() {
  should_run "ms-doctor" || return 0
  start_timer
  require_tool ms "ms-doctor" "pre" || return 0
  local out rc=0
  out=$(timeout 15 ms doctor 2>&1) || rc=$?
  if [[ $rc -eq 0 ]]; then
    record_check "ms-doctor" "pre" "pass" "exit 0"
  elif printf '%s\n' "$out" | grep -qi "LockBusy"; then
    record_check "ms-doctor" "pre" "warn" "LockBusy (ms mcp serve holds Tantivy lock)"
  else
    record_check "ms-doctor" "pre" "fail" "exit $rc"
  fi
  return 0
}

run_pre_checks() {
  [[ "$MODE" == "pre" || "$MODE" == "post" || "$MODE" == "all" ]] || return 0
  printf '=== pre checks (infrastructure) ===\n'
  check_acfs_doctor
  check_ntm_doctor
  check_am_daemon
  check_cass_health
  check_cm_context
  check_ms_doctor
}

# ---------------------------------------------------------------------------
# Post checks (session + agents + MCP + governance, 10 more)
# ---------------------------------------------------------------------------

check_ntm_session() {
  should_run "ntm-session" || return 0
  start_timer
  require_tool ntm "ntm-session" "post" || return 0
  local out rc=0
  out=$(timeout 15 ntm status "$NTM_SESSION" 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && printf '%s\n' "$out" | grep -qi "pane"; then
    record_check "ntm-session" "post" "pass" "panes exist"
  else
    record_check "ntm-session" "post" "fail" "session missing or no panes"
  fi
  return 0
}

check_mcp_claude() {
  should_run "mcp-claude-am" || should_run "mcp-claude-ms" || return 0
  start_timer
  if ! command -v claude >/dev/null 2>&1; then
    should_run "mcp-claude-am" && record_check "mcp-claude-am" "post" "fail" "claude not installed"
    should_run "mcp-claude-ms" && record_check "mcp-claude-ms" "post" "fail" "claude not installed"
    return 0
  fi
  local out
  # CLAUDECODE env var causes claude to attach to a running session instead
  # of producing independent status output. Unset to get clean MCP list. (F5)
  out=$(timeout 15 env -u CLAUDECODE claude mcp list 2>&1) || true

  if should_run "mcp-claude-am"; then
    start_timer
    if printf '%s\n' "$out" | grep -qE "^mcp-agent-mail:.*Connected"; then
      record_check "mcp-claude-am" "post" "pass" "Connected"
    else
      record_check "mcp-claude-am" "post" "fail" "not connected or timeout"
    fi
  fi

  if should_run "mcp-claude-ms"; then
    start_timer
    if printf '%s\n' "$out" | grep -qE "^meta-skill:.*Connected"; then
      record_check "mcp-claude-ms" "post" "pass" "Connected"
    else
      record_check "mcp-claude-ms" "post" "fail" "not connected or timeout"
    fi
  fi
  return 0
}

check_mcp_codex() {
  should_run "mcp-codex-am" || should_run "mcp-codex-ms" || return 0
  start_timer
  if ! command -v codex >/dev/null 2>&1; then
    should_run "mcp-codex-am" && record_check "mcp-codex-am" "post" "fail" "codex not installed"
    should_run "mcp-codex-ms" && record_check "mcp-codex-ms" "post" "fail" "codex not installed"
    return 0
  fi
  local out ready_line
  out=$(timeout 30 codex exec "exit" 2>&1) || true
  ready_line=$(printf '%s\n' "$out" | grep -E "^mcp startup: ready:" || true)

  if should_run "mcp-codex-am"; then
    start_timer
    if printf '%s\n' "$ready_line" | grep -qF "mcp-agent-mail"; then
      record_check "mcp-codex-am" "post" "pass" "in ready line"
    else
      record_check "mcp-codex-am" "post" "fail" "not in ready line or timeout"
    fi
  fi

  if should_run "mcp-codex-ms"; then
    start_timer
    if printf '%s\n' "$ready_line" | grep -qF "meta-skill"; then
      record_check "mcp-codex-ms" "post" "pass" "in ready line"
    else
      record_check "mcp-codex-ms" "post" "fail" "not in ready line or timeout"
    fi
  fi
  return 0
}

# AGENTS.md parser — side-effect-free (v19-F1)
# Parser contract: depends on exact table format. This is intentional.
EXPECTED_AGENTS=()

parse_expected_agents() {
  EXPECTED_AGENTS=()
  while IFS='|' read -r _ prog name _; do
    name=$(printf '%s' "$name" | xargs)
    [[ -z "$name" || "$name" == "Agent Name" || "$name" =~ ^-+$ ]] && continue
    EXPECTED_AGENTS+=("$name")
  done < <(awk '/^\| Program \| Agent Name/{found=1; next} found && /^#/{exit} found' "$AGENTS_MD")
  [[ ${#EXPECTED_AGENTS[@]} -gt 0 ]]
}

check_agents_registered() {
  start_timer
  local missing=()
  for name in "${EXPECTED_AGENTS[@]}"; do
    if ! printf '%s\n' "$actual_agents" | grep -qxF "$name"; then
      missing+=("$name")
    fi
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    record_check "agents-registered" "post" "pass" "all ${#EXPECTED_AGENTS[@]} agents present"
  else
    record_check "agents-registered" "post" "fail" "missing: ${missing[*]}"
  fi
  return 0
}

check_agents_no_extra() {
  start_timer
  local extras=()
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    local found=false
    for expected in "${EXPECTED_AGENTS[@]}"; do
      [[ "$name" == "$expected" ]] && { found=true; break; }
    done
    [[ "$found" == "false" ]] && extras+=("$name")
  done <<< "$actual_agents"
  if [[ ${#extras[@]} -eq 0 ]]; then
    record_check "agents-no-extra" "post" "pass" "no extra agents"
  else
    record_check "agents-no-extra" "post" "fail" "extras: ${extras[*]}"
  fi
  return 0
}

check_governance_contracts() {
  should_run "governance-contracts" || return 0
  start_timer
  local script="$REPO_DIR/scripts/check_doc_contract_drift.sh"
  if [[ ! -f "$script" ]]; then
    record_check "governance-contracts" "post" "fail" "script not found: $script"
    return 0
  fi
  local rc=0
  timeout 30 bash -c "cd '$REPO_DIR' && bash '$script'" > "$tmpdir/gov_contracts.log" 2>&1 || rc=$?
  if [[ $rc -eq 0 ]]; then
    record_check "governance-contracts" "post" "pass" "all contracts pass"
  else
    record_check "governance-contracts" "post" "fail" "exit $rc"
  fi
  return 0
}

check_governance_anchors() {
  should_run "governance-anchors" || return 0
  start_timer
  local script="$REPO_DIR/scripts/check_review_anchors.sh"
  if [[ ! -f "$script" ]]; then
    record_check "governance-anchors" "post" "fail" "script not found: $script"
    return 0
  fi
  local rc=0
  timeout 30 bash -c "cd '$REPO_DIR' && bash '$script'" > "$tmpdir/gov_anchors.log" 2>&1 || rc=$?
  if [[ $rc -eq 0 ]]; then
    record_check "governance-anchors" "post" "pass" "all anchors valid"
  else
    record_check "governance-anchors" "post" "fail" "exit $rc"
  fi
  return 0
}

check_governance_tests() {
  should_run "governance-tests" || return 0
  start_timer
  local script="$REPO_DIR/scripts/test_governance_gates.sh"
  if [[ ! -f "$script" ]]; then
    record_check "governance-tests" "post" "fail" "script not found: $script"
    return 0
  fi
  local rc=0
  timeout 120 env GOVERNANCE_TEST_MODE=ci bash "$script" > "$tmpdir/gov_tests.log" 2>&1 || rc=$?
  if [[ $rc -eq 0 ]]; then
    record_check "governance-tests" "post" "pass" "all governance tests pass"
  else
    record_check "governance-tests" "post" "fail" "exit $rc"
  fi
  return 0
}

run_post_checks() {
  [[ "$MODE" == "post" || "$MODE" == "all" ]] || return 0
  printf '\n=== post checks (session readiness) ===\n'

  check_ntm_session
  check_mcp_claude
  check_mcp_codex

  # Agents block — only enters if at least one agents check is requested (v19-F1)
  if should_run "agents-registered" || should_run "agents-no-extra"; then
    local agents_ok=false
    if [[ "$am_daemon_ok" != "true" ]]; then
      should_run "agents-registered" && {
        start_timer
        record_check "agents-registered" "post" "skip" "am-daemon failed"
      }
      should_run "agents-no-extra" && {
        start_timer
        record_check "agents-no-extra" "post" "skip" "am-daemon failed"
      }
    elif parse_expected_agents; then
      agents_ok=true
    else
      should_run "agents-registered" && {
        start_timer
        record_check "agents-registered" "post" "fail" "no agents found in AGENTS.md table"
      }
    fi

    if [[ "$agents_ok" == "true" ]]; then
      should_run "agents-registered" && check_agents_registered
      should_run "agents-no-extra" && check_agents_no_extra
    elif [[ "$am_daemon_ok" == "true" ]]; then
      # Parser failed but AM is up — skip agents-no-extra
      should_run "agents-no-extra" && {
        start_timer
        record_check "agents-no-extra" "post" "skip" "agents table parse failed"
      }
    fi
  fi

  # Governance checks ALWAYS run regardless of agents block
  check_governance_contracts
  check_governance_anchors
  check_governance_tests
}

# ---------------------------------------------------------------------------
# Cargo checks (opt-in build gate, +4)
# ---------------------------------------------------------------------------

check_cargo_fmt() {
  should_run "cargo-fmt" || return 0
  start_timer
  require_tool cargo "cargo-fmt" "cargo" || return 0
  local rc=0
  timeout 30 cargo fmt --check > "$tmpdir/cargo_fmt.log" 2>&1 || rc=$?
  if [[ $rc -eq 0 ]]; then
    record_check "cargo-fmt" "cargo" "pass" "exit 0"
  else
    record_check "cargo-fmt" "cargo" "fail" "exit $rc"
  fi
  return 0
}

check_cargo_check() {
  should_run "cargo-check" || return 0
  start_timer
  require_tool cargo "cargo-check" "cargo" || return 0
  local rc=0
  timeout 120 cargo check --all-targets > "$tmpdir/cargo_check.log" 2>&1 || rc=$?
  if [[ $rc -eq 0 ]]; then
    record_check "cargo-check" "cargo" "pass" "exit 0"
  else
    record_check "cargo-check" "cargo" "fail" "exit $rc"
  fi
  return 0
}

check_cargo_clippy() {
  should_run "cargo-clippy" || return 0
  start_timer
  require_tool cargo "cargo-clippy" "cargo" || return 0
  local rc=0
  timeout 120 cargo clippy --all-targets -- -D warnings > "$tmpdir/cargo_clippy.log" 2>&1 || rc=$?
  if [[ $rc -eq 0 ]]; then
    record_check "cargo-clippy" "cargo" "pass" "exit 0"
  else
    record_check "cargo-clippy" "cargo" "fail" "exit $rc"
  fi
  return 0
}

check_cargo_test() {
  should_run "cargo-test" || return 0
  start_timer
  require_tool cargo "cargo-test" "cargo" || return 0
  local rc=0
  timeout 120 cargo test --workspace > "$tmpdir/cargo_test.log" 2>&1 || rc=$?
  if [[ $rc -eq 0 ]]; then
    record_check "cargo-test" "cargo" "pass" "exit 0"
  else
    record_check "cargo-test" "cargo" "fail" "exit $rc"
  fi
  return 0
}

run_cargo_checks() {
  { [[ "$CARGO" == "true" ]] || [[ "$MODE" == "all" ]]; } || return 0
  printf '\n=== cargo checks (build gate) ===\n'
  check_cargo_fmt
  check_cargo_check
  check_cargo_clippy
  check_cargo_test
}

# ---------------------------------------------------------------------------
# Compute total (unique checks that should have run)
# ---------------------------------------------------------------------------

compute_total() {
  if [[ -n "$CHECK_FILTER" ]]; then
    # Count unique IDs in filter
    IFS=',' read -ra ids <<< "$CHECK_FILTER"
    TOTAL=${#ids[@]}
  else
    case "$MODE" in
      pre)  TOTAL=6 ;;
      post) TOTAL=16 ;;
      *)    TOTAL=20 ;;
    esac
    if [[ "$MODE" == "post" && "$CARGO" == "true" ]]; then
      TOTAL=20
    fi
  fi
}

# ---------------------------------------------------------------------------
# Report generation
# ---------------------------------------------------------------------------

generate_report() {
  local now_us=${EPOCHREALTIME/./}
  local start_us=${_script_start/./}
  local total_ms=$(( (now_us - start_us) / 1000 ))

  local result="clean"
  if [[ $FAIL -gt 0 ]]; then
    result="fail"
  elif [[ $WARN -gt 0 ]]; then
    result="warn"
  fi

  local report_mode="$MODE"
  if [[ "$MODE" == "all" ]]; then
    report_mode="check"
  fi

  local checks_json
  checks_json=$(jq -s '.' "$checks_file")

  jq -n \
    --arg ver "$PREFLIGHT_VERSION" \
    --arg result "$result" \
    --arg mode "$report_mode" \
    --argjson cargo "$( [[ "$CARGO" == "true" ]] && echo true || echo false )" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson duration "$total_ms" \
    --argjson total "$TOTAL" \
    --argjson pass "$PASS" \
    --argjson fail "$FAIL" \
    --argjson warn "$WARN" \
    --argjson fix "$FIX" \
    --argjson skip "$SKIP" \
    --argjson checks "$checks_json" \
    '{preflight_version:$ver, result:$result, mode:$mode, cargo:$cargo,
      timestamp:$ts, duration_ms:$duration,
      summary:{total:$total, pass:$pass, fail:$fail, warn:$warn, fix:$fix, skip:$skip},
      checks:$checks}' \
    > "$REPORT_FILE"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print_summary() {
  local effective=$((TOTAL - SKIP))
  local pass_pct=0
  if [[ $effective -gt 0 ]]; then
    pass_pct=$(( (PASS + FIX) * 100 / effective ))
  fi

  printf '\n=== preflight summary ===\n'
  printf 'Total: %d  Pass: %d  Fix: %d  Warn: %d  Fail: %d  Skip: %d  (%d%%)\n' \
    "$TOTAL" "$PASS" "$FIX" "$WARN" "$FAIL" "$SKIP" "$pass_pct"
  printf 'Report: %s\n' "$REPORT_FILE"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

parse_args "$@"
check_core_deps
setup_workspace

run_pre_checks
run_post_checks
run_cargo_checks

compute_total
generate_report
print_summary

if [[ $FAIL -gt 0 ]]; then
  exit 1
else
  exit 0
fi
