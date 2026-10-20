#!/usr/bin/env bash
#
# check-health-assessment-requirements.sh
#
# Checks whether workspaces in a Terraform Enterprise / HCP Terraform
# organization meet the requirements for health assessments, and prints a
# table with one column per requirement:
#
#   1. Terraform version   >= 0.15.4 (drift detection)
#                          >= 1.3.0  (drift detection + continuous validation)
#   2. Execution mode      remote or agent (not local)
#   3. Latest run          not errored / canceled / discarded
#   4. Applied run         at least one successfully applied run
#
# Requirements: bash 4+, curl, jq, awk
#
# Usage:
#   export TFE_TOKEN=xxxx                 # or rely on ~/.terraform.d/credentials.tfrc.json
#   export TFE_HOSTNAME=tfe.example.com   # default: app.terraform.io
#   ./check-health-assessment-requirements.sh -o my-org
#   ./check-health-assessment-requirements.sh -o my-org -w my-workspace -f csv
#
# Exit codes: 0 = all workspaces eligible, 1 = at least one not eligible, 2 = usage/API error

set -euo pipefail

TFE_HOSTNAME="${TFE_HOSTNAME:-app.terraform.io}"
TFE_ORG="${TFE_ORG:-}"
WORKSPACE_FILTER=""
FORMAT="table"

MIN_DRIFT="0.15.4"
MIN_CV="1.3.0"

usage() {
  cat <<USAGE
Usage: $0 -o <organization> [-w <workspace-name>] [-H <hostname>] [-f table|csv]

  -o  Organization name         (or TFE_ORG env var)
  -w  Check a single workspace  (default: all workspaces in the org)
  -H  TFE hostname              (or TFE_HOSTNAME env var, default: app.terraform.io)
  -f  Output format: table (default) or csv

Auth: TFE_TOKEN env var, or the token stored by 'terraform login'.
USAGE
  exit 2
}

while getopts "o:w:H:f:h" opt; do
  case "$opt" in
    o) TFE_ORG="$OPTARG" ;;
    w) WORKSPACE_FILTER="$OPTARG" ;;
    H) TFE_HOSTNAME="$OPTARG" ;;
    f) FORMAT="$OPTARG" ;;
    *) usage ;;
  esac
done

[[ -n "$TFE_ORG" ]] || usage
[[ "$FORMAT" == "table" || "$FORMAT" == "csv" ]] || usage
for cmd in curl jq awk; do
  command -v "$cmd" >/dev/null || { echo "$cmd is required" >&2; exit 2; }
done

# --- Authentication ---------------------------------------------------------
if [[ -z "${TFE_TOKEN:-}" ]]; then
  CRED_FILE="$HOME/.terraform.d/credentials.tfrc.json"
  if [[ -f "$CRED_FILE" ]]; then
    TFE_TOKEN="$(jq -r --arg h "$TFE_HOSTNAME" '.credentials[$h].token // empty' "$CRED_FILE")"
  fi
fi
[[ -n "${TFE_TOKEN:-}" ]] || { echo "No token found. Set TFE_TOKEN or run 'terraform login $TFE_HOSTNAME'." >&2; exit 2; }

# --- Helpers ----------------------------------------------------------------
api() {
  # -g disables curl URL globbing so [] works in query strings
  curl -sSfg \
    -H "Authorization: Bearer ${TFE_TOKEN}" \
    -H "Content-Type: application/vnd.api+json" \
    "https://${TFE_HOSTNAME}/api/v2$1"
}

# version_ge A B -> true if A >= B
version_ge() {
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]
}

# First x.y.z in a version string or constraint ("~> 1.5.0" -> "1.5.0")
extract_version() {
  grep -oE '[0-9]+\.[0-9]+\.[0-9]+' <<<"$1" | head -n1 || true
}

# One compact JSON workspace object per line, with pagination.
list_workspaces() {
  if [[ -n "$WORKSPACE_FILTER" ]]; then
    api "/organizations/${TFE_ORG}/workspaces/${WORKSPACE_FILTER}" | jq -c '.data'
    return
  fi
  local page=1 resp next
  while :; do
    resp="$(api "/organizations/${TFE_ORG}/workspaces?page[number]=${page}&page[size]=100")"
    jq -c '.data[]' <<<"$resp"
    next="$(jq -r '.meta.pagination["next-page"] // empty' <<<"$resp")"
    [[ -n "$next" ]] || break
    page="$next"
  done
}

# --- Per-workspace check ----------------------------------------------------
ROWS=()
TOTAL=0
ELIGIBLE=0
INELIGIBLE=0
TAB=$'\t'

