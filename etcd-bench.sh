#!/usr/bin/env bash
set -uo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.0.0"

RKE2_DATA_DIR="${RKE2_DATA_DIR:-/var/lib/rancher/rke2}"
RKE2_KUBECONFIG="${RKE2_KUBECONFIG:-/etc/rancher/rke2/rke2.yaml}"
CRI_CONFIG_FILE="${CRI_CONFIG_FILE:-${RKE2_DATA_DIR}/agent/etc/crictl.yaml}"
CRICTL_BIN="${CRICTL_BIN:-${RKE2_DATA_DIR}/bin/crictl}"
KUBECTL_BIN="${KUBECTL_BIN:-${RKE2_DATA_DIR}/bin/kubectl}"
ETCD_CACERT="${ETCD_CACERT:-${RKE2_DATA_DIR}/server/tls/etcd/server-ca.crt}"
ETCD_CERT="${ETCD_CERT:-${RKE2_DATA_DIR}/server/tls/etcd/server-client.crt}"
ETCD_KEY="${ETCD_KEY:-${RKE2_DATA_DIR}/server/tls/etcd/server-client.key}"
ETCD_DIAL_TIMEOUT="${ETCD_DIAL_TIMEOUT:-5s}"
ETCD_COMMAND_TIMEOUT="${ETCD_COMMAND_TIMEOUT:-30s}"
METRICS_URL="${METRICS_URL:-https://127.0.0.1:2379/metrics}"

RUN_PERF=false
RUN_METRICS=true
RUN_KUBERNETES=true
SHOW_JSON=false
ETCD_CONTAINER=""
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
declare -a SUMMARY_LINES=()

usage() {
  cat <<USAGE
Usage: sudo ./${SCRIPT_NAME} [options]

Options:
  --perf                 Run 'etcdctl check perf' (generates temporary writes)
  --no-metrics           Skip collection of selected etcd metrics
  --skip-kubernetes      Skip Kubernetes node and kube-system pod checks
  --json                 Print raw endpoint status in JSON
  --timeout DURATION     etcd command timeout (default: ${ETCD_COMMAND_TIMEOUT})
  --dial-timeout VALUE   etcd connection timeout (default: ${ETCD_DIAL_TIMEOUT})
  --version              Print script version
  -h, --help             Show this help

Exit codes:
  0  Requested checks passed; warnings may be present
  1  One or more diagnostic checks failed
  2  Invalid usage or a required prerequisite is missing
USAGE
}

section() {
  printf '\n------------------------------------------------------------\n'
  printf ' %s\n' "$1"
  printf '%s\n' '------------------------------------------------------------'
}

record_result() {
  local status="$1" label="$2" detail="${3:-}"
  case "$status" in
    PASS) ((PASS_COUNT += 1)) ;;
    WARN) ((WARN_COUNT += 1)) ;;
    FAIL) ((FAIL_COUNT += 1)) ;;
  esac
  if [[ -n "$detail" ]]; then
    SUMMARY_LINES+=("$(printf '%-4s  %s — %s' "$status" "$label" "$detail")")
  else
    SUMMARY_LINES+=("$(printf '%-4s  %s' "$status" "$label")")
  fi
}

error_exit() { printf 'ERROR: %s\n' "$1" >&2; exit 2; }
require_file() { [[ -e "$1" ]] || error_exit "$2 not found: $1"; }
require_executable() { [[ -x "$1" ]] || error_exit "$2 is not executable: $1"; }
validate_duration() { [[ "$1" =~ ^[0-9]+(ms|s|m|h)$ ]]; }

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --perf) RUN_PERF=true ;;
      --no-metrics) RUN_METRICS=false ;;
      --skip-kubernetes) RUN_KUBERNETES=false ;;
      --json) SHOW_JSON=true ;;
      --timeout)
        shift; (($# > 0)) || error_exit "--timeout requires a duration"
        validate_duration "$1" || error_exit "Invalid timeout '$1'"
        ETCD_COMMAND_TIMEOUT="$1"
        ;;
      --dial-timeout)
        shift; (($# > 0)) || error_exit "--dial-timeout requires a duration"
        validate_duration "$1" || error_exit "Invalid dial timeout '$1'"
        ETCD_DIAL_TIMEOUT="$1"
        ;;
      --version) printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"; exit 0 ;;
      -h|--help) usage; exit 0 ;;
      *) error_exit "Unknown option: $1. Use --help for usage." ;;
    esac
    shift
  done
}

