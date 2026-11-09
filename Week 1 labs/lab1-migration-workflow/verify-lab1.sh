#!/usr/bin/env bash
# Week 1 Lab 1 verification for one or both source clouds.
#   verify-lab1.sh <azure|aws|both> <GCP_PROJECT_ID>        env: EC2_IP (AWS variant without laptop credentials)
set -uo pipefail
MODE="${1:?usage: $0 <azure|aws|both> <GCP_PROJECT_ID>}"; PROJECT="${2:?usage: $0 <azure|aws|both> <GCP_PROJECT_ID>}"
D=$(cd "$(dirname "$0")/.." && pwd); export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-2}"
[ "$MODE" = azure ] || [ "$MODE" = both ] && { echo "################ Azure -> GCP"; bash "$D/azure-to-gcp-vm-migration/scripts/verify-lab1.sh" "$PROJECT"; echo; }
[ "$MODE" = aws ]   || [ "$MODE" = both ] && { echo "################ AWS -> GCP";   bash "$D/aws-to-gcp-vm-migration/scripts/verify-lab1.sh" "$PROJECT"; echo; }
echo "################ Everything named apacheserver in project $PROJECT"
gcloud compute instances list --project "$PROJECT" --filter="name~apacheserver" --format="table(name,zone.basename(),status,networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null
for vm in apacheserver-gcp apacheserver-gcp-aws; do
  gcloud compute instances describe "$vm" --project "$PROJECT" --zone "${ZONE:-us-central1-a}" >/dev/null 2>&1 || continue
  echo "-- $vm serial console (cloud-init datasource and any fsck or panic lines)"
  gcloud compute instances get-serial-port-output "$vm" --project "$PROJECT" --zone "${ZONE:-us-central1-a}" 2>/dev/null | grep -iE "cloud-init.*finished|Datasource Data|fsck.*fail|UNEXPECTED|emergency (mode|shell)|Kernel panic" | tail -3 | cut -c1-150
done
