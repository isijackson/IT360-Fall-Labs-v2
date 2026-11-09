#!/usr/bin/env bash
# Week 1 Lab 2 rollback (same as destroy-lab2.sh): DigitalOcean droplet, GCP client and rule, Azure group.
#   rollback-lab2.sh <GCP_PROJECT_ID> [-n] [-y]
exec bash "$(cd "$(dirname "$0")" && pwd)/destroy-lab2.sh" "$@"
