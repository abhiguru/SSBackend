#!/usr/bin/env bash
set -euo pipefail

cd /home/gcswebserver/ws/SSMasala/backend
/usr/bin/docker compose up -d --remove-orphans
