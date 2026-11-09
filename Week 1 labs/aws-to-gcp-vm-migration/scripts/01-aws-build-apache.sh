#!/usr/bin/env bash
# Steps 1-4: launch an Ubuntu 22.04 t2.micro, open SSH (from this machine's IP only) and HTTP (from
# everyone), install and verify Apache.
# Run where the AWS CLI is configured (e.g. the Vocareum terminal). Needs: aws, ssh, curl.
set -euo pipefail
KEY_NAME="${KEY_NAME:-vockey}"                       # EC2 key pair name
KEY_FILE="${KEY_FILE:-$HOME/.ssh/labsuser.pem}"      # matching private key
NAME="${NAME:-apacheserver1}"
MY_IP=$(curl -s -4 --max-time 10 https://api.ipify.org || curl -s -4 --max-time 10 https://ifconfig.me)
[ -n "$MY_IP" ] || { echo "could not find this machine's public IP; SSH would have no source"; exit 1; }
echo "ADMIN_IP=$MY_IP (SSH is opened to this /32 only)"

VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
SG=$(aws ec2 create-security-group --group-name "${NAME}-sg" --description "SSH from admin and HTTP for ${NAME}" \
      --vpc-id "$VPC" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG" --ip-permissions \
  "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=$MY_IP/32,Description=ssh-from-admin}]" \
  IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges='[{CidrIp=0.0.0.0/0}]' >/dev/null
AMI=$(aws ec2 describe-images --owners 099720109477 \
  --filters 'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*' 'Name=state,Values=available' \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)
ID=$(aws ec2 run-instances --image-id "$AMI" --instance-type t2.micro --key-name "$KEY_NAME" \
  --security-group-ids "$SG" --associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME}}]" \
  --query 'Instances[0].InstanceId' --output text)
echo "Instance: $ID   Security group: $SG   AMI: $AMI"
aws ec2 wait instance-running --instance-ids "$ID"
IP=$(aws ec2 describe-instances --instance-ids "$ID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "Public IP: $IP"
chmod 400 "$KEY_FILE"
until nc -z -w3 "$IP" 22; do sleep 5; done
ssh -o StrictHostKeyChecking=no -i "$KEY_FILE" "ubuntu@$IP" \
  'sudo apt-get update -qq >/dev/null; sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apache2 >/dev/null;
   sudo systemctl enable apache2 >/dev/null 2>&1; sudo systemctl start apache2; echo "apache2: $(systemctl is-active apache2)"'
echo "HTTP from outside: $(curl -s -o /dev/null -w '%{http_code}' http://$IP/)  ->  open http://$IP"
