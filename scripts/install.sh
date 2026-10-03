#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${MY_NVR_REPO_URL:-https://github.com/RobertRupa/my-nvr.git}"
REPO_REF="${MY_NVR_REPO_REF:-refs/heads/main}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

log() { printf '\n[my-nvr] %s\n' "$*"; }
die() { printf '\n[my-nvr] ERROR: %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run this installer as root (sudo)."
[[ -r /etc/os-release ]] || die "Cannot identify operating system."

# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "debian" ]] || die "Supported production baseline is Debian 12."
if [[ "${VERSION_ID:-}" != "12" && "${MY_NVR_ALLOW_UNSUPPORTED:-0}" != "1" ]]; then
  die "Supported production baseline is Debian 12. Set MY_NVR_ALLOW_UNSUPPORTED=1 only for testing."
fi

export DEBIAN_FRONTEND=noninteractive

log "Installing base packages"
apt-get update
apt-get install -y ca-certificates curl git jq openssl unattended-upgrades

log "Enabling unattended security upgrades"
cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

if ! dpkg-query -W -f='${Status}' docker-ce 2>/dev/null | grep -q "ok installed"; then
  if command -v docker >/dev/null 2>&1; then
    die "Docker is already installed but not from docker-ce. Clean or migrate the host before production provisioning."
  fi

  log "Adding official Docker APT repository"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

systemctl enable --now docker

log "Creating persistent directories"
install -d -m 0755 /etc/my-nvr/frigate
install -d -m 0755 /srv/frigate
install -d -m 0700 /var/lib/my-nvr/backups

if [[ ! -f /etc/my-nvr/frigate/config.yml ]]; then
  install -m 0640 "$REPO_DIR/config/frigate.example.yml" /etc/my-nvr/frigate/config.yml
fi

if [[ ! -s /etc/my-nvr/portainer-admin-password ]]; then
  log "Creating Portainer administrator password"
  PASSWORD="$(openssl rand -base64 32 | tr -d '\n' | tr '/+' '_-' | cut -c1-28)"
  umask 077
  printf '%s' "$PASSWORD" >/etc/my-nvr/portainer-admin-password
  unset PASSWORD
fi
chmod 0600 /etc/my-nvr/portainer-admin-password

log "Starting Portainer"
docker compose -f "$REPO_DIR/portainer-compose.yml" pull
docker compose -f "$REPO_DIR/portainer-compose.yml" up -d

log "Waiting for Portainer API"
for _ in $(seq 1 60); do
  if curl -kfsS https://127.0.0.1:9443/api/status >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
curl -kfsS https://127.0.0.1:9443/api/status >/dev/null 2>&1 || die "Portainer API did not become ready."

log "Creating Portainer Git stack"
MY_NVR_REPO_URL="$REPO_URL" MY_NVR_REPO_REF="$REPO_REF" bash "$SCRIPT_DIR/portainer-bootstrap.sh"

log "Waiting for Frigate"
for _ in $(seq 1 60); do
  if docker inspect -f '{{.State.Running}}' frigate 2>/dev/null | grep -q true; then
    break
  fi
  sleep 2
done

docker inspect -f '{{.State.Running}}' frigate 2>/dev/null | grep -q true || {
  docker logs --tail 100 frigate || true
  die "Frigate did not start."
}

HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[[ -n "$HOST_IP" ]] || HOST_IP="<server-ip>"

cat <<EOF

my-nvr provisioning completed.

Frigate:   https://${HOST_IP}:8971
Portainer: https://${HOST_IP}:9443

Portainer user: admin
Portainer password (root-only file):
  sudo cat /etc/my-nvr/portainer-admin-password

Camera setup is optional. You can finish appliance setup without adding a camera.
EOF
