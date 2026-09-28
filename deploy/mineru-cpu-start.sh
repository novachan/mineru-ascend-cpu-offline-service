#!/usr/bin/env bash
set -euo pipefail

docker rm -f mineru-cpu 2>/dev/null || true

exec docker run -d \
  --name mineru-cpu \
  -p 8856:8856 \
  --restart unless-stopped \
  mineru-cpu:3.4.5
