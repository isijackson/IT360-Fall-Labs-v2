#!/usr/bin/env bash
# Lab 1 teardown, AWS side. Finds everything the lab created by NAME, so no IDs are needed.
# Run where the AWS CLI is configured (laptop profile, AWS CloudShell, or the Vocareum terminal).
#   05-cleanup-aws.sh        list what will be deleted, ask, then delete
#   05-cleanup-aws.sh -n     dry run: list only
#   05-cleanup-aws.sh -y     delete without asking
# NAME defaults to apacheserver1 (override with NAME=... in the environment).
set -uo pipefail
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-us-east-2}}"; export AWS_PAGER=""
NAME="${NAME:-apacheserver1}"; DRY=0; YES=0
for a in "$@"; do case "$a" in -n) DRY=1;; -y) YES=1;; *) echo "usage: $0 [-n] [-y]"; exit 2;; esac; done
q() { aws "$@" --output text 2>/dev/null; }

INSTANCES=$(q ec2 describe-instances --filters "Name=tag:Name,Values=$NAME" \
  "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'Reservations[].Instances[].InstanceId')
VOLUMES=$(q ec2 describe-volumes --filters "Name=tag:Name,Values=${NAME}-scratch" --query 'Volumes[].VolumeId')
SGS=$(q ec2 describe-security-groups --filters "Name=group-name,Values=${NAME}-sg" --query 'SecurityGroups[].GroupId')
AMIS=$(q ec2 describe-images --owners self --filters "Name=name,Values=${NAME}*" --query 'Images[].ImageId')
SNAPS=$(q ec2 describe-images --owners self --filters "Name=name,Values=${NAME}*" \
  --query 'Images[].BlockDeviceMappings[].Ebs.SnapshotId')
BUCKETS=$(q s3api list-buckets --query "Buckets[?starts_with(Name,'${NAME}')].Name")
ROLE=$(q iam get-role --role-name vmimport --query Role.RoleName)
KEYS=$(q ec2 describe-key-pairs --filters "Name=key-name,Values=${NAME}-key" --query 'KeyPairs[].KeyName')

echo "Lab 1 resources named '$NAME' in $(q sts get-caller-identity --query Account) / $(aws configure get region 2>/dev/null || echo "$AWS_DEFAULT_REGION"):"
printf '  instances:       %s\n  scratch volumes: %s\n  security groups: %s\n  AMIs:            %s\n  snapshots:       %s\n  S3 buckets:      %s\n  IAM role:        %s\n  key pairs:       %s\n' \
  "${INSTANCES:-none}" "${VOLUMES:-none}" "${SGS:-none}" "${AMIS:-none}" "${SNAPS:-none}" "${BUCKETS:-none}" "${ROLE:-none}" "${KEYS:-none}"
[ -z "$INSTANCES$VOLUMES$SGS$AMIS$SNAPS$BUCKETS$ROLE$KEYS" ] && { echo "Nothing to delete."; exit 0; }
[ "$DRY" = 1 ] && exit 0
if [ "$YES" != 1 ]; then read -r -p "Delete all of the above? [y/N] " ans; [ "$ans" = y ] || { echo "Aborted."; exit 1; }; fi

for i in $INSTANCES; do aws ec2 terminate-instances --instance-ids "$i" >/dev/null && echo "terminating $i"; done
[ -n "$INSTANCES" ] && aws ec2 wait instance-terminated --instance-ids $INSTANCES && echo "instances terminated"
for v in $VOLUMES; do aws ec2 wait volume-available --volume-ids "$v" 2>/dev/null; aws ec2 delete-volume --volume-id "$v" && echo "deleted volume $v"; done
for a in $AMIS; do aws ec2 deregister-image --image-id "$a" && echo "deregistered AMI $a"; done
for s in $SNAPS; do aws ec2 delete-snapshot --snapshot-id "$s" && echo "deleted snapshot $s"; done
for g in $SGS; do
  for t in 1 2 3 4 5 6; do aws ec2 delete-security-group --group-id "$g" 2>/dev/null && { echo "deleted security group $g"; break; }; sleep 10; done
done
for b in $BUCKETS; do aws s3 rb "s3://$b" --force >/dev/null && echo "deleted bucket $b"; done
if [ -n "$ROLE" ]; then
  for p in $(q iam list-role-policies --role-name vmimport --query PolicyNames); do aws iam delete-role-policy --role-name vmimport --policy-name "$p"; done
  for p in $(q iam list-attached-role-policies --role-name vmimport --query 'AttachedPolicies[].PolicyArn'); do aws iam detach-role-policy --role-name vmimport --policy-arn "$p"; done
  aws iam delete-role --role-name vmimport && echo "deleted IAM role vmimport"
fi
for k in $KEYS; do aws ec2 delete-key-pair --key-name "$k" && rm -f "$HOME/.ssh/$k.pem" && echo "deleted key pair $k"; done
echo "Remaining non-terminated instances in this region: $(q ec2 describe-instances \
  --filters Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' | wc -w | tr -d ' ')"
echo "AWS_CLEANUP_DONE"
