#!/usr/bin/env bash
# One-shot teardown for Week 1 Lab 1. Runs the AWS and GCP cleanup scripts, skipping any cloud
# whose CLI is not logged in. Usage: destroy-lab1.sh <GCP_PROJECT_ID> [-n] [-y]
# In the Vocareum setup the AWS CLI lives in the Vocareum terminal and gcloud in Cloud Shell,
# so run 05-cleanup-aws.sh and 06-cleanup-gcp.sh separately there; this wrapper is for a
# machine that has both CLIs configured.
set -uo pipefail
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-2}"
PROJECT="${1:?usage: $0 <GCP_PROJECT_ID> [-n] [-y]}"; shift
D=$(cd "$(dirname "$0")" && pwd)
if aws sts get-caller-identity >/dev/null 2>&1; then bash "$D/05-cleanup-aws.sh" "$@"; else echo "AWS CLI not logged in: skipping AWS (run 05-cleanup-aws.sh -y in AWS CloudShell)"; fi
if gcloud auth print-access-token >/dev/null 2>&1; then bash "$D/06-cleanup-gcp.sh" "$PROJECT" "$@"; else echo "gcloud not logged in: skipping GCP (run 06-cleanup-gcp.sh in Cloud Shell)"; fi
