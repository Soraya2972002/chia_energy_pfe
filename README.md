# Chia Energy PFE 🌱⚡

This repository contains the monitoring and data extraction scripts used for analyzing the **energy consumption** and **storage impact** of different Chia plotting and farming configurations. This project was conducted as part of my final-year engineering project at INSA Lyon and ESTIN Béjaïa, **Supervised by:** Mme Clementine Gritti.
Special thanks for the guidance and support throughout the project.
## Repository Structure
```
chia-energy-pfe/
├── data_extraction/
│ ├── disktats_extraction.py # Extract write stats from /proc/diskstats snapshots
│ ├── extract_metrics.sh # Main script to extract all monitoring metrics
│ ├── kwollect_extraction.py # Compute energy from Kwollect wattmeter JSON
│ ├── scaphandre_host_extraction.py # Calculate host-level energy usage from Scaphandre
│ └── scaphandre_process_extraction.py # Calculate Chia process energy from Scaphandre
│
├── farming/
│ └── farming_monitoring.sh # Full monitoring script for Chia farming over 8h
│
└── plotting/
├── bladebit_cudaplot_plotting.sh # CUDA-based plotting using Bladebit
├── bladebit_hybrid_plotting.sh # Hybrid (RAM + disk) plotting with Bladebit
├── bladebit_ramplot_plotting.sh # Full-RAM plotting with Bladebit
├── madmax_plotting.sh # Madmax fast disk plotting
└── standard_chia_plotting.sh # Standard Chia plotting (v2)
```
## 📊 Features

- Supports monitoring for:
  - Disk I/O (`iotop`, `pidstat`, `/proc/diskstats`)
  - Energy usage (via `Scaphandre`, `Kwollect`)
- Compatible with:
  - Chia CLI (standard plotting & farming)
  - Bladebit (RAMPlot, CUDAPlot, Hybrid)
  - Madmax plotter

## 🛠️ Requirements

- Linux system (Grid'5000 recommended)
- `iotop`, `pidstat` (sysstat), `jq`, `curl`
- [`Scaphandre`](https://github.com/hubblo-org/scaphandre)
- Python 3 (with `json` module)
- Access to Grid'5000 Wattmeter/Kwollect API

## ⌨️ Usage

### 1. Monitor Plotting

Choose your plotting method from the `plotting/` folder and run the corresponding `.sh` file.

Example:

```bash
bash plotting/bladebit_ramplot_plotting.sh
```
### 2. Monitor Farming
Run the farming monitoring script (runs for 8 hours by default):
``` bash farming/farming_monitoring.sh  ```

### 3. Extract Metrics
After an experiment, extract data using:

```  bash data_extraction/extract_metrics.sh ```

Make sure to configure: `LOG_DIR`, `DISK_NAME`, `JOB_ID`, `START_TIME`, `END_TIME`

## 📚 License

MIT — Free to use, modify, and distribute for research and educational purposes.

## 🎓 Author

- Soraya Djerrab
- Computer Engineering & Cybersecurity 
- INSA Lyon / ESTIN Béjaïa
- July 2025

