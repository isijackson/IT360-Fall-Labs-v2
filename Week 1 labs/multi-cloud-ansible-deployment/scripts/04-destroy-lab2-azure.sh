#!/usr/bin/env bash
# Lab 2 teardown, Azure side: deletes the client VM and everything az vm create made for it
# (NIC, public IP, NSG, VNet, OS disk). The Vocareum resource group itself is pre-created and
# stays. In your own subscription the lab's group ansible-lab-rg is deleted whole. Run where az is signed in
# (laptop or the portal's Cloud Shell; the Vocareum sandbox blocks the Azure CLI on a laptop).
#   04-destroy-lab2-azure.sh [RESOURCE_GROUP] [-n] [-y]   -n = dry run, -y = no confirmation prompt
# If RESOURCE_GROUP is omitted and the subscription has exactly one group, that one is used.
set -uo pipefail
VM="${VM:-ansible-client-azure}"; RG=""; DRY=0; YES=0
for a in "$@"; do case "$a" in -n) DRY=1;; -y) YES=1;; *) RG="$a";; esac; done
# Own subscription (deploy-lab2.sh): the lab created the group ansible-lab-rg, so delete the whole group.
if [ -z "$RG" ] && az group show -n "${AZ_RG:-ansible-lab-rg}" -o none 2>/dev/null; then
  RG="${AZ_RG:-ansible-lab-rg}"; echo "Lab 2 resources on Azure: resource group $RG ($(az resource list -g "$RG" --query 'length(@)') resources)"
  [ "$DRY" = 1 ] && exit 0
  if [ "$YES" != 1 ]; then read -r -p "Delete resource group $RG and everything in it? [y/N] " ans; [ "$ans" = y ] || { echo "Aborted."; exit 1; }; fi
  az group delete -n "$RG" --yes -o none && echo "deleted resource group $RG"; echo "AZURE_CLEANUP_DONE"; exit 0
fi
if [ -z "$RG" ]; then
  RG=$(az group list --query "[].name" -o tsv); [ "$(echo "$RG" | grep -c .)" = 1 ] || { echo "Pass the resource group name; found: $RG"; exit 2; }
fi
IDS=$(az resource list -g "$RG" --query "[?starts_with(name,'$VM')].[type,name]" -o tsv 2>/dev/null)
echo "Lab 2 resources in resource group $RG:"
[ -n "$IDS" ] && echo "$IDS" | sed 's/^/  /' || echo "  none"
[ -z "$IDS" ] && { echo "Nothing to delete."; exit 0; }
[ "$DRY" = 1 ] && exit 0
if [ "$YES" != 1 ]; then read -r -p "Delete all of the above? [y/N] " ans; [ "$ans" = y ] || { echo "Aborted."; exit 1; }; fi
az vm show -g "$RG" -n "$VM" >/dev/null 2>&1 && az vm delete -g "$RG" -n "$VM" --yes >/dev/null && echo "deleted VM $VM"
# dependents in the order Azure allows; retry because deletes finish asynchronously
for t in Microsoft.Network/networkInterfaces Microsoft.Network/publicIPAddresses Microsoft.Network/networkSecurityGroups \
         Microsoft.Network/virtualNetworks Microsoft.Compute/disks; do
  for id in $(az resource list -g "$RG" --resource-type "$t" --query "[?starts_with(name,'$VM')].id" -o tsv); do
    for try in 1 2 3 4 5 6; do az resource delete --ids "$id" >/dev/null 2>&1 && { echo "deleted ${id##*/} ($t)"; break; }; sleep 15; done
  done
done
echo "Remaining lab resources: $(az resource list -g "$RG" --query "length([?starts_with(name,'$VM')])" -o tsv)"
echo "AZURE_CLEANUP_DONE"
