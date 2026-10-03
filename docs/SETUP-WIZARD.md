# End-user setup wizard

This document defines the product-level first-run wizard. It is intentionally separate from Portainer and from Frigate's advanced administration UI.

## Goals

- finish setup without Linux knowledge,
- do not expose Docker or YAML to the end user,
- allow an appliance to be provisioned without a camera,
- validate storage and network before enabling recording,
- keep service/admin functions separate from normal use.

## Wizard flow

### 1. Welcome and system check

Show:

- appliance model/version,
- network status,
- available storage,
- detected acceleration hardware,
- Frigate service status.

Blocking errors: no writable storage, Docker/Frigate service failure.

### 2. Network and device name

Configure:

- hostname/device name,
- DHCP or static addressing,
- DNS and gateway,
- optional NTP/timezone review.

Do not require static IP.

### 3. Add camera — OPTIONAL

This step must have both:

- **Add camera**
- **Skip for now**

Skipping must not mark setup as incomplete.

Recommended implementation: open/delegate to Frigate 0.18 camera management wizard, because Frigate can probe ONVIF streams and generate its own validated camera configuration.

If skipped, the appliance remains on the disabled placeholder configuration and all core services stay healthy.

### 4. Storage

Show:

- recording path,
- filesystem,
- free/total capacity,
- estimated retention where calculable.

Default recording path: `/srv/frigate`.

### 5. Detection / acceleration

Only expose choices that were actually detected and validated.

Examples:

- CPU/OpenVINO,
- Intel GPU/NPU,
- Coral,
- Hailo,
- NVIDIA.

Do not write device mappings into the generic base compose file unless the target device exists.

### 6. Retention and recording policy

Present product-level presets such as:

- conservative,
- balanced,
- extended retention.

Translate those presets to Frigate configuration internally.

### 7. Administrator access

Normal end users should use Frigate/product UI.

Portainer is service/admin tooling and should be placed behind an explicit **Service mode** entry in the final product UI.

### 8. Summary

Show:

- network address,
- storage status,
- camera count,
- acceleration mode,
- Frigate status,
- software version.

Allow completion with camera count = 0.

## State

The product wizard should keep its own small state file, for example:

`/etc/my-nvr/setup-state.json`

It must not use a modified copy of `compose.yml` as state.

Suggested fields:

```json
{
  "schema": 1,
  "completed": true,
  "camera_step_skipped": true,
  "completed_at": "2026-10-03T20:00:00Z"
}
```

Do not store camera passwords in this state file.
