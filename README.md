# RKE2 ETCD Benchmark

![License](https://img.shields.io/github/license/pitshou243/etcd-bench)
![Release](https://img.shields.io/github/v/release/pitshou243/etcd-bench)
![Shell](https://img.shields.io/badge/Bash-5%2B-blue)
![Platform](https://img.shields.io/badge/Platform-RKE2-success)

A lightweight Bash utility for collecting **embedded etcd health,
consistency, and performance diagnostics** from **RKE2** clusters.

The tool is intended for Kubernetes administrators, SREs, consultants,
and support engineers who need a quick way to assess the health of the
embedded etcd datastore before deeper troubleshooting.

> **Note** By default the tool performs **read-only diagnostics**. The
> write-generating `etcdctl check perf` benchmark runs **only** when
> `--perf` is specified.

------------------------------------------------------------------------

# Table of Contents

-   Overview
-   Features
-   Requirements
-   Installation
-   Usage
-   Command-line Options
-   Environment Variables
-   What the Tool Collects
-   Understanding the Results
-   Operational Considerations
-   Troubleshooting
-   Limitations
-   Roadmap
-   Contributing
-   License

------------------------------------------------------------------------

# Overview

The script automates common `etcdctl` commands used during RKE2
troubleshooting and presents them in a single report.

It validates prerequisites, locates the embedded etcd container,
executes diagnostics using the RKE2 certificates, and prints a
consolidated report with a final **PASS/WARN/FAIL** summary.

------------------------------------------------------------------------

# Features

-   Read-only diagnostics by default
-   Optional `etcdctl check perf`
-   Kubernetes node and kube-system checks
-   etcd member validation
-   Endpoint health
-   Endpoint status
-   Alarm detection
-   HashKV consistency verification
-   Optional JSON endpoint output
-   Selected etcd metrics collection
-   Configurable timeouts
-   PASS/WARN/FAIL summary
-   Meaningful exit codes

------------------------------------------------------------------------

# Requirements

-   RKE2 cluster using **embedded etcd**
-   Bash
-   Root (recommended)
-   Running `rke2-server`
-   Access to the RKE2 certificates

Not intended for:

-   External datastore
-   RKE1
-   Generic Kubernetes
-   K3s (without modification)

------------------------------------------------------------------------

# Installation

``` bash
git clone https://github.com/pitshou243/etcd-bench.git
cd etcd-bench
chmod +x etcd-bench.sh
```

------------------------------------------------------------------------

# Usage

Run diagnostics:

``` bash
sudo ./etcd-bench.sh
```

Include the performance benchmark:

``` bash
sudo ./etcd-bench.sh --perf
```

Include raw JSON endpoint status:

``` bash
sudo ./etcd-bench.sh --json
```

Save the output:

``` bash
sudo ./etcd-bench.sh 2>&1 | tee etcd-bench-$(date +%F-%H%M).log
```

------------------------------------------------------------------------

# Command-line Options

  Option                Description
  --------------------- ----------------------------------
  `--perf`              Run `etcdctl check perf`
  `--json`              Show endpoint status in JSON
  `--no-metrics`        Skip metrics collection
  `--skip-kubernetes`   Skip Kubernetes checks
  `--timeout`           Override etcd command timeout
  `--dial-timeout`      Override etcd connection timeout
  `--help`              Show help
  `--version`           Show version

------------------------------------------------------------------------

# Environment Variables

  Variable                 Default
  ------------------------ -----------------------------------------
  `RKE2_DATA_DIR`          `/var/lib/rancher/rke2`
  `RKE2_KUBECONFIG`        `/etc/rancher/rke2/rke2.yaml`
  `CRI_CONFIG_FILE`        `<RKE2_DATA_DIR>/agent/etc/crictl.yaml`
  `ETCD_COMMAND_TIMEOUT`   `30s`
  `ETCD_DIAL_TIMEOUT`      `5s`

------------------------------------------------------------------------

# What the Tool Collects

  Check                   Purpose
  ----------------------- -------------------------------------------
  Kubernetes Nodes        Verify cluster health
  kube-system Pods        Detect unhealthy control plane components
  etcd Members            Verify membership
  Endpoint Health         Connectivity and responsiveness
  Endpoint Status         Leader, revision, DB size, raft indexes
  Alarm List              Detect active alarms
  HashKV                  Consistency verification
  Metrics                 Selected etcd metrics
  Performance Benchmark   Optional write benchmark

------------------------------------------------------------------------

# Understanding the Results

## Endpoint Health

All endpoints should report healthy.

Failures may indicate:

-   quorum loss
-   certificate issues
-   networking problems
-   disk latency
-   etcd instability

## Endpoint Status

Review:

-   Leader
-   Database size
-   Revision
-   Raft term
-   Applied index

Large differences between members should be investigated.

## Alarm List

Healthy clusters normally return no alarms.

Important alarms include:

-   `NOSPACE`
-   `CORRUPT`

## HashKV

All members should report matching hashes.

Hash mismatches should be investigated before performing recovery
operations.

## Performance Benchmark

The benchmark runs only with:

``` bash
sudo ./etcd-bench.sh --perf
```

It generates temporary writes.

Avoid running repeatedly on overloaded production clusters.

------------------------------------------------------------------------

# Example Summary

``` text
PASS  Kubernetes Nodes
PASS  ETCD Member List
PASS  Endpoint Health
PASS  Endpoint Status
PASS  HashKV
WARN  Metrics endpoint unavailable
WARN  Performance benchmark skipped

Overall Status: PASS WITH WARNINGS
```

------------------------------------------------------------------------

# Operational Considerations

-   Prefer running on an etcd node.
-   Collect data **before restarting** `rke2-server`.
-   Correlate findings with:
    -   journalctl
    -   iostat
    -   vmstat
    -   pidstat
    -   sar
    -   Prometheus

------------------------------------------------------------------------

# Troubleshooting

## No etcd container found

Verify:

``` bash
sudo systemctl status rke2-server
```

and

``` bash
sudo /var/lib/rancher/rke2/bin/crictl ps
```

## Metrics unavailable

Enable metrics in RKE2 if appropriate:

``` yaml
etcd-expose-metrics: true
```

------------------------------------------------------------------------

# Limitations

-   Point-in-time snapshot
-   Does not repair etcd
-   Does not compact or defragment
-   Does not modify cluster membership
-   Not a replacement for continuous monitoring

------------------------------------------------------------------------

# Roadmap

-   Export JSON reports
-   Prometheus text output
-   Automatic health scoring
-   Multi-node comparison
-   HTML report generation
-   Support bundle integration

------------------------------------------------------------------------

# Contributing

Contributions are welcome.

Before opening a Pull Request:

``` bash
bash -n etcd-bench.sh
shellcheck etcd-bench.sh
```

Please test changes on a non-production RKE2 cluster.

------------------------------------------------------------------------

# License

This project is licensed under the MIT License.

------------------------------------------------------------------------

# Disclaimer

This is an independent community project and is **not** an official SUSE
or Rancher support utility.

Always validate results before making production changes.# etcd-bench
