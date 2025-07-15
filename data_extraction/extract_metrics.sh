#!/bin/bash
###############################################################################
# Script Name:       extract_metrics.sh
# Description:       This script extracts monitoring and energy metrics from
#                    previously recorded log files of Chia plotting/farming
#                    experiments. It supports data extraction from:
#                      - pidstat.log      → Per-process I/O activity
#                      - iotop.log        → Real-time disk usage (MB/s)
#                      - /proc/diskstats  → SSD wear and total writes
#                      - scaphandre.json  → Host-level and process-level energy
#                      - Kwollect JSON API → External wattmeter energy usage
#
# Author:            Soraya Djerrab
# Date:              July 2025
# Institution:       INSA Lyon / ESTIN Béjaïa
#
# Usage:             ./extract_metrics.sh
#
# Requirements:
#   - Log files from a completed Chia experiment (stored in LOG_DIR)
#   - Python 3 installed with `jq` for JSON processing
#   - Access to Grid5000 API for Kwollect wattmeter data (valid JOB_ID)
#   - Python helper scripts:
#       - scaphandre_host_extraction.py
#       - scaphandre_process_extraction.py
#       - disktats_extraction.py
#
# Important Notes:
#   - Set the correct disk name (e.g., DISK_NAME="sda") for diskstats parsing
#   - Kwollect requires valid job ID and start/end timestamps to function
#   - All extractions operate on completed logs
#
# Output:
#   - Printed summaries for total energy (Wh/kWh), write operations, and SSD writes
###############################################################################


# --------- Configurable Variables ---------
LOG_DIR="/path/to/logs"  # Modify this path
DISK_NAME=""           # Set your disk name (e.g., sda, nvme0n1)
SCAPHANDRE_LOG="$LOG_DIR/scaphandre.json"
KWOLLECT_JSON="$LOG_DIR/metrics_only_wattmeter.json"
IOTOP_LOG="$LOG_DIR/iotop.log"
PIDSTAT_LOG="$LOG_DIR/pidstat.log"
JOB_ID=""
START_TIME=""
END_TIME=""


# --------- Extract from PIDSTAT ---------
echo "[+] Extracting total write data from pidstat.log"
TB_WRITTEN_PIDSTAT=$(grep 'chia' "$PIDSTAT_LOG" | \
    awk '{sum += $6} END {printf "%.3f", sum/(1024 * 1024 * 1024)}')
echo "[PIDSTAT] Total written: $TB_WRITTEN_PIDSTAT TB"

# --------- Extract from IOTOP ---------
echo "[+] Extracting total write rate from iotop.log"
TB_WRITTEN_IOTOP=$(grep -i 'chia' "$IOTOP_LOG" | awk '
BEGIN { interval_seconds = 1 }
{ sum_mb_per_sec += $6 }
END {
    total_mb = sum_mb_per_sec * interval_seconds
    total_tb = total_mb / 1048576
    printf "%.3f", total_tb
}')
echo "[IOTOP] Total written: $TB_WRITTEN_IOTOP TB"

# --------- Extract from /proc/diskstats snapshots ---------
echo "[+] Extracting disk write deltas from diskstats"
python3 disktats_extraction.py

# --------- Extract from Scaphandre (host-level) ---------
echo "[+] Calculating host-level energy from scaphandre log"
cat $SCAPHANDRE_LOG | jq -c '.' > scaphandre_json
python3 disktats_extraction.py

# --------- Extract from Scaphandre (process-level) ---------
echo "[+] Calculating process-level energy for chia's process from scaphandre log"
cat $SCAPHANDRE_LOG | jq -c '.' > scaphandre_json
python3 scaphandre_process_extraction.py

# --------- Extract from Kwollect JSON wattmeter ---------
echo "[+] Extracting total energy from Kwollect wattmeter JSON"
curl 'https://api.grid5000.fr/stable/sites/lyon/metrics?job_id="$JOB_ID"start_time="$START_TIME"&end_time="$END_TIME"&metrics=wattmetre_power_watt'  > "$KWOLLECT_JSON"
grep 'wattmetre_power_watt' metrics_only_wattmeter.json | cut -d':' -f8 | cut -d',' -f1 > power_values.txt
python3 kwollect_extraction.py
