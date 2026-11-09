#!/usr/bin/env bash
# Week 1 Lab 1 (Azure -> GCP) end to end from one laptop. Needs: az login done, gcloud auth done,
# qemu-img and GNU tar installed (brew install qemu gnu-tar). About 25 minutes; prints every milestone.
#   deploy-lab1.sh <GCP_PROJECT_ID>          env: NAME LOCATION SIZE RG (Azure) ZONE BUCKET (GCP)
set -euo pipefail
PROJECT="${1:?usage: $0 <GCP_PROJECT_ID>}"; D=$(cd "$(dirname "$0")" && pwd); LOG="${LOG:-$HOME/lab1-deploy.log}"
az account show --query "{subscription:name,user:user.name}" -o tsv >/dev/null || { echo "run: az login"; exit 1; }
gcloud auth print-access-token >/dev/null 2>&1 || { echo "run: gcloud auth login"; exit 1; }
echo "Azure subscription: $(az account show --query name -o tsv)   GCP project: $PROJECT   log: $LOG"
T0=$(date +%s)
bash "$D/00-azure-all-in-one.sh" 2>&1 | tee "$LOG"
AZ_IP=$(grep -o 'IMAGE_URL=http://[0-9.]*' "$LOG" | tail -1 | cut -d/ -f3); [ -n "$AZ_IP" ] || { echo "no IMAGE_URL in $LOG"; exit 1; }
T1=$(date +%s)
bash "$D/04-gcp-import-and-launch.sh" "$PROJECT" "$AZ_IP" 2>&1 | tee -a "$LOG"
T2=$(date +%s)
# Step 11: the image was published over plain HTTP for the transfer only; take the link down now
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$HOME/.ssh/${NAME:-apacheserver1}-key" "ubuntu@$AZ_IP" 'sudo rm -f /var/www/html/disk.qcow2' && echo "disk.qcow2 link removed on Azure (Step 11)"
GCP_IP=$(grep -o 'GCP_VM_IP=[0-9.]*' "$LOG" | tail -1 | cut -d= -f2)
# Step timing table from the T_<step>=<epoch> markers the scripts print (last occurrence of each wins)
awk -F'[=]' '/^T_[A-Z_]+=[0-9]+$/{t[substr($1,3)]=$2}
  function d(a,b,  s){ if(!(a in t)||!(b in t)) return "   -  "; s=t[b]-t[a]; if(s<0) return "   -  "; return sprintf("%3d:%02d",int(s/60),s%60) }
  END{ print ""; print "Step timing (min:sec)";
       printf "  %-34s %s\n","Create the source VM",           d("START","VM_READY");
       printf "  %-34s %s\n","Install Apache, first HTTP 200", d("VM_READY","APACHE_OK");
       printf "  %-34s %s\n","Prepare the OS for GCE (Step 6)",d("APACHE_OK","PREP_DONE");
       printf "  %-34s %s\n","Capture: freeze, copy, check, qcow2",d("PREP_DONE","CAPTURE_DONE");
       printf "  %-34s %s\n","Download the qcow2",             d("IMPORT_START","DOWNLOAD_DONE");
       printf "  %-34s %s\n","Convert to raw and tar",         d("DOWNLOAD_DONE","CONVERT_DONE");
       printf "  %-34s %s\n","Upload to Cloud Storage",        d("CONVERT_DONE","UPLOAD_DONE");
       printf "  %-34s %s\n","Create the Compute Engine image",d("UPLOAD_DONE","IMAGE_READY");
       printf "  %-34s %s\n","Create the VM",                  d("IMAGE_READY","VM_CREATED");
       printf "  %-34s %s\n","Boot to first HTTP 200",         d("VM_CREATED","HTTP_OK");
       printf "  %-34s %s\n","Total",                          d("START","HTTP_OK") }' "$LOG"
echo; echo "Timing (minutes): Azure build + capture $(( (T1-T0)/60 )), transfer + GCP launch $(( (T2-T1)/60 )), total $(( (T2-T0)/60 ))"
echo "Before: http://$AZ_IP/   (Azure apacheserver1)"
echo "After:  http://$GCP_IP/   (GCP apacheserver-gcp, image apacheserver-image)"
echo "LAB1_DEPLOY_DONE"
