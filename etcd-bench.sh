#!/usr/bin/env bash
set -euo pipefail

RKE2_DATA_DIR="${RKE2_DATA_DIR:-/var/lib/rancher/rke2}"
RKE2_KUBECONFIG="${RKE2_KUBECONFIG:-/etc/rancher/rke2/rke2.yaml}"
CRI_CONFIG_FILE="${CRI_CONFIG_FILE:-${RKE2_DATA_DIR}/agent/etc/crictl.yaml}"
CRICTL_BIN="${CRICTL_BIN:-${RKE2_DATA_DIR}/bin/crictl}"
KUBECTL_BIN="${KUBECTL_BIN:-${RKE2_DATA_DIR}/bin/kubectl}"

export CRI_CONFIG_FILE
export KUBECONFIG="${RKE2_KUBECONFIG}"

ETCD_CACERT="${RKE2_DATA_DIR}/server/tls/etcd/server-ca.crt"
ETCD_CERT="${RKE2_DATA_DIR}/server/tls/etcd/server-client.crt"
ETCD_KEY="${RKE2_DATA_DIR}/server/tls/etcd/server-client.key"

echo "============================================================"
echo " RKE2 ETCD BENCHMARK / DIAGNOSTICS"
echo "============================================================"

for f in "${CRICTL_BIN}" "${KUBECTL_BIN}" "${RKE2_KUBECONFIG}" "${ETCD_CACERT}" "${ETCD_CERT}" "${ETCD_KEY}"; do
  if [[ ! -e "$f" ]]; then
    echo "ERROR: missing required file: $f"
    exit 1
  fi
done

ETCD_CONTAINER="$("${CRICTL_BIN}" ps --label io.kubernetes.container.name=etcd --quiet | head -1)"

if [[ -z "${ETCD_CONTAINER}" ]]; then
  echo "ERROR: etcd container not found. Run on an RKE2 server node."
  exit 1
fi

echo "Using kubeconfig: ${RKE2_KUBECONFIG}"
echo "Using crictl config: ${CRI_CONFIG_FILE}"
echo "Using etcd container: ${ETCD_CONTAINER}"
echo

etcdctl_exec() {
  "${CRICTL_BIN}" exec "${ETCD_CONTAINER}" etcdctl \
    --cert "${ETCD_CERT}" \
    --key "${ETCD_KEY}" \
    --cacert "${ETCD_CACERT}" \
    "$@"
}

section() {
  echo
  echo "------------------------------------------------------------"
  echo " $1"
  echo "------------------------------------------------------------"
}

section "Kubernetes Nodes"
"${KUBECTL_BIN}" --kubeconfig "${RKE2_KUBECONFIG}" get nodes -o wide || true

section "Kube-system Pods"
"${KUBECTL_BIN}" --kubeconfig "${RKE2_KUBECONFIG}" -n kube-system get pods -o wide || true

section "ETCD Member List"
etcdctl_exec member list -w table || true

section "ETCD Endpoint Health"
etcdctl_exec endpoint health --cluster -w table || true

section "ETCD Endpoint Status"
etcdctl_exec endpoint status --cluster -w table || true

section "ETCD Alarm List"
etcdctl_exec alarm list || true

section "ETCD HashKV (consistency check)"
etcdctl_exec endpoint hashkv --cluster -w table || true

section "ETCD Performance Check"
etcdctl_exec check perf || true

section "ETCD Endpoint Status (JSON)"
etcdctl_exec endpoint status --cluster -w json || true

section "ETCD Metrics (sample)"

if curl -sk \
  --cacert "${ETCD_CACERT}" \
  --cert "${ETCD_CERT}" \
  --key "${ETCD_KEY}" \
  https://127.0.0.1:2379/metrics >/dev/null 2>&1; then

  curl -sk \
    --cacert "${ETCD_CACERT}" \
    --cert "${ETCD_CERT}" \
    --key "${ETCD_KEY}" \
    https://127.0.0.1:2379/metrics | \
    egrep 'etcd_server_has_leader|etcd_server_leader_changes_seen_total|etcd_disk_wal_fsync_duration_seconds|etcd_disk_backend_commit_duration_seconds|etcd_network_peer_round_trip_time_seconds' || true
else
  echo "Metrics endpoint not reachable."
  echo "If needed, enable etcd metrics with:"
  echo "  etcd-expose-metrics: true"
fi

echo
echo "============================================================"
echo " DONE"
echo "============================================================"
