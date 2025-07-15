#!/bin/bash
###############################################################################
# Script Name:       farming_monitoring.sh
# Description:       This script starts the Chia farming process and monitors
#                    system resource usage and energy consumption over a fixed
#                    duration (default: 8 hours). It logs:
#                    - Disk I/O activity (iotop, pidstat, /proc/diskstats)
#                    - Energy usage (via Scaphandre)
#                    - Periodic farming summaries (chia farm summary)
#
# Author:            Soraya Djerrab
# Date:              July 2025
# Institution:       INSA Lyon / ESTIN Béjaïa
#
# Usage:             bash monitor_farming.sh
#
# Requirements:
#   - Chia CLI installed and initialized with plots/farmer keys
#   - Grid5000 node with sudo-g5k access
#   - Tools: iotop, pidstat (sysstat), Rust, Scaphandre
#
# Notes:
#   - Duration is currently hardcoded to 8 hours (modify FARM_DURATION_SECONDS)
#   - Farm summaries are appended to `farmsummary.log` every ~2 minutes
#   - The script ensures that all monitoring tools remain active during farming
#
# Output Logs:
#   - farm.log             → High-level farming logs and disk stats
#   - script.log           → Full stdout/stderr of the script
#   - scaphandre_report.json → Power consumption trace
#   - iotop.log            → Real-time disk I/O usage
#   - pidstat.log          → Per-process I/O monitoring
#   - farmsummary.log      → Periodic output of `chia farm summary`
###############################################################################



DISK_NAME=""

# Log files
LOG_FILE="farm.log"
SCAPHANDRE_LOG="scaphandre_report.json"
SCRIPT_LOG="script.log"
IOTOP_LOG="iotop.log"
PIDSTAT_LOG="pidstat.log"
FARM_SUMMARY="farmsummary.log"


# Redirect all output to the log file
exec > "$SCRIPT_LOG" 2>&1

# Clear previous logs
> "$LOG_FILE"
> "$SCAPHANDRE_LOG"
> "$IOTOP_LOG"
> "$SCRIPT_LOG"
> "$PIDSTAT_LOG"


# Install required tools
sudo-g5k apt update

# Check if sysstat is installed
if ! dpkg -l | grep -q sysstat; then
    echo "sysstat is not installed. Installing..."
    sudo-g5k apt install -y sysstat
fi

if ! dpkg -s iotop &>/dev/null; then
    sudo-g5k apt install -y iotop
fi

if ! command -v cargo &>/dev/null; then
    if ! command -v rustup &>/dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source $HOME/.cargo/env
    fi
fi

if ! command -v scaphandre &>/dev/null; then
    cd scaphandre
    cargo build --release
    sudo-g5k cp target/release/scaphandre /usr/local/bin/scaphandre
    cd -
fi

# Initial disk stats
initial_stats=$(grep '^ *8' /proc/diskstats)
echo "Initial stats: $initial_stats" >> "$LOG_FILE"
initial_reads=$(echo "$initial_stats" | awk '{print $4}')
initial_writes=$(echo "$initial_stats" | awk '{print $8}')


# Start scaphandre
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting Scaphandre monitoring" >> "$LOG_FILE"
sudo-g5k scaphandre json -f  "$SCAPHANDRE_LOG" &
SCAPHANDRE_PID=$!

# Start farming
FARM_START_TIME=$(date +%s)
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting farming" >> "$LOG_FILE"
#chia stop all
#chia init --fix-ssl-permissions
chia start farmer

#start pidstat
pidstat -d 1 >> "$PIDSTAT_LOG" &
PIDSTAT_PID=$!


IOTOP_PID=""

# Function to start iotop
start_iotop() {
    sudo-g5k iotop -o -b  >> "$IOTOP_LOG" &
    IOTOP_PID=$!
}

# Start initial iotop
start_iotop

# Monitor for 8 hours
FARM_DURATION_SECONDS=$((8*3600))
FARM_END_TIME=$((FARM_START_TIME + FARM_DURATION_SECONDS))
i=0
# Main monitoring loop
while [ "$(date +%s)" -lt "$FARM_END_TIME" ]; do
    # Check scaphandre
    if ! kill -0 "$SCAPHANDRE_PID" 2>/dev/null; then
        echo "[ERROR] Scaphandre stopped, restarting..." >> "$LOG_FILE"
        sudo-g5k scaphandre json -f "$SCAPHANDRE_LOG" &
        SCAPHANDRE_PID=$!
    fi
    # Check pidstat
    if ! ps -p $PIDSTAT_PID > /dev/null; then
        echo "[ERROR] pidstat is not running. Restarting..." >> "$LOG_FILE"
        pidstat -d 1 >> "$PIDSTAT_LOG" &
        PIDSTAT_PID=$!
    fi
    # Check iotop
    if [ -n "$IOTOP_PID" ] && ! kill -0 "$IOTOP_PID" 2>/dev/null; then
        echo "[ERROR] iotop stopped, restarting..." >> "$LOG_FILE"
        start_iotop
    fi
    i=$((i + 1))
    if [ "$i" -eq 4 ]; then 
       farm_summary=$(chia farm summary)
       echo "[$(date +'%Y-%m-%d %H:%M:%S')] $farm_summary" >> "$FARM_SUMMARY"
       i=0
    fi
    sleep 30
    
done

# Stop all monitoring
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Stopping farming and monitoring tools" >> "$LOG_FILE"
chia stop all
[ -n "$IOTOP_PID" ] && kill -SIGINT "$IOTOP_PID" 2>/dev/null
[ -n "$SCAPHANDRE_PID" ] && sudo kill -SIGINT "$SCAPHANDRE_PID"
[ -n "$PIDSTAT_PID" ] && kill "$PIDSTAT_PID" 2>/dev/null

# Final disk stats
final_stats=$(grep '^ *8' /proc/diskstats)
echo "Final stats: $final_stats" >> "$LOG_FILE"
final_reads=$(echo "$final_stats" | awk '{print $4}')
final_writes=$(echo "$final_stats" | awk '{print $8}')

# Output summary
FARM_END_ACTUAL=$(date +%s)
FARM_DURATION=$((FARM_END_ACTUAL - FARM_START_TIME))

echo "----- Monitoring Summary -----"
echo "Duration: $(($FARM_DURATION / 3600))h $((($FARM_DURATION % 3600) / 60))m $(($FARM_DURATION % 60))s"
echo "Total Reads: $((final_reads - initial_reads))"
echo "Total Writes: $((final_writes - initial_writes))"
kill $$
