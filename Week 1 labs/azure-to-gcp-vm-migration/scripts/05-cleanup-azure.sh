#!/usr/bin/env bash
# Lab 1 (Azure variant) teardown, Azure side: the VM and everything az vm create made for it (NIC, public IP,
# NSG, VNet, OS disk, scratch disk). The resource group is deleted only if this lab created it (NAME-rg);
# on the Vocareum sandbox the pre-created group stays. Run in Cloud Shell.
#   05-cleanup-azure.sh [-n] [-y]        RG=<group> to point at an existing group
set -uo pipefail
NAME="${NAME:-apacheserver1}"; DRY=0; YES=0
for a in "$@"; do case "$a" in -n) DRY=1;; -y) YES=1;; *) echo "usage: $0 [-n] [-y]"; exit 2;; esac; done
RG="${RG:-$(az group list --query "[?name=='${NAME}-rg'].name" -o tsv)}"; [ -z "$RG" ] && RG=$(az group list --query "[0].name" -o tsv)
IDS=$(az resource list -g "$RG" --query "[?starts_with(name,'$NAME')].[type,name]" -o tsv 2>/dev/null)
echo "Lab 1 resources in resource group $RG:"; [ -n "$IDS" ] && echo "$IDS" | sed 's/^/  /' || echo "  none"
[ -z "$IDS" ] && { echo "Nothing to delete."; exit 0; }; [ "$DRY" = 1 ] && exit 0
if [ "$YES" != 1 ]; then read -r -p "Delete all of the above? [y/N] " ans; [ "$ans" = y ] || { echo "Aborted."; exit 1; }; fi
if [ "$RG" = "${NAME}-rg" ]; then az group delete -n "$RG" --yes -o none && echo "deleted resource group $RG (everything in it)"; else
  az vm show -g "$RG" -n "$NAME" -o none 2>/dev/null && az vm delete -g "$RG" -n "$NAME" --yes -o none && echo "deleted VM $NAME"
  for t in Microsoft.Network/networkInterfaces Microsoft.Network/publicIPAddresses Microsoft.Network/networkSecurityGroups Microsoft.Network/virtualNetworks Microsoft.Compute/disks; do
    for id in $(az resource list -g "$RG" --resource-type "$t" --query "[?starts_with(name,'$NAME')].id" -o tsv); do
      for try in 1 2 3 4 5 6; do az resource delete --ids "$id" -o none 2>/dev/null && { echo "deleted ${id##*/}"; break; }; sleep 15; done; done; done
fi
rm -f ~/.ssh/${NAME}-key ~/.ssh/${NAME}-key.pub
echo "AZURE_CLEANUP_DONE"
