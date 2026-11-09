#!/usr/bin/env bash
# One-shot teardown for Week 1 Lab 2. Runs the DigitalOcean, GCP and Azure cleanup scripts,
# skipping any cloud whose CLI is not logged in. Usage: destroy-lab2.sh <GCP_PROJECT_ID> [-n] [-y]
# On the Vocareum Azure sandbox the Azure CLI only works inside the portal's Cloud Shell, so run
# 04-destroy-lab2-azure.sh there; the other two run from any machine with doctl and gcloud.
set -uo pipefail
PROJECT="${1:?usage: $0 <GCP_PROJECT_ID> [-n] [-y]}"; shift
D=$(cd "$(dirname "$0")" && pwd)
if doctl account get ${DO_CONTEXT:+--context $DO_CONTEXT} >/dev/null 2>&1; then bash "$D/02-destroy-lab2-do.sh" "$@"; else echo "doctl not logged in: skipping DigitalOcean"; fi
if gcloud auth print-access-token >/dev/null 2>&1; then bash "$D/03-destroy-lab2-gcp.sh" "$PROJECT" "$@"; else echo "gcloud not logged in: skipping GCP"; fi
if az account show >/dev/null 2>&1; then bash "$D/04-destroy-lab2-azure.sh" "$@"; else echo "az not logged in: skipping Azure (run 04-destroy-lab2-azure.sh in Cloud Shell)"; fi
