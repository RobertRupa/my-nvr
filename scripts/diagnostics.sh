#!/usr/bin/env bash
set -Eeuo pipefail

echo "=== OS ==="
cat /etc/os-release
uname -a

echo
echo "=== Storage ==="
df -h / /srv/frigate 2>/dev/null || true

echo
echo "=== Docker ==="
docker version || true
docker compose version || true
docker info --format 'Driver={{.Driver}} Cgroup={{.CgroupDriver}}' || true

echo
echo "=== Containers ==="
docker ps -a --filter name=frigate --filter name=portainer

echo
echo "=== Frigate ==="
docker inspect -f 'Image={{.Config.Image}} Running={{.State.Running}} Status={{.State.Status}}' frigate 2>/dev/null || true
docker logs --tail 80 frigate 2>&1 || true

echo
echo "=== Portainer ==="
docker inspect -f 'Image={{.Config.Image}} Running={{.State.Running}} Status={{.State.Status}}' portainer 2>/dev/null || true
docker logs --tail 40 portainer 2>&1 || true

echo
echo "=== Acceleration devices ==="
ls -l /dev/dri /dev/accel /dev/hailo0 /dev/bus/usb 2>/dev/null || true