print_header() {
  cat <<HEADER
============================================================
 RKE2 ETCD BENCHMARK / DIAGNOSTICS
============================================================
 Script version : ${SCRIPT_VERSION}
 Timestamp      : $(date --iso-8601=seconds 2>/dev/null || date)
 Hostname       : $(hostname -f 2>/dev/null || hostname)
 Read-only mode : $([[ "$RUN_PERF" == true ]] && echo "No (--perf enabled)" || echo "Yes")
============================================================
HEADER
}

validate_prerequisites() {
  require_executable "$CRICTL_BIN" "crictl"
  require_file "$CRI_CONFIG_FILE" "crictl configuration"
  require_file "$ETCD_CACERT" "etcd CA certificate"
  require_file "$ETCD_CERT" "etcd client certificate"
  require_file "$ETCD_KEY" "etcd client key"
  if [[ "$RUN_KUBERNETES" == true ]]; then
    require_executable "$KUBECTL_BIN" "kubectl"
    require_file "$RKE2_KUBECONFIG" "RKE2 kubeconfig"
  fi
  export CRI_CONFIG_FILE
  export KUBECONFIG="$RKE2_KUBECONFIG"
}

find_etcd_container() {
  local output
  if ! output="$("$CRICTL_BIN" --config "$CRI_CONFIG_FILE" ps --label io.kubernetes.container.name=etcd --state Running --quiet 2>&1)"; then
    error_exit "Unable to query the container runtime: $output"
  fi
  ETCD_CONTAINER="$(printf '%s\n' "$output" | awk 'NF {print; exit}')"
  [[ -n "$ETCD_CONTAINER" ]] || error_exit "No running etcd container found. Run this on an RKE2 server node with the etcd role."
}

etcdctl_exec() {
  "$CRICTL_BIN" --config "$CRI_CONFIG_FILE" exec "$ETCD_CONTAINER" etcdctl \
    --dial-timeout="$ETCD_DIAL_TIMEOUT" \
    --command-timeout="$ETCD_COMMAND_TIMEOUT" \
    --cert="$ETCD_CERT" \
    --key="$ETCD_KEY" \
    --cacert="$ETCD_CACERT" \
    "$@"
}

run_check() {
  local label="$1" output rc
  shift
  section "$label"
  output="$("$@" 2>&1)"; rc=$?
  printf '%s\n' "$output"
  if ((rc == 0)); then
    record_result PASS "$label"
  else
    record_result FAIL "$label" "command exited with status $rc"
  fi
  return 0
}

print_runtime_details() {
  section "Runtime Details"
  printf 'Kubeconfig       : %s\n' "$RKE2_KUBECONFIG"
  printf 'crictl config    : %s\n' "$CRI_CONFIG_FILE"
  printf 'etcd container   : %s\n' "$ETCD_CONTAINER"
  printf 'Command timeout  : %s\n' "$ETCD_COMMAND_TIMEOUT"
  printf 'Dial timeout     : %s\n' "$ETCD_DIAL_TIMEOUT"
  printf 'etcdctl version  : '
  etcdctl_exec version 2>/dev/null | head -1 || printf 'unavailable\n'
}

run_kubernetes_checks() {
  if [[ "$RUN_KUBERNETES" != true ]]; then
    record_result WARN "Kubernetes checks" "skipped by request"
    return
  fi
  run_check "Kubernetes Nodes" "$KUBECTL_BIN" --kubeconfig "$RKE2_KUBECONFIG" --request-timeout="$ETCD_COMMAND_TIMEOUT" get nodes -o wide
  run_check "Kube-system Pods" "$KUBECTL_BIN" --kubeconfig "$RKE2_KUBECONFIG" --request-timeout="$ETCD_COMMAND_TIMEOUT" -n kube-system get pods -o wide
}

