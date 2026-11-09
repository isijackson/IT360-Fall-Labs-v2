#!/usr/bin/env bash
# Steps 9-17: run on a laptop with gcloud, qemu-img and GNU tar (brew install qemu gnu-tar) or in
# Cloud Shell. Downloads the qcow2 from the Azure VM, converts it to Compute Engine raw tar.gz, uploads
# it, creates the image, launches the VM, opens HTTP and validates.
#   04-gcp-import-and-launch.sh <PROJECT_ID> <AZURE_PUBLIC_IP>        (ZONE, BUCKET env vars optional)
set -euo pipefail
PROJECT="${1:?usage: $0 <PROJECT_ID> <AZURE_PUBLIC_IP>}"
SRC_IP="${2:?usage: $0 <PROJECT_ID> <AZURE_PUBLIC_IP>}"
ZONE="${ZONE:-us-central1-a}"; B="${BUCKET:-${PROJECT}-apache-migration}"
WORK="${WORK:-$HOME/lab1-import}"; mkdir -p "$WORK"; cd "$WORK"

gcloud config set project "$PROJECT" >/dev/null
gcloud services enable compute.googleapis.com storage.googleapis.com
gcloud storage buckets create "gs://$B" --location=us-central1 --uniform-bucket-level-access 2>/dev/null || true

echo "T_IMPORT_START=$(date +%s)"
echo "== Step 10: download and verify"; echo "DOWNLOAD_START $(date +%H:%M:%S)"
# resumable: a dropped connection continues the same file
curl -sf --retry 10 --retry-all-errors --retry-delay 5 -C - -O "http://$SRC_IP/disk.qcow2"; ls -l disk.qcow2; (md5sum disk.qcow2 2>/dev/null || md5 disk.qcow2); echo "T_DOWNLOAD_DONE=$(date +%s)"
echo "== Step 12: convert to Compute Engine raw tar.gz"; echo "CONVERT_START $(date +%H:%M:%S)"
command -v qemu-img >/dev/null || sudo apt-get install -y -qq qemu-utils >/dev/null
qemu-img convert -O raw disk.qcow2 disk.raw && rm disk.qcow2
TAR=$(command -v gtar || command -v tar)   # macOS: brew install gnu-tar (bsdtar has no oldgnu format)
$TAR --format=oldgnu -Sczf disk.tar.gz disk.raw && rm disk.raw; ls -l disk.tar.gz; echo "T_CONVERT_DONE=$(date +%s)"
echo "== Step 13: upload"; echo "UPLOAD_START $(date +%H:%M:%S)"
gcloud storage cp disk.tar.gz "gs://$B/disk.tar.gz"; echo "T_UPLOAD_DONE=$(date +%s)"
echo "== Steps 14-15: image and VM (boot disk = image size; Azure OS disks are 30 GB)"; echo "IMAGE_CREATE $(date +%H:%M:%S)"
gcloud compute images describe apacheserver-image >/dev/null 2>&1 || gcloud compute images create apacheserver-image \
  --source-uri="gs://$B/disk.tar.gz" --family=apacheserver --description="Migrated from Azure apacheserver1" \
  || echo "image create call did not return (gcloud read timeout is 300 s); the operation keeps running, waiting for READY"
for i in $(seq 1 60); do [ "$(gcloud compute images describe apacheserver-image --format='value(status)' 2>/dev/null)" = READY ] && break; sleep 10; done
[ "$(gcloud compute images describe apacheserver-image --format='value(status)' 2>/dev/null)" = READY ] || { echo "apacheserver-image is not READY after 10 minutes"; exit 1; }
echo "T_IMAGE_READY=$(date +%s)"
gcloud compute instances describe apacheserver-gcp --zone="$ZONE" >/dev/null 2>&1 || gcloud compute instances create apacheserver-gcp \
  --zone="$ZONE" --machine-type=e2-micro --image=apacheserver-image --tags=http-server \
  || echo "instance create call did not return (gcloud read timeout); waiting for the VM"
for i in $(seq 1 30); do [ "$(gcloud compute instances describe apacheserver-gcp --zone="$ZONE" --format='value(status)' 2>/dev/null)" = RUNNING ] && break; sleep 10; done
[ "$(gcloud compute instances describe apacheserver-gcp --zone="$ZONE" --format='value(status)' 2>/dev/null)" = RUNNING ] || { echo "apacheserver-gcp is not RUNNING after 5 minutes"; exit 1; }
echo "T_VM_CREATED=$(date +%s)"
echo "== Step 16: firewall"
gcloud compute firewall-rules describe allow-http >/dev/null 2>&1 || gcloud compute firewall-rules create allow-http \
  --allow=tcp:80 --target-tags=http-server --source-ranges=0.0.0.0/0
IP=$(gcloud compute instances describe apacheserver-gcp --zone="$ZONE" --format='value(networkInterfaces[0].accessConfigs[0].natIP)')
echo "GCP_VM_IP=$IP"
echo "== Step 17: validate from the outside"
for i in $(seq 1 30); do
  code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://$IP/" || true); echo "$(date +%H:%M:%S) http://$IP/ -> $code"
  if [ "$code" = 200 ]; then curl -s "http://$IP/" | grep -o '<title>.*</title>'; echo "GCP_HTTP_OK"; echo "T_HTTP_OK=$(date +%s)"; echo "IMPORT_DONE $(date +%H:%M:%S)"; exit 0; fi
  sleep 10
done
echo "Apache did not answer on http://$IP/ within 5 minutes"; exit 1
