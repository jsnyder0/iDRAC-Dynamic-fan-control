<div id="top"></div>

# Dell iDRAC Fan Controller

> Intelligent, gradual fan speed control for Dell PowerEdge servers — keeps your server quiet under light load while automatically scaling up as temperatures rise, and handing off to Dell's built-in protection when it matters most.

Unlike simple on/off fan controllers that jump between a fixed quiet speed and full Dell control, this controller scales fan speed **continuously** across a configurable temperature range. Three defined zones give you fine-grained control over noise, airflow, and thermal safety.

## Table of contents
<ol>
  <li><a href="#how-it-works">How it works</a></li>
  <li><a href="#container-console-log-example">Container console log example</a></li>
  <li><a href="#requirements">Requirements</a></li>
  <li><a href="#supported-architectures">Supported architectures</a></li>
  <li><a href="#download-docker-image">Download Docker image</a></li>
  <li><a href="#usage">Usage</a></li>
  <li><a href="#parameters">Parameters</a></li>
  <li><a href="#troubleshooting">Troubleshooting</a></li>
  <li><a href="#contributing">Contributing</a></li>
  <li><a href="#license">License</a></li>
</ol>

<!-- HOW IT WORKS -->
## How it works

### Three-zone fan control

Fan speed is determined by three zones based on CPU temperature:


| Zone | Condition | Behaviour |
|---|---|---|
| **Quiet** | `temp ≤ LOWER_THRESHOLD` | Fans held at `FAN_SPEED_MIN` |
| **Dynamic** | `LOWER_THRESHOLD < temp < UPPER_THRESHOLD` | Fan speed scales linearly between `FAN_SPEED_MIN` and `FAN_SPEED_MAX` |
| **Dell default** | `temp ≥ UPPER_THRESHOLD` | Dell's built-in dynamic control takes over for maximum cooling |

### Fan speed curve

The chart below uses the default threshold and speed values as an example:

```mermaid
xychart-beta
    title "Fan speed vs CPU temperature (example: lower=45°C, upper=75°C, min=5%, max=50%)"
    x-axis "CPU Temperature (°C)" [30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80]
    y-axis "Fan Speed (%)" 0 --> 100
    line [5, 5, 5, 5, 11, 18, 25, 33, 40, 50, 50]
```

> Above the upper threshold the chart shows `FAN_SPEED_MAX` but in practice Dell's dynamic control takes over and fans ramp freely beyond that point.

### State machine

```mermaid
stateDiagram-v2
    direction LR

    [*] --> Dell_Default

    Dell_Default : Dell Default\n(safety)
    Quiet : Quiet\n(FAN_SPEED_MIN)
    Dynamic : Dynamic\n(scaled FAN_SPEED_MIN → FAN_SPEED_MAX)

    Dell_Default --> Quiet : temp ≤ lower threshold
    Dell_Default --> Dynamic : lower < temp < upper

    Quiet --> Dynamic : temp > lower threshold
    Quiet --> Dell_Default : temp ≥ upper threshold

    Dynamic --> Quiet : temp ≤ lower threshold − hysteresis
    Dynamic --> Dell_Default : temp ≥ upper threshold
```

**Hysteresis:** when returning from Dynamic to Quiet, the temperature must drop 2°C *below* the lower threshold. This prevents rapid fan oscillation when the CPU hovers near the boundary.

### Main loop

```mermaid
flowchart TD
    A([Container start]) --> B{ENABLE_DELL_CONTROL\nON_STARTUP?}
    B -- true --> C[Apply Dell default\nfan control]
    B -- false --> D
    C --> D[Validate env vars\nDetect server model\nProbe sensors]
    D --> E[Read all sensors\nsdr list full]
    E --> F{IPMI\nsucceeded?}
    F -- no --> G[Increment failure\ncounter]
    G --> H{Failures ≥\nMAX_CONSECUTIVE?}
    H -- yes --> I([Apply Dell default\nand exit])
    H -- no --> E
    F -- yes --> J[Take max of all\nCPU temperatures]
    J --> K{Which\nzone?}
    K -- temp ≤ lower --> L[Apply FAN_SPEED_MIN]
    K -- between thresholds --> M[Calculate scaled speed\nlinear interpolation\nround up]
    M --> N[Apply scaled speed]
    K -- temp ≥ upper --> O[Apply Dell default\nfan control]
    L --> P[Print status row]
    N --> P
    O --> P
    P --> Q[Sleep CHECK_INTERVAL]
    Q --> E
```

