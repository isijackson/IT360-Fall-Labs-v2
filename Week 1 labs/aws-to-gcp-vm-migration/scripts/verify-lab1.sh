#!/usr/bin/env bash
# Week 1 Lab 1 (AWS -> GCP) verification: what exists on each side and whether both web servers answer.
#   verify-lab1.sh <GCP_PROJECT_ID>          env: NAME ZONE AWS_DEFAULT_REGION (us-east-2) GCP_VM IMAGE
set -uo pipefail
PROJECT="${1:?usage: $0 <GCP_PROJECT_ID>}"; NAME="${NAME:-apacheserver1}"; ZONE="${ZONE:-us-central1-a}"
GCP_VM="${GCP_VM:-apacheserver-gcp-aws}"; IMAGE="${IMAGE:-apacheserver-image-aws}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-2}"; export AWS_PAGER=""
http() { curl -s -m 8 -o /dev/null -w '%{http_code}' "http://$1/"; }
if aws sts get-caller-identity >/dev/null 2>&1; then
  echo "== AWS (account $(aws sts get-caller-identity --query Account --output text), $AWS_DEFAULT_REGION)"
  aws ec2 describe-instances --filters "Name=tag:Name,Values=$NAME" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].{id:InstanceId,state:State.Name,type:InstanceType,ip:PublicIpAddress,az:Placement.AvailabilityZone}' --output table
  EC2_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$NAME" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null)
  aws ec2 describe-volumes --filters "Name=tag:Name,Values=${NAME}-scratch" --query 'Volumes[].{volume:VolumeId,gb:Size,state:State}' --output table
  aws ec2 describe-security-groups --filters "Name=group-name,Values=${NAME}-sg" --query 'SecurityGroups[0].IpPermissions[].{port:FromPort,from:IpRanges[0].CidrIp}' --output table
else
  echo "== AWS: no laptop credentials; check in the console or CloudShell:"
  echo "   aws ec2 describe-instances --filters Name=tag:Name,Values=$NAME --query 'Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]' --output table"
  EC2_IP="${EC2_IP:-}"
fi
[ -n "$EC2_IP" ] && [ "$EC2_IP" != None ] && { echo "http://$EC2_IP/ -> $(http "$EC2_IP")"; echo "http://$EC2_IP/disk.qcow2 -> $(curl -s -m 8 -o /dev/null -w '%{http_code}' "http://$EC2_IP/disk.qcow2") (should be 404 after Step 11)"; }
echo "== GCP (project $PROJECT)"
gcloud compute images list --project "$PROJECT" --no-standard-images --filter="name=$IMAGE" --format="table(name,family,diskSizeGb,status)" 2>/dev/null
gcloud compute instances list --project "$PROJECT" --filter="name=$GCP_VM" --format="table(name,zone.basename(),machineType.basename(),status,networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null
gcloud compute firewall-rules list --project "$PROJECT" --filter="name=allow-http" --format="table(name,sourceRanges.list(),allowed[].map().firewall_rule().list())" 2>/dev/null
gcloud storage ls "gs://${PROJECT}-apache-migration-aws/" 2>/dev/null
GCP_IP=$(gcloud compute instances describe "$GCP_VM" --project "$PROJECT" --zone "$ZONE" --format='value(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null)
[ -n "$GCP_IP" ] && { echo "http://$GCP_IP/ -> $(http "$GCP_IP")"; curl -s -m 8 "http://$GCP_IP/" | grep -o '<title>.*</title>'; }
echo "== Same server? (the marker Step 6 wrote on AWS must be served from GCP; cloud-init renames the host to the GCE instance name)"
[ -n "$GCP_IP" ] && echo "GCP: $(curl -s -m 8 "http://$GCP_IP/migrated-from.txt")"
[ -n "$EC2_IP" ] && [ "$EC2_IP" != None ] && echo "AWS: $(curl -s -m 8 "http://$EC2_IP/migrated-from.txt")"
