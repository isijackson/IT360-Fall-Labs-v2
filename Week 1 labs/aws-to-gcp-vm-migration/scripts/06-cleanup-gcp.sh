#!/usr/bin/env bash
# Lab 1 (AWS variant) teardown, GCP side: the -aws suffixed VM, image and bucket. Finds the VM, image, bucket and firewall rules the lab created.
# Run in Cloud Shell or anywhere gcloud is logged in.
#   06-cleanup-gcp.sh <PROJECT_ID> [-n] [-y]     -n = dry run, -y = no confirmation prompt
set -uo pipefail
PROJECT="${1:?usage: $0 <PROJECT_ID> [-n] [-y]}"; shift; DRY=0; YES=0
for a in "$@"; do case "$a" in -n) DRY=1;; -y) YES=1;; *) echo "usage: $0 <PROJECT_ID> [-n] [-y]"; exit 2;; esac; done
B="${BUCKET:-${PROJECT}-apache-migration-aws}"; GCP_VM="${GCP_VM:-apacheserver-gcp-aws}"; IMAGE="${IMAGE:-apacheserver-image-aws}"
g() { gcloud "$@" --project="$PROJECT" --quiet 2>/dev/null; }

VMS=$(g compute instances list --filter="name=$GCP_VM" --format="value(name,zone.basename())")
IMAGES=$(g compute images list --no-standard-images --filter="name=$IMAGE OR family=apacheserver-aws" --format="value(name)")
BUCKET=$(gcloud storage ls --project="$PROJECT" 2>/dev/null | grep -x "gs://$B/")
# allow-http is shared with the Azure variant: keep it while any other http-server VM is still in the project
OTHERS=$(g compute instances list --filter="tags.items=http-server AND NOT name=$GCP_VM" --format="value(name)")
# exact name match: a gcloud filter "name=allow-http" also matches default-allow-http (word pattern) and would delete the project default
RULES=$([ -z "$OTHERS" ] && g compute firewall-rules list --format="value(name)" | grep -x "allow-http")

echo "Lab 1 resources in project $PROJECT:"
printf '  VMs (name zone): %s\n  images:          %s\n  bucket:          %s\n  firewall rules:  %s\n' \
  "${VMS:-none}" "${IMAGES:-none}" "${BUCKET:-none}" "${RULES:-none}"
[ -z "$VMS$IMAGES$BUCKET$RULES" ] && { echo "Nothing to delete."; exit 0; }
[ "$DRY" = 1 ] && exit 0
if [ "$YES" != 1 ]; then read -r -p "Delete all of the above? [y/N] " ans; [ "$ans" = y ] || { echo "Aborted."; exit 1; }; fi

echo "$VMS" | while read -r name zone; do [ -n "$name" ] && g compute instances delete "$name" --zone="$zone" && echo "deleted VM $name"; done
for i in $IMAGES; do g compute images delete "$i" && echo "deleted image $i"; done
[ -n "$BUCKET" ] && gcloud storage rm -r "gs://$B" --project="$PROJECT" >/dev/null 2>&1 && echo "deleted bucket gs://$B"
for r in $RULES; do g compute firewall-rules delete "$r" && echo "deleted firewall rule $r"; done
rm -rf "${WORK:-$HOME/lab1-import-aws}"   # the working folder 04-gcp-import-and-launch.sh downloads into
echo "Remaining lab VMs: $(g compute instances list --filter="name~apacheserver" --format="value(name)" | grep -c . )"
echo "GCP_CLEANUP_DONE"
