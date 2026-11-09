#!/usr/bin/env bash
# Week 1 Lab 1 teardown for one or both source clouds (same as the per-variant rollback-lab1.sh).
#   destroy-lab1.sh <azure|aws|both> <GCP_PROJECT_ID> [-n] [-y]      -n list only, -y no prompt
# AWS side without laptop credentials: run  bash 05-cleanup-aws.sh -y  in AWS CloudShell (us-east-2);
# this wrapper then cleans the GCP side only.
set -uo pipefail
MODE="${1:?usage: $0 <azure|aws|both> <GCP_PROJECT_ID> [-n] [-y]}"; PROJECT="${2:?usage: $0 <azure|aws|both> <GCP_PROJECT_ID> [-n] [-y]}"; shift 2
D=$(cd "$(dirname "$0")/.." && pwd); export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-2}"
[ "$MODE" = azure ] || [ "$MODE" = both ] && { echo "################ Azure -> GCP"; bash "$D/azure-to-gcp-vm-migration/scripts/destroy-lab1.sh" "$PROJECT" "$@"; echo; }
[ "$MODE" = aws ]   || [ "$MODE" = both ] && { echo "################ AWS -> GCP";   bash "$D/aws-to-gcp-vm-migration/scripts/destroy-lab1.sh" "$PROJECT" "$@"; echo; }
echo "################ Left in project $PROJECT:"
gcloud compute instances list --project "$PROJECT" --filter="name~apacheserver" --format="value(name,status)" 2>/dev/null | sed 's/^/  VM /'
gcloud compute images list --project "$PROJECT" --no-standard-images --filter="name~apacheserver" --format="value(name)" 2>/dev/null | sed 's/^/  image /'
gcloud storage ls --project "$PROJECT" 2>/dev/null | grep apache-migration | sed 's/^/  bucket /'
echo "  (nothing above this line = clean)"
