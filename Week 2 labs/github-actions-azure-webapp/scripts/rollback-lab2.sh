#!/usr/bin/env bash
# Week 2 Lab 2.2 rollback: the Azure resource group (plan + web app together) and, with --repo, the
# GitHub repository.   rollback-lab2.sh [-n] [-y] [--repo]
set -uo pipefail; DRY=0; YES=0; REPO=0
for a in "$@"; do case "$a" in -n) DRY=1;; -y) YES=1;; --repo) REPO=1;; *) echo "usage: $0 [-n] [-y] [--repo]"; exit 2;; esac; done
RG=canyon-soccer-rg; GH_USER=$(gh api user --jq .login 2>/dev/null)
G=$(az group show -n "$RG" --query name -o tsv 2>/dev/null); R=$( [ "$REPO" = 1 ] && gh repo view "$GH_USER/canyon-schedule" --json nameWithOwner --jq .nameWithOwner 2>/dev/null)
echo "Lab 2 resources:"; printf '  Azure resource group: %s\n  GitHub repo: %s\n' "${G:-none}" "${R:-$([ "$REPO" = 1 ] && echo none || echo '(not requested, pass --repo)')}"
[ -z "$G$R" ] && { echo "Nothing to delete."; exit 0; }; [ "$DRY" = 1 ] && exit 0
if [ "$YES" != 1 ]; then read -r -p "Delete all of the above? [y/N] " ans; [ "$ans" = y ] || { echo "Aborted."; exit 1; }; fi
[ -n "$G" ] && az group delete -n "$RG" --yes --no-wait -o none && echo "resource group deletion started (plan and web app go with it)"
[ -n "$R" ] && gh repo delete "$R" --yes && echo "deleted repo $R"
echo "LAB2_ROLLBACK_DONE"
