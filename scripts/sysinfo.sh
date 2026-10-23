#!/usr/bin/env bash
set -euo pipefail

echo "User: $(id -un)"
echo "Effective UID: $(id -u)"
echo "Hostname: $(hostname)"
echo "Kernel: $(uname -r)"
echo "Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "Disk usage:"
df -h /
echo "Memory usage:"
free -h
if docker info >/dev/null 2>&1; then
  echo "Docker daemon: running"
else
  echo "Docker daemon: not running"
fi
