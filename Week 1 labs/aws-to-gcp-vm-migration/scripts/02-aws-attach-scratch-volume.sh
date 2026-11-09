#!/usr/bin/env bash
# Step 5: create a 10 GB gp3 volume in the instance's AZ and attach it as /dev/sdf (appears as /dev/xvdf on t2, /dev/nvme1n1 on t3).
set -euo pipefail
I="${1:?usage: $0 <INSTANCE_ID>}"
AZ=$(aws ec2 describe-instances --instance-ids "$I" --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text)
V=$(aws ec2 create-volume --availability-zone "$AZ" --size 10 --volume-type gp3 \
     --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=apacheserver1-scratch}]' --query VolumeId --output text)
aws ec2 wait volume-available --volume-ids "$V"
aws ec2 attach-volume --volume-id "$V" --instance-id "$I" --device /dev/sdf --query State --output text
echo "Scratch volume $V attached to $I. Remember it for cleanup."
