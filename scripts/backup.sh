#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root." >&2; exit 1; }

BACKUP_ROOT="${MY_NVR_BACKUP_DIR:-/var/lib/my-nvr/backups}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DEST="$BACKUP_ROOT/$STAMP"

install -d -m 0700 "$DEST"

tar -C /etc -czf "$DEST/my-nvr-config.tgz" my-nvr

if docker volume inspect portainer_data >/dev/null 2>&1; then
  docker run --rm     -v portainer_data:/source:ro     -v "$DEST:/backup"     alpine:3.22     sh -c 'cd /source && tar -czf /backup/portainer-data.tgz .'
fi

cat >"$DEST/manifest.txt" <<EOF
created_utc=$STAMP
hostname=$(hostname)
frigate_image=$(docker inspect -f '{{.Config.Image}}' frigate 2>/dev/null || true)
portainer_image=$(docker inspect -f '{{.Config.Image}}' portainer 2>/dev/null || true)
EOF

chmod -R go-rwx "$DEST"
echo "Backup created: $DEST"