<p align="right">(<a href="#top">back to top</a>)</p>

## Container console log example

![image](https://user-images.githubusercontent.com/37409593/216442212-d2ad7ff7-0d6f-443f-b8ac-c67b5f613b83.png)

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- REQUIREMENTS -->
## Requirements
### iDRAC version

This Docker container only works on Dell PowerEdge servers that support IPMI commands, i.e. < iDRAC 9 firmware 3.30.30.30.

### To access iDRAC over LAN (not needed in "local" mode) :

1. Log into your iDRAC web console

![001](https://user-images.githubusercontent.com/37409593/210168273-7d760e47-143e-4a6e-aca7-45b483024139.png)

2. In the left side menu, expand "iDRAC settings", click "Network" then click "IPMI Settings" link at the top of the web page.

![002](https://user-images.githubusercontent.com/37409593/210168249-994f29cc-ac9e-4667-84f7-07f6d9a87522.png)

3. Check the "Enable IPMI over LAN" checkbox then click "Apply" button.

![003](https://user-images.githubusercontent.com/37409593/210168248-a68982c4-9fe7-40e7-8b2c-b3f06fbfee62.png)

4. Test access to IPMI over LAN running the following commands :
```bash
apt -y install ipmitool
ipmitool -I lanplus \
  -H <iDRAC IP address> \
  -U <iDRAC username> \
  -P <iDRAC password> \
  sdr elist all
```

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- SUPPORTED ARCHITECTURES -->
## Supported architectures

This Docker container is currently built and available for the following CPU architectures :
- AMD64
- ARM64

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- DOWNLOAD DOCKER IMAGE -->
## Download Docker image

- [Docker Hub](https://hub.docker.com/r/jeffsnyder0/dell_idrac_fan_controller)
- [GitHub Containers Repository](https://github.com/jsnyder0/iDRAC-Dynamic-fan-control/pkgs/container/iDRAC-Dynamic-fan-control)

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- USAGE -->
## Usage

1. with local iDRAC:

```bash
docker run -d \
  --name Dell_iDRAC_fan_controller \
  --restart=unless-stopped \
  -e IDRAC_HOST=local \
  -e FAN_SPEED_MIN=5 \
  -e FAN_SPEED_MAX=50 \
  -e CPU_TEMPERATURE_LOWER_THRESHOLD=45 \
  -e CPU_TEMPERATURE_UPPER_THRESHOLD=75 \
  -e CHECK_INTERVAL=60 \
  --device=/dev/ipmi0:/dev/ipmi0:rw \
  jeffsnyder0/dell_idrac_fan_controller:latest
```

2. with LAN iDRAC:

```bash
docker run -d \
  --name Dell_iDRAC_fan_controller \
  --restart=unless-stopped \
  -e IDRAC_HOST=<iDRAC IP address> \
  -e IDRAC_USERNAME=<iDRAC username> \
  -e IDRAC_PASSWORD=<iDRAC password> \
  -e FAN_SPEED_MIN=5 \
  -e FAN_SPEED_MAX=50 \
  -e CPU_TEMPERATURE_LOWER_THRESHOLD=45 \
  -e CPU_TEMPERATURE_UPPER_THRESHOLD=75 \
  -e CHECK_INTERVAL=60 \
  jeffsnyder0/dell_idrac_fan_controller:latest
```

`docker-compose.yml` examples:

1. to use with local iDRAC:

```yml
version: '3.8'

services:
  Dell_iDRAC_fan_controller:
    image: jeffsnyder0/dell_idrac_fan_controller:latest
    container_name: Dell_iDRAC_fan_controller
    restart: unless-stopped
    environment:
      - IDRAC_HOST=local
      - FAN_SPEED_MIN=5
      - FAN_SPEED_MAX=50
      - CPU_TEMPERATURE_LOWER_THRESHOLD=45
      - CPU_TEMPERATURE_UPPER_THRESHOLD=75
      - CHECK_INTERVAL=60
    devices:
      - /dev/ipmi0:/dev/ipmi0:rw
```

2. to use with LAN iDRAC:

```yml
version: '3.8'

services:
  Dell_iDRAC_fan_controller:
    image: jeffsnyder0/dell_idrac_fan_controller:latest
    container_name: Dell_iDRAC_fan_controller
    restart: unless-stopped
    environment:
      - IDRAC_HOST=<iDRAC IP address>
      - IDRAC_USERNAME=<iDRAC username>
      - IDRAC_PASSWORD=<iDRAC password>
      - FAN_SPEED_MIN=5
      - FAN_SPEED_MAX=50
      - CPU_TEMPERATURE_LOWER_THRESHOLD=45
      - CPU_TEMPERATURE_UPPER_THRESHOLD=75
      - CHECK_INTERVAL=60
```

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- PARAMETERS -->
## Parameters

### Parameters

| Parameter | Required | Default | Description |
|---|---|---|---|
| `IDRAC_HOST` | Yes | `local` | `local` for direct IPMI access, or the iDRAC IP address for LAN access |
| `IDRAC_USERNAME` | LAN only | `root` | iDRAC username |
| `IDRAC_PASSWORD` | LAN only | `calvin` | iDRAC password |
| `FAN_SPEED_MIN` | Yes | `5` | Minimum fan speed (%) applied when CPU temp is at or below the lower threshold |
| `FAN_SPEED_MAX` | Yes | `50` | Maximum fan speed (%) before handing control back to Dell |
| `CPU_TEMPERATURE_LOWER_THRESHOLD` | Yes | `45` | Temperature (°C) at or below which minimum fan speed is applied |
| `CPU_TEMPERATURE_UPPER_THRESHOLD` | Yes | `75` | Temperature (°C) at or above which Dell default fan control is restored |
| `CHECK_INTERVAL` | Yes | `60` | Seconds between each sensor read and fan speed update |
| `ENABLE_DELL_CONTROL_ON_STARTUP` | No | `false` | If `true`, restores Dell default fan control before the first temperature read. Useful as an extra fail-safe on container restart. |
| `DISABLE_THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE` | No | `false` | Disable Dell's extra cooling response for non-Dell PCIe cards. Gen 13 and older only. |
| `KEEP_THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE_STATE_ON_EXIT` | No | `false` | If `false`, resets PCIe card cooling response to Dell default on exit. Gen 13 and older only. |

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- TROUBLESHOOTING -->
## Troubleshooting

If your server frequently switches back to Dell default fan control:
1. Check `Tcase` (case temperature) of your CPU on the Intel Ark website and set `CPU_TEMPERATURE_UPPER_THRESHOLD` to a slightly lower value than Tcase.
2. Raise `FAN_SPEED_MAX` to increase airflow in the dynamic range, which helps keep temps below the upper threshold.
3. Lower `CPU_TEMPERATURE_LOWER_THRESHOLD` to give a wider dynamic range for gradual fan speed scaling.
4. If neither adjustment helps, it may be time to replace your thermal paste.

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- CONTRIBUTING -->
## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement".
Don't forget to give the project a star! Thanks again!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

To test locally, use either :
```bash
docker build -t jeffsnyder0/dell_idrac_fan_controller:dev .
docker run -d ...
```
or run directly without Docker:
```bash
export IDRAC_HOST=<iDRAC IP address>
export IDRAC_USERNAME=<iDRAC username>
export IDRAC_PASSWORD=<iDRAC password>
export FAN_SPEED_MIN=5
export FAN_SPEED_MAX=50
export CPU_TEMPERATURE_LOWER_THRESHOLD=45
export CPU_TEMPERATURE_UPPER_THRESHOLD=75
export CHECK_INTERVAL=60
export ENABLE_DELL_CONTROL_ON_STARTUP=false
export DISABLE_THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE=false
export KEEP_THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE_STATE_ON_EXIT=false

chmod +x Dell_iDRAC_fan_controller.sh
./Dell_iDRAC_fan_controller.sh
```

To run the test suite (no iDRAC connection required):
```bash
bash tests/run_tests.sh
```

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- LICENSE -->
## License

Shield: [![CC BY-NC-SA 4.0][cc-by-nc-sa-shield]][cc-by-nc-sa]

This work is licensed under a
[Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License][cc-by-nc-sa]. The full license description can be read [here][link-to-license-file].

[![CC BY-NC-SA 4.0][cc-by-nc-sa-image]][cc-by-nc-sa]

[cc-by-nc-sa]: http://creativecommons.org/licenses/by-nc-sa/4.0/
[cc-by-nc-sa-image]: https://licensebuttons.net/l/by-nc-sa/4.0/88x31.png
[cc-by-nc-sa-shield]: https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg
[link-to-license-file]: ./LICENSE

<p align="right">(<a href="#top">back to top</a>)</p>
