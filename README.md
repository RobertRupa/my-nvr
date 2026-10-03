# my-nvr

Production-oriented Frigate NVR appliance stack for Debian 12.

## Architecture

- Debian 12 (Bookworm), minimal installation
- Docker Engine from the official Docker APT repository
- Docker Compose plugin
- Frigate pinned to 0.18.0
- Portainer CE pinned to 2.45.1 LTS
- Frigate stack managed by Portainer from this Git repository
- Persistent configuration in `/etc/my-nvr`
- Recordings in `/srv/frigate`
- Backups in `/var/lib/my-nvr/backups`

Portainer is a service/admin interface. Git is the source of truth for the application stack. Camera configuration remains device-local.

## Production layout

```text
/etc/my-nvr/
├── frigate/
│   └── config.yml
└── portainer-admin-password

/srv/frigate/                 recordings and media
/var/lib/my-nvr/backups/      configuration backups
/opt/my-nvr/repo/             optional local checkout
```

## Clean Debian installation

Recommended target: Debian 12 minimal, x86_64/amd64.

```bash
sudo apt update
sudo apt install -y git
sudo mkdir -p /opt/my-nvr
sudo chown "$USER":"$USER" /opt/my-nvr
git clone https://github.com/RobertRupa/my-nvr.git /opt/my-nvr/repo
sudo /opt/my-nvr/repo/scripts/install.sh
```

The installer:

1. validates Debian,
2. installs required packages,
3. installs Docker Engine and the Compose plugin from Docker's official APT repository,
4. enables unattended security upgrades,
5. creates persistent NVR directories,
6. creates a minimal Frigate configuration that can boot without a real camera,
7. installs and starts Portainer,
8. creates the local Docker environment in Portainer,
9. creates a Portainer Git stack named `my-nvr` from this repository,
10. verifies that Frigate and Portainer are running.

At the end it prints the Frigate and Portainer addresses.

## Setup wizard design

The planned end-user wizard is documented in [docs/SETUP-WIZARD.md](docs/SETUP-WIZARD.md).

Important: **Step 3 — Add camera is optional.** The system must be able to finish initial setup and remain healthy without a connected camera.

Frigate 0.18 already includes a camera setup wizard in its own UI. The product wizard should therefore link/delegate to Frigate camera management rather than duplicate camera-specific RTSP/ONVIF logic.

## Ports

| Service | Port | Purpose |
|---|---:|---|
| Frigate | 8971/tcp | authenticated HTTPS UI |
| Frigate | 8554/tcp | RTSP restream |
| Frigate | 8555/tcp+udp | WebRTC |
| Portainer | 9443/tcp | HTTPS admin/service UI |

Port 5000 is intentionally not exposed because it provides Frigate's internal unauthenticated API.

## Updating

Do not use Watchtower or blind `latest` pulls in production.

Application versions are pinned in the repository. Update the repository only after validation, then use Portainer **Pull and redeploy** for the Git stack or run:

```bash
sudo /opt/my-nvr/repo/scripts/update.sh
```

The update helper backs up configuration before redeployment.

## Backup

```bash
sudo /opt/my-nvr/repo/scripts/backup.sh
```

Backups include Frigate configuration and the Portainer database volume export. Recordings are intentionally excluded.

## Diagnostics

```bash
sudo /opt/my-nvr/repo/scripts/diagnostics.sh
```

## Hardware acceleration

The base compose file is deliberately hardware-neutral. Add and validate hardware acceleration only for the target appliance hardware. See [docs/HARDWARE.md](docs/HARDWARE.md).

## Security notes

- Portainer is intended for administrators/service personnel, not normal end users.
- Portainer uses HTTPS on port 9443.
- Port 8000 (Edge Agent tunnel) is not exposed.
- Frigate internal port 5000 is not exposed.
- Device secrets and camera credentials must not be committed to Git.
- The Portainer initial admin password is stored root-only in `/etc/my-nvr/portainer-admin-password`.
- Use a firewall/VLAN policy appropriate to the deployment network.

## Supported baseline

This repository intentionally targets a narrow, reproducible baseline rather than every possible Linux/Docker combination. Broader hardware support should be introduced as tested compose overlays or release profiles.
