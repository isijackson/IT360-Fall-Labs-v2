#!/usr/bin/env bash
# Lab 1 (Azure variant) teardown, GCP side. Finds the VM, image, bucket and firewall rules the lab created.
# Run in Cloud Shell or anywhere gcloud is logged in.
#   06-cleanup-gcp.sh <PROJECT_ID> [-n] [-y]     -n = dry run, -y = no confirmation prompt
set -uo pipefail
PROJECT="${1:?usage: $0 <PROJECT_ID> [-n] [-y]}"; shift; DRY=0; YES=0
for a in "$@"; do case "$a" in -n) DRY=1;; -y) YES=1;; *) echo "usage: $0 <PROJECT_ID> [-n] [-y]"; exit 2;; esac; done
B="${BUCKET:-${PROJECT}-apache-migration}"
g() { gcloud "$@" --project="$PROJECT" --quiet 2>/dev/null; }

VMS=$(g compute instances list --filter="name~^apacheserver-gcp$" --format="value(name,zone.basename())")   # regex: never the -aws VM
IMAGES=$(g compute images list --no-standard-images --filter="name~^apacheserver-image$ OR family~^apacheserver$" --format="value(name)")
BUCKET=$(gcloud storage ls --project="$PROJECT" 2>/dev/null | grep -x "gs://$B/")
# allow-http is shared with the AWS variant: keep it while any other http-server VM is still in the project
OTHERS=$(g compute instances list --filter="tags.items=http-server" --format="value(name)" | grep -vx "apacheserver-gcp")
# exact name match (a gcloud filter "name=allow-http" also matches default-allow-http by word pattern)
if [ -z "$OTHERS" ]; then DEL="allow-http|allow-ssh-admin"; else DEL="allow-ssh-admin"; echo "keeping allow-http: still used by $OTHERS"; fi
RULES=$(g compute firewall-rules list --format="value(name)" | grep -xE "$DEL")

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
rm -rf "${WORK:-$HOME/lab1-import}"   # the working folder 04-gcp-import-and-launch.sh downloads into
echo "Remaining lab VMs: $(g compute instances list --filter="name~apacheserver" --format="value(name)" | grep -c . )"
echo "GCP_CLEANUP_DONE"
