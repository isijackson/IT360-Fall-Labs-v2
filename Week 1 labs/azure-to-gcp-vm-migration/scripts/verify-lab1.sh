#!/usr/bin/env bash
# Week 1 Lab 1 (Azure -> GCP) verification: what exists on each side and whether both web servers answer.
#   verify-lab1.sh <GCP_PROJECT_ID>          env: NAME RG ZONE
set -uo pipefail
PROJECT="${1:?usage: $0 <GCP_PROJECT_ID>}"; NAME="${NAME:-apacheserver1}"; RG="${RG:-${NAME}-rg}"; ZONE="${ZONE:-us-central1-a}"
http() { curl -s -m 8 -o /dev/null -w '%{http_code}' "http://$1/"; }
echo "== Azure (subscription: $(az account show --query name -o tsv 2>/dev/null))"
az vm show -d -g "$RG" -n "$NAME" --query "{vm:name,state:powerState,ip:publicIps,size:hardwareProfile.vmSize,region:location}" -o table 2>/dev/null || echo "VM $NAME not found in $RG"
AZ_IP=$(az vm show -d -g "$RG" -n "$NAME" --query publicIps -o tsv 2>/dev/null)
az disk list -g "$RG" --query "[].{disk:name,gb:diskSizeGb,state:diskState}" -o table 2>/dev/null
az network nsg rule list -g "$RG" --nsg-name "${NAME}NSG" --query "[].{rule:name,port:destinationPortRange,from:sourceAddressPrefix}" -o table 2>/dev/null
[ -n "$AZ_IP" ] && { echo "http://$AZ_IP/ -> $(http "$AZ_IP")"; echo "http://$AZ_IP/disk.qcow2 -> $(curl -s -m 8 -o /dev/null -w '%{http_code}' "http://$AZ_IP/disk.qcow2") (should be 404 after Step 11)"; }
echo "== GCP (project $PROJECT)"
gcloud compute images list --project "$PROJECT" --no-standard-images --filter="family=apacheserver" --format="table(name,family,diskSizeGb,status)" 2>/dev/null
gcloud compute instances list --project "$PROJECT" --filter="name=apacheserver-gcp" --format="table(name,zone.basename(),machineType.basename(),status,networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null
gcloud compute firewall-rules list --project "$PROJECT" --filter="name=allow-http" --format="table(name,sourceRanges.list(),allowed[].map().firewall_rule().list())" 2>/dev/null
gcloud storage ls "gs://${PROJECT}-apache-migration/" 2>/dev/null
GCP_IP=$(gcloud compute instances describe apacheserver-gcp --project "$PROJECT" --zone "$ZONE" --format='value(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null)
[ -n "$GCP_IP" ] && { echo "http://$GCP_IP/ -> $(http "$GCP_IP")"; curl -s -m 8 "http://$GCP_IP/" | grep -o '<title>.*</title>'; }
echo "== Same server? (the marker Step 6 wrote on Azure must be served from GCP; cloud-init renames the host to the GCE instance name)"
[ -n "$GCP_IP" ] && { echo "GCP:   $(curl -s -m 8 "http://$GCP_IP/migrated-from.txt")"; }
[ -n "$AZ_IP" ] && { echo "Azure: $(curl -s -m 8 "http://$AZ_IP/migrated-from.txt")"; }
