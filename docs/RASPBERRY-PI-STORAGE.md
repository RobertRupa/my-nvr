# Raspberry Pi: SD boot with root filesystem on NVMe

This document describes the recommended storage layout for Raspberry Pi systems where direct NVMe boot is unavailable or unreliable, but Linux can access the NVMe device after the firmware/kernel start from microSD.

The goal is to minimize writes to the microSD card while keeping the system easy to recover.

## Recommended layout

```text
Raspberry Pi
├── microSD
│   ├── partition 1 (FAT) -> /boot/firmware
│   └── partition 2 (ext4) -> recovery copy of the old root filesystem
│
├── NVMe
│   └── ext4 partition -> /
│
└── RAM
    ├── /tmp -> tmpfs
    └── zram -> primary swap
```

With this layout the Pi still starts firmware and the kernel from microSD, but almost all normal Linux I/O happens on NVMe.

This is preferable to keeping `/` on microSD and moving Docker, containerd, logs and application data individually.

## Why this protects the SD card

When `/` is on NVMe, the following high-write paths automatically move away from microSD:

- `/var/lib/docker`
- `/var/lib/containerd`
- `/var/log`
- `/var/cache`
- `/home`
- package installation/update writes
- application databases
- Ollama/model data if installed under the root filesystem
- Frigate/Portainer metadata stored under the root filesystem

The SD card is then used mainly for `/boot/firmware`, which changes only during kernel/firmware updates.

## Example tested layout

Example from a Raspberry Pi 5 test system:

```text
microSD:
  /dev/mmcblk0p1   512 MiB  vfat   /boot/firmware
  /dev/mmcblk0p2  59.1 GiB  ext4   old root filesystem

NVMe:
  /dev/nvme0n1p1   512 MiB  vfat   unused for this boot mode
  /dev/nvme0n1p2  57.1 GiB  ext4   new root filesystem

RAM:
  /tmp             tmpfs
  /dev/zram0       swap
```

Example identifiers from that machine:

```text
SD boot PARTUUID:  1a4c90c8-01
SD root PARTUUID:  1a4c90c8-02
NVMe root PARTUUID: 85e80cc5-02
```

**Do not copy these PARTUUID values to another machine. Always detect the actual identifiers with `lsblk` or `blkid`.**

## 1. Inspect the current system

Run:

```bash
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,UUID,PARTUUID,MOUNTPOINTS,MODEL
findmnt /
findmnt /boot/firmware
cat /etc/fstab
cat /boot/firmware/cmdline.txt
swapon --show
zramctl
```

The expected starting point is:

- current root filesystem on microSD,
- `/boot/firmware` on the SD FAT partition,
- NVMe visible as `/dev/nvme0n1`,
- an ext4 partition available for the future root filesystem.

## 2. Mount the NVMe root partition

Example:

```bash
sudo mkdir -p /mnt/nvme-root
sudo mount /dev/nvme0n1p2 /mnt/nvme-root
findmnt /mnt/nvme-root
```

Check that the destination really is the intended NVMe partition before copying data.

## 3. Copy the current root filesystem to NVMe

Stop or quiesce write-heavy applications first when practical, especially Docker and databases:

```bash
sudo systemctl stop docker 2>/dev/null || true
sudo systemctl stop containerd 2>/dev/null || true
```

Copy the root filesystem:

```bash
sudo rsync -aAXHvx --numeric-ids \
  --exclude='/dev/*' \
  --exclude='/proc/*' \
  --exclude='/sys/*' \
  --exclude='/tmp/*' \
  --exclude='/run/*' \
  --exclude='/mnt/*' \
  --exclude='/media/*' \
  --exclude='/lost+found' \
  --exclude='/boot/firmware/*' \
  / /mnt/nvme-root/
```

Run a second synchronization pass to catch files that changed during the first copy:

```bash
sudo rsync -aAXHvx --numeric-ids --delete \
  --exclude='/dev/*' \
  --exclude='/proc/*' \
  --exclude='/sys/*' \
  --exclude='/tmp/*' \
  --exclude='/run/*' \
  --exclude='/mnt/*' \
  --exclude='/media/*' \
  --exclude='/lost+found' \
  --exclude='/boot/firmware/*' \
  / /mnt/nvme-root/
```

## 4. Configure fstab inside the NVMe root

Back up the copied configuration:

```bash
sudo cp /mnt/nvme-root/etc/fstab /mnt/nvme-root/etc/fstab.pre-nvme
```

Determine the actual identifiers:

```bash
lsblk -o NAME,PARTUUID,UUID,FSTYPE,MOUNTPOINTS
```

Then edit:

```bash
sudo nano /mnt/nvme-root/etc/fstab
```

Recommended structure:

```fstab
proc                    /proc           proc    defaults          0 0
PARTUUID=<SD-BOOT>      /boot/firmware  vfat    defaults          0 2
PARTUUID=<NVME-ROOT>    /               ext4    defaults,noatime  0 1
```

For the example machine this would be:

