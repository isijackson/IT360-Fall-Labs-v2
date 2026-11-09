#!/usr/bin/env bash
# Week 1 Lab 1 (AWS variant) rollback (same as destroy-lab1.sh): AWS instance, AMI, snapshots, buckets, key pair; GCP VM, image, bucket, rule.
#   rollback-lab1.sh <GCP_PROJECT_ID> [-n] [-y]
exec bash "$(cd "$(dirname "$0")" && pwd)/destroy-lab1.sh" "$@"
