#!/usr/bin/env bash
# Week 3 Lab 3.3 rollback: Jenkins and registry containers, containers started from the menu-board
# images (smoke tests, the handout's test runs on 8081/8082), volumes, network, built images.
#   rollback-lab3-2.sh [-n] [-y]
set -uo pipefail; DRY=0; YES=0
for a in "$@"; do case "$a" in -n) DRY=1;; -y) YES=1;; *) echo "usage: $0 [-n] [-y]"; exit 2;; esac; done
C=$(docker ps -a --format '{{.Names}}' | grep -E '^(jenkins|registry)$' | tr '\n' ' ')
V=$(docker volume ls -q | grep -E '^brewlab-git$' | tr '\n' ' ')
I=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E 'menu-board|^it360-jenkins' | tr '\n' ' ')
# a running container keeps its image in use and makes docker rmi fail, so those containers go too
M=$(for i in $I; do case "$i" in *menu-board*) docker ps -aq --filter ancestor="$i";; esac; done | sort -u | tr '\n' ' ')
N=$(docker network ls --format '{{.Name}}' | grep -x brewlab)
echo "Lab 3.3 resources on this machine:"; printf '  containers: %s\n  containers from menu-board images: %s\n  volumes: %s\n  images: %s\n  network: %s\n' "${C:-none}" "${M:-none}" "${V:-none}" "${I:-none}" "${N:-none}"
[ -z "$C$M$V$I$N" ] && { echo "Nothing to delete."; exit 0; }
[ "$DRY" = 1 ] && exit 0
if [ "$YES" != 1 ]; then read -r -p "Delete all of the above? [y/N] " ans; [ "$ans" = y ] || { echo "Aborted."; exit 1; }; fi
[ -n "$C" ] && docker rm -f $C >/dev/null && echo "removed containers"
[ -n "${M// /}" ] && docker rm -f $M >/dev/null && echo "removed containers started from menu-board images"
[ -n "$V" ] && docker volume rm $V >/dev/null && echo "removed volumes"
if [ -n "$I" ]; then
  if docker rmi -f $I >/dev/null 2>&1; then echo "removed images"
  else echo "WARNING: some images were not removed; check: docker images | grep -E 'menu-board|it360-jenkins'"; fi
fi
[ -n "$N" ] && docker network rm brewlab >/dev/null && echo "removed network"
echo "LAB3_2_ROLLBACK_DONE"
