#!/usr/bin/env bash
# Week 1 Lab 1, both source clouds, from one laptop.
#   deploy-lab1.sh <azure|aws|both> <GCP_PROJECT_ID>
# azure : az login + gcloud on the laptop (about 20 min, prints the step-timing table)
# aws   : AWS credentials on the laptop (AWS_PROFILE, region us-east-2) + gcloud. Without laptop
#         credentials run 00-aws-all-in-one.sh in AWS CloudShell first and pass its IP:
#         EC2_IP=<ip> deploy-lab1.sh aws <PROJECT>   (runs only the GCP import and reminds you of Step 11)
# both  : azure first, then aws (set PARALLEL=1 to run them side by side; the two downloads then share bandwidth)
set -uo pipefail
MODE="${1:?usage: $0 <azure|aws|both> <GCP_PROJECT_ID>}"; PROJECT="${2:?usage: $0 <azure|aws|both> <GCP_PROJECT_ID>}"
D=$(cd "$(dirname "$0")/.." && pwd); AZ="$D/azure-to-gcp-vm-migration/scripts"; AW="$D/aws-to-gcp-vm-migration/scripts"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-2}"
run_azure() { LOG="$HOME/lab1-azure-deploy.log" bash "$AZ/deploy-lab1.sh" "$PROJECT"; }
run_aws() {
  if aws sts get-caller-identity >/dev/null 2>&1; then LOG="$HOME/lab1-aws-deploy.log" bash "$AW/deploy-lab1.sh" "$PROJECT"
  elif [ -n "${EC2_IP:-}" ]; then
    echo "AWS: no laptop credentials; importing the image published by CloudShell at http://$EC2_IP/disk.qcow2"
    bash "$AW/04-gcp-import-and-launch.sh" "$PROJECT" "$EC2_IP" 2>&1 | tee "$HOME/lab1-aws-deploy.log"
    echo "Step 11, in CloudShell: ssh -i ~/.ssh/apacheserver1-key.pem ubuntu@$EC2_IP 'sudo rm -f /var/www/html/disk.qcow2'"
  else
    echo "AWS: no laptop credentials. Either set AWS_PROFILE, or run scripts/00-aws-all-in-one.sh in AWS CloudShell"
    echo "     (us-east-2) and rerun:  EC2_IP=<its IMAGE_URL host> $0 aws $PROJECT"; return 2
  fi
}
case "$MODE" in
  azure) run_azure ;;
  aws)   run_aws ;;
  both)  if [ "${PARALLEL:-0}" = 1 ]; then run_azure & A=$!; run_aws; wait $A; else run_azure; run_aws; fi ;;
  *) echo "usage: $0 <azure|aws|both> <GCP_PROJECT_ID>"; exit 2 ;;
esac
echo; echo "Logs: $HOME/lab1-azure-deploy.log  $HOME/lab1-aws-deploy.log   Verify: $(dirname "$0")/verify-lab1.sh $MODE $PROJECT"