check_workspace() {
  local ws="$1"
  local id name tf_version exec_mode latest_run_id assess_enabled
  local ver_cell exec_cell run_cell applied_cell overall="YES" tier="-"

  id="$(jq -r '.id' <<<"$ws")"
  name="$(jq -r '.attributes.name' <<<"$ws")"
  tf_version="$(jq -r '.attributes["terraform-version"] // ""' <<<"$ws")"
  exec_mode="$(jq -r '.attributes["execution-mode"] // ""' <<<"$ws")"
  assess_enabled="$(jq -r '.attributes["assessments-enabled"] // false' <<<"$ws")"
  latest_run_id="$(jq -r '.relationships["latest-run"].data.id // empty' <<<"$ws")"

  # 1. Terraform version ------------------------------------------------------
  if [[ "$tf_version" == "latest" ]]; then
    ver_cell="PASS (latest)"
    tier="drift + continuous validation"
  else
    local v
    v="$(extract_version "$tf_version")"
    if [[ -z "$v" ]]; then
      ver_cell="FAIL (unparseable: ${tf_version:-empty})"; overall="NO"
    elif version_ge "$v" "$MIN_CV"; then
      ver_cell="PASS (${tf_version})"; tier="drift + continuous validation"
    elif version_ge "$v" "$MIN_DRIFT"; then
      ver_cell="PASS (${tf_version})"; tier="drift only"
    else
      ver_cell="FAIL (${tf_version} < ${MIN_DRIFT})"; overall="NO"
    fi
  fi

  # 2. Execution mode ---------------------------------------------------------
  case "$exec_mode" in
    remote|agent) exec_cell="PASS (${exec_mode})" ;;
    *)            exec_cell="FAIL (${exec_mode:-unknown})"; overall="NO" ;;
  esac

  # 3. Latest run status ------------------------------------------------------
  if [[ -z "$latest_run_id" ]]; then
    run_cell="FAIL (no runs)"; overall="NO"
  else
    local run_status
    run_status="$(api "/runs/${latest_run_id}" | jq -r '.data.attributes.status')"
    case "$run_status" in
      applied|planned_and_finished|planned_and_saved)
        run_cell="PASS (${run_status})" ;;
      errored|canceled|force_canceled|discarded)
        run_cell="FAIL (${run_status})"; overall="NO" ;;
      *)
        run_cell="WARN (${run_status})"; overall="NO" ;;   # in progress: not yet confirmed healthy
    esac
  fi

  # 4. At least one applied run ----------------------------------------------
  local applied_count
  applied_count="$(api "/workspaces/${id}/runs?filter[status]=applied&page[size]=1" \
                   | jq -r '.meta.pagination["total-count"] // 0')"
  if (( applied_count > 0 )); then
    applied_cell="PASS (${applied_count} applied)"
  else
    applied_cell="FAIL (none)"; overall="NO"
  fi

  [[ "$overall" == "NO" ]] && tier="-"

  TOTAL=$((TOTAL + 1))
  if [[ "$overall" == "YES" ]]; then ELIGIBLE=$((ELIGIBLE + 1)); else INELIGIBLE=$((INELIGIBLE + 1)); fi

  ROWS+=("${name}${TAB}${ver_cell}${TAB}${exec_cell}${TAB}${run_cell}${TAB}${applied_cell}${TAB}${overall}${TAB}${tier}${TAB}${assess_enabled}")
}

# --- Output -----------------------------------------------------------------
print_output() {
  local header="WORKSPACE${TAB}TERRAFORM VERSION${TAB}EXECUTION MODE${TAB}LATEST RUN${TAB}APPLIED RUN${TAB}ELIGIBLE${TAB}HEALTH TIER${TAB}ASSESSMENTS ENABLED"
  {
    echo "$header"
    printf '%s\n' "${ROWS[@]}"
  } | if [[ "$FORMAT" == "csv" ]]; then
    awk -F'\t' 'BEGIN{OFS=","} { for(i=1;i<=NF;i++){ gsub(/"/,"\"\"",$i); $i="\"" $i "\"" } print }'
  else
    awk -F'\t' '
      { for(i=1;i<=NF;i++){ cell[NR,i]=$i; if(length($i)>w[i]) w[i]=length($i) } n=NR; nf=NF }
      END {
        for(r=1;r<=n;r++){
          line=""
          for(i=1;i<=nf;i++) line = line sprintf("%-" w[i] "s  ", cell[r,i])
          print line
          if(r==1){ sep=""; for(i=1;i<=nf;i++){ s=""; for(j=0;j<w[i];j++) s=s "-"; sep=sep s "  " } print sep }
        }
      }'
  fi
}

# --- Main -------------------------------------------------------------------
while IFS= read -r ws; do
  check_workspace "$ws"
done < <(list_workspaces)

if (( TOTAL == 0 )); then
  echo "No workspaces found in organization '${TFE_ORG}'." >&2
  exit 2
fi

print_output
if [[ "$FORMAT" == "table" ]]; then
  echo
  echo "Host: ${TFE_HOSTNAME}  Org: ${TFE_ORG}  Checked: ${TOTAL}  Eligible: ${ELIGIBLE}  Not eligible: ${INELIGIBLE}"
fi

(( INELIGIBLE == 0 )) || exit 1
