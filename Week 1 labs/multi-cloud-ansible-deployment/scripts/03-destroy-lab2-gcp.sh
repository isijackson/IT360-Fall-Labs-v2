#!/usr/bin/env bash
# Lab 2 teardown, GCP side: deletes the client VM (its ssh-keys metadata goes with it) and the
# allow-ssh-ansible firewall rule. Run in Cloud Shell or anywhere gcloud is logged in.
#   03-destroy-lab2-gcp.sh <PROJECT_ID> [-n] [-y]     -n = dry run, -y = no confirmation prompt
set -uo pipefail
PROJECT="${1:?usage: $0 <PROJECT_ID> [-n] [-y]}"; shift; DRY=0; YES=0
for a in "$@"; do case "$a" in -n) DRY=1;; -y) YES=1;; *) echo "usage: $0 <PROJECT_ID> [-n] [-y]"; exit 2;; esac; done
VM="${VM:-ansible-client-gcp}"
g() { gcloud "$@" --project="$PROJECT" --quiet 2>/dev/null; }
VMS=$(g compute instances list --filter="name=$VM" --format="value(name,zone.basename())")
RULES=$(g compute firewall-rules list --filter="name=allow-ssh-ansible" --format="value(name)")
echo "Lab 2 resources in project $PROJECT:"
printf '  VMs (name zone): %s\n  firewall rules:  %s\n' "${VMS:-none}" "${RULES:-none}"
[ -z "$VMS$RULES" ] && { echo "Nothing to delete."; exit 0; }
[ "$DRY" = 1 ] && exit 0
if [ "$YES" != 1 ]; then read -r -p "Delete all of the above? [y/N] " ans; [ "$ans" = y ] || { echo "Aborted."; exit 1; }; fi
echo "$VMS" | while read -r name zone; do [ -n "$name" ] && g compute instances delete "$name" --zone="$zone" && echo "deleted VM $name"; done
for r in $RULES; do g compute firewall-rules delete "$r" && echo "deleted firewall rule $r"; done
echo "Remaining lab VMs: $(g compute instances list --filter="name~ansible-client" --format="value(name)" | grep -c .)"
echo "GCP_CLEANUP_DONE"
