# Operations

## Service ownership

- Docker: systemd
- Portainer: `portainer-compose.yml`
- Frigate: Portainer Git stack `my-nvr`
- Application source of truth: Git repository
- Per-device configuration: `/etc/my-nvr`
- Media: `/srv/frigate`

Do not edit a detached copy of `compose.yml` inside Portainer. A Git-backed Portainer stack should be changed in Git and then redeployed.

## Common checks

```bash
docker ps
docker logs --tail 100 frigate
docker logs --tail 100 portainer
sudo bash /opt/my-nvr/repo/scripts/diagnostics.sh
```

## Backup

```bash
sudo bash /opt/my-nvr/repo/scripts/backup.sh
```

Backups do not include recordings.

## Update

```bash
sudo bash /opt/my-nvr/repo/scripts/update.sh
```

The helper:

1. backs up device configuration and Portainer data,
2. fast-forwards the local repository,
3. authenticates to the local Portainer API,
4. asks Portainer to pull and redeploy the Git stack.

Automatic polling-based GitOps is intentionally disabled in the baseline release.

## Recovery

If Frigate configuration is invalid, Frigate 0.18 can enter safe mode so that configuration can be repaired from the UI.

If Portainer is unavailable, application data remains on the host. Do not delete `/etc/my-nvr`, `/srv/frigate`, or the `portainer_data` Docker volume during diagnosis.

## Ports

Do not expose Frigate port 5000 externally.

Portainer Edge tunnel port 8000 is also omitted because this appliance does not require Edge Agent connectivity in the baseline design.
