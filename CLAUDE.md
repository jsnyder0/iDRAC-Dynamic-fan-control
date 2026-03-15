# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Dockerized Bash script that dynamically controls fan speeds on Dell PowerEdge servers via IPMI commands through iDRAC. It monitors CPU temperatures and switches between a user-defined static fan speed and Dell's default dynamic fan control profile based on configurable thresholds.

## Building and Running

**Build the Docker image locally:**
```bash
docker build -t jeffsnyder0/dell_idrac_fan_controller:dev .
```

**Run without Docker (for local testing):**
```bash
export IDRAC_HOST=<iDRAC IP or "local">
export IDRAC_USERNAME=<username>
export IDRAC_PASSWORD=<password>
export FAN_SPEED=<0-100>
export CPU_TEMPERATURE_THRESHOLD=<celsius>
export CHECK_INTERVAL=<seconds>
export DISABLE_THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE=false
export KEEP_THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE_STATE_ON_EXIT=false

chmod +x Dell_iDRAC_fan_controller.sh
./Dell_iDRAC_fan_controller.sh
```

**Run with LAN iDRAC:**
```bash
docker run -d \
  --name Dell_iDRAC_fan_controller \
  --restart=unless-stopped \
  -e IDRAC_HOST=<IP> \
  -e IDRAC_USERNAME=<username> \
  -e IDRAC_PASSWORD=<password> \
  -e FAN_SPEED=5 \
  -e CPU_TEMPERATURE_THRESHOLD=50 \
  -e CHECK_INTERVAL=60 \
  jeffsnyder0/dell_idrac_fan_controller:latest
```

**Run with local iDRAC** (requires `--device=/dev/ipmi0:/dev/ipmi0:rw`).

## Architecture

The project is split across three Bash files sourced together:

- **`constants.sh`** — Defines `TABLE_HEADER_PRINT_INTERVAL=10` (how often the table header reprints).
- **`functions.sh`** — All reusable functions: IPMI fan control commands, temperature retrieval and parsing, table formatting, error/warning helpers, and graceful exit handler.
- **`Dell_iDRAC_fan_controller.sh`** — Entry point. Sources the above two files, initializes state from env vars, detects server generation, probes for sensor presence, then runs the main monitoring loop.

### Key design decisions

- **Gen 14+ detection**: The script checks the server model string against `[RT][0-9][4-9]0` to set temperature sensor indices (`CPU1_TEMPERATURE_INDEX`, `CPU2_TEMPERATURE_INDEX`), since IPMI SDR output ordering differs between generations.
- **Third-party PCIe cooling response**: Only applicable to Gen 13 and older servers. The IPMI raw commands (`0x30 0xce ...`) toggle Dell's default cooling response for non-Dell PCIe cards.
- **Fan control mode**: IPMI raw `0x30 0x30 0x01 0x01` = Dell default dynamic; `0x30 0x30 0x01 0x00` + `0x30 0x30 0x02 0xff <speed>` = user static.
- **Graceful exit**: SIGINT/SIGQUIT/SIGTERM are trapped to restore Dell default fan control before container stops.
- **`healthcheck.sh`** — Runs `ipmitool sdr type temperature` to verify IPMI connectivity; used by Docker's `HEALTHCHECK`.

## CI/CD

The GitHub Actions workflow (`.github/workflows/build_and_publish_docker_image.yml`) triggers on version tags (`v[0-9]+.[0-9]+`) and publishes multi-arch images (AMD64 + ARM64) to both Docker Hub (`jeffsnyder0/dell_idrac_fan_controller`) and GitHub Container Registry (`ghcr.io/jsnyder0/iDRAC-Dynamic-fan-control`).

To release: push a tag matching `v[0-9]+.[0-9]+`.

## Constraints

- Only works with iDRAC versions that support IPMI commands (iDRAC < firmware 3.30.30.30 for iDRAC 9).
- Local mode requires the `/dev/ipmi0` (or `/dev/ipmi/0` or `/dev/ipmidev/0`) device to be exposed to the container.