```fstab
proc                    /proc           proc    defaults          0 0
PARTUUID=1a4c90c8-01    /boot/firmware  vfat    defaults          0 2
PARTUUID=85e80cc5-02    /               ext4    defaults,noatime  0 1
```

## 5. Point the SD boot configuration at the NVMe root

Back up the live SD boot command line:

```bash
sudo cp /boot/firmware/cmdline.txt /boot/firmware/cmdline.txt.pre-nvme
```

Inspect it:

```bash
cat /boot/firmware/cmdline.txt
```

Replace only the root PARTUUID, for example:

```text
root=PARTUUID=<OLD-SD-ROOT>
```

with:

```text
root=PARTUUID=<NVME-ROOT>
```

Keep `cmdline.txt` as a single line.

Ensure that `rootwait` is present. A typical command line contains:

```text
root=PARTUUID=<NVME-ROOT> rootfstype=ext4 fsck.repair=yes rootwait
```

The exact remaining console and platform parameters should be preserved from the existing installation.

## 6. Reboot

Before rebooting:

```bash
sync
sudo umount /mnt/nvme-root
sudo reboot
```

## 7. Verify after reboot

The most important checks are:

```bash
findmnt /
findmnt /boot/firmware
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,PARTUUID,MODEL
df -hT
```

Expected result:

```text
/               -> /dev/nvme0n1p2
/boot/firmware  -> /dev/mmcblk0p1
```

Also verify Docker and the NVR stack:

```bash
docker info | grep 'Docker Root Dir'
docker ps
sudo bash /opt/my-nvr/repo/scripts/diagnostics.sh
```

When `/` is on NVMe, Docker can remain at its default `/var/lib/docker`; it is already physically stored on NVMe.

## 8. Keep the old SD root as recovery storage

Do not immediately erase `/dev/mmcblk0p2`.

Keeping the previous root filesystem temporarily gives a simple rollback path.

After the system has been proven stable, that partition can be left unused as an emergency recovery root or repurposed deliberately.

## Rollback

If the NVMe-root setup does not boot:

1. mount/read the SD boot partition from another Linux system if needed,
2. open `cmdline.txt`,
3. restore the original SD root PARTUUID.

If the Pi still boots far enough to access the filesystem, restore the saved file:

```bash
sudo cp /boot/firmware/cmdline.txt.pre-nvme /boot/firmware/cmdline.txt
sync
sudo reboot
```

For the example test machine the rollback root would be:

```text
root=PARTUUID=1a4c90c8-02
```

## ZRAM and swap

If ZRAM is already active, keep it as the primary swap.

Check:

```bash
swapon --show
zramctl
```

Example:

```text
/dev/zram0  2G  priority 100
```

For an 8 GB Raspberry Pi, a 2 GB ZRAM device is a reasonable baseline.

A disk-backed swap file on NVMe is optional. It should be lower priority than ZRAM and is useful only if workload memory pressure requires it.

Avoid swap on microSD.

## /tmp in RAM

Check:

```bash
findmnt /tmp
```

Recommended result:

```text
/tmp  tmpfs
```

A 2 GB tmpfs is a reasonable baseline on an 8 GB Pi, provided application memory use is monitored.

## noatime

The root filesystem should use `noatime` to avoid needless access-time metadata writes:

```bash
findmnt /
```

Expected mount options include:

```text
rw,noatime
```

## NVMe TRIM

Enable the standard periodic TRIM timer:

```bash
sudo systemctl enable --now fstrim.timer
systemctl status fstrim.timer --no-pager
```

Test manually:

```bash
sudo fstrim -v /
```

Use manual TRIM only as a validation step; the weekly systemd timer is normally sufficient.

## Journald

When the root filesystem is on NVMe, persistent journald writes no longer wear the microSD card.

Check usage:

```bash
journalctl --disk-usage
```

Do not disable persistent logs solely to protect the SD card once rootfs is on NVMe. For a production NVR, retaining bounded logs is operationally useful.

If desired, cap journal size in `/etc/systemd/journald.conf`, for example:

```ini
[Journal]
SystemMaxUse=256M
RuntimeMaxUse=64M
```

Then restart journald:

```bash
sudo systemctl restart systemd-journald
```

## Docker logging

Docker's default `json-file` driver can grow without useful limits if applications are noisy.

For production appliances, use Docker's `local` logging driver or configure explicit rotation.

Example `/etc/docker/daemon.json`:

```json
{
  "log-driver": "local",
  "log-opts": {
    "max-size": "20m"
  }
}
```

Restart Docker after changing daemon configuration:

```bash
sudo systemctl restart docker
```

Validate:

```bash
docker info | grep 'Logging Driver'
```

## Final recommended state

```text
microSD
└── /boot/firmware

NVMe
└── /
    ├── /etc
    ├── /usr
    ├── /var
    │   ├── lib/docker
    │   ├── lib/containerd
    │   └── log
    ├── /home
    └── application data

RAM
├── /tmp
└── zram swap
```

This layout avoids maintaining multiple bind mounts for Docker, containerd, logs and application data while reducing microSD writes to a minimum.
