#!/usr/bin/env bash
# One-shot teardown for the Azure-to-GCP variant: 05 in a shell where az is signed in, 06 where gcloud is.
#   destroy-lab1.sh <GCP_PROJECT_ID> [-n] [-y]
set -uo pipefail
PROJECT="${1:?usage: $0 <GCP_PROJECT_ID> [-n] [-y]}"; shift; D=$(cd "$(dirname "$0")" && pwd)
if az account show >/dev/null 2>&1; then bash "$D/05-cleanup-azure.sh" "$@"; else echo "az not signed in: run 05-cleanup-azure.sh in the portal Cloud Shell"; fi
if gcloud auth print-access-token >/dev/null 2>&1; then bash "$D/06-cleanup-gcp.sh" "$PROJECT" "$@"; else echo "gcloud not signed in: run 06-cleanup-gcp.sh in Cloud Shell"; fi
