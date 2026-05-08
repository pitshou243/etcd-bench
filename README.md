# etcd-bench
# RKE2 etcd Benchmark & Diagnostics Script

A lightweight diagnostic and benchmarking script for **RKE2 embedded etcd**, designed for:

- Troubleshooting etcd performance issues
- Collecting quick health diagnostics
- Running `etcdctl check perf`
- Supporting SUSE / Rancher support workflows

---

## TL;DR

This script:

- Uses `etcdctl` **inside the etcd container** (no host install required)
- Uses the **RKE2 kubeconfig**
- Prints output directly to stdout
- Provides quick insight into etcd and cluster health

---

## Requirements

Run on an **RKE2 server node**:

- Root access
- RKE2 installed
- Access to:
  - `/var/lib/rancher/rke2`
  - `/etc/rancher/rke2/rke2.yaml`

---

## Usage

```bash
chmod +x etcd-bench.sh
sudo ./etcd-bench.sh
