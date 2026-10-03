# Hardware profiles

The base `compose.yml` is hardware-neutral by design.

## Why

Frigate performs best on bare-metal Debian with direct access to acceleration devices, but device mappings are hardware-specific. A generic production image must not fail to start just because `/dev/dri`, Coral, Hailo or NVIDIA hardware is absent.

## Policy

Add tested hardware support as explicit compose overlays, for example:

```text
profiles/
├── intel-dri.compose.yml
├── coral-usb.compose.yml
├── hailo.compose.yml
└── nvidia.compose.yml
```

Each profile must document:

- supported hardware,
- required host drivers/packages,
- required `devices:` mappings,
- required Frigate detector configuration,
- validation command,
- rollback/removal procedure.

Do not enable privileged mode globally.

## Intel / AMD DRI example

A future validated overlay may add a render node such as:

```yaml
services:
  frigate:
    devices:
      - /dev/dri/renderD128:/dev/dri/renderD128
```

The exact device must be detected on the appliance; do not assume that `renderD128` exists.

## Validation

Useful host checks:

```bash
ls -l /dev/dri /dev/accel 2>/dev/null
lspci -nn
docker exec frigate ls -l /dev/dri 2>/dev/null
```
