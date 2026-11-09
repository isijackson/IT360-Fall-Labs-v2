#!/usr/bin/env bash
# Lab 2 teardown, DigitalOcean side: deletes the controller droplet (and optionally the SSH key
# you uploaded for it). Needs doctl logged in (doctl auth init).
#   02-destroy-lab2-do.sh [-n] [-y]        -n = dry run, -y = no confirmation prompt
# DROPLET defaults to ansible-controller. Set DO_KEY_NAME=<name> to also delete that uploaded key.
set -uo pipefail
DROPLET="${DROPLET:-ansible-controller}"; DRY=0; YES=0
for a in "$@"; do case "$a" in -n) DRY=1;; -y) YES=1;; *) echo "usage: $0 [-n] [-y]"; exit 2;; esac; done
CTX=${DO_CONTEXT:+--context $DO_CONTEXT}
IDS=$(doctl compute droplet list $CTX --format ID,Name,PublicIPv4 --no-header 2>/dev/null | awk -v n="$DROPLET" '$2==n{print $1" ("$3")"}')
KEY=$( [ -n "${DO_KEY_NAME:-}" ] && doctl compute ssh-key list $CTX --format ID,Name --no-header 2>/dev/null | awk -v n="$DO_KEY_NAME" '$2==n{print $1}')
echo "Lab 2 resources on DigitalOcean:"
printf '  droplet %s: %s\n  ssh key %s: %s\n' "$DROPLET" "${IDS:-none}" "${DO_KEY_NAME:-(not requested)}" "${KEY:-none}"
[ -z "$IDS$KEY" ] && { echo "Nothing to delete."; exit 0; }
[ "$DRY" = 1 ] && exit 0
if [ "$YES" != 1 ]; then read -r -p "Delete all of the above? [y/N] " ans; [ "$ans" = y ] || { echo "Aborted."; exit 1; }; fi
for id in $(echo "$IDS" | awk '{print $1}'); do doctl compute droplet delete "$id" $CTX --force && echo "deleted droplet $id"; done
[ -n "$KEY" ] && doctl compute ssh-key delete "$KEY" $CTX --force && echo "deleted ssh key $KEY"
echo "Remaining droplets: $(doctl compute droplet list $CTX --format Name --no-header 2>/dev/null | grep -c .)"
echo "DO_CLEANUP_DONE"
