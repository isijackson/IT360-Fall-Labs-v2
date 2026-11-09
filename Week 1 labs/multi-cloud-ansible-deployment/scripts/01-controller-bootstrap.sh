#!/usr/bin/env bash
# Part 1 + Part 3 (key generation). Run ON THE CONTROLLER as root right after first login.
set -euo pipefail
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq software-properties-common >/dev/null
add-apt-repository --yes --update ppa:ansible/ansible >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ansible >/dev/null
ansible --version | head -1
[ -f ~/.ssh/id_rsa ] || ssh-keygen -t rsa -b 2048 -N "" -f ~/.ssh/id_rsa -q
echo "Controller public key (add this to every client VM):"
cat ~/.ssh/id_rsa.pub