run_etcd_checks() {
  run_check "ETCD Member List" etcdctl_exec member list -w table
  run_check "ETCD Endpoint Health" etcdctl_exec endpoint health --cluster -w table
  run_check "ETCD Endpoint Status" etcdctl_exec endpoint status --cluster -w table
  run_check "ETCD Alarm List" etcdctl_exec alarm list
  run_check "ETCD HashKV Consistency Check" etcdctl_exec endpoint hashkv --cluster -w table
  if [[ "$SHOW_JSON" == true ]]; then
    run_check "ETCD Endpoint Status (JSON)" etcdctl_exec endpoint status --cluster -w json
  else
    record_result WARN "ETCD endpoint JSON" "not requested; use --json"
  fi
}

run_perf_check() {
  if [[ "$RUN_PERF" != true ]]; then
    record_result WARN "ETCD Performance Check" "skipped; use --perf"
    return
  fi
  section "ETCD Performance Check"
  printf 'WARNING: This test generates temporary write activity in etcd.\n'
  local output rc
  output="$(etcdctl_exec check perf 2>&1)"; rc=$?
  printf '%s\n' "$output"
  if ((rc == 0)); then
    record_result PASS "ETCD Performance Check"
  else
    record_result FAIL "ETCD Performance Check" "benchmark exited with status $rc"
  fi
}

run_metrics_check() {
  if [[ "$RUN_METRICS" != true ]]; then
    record_result WARN "ETCD Metrics" "skipped by request"
    return
  fi
  section "ETCD Metrics (Selected)"
  if ! command -v curl >/dev/null 2>&1; then
    printf 'curl is not installed; metrics collection skipped.\n'
    record_result WARN "ETCD Metrics" "curl is not installed"
    return
  fi

  local metrics filtered rc
  metrics="$(curl --fail --silent --show-error --connect-timeout 5 --max-time 15 \
    --cacert "$ETCD_CACERT" --cert "$ETCD_CERT" --key "$ETCD_KEY" "$METRICS_URL" 2>&1)"; rc=$?
  if ((rc != 0)); then
    printf '%s\n' "$metrics"
    printf 'Metrics endpoint unavailable at %s. Review: etcd-expose-metrics: true\n' "$METRICS_URL"
    record_result WARN "ETCD Metrics" "endpoint unavailable"
    return
  fi

  filtered="$(printf '%s\n' "$metrics" | grep -E '^(etcd_server_has_leader|etcd_server_leader_changes_seen_total|etcd_disk_wal_fsync_duration_seconds|etcd_disk_backend_commit_duration_seconds|etcd_network_peer_round_trip_time_seconds)' || true)"
  if [[ -n "$filtered" ]]; then
    printf '%s\n' "$filtered"
    record_result PASS "ETCD Metrics"
  else
    printf 'Metrics endpoint reachable, but selected metrics were not found.\n'
    record_result WARN "ETCD Metrics" "selected metrics not found"
  fi
}

print_summary() {
  section "Summary"
  local line
  for line in "${SUMMARY_LINES[@]}"; do printf '%s\n' "$line"; done
  printf '\nPassed: %d  Warnings: %d  Failed: %d\n' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
  if ((FAIL_COUNT > 0)); then
    printf 'Overall status: FAIL\n'
  elif ((WARN_COUNT > 0)); then
    printf 'Overall status: PASS WITH WARNINGS\n'
  else
    printf 'Overall status: PASS\n'
  fi
}

main() {
  parse_args "$@"
  print_header
  validate_prerequisites
  find_etcd_container
  print_runtime_details
  run_kubernetes_checks
  run_etcd_checks
  run_perf_check
  run_metrics_check
  print_summary
  ((FAIL_COUNT > 0)) && exit 1
  exit 0
}

main "$@"
