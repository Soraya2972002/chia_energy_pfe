#!/bin/bash
###############################################################################
# Script Name:       standard_chia_plotting.sh
# Description:       This script performs Chia plotting while simultaneously
#                    collecting monitoring data from multiple tools:
#                    - Scaphandre (for energy consumption)
#                    - CodeCarbon (CO₂ estimation, assumed to run separately)
#                    - iotop (disk I/O per process)
#                    - pidstat (per-process I/O statistics)
#                    - /proc/diskstats (global disk reads/writes)
#
#                    It automatically installs missing dependencies, ensures
#                    required monitoring services are running during the plot,
#                    and logs detailed output for post-processing.
#
# Author:            Soraya Djerrab
# Date:              July 2025
# Institution:       INSA Lyon / ESTIN Béjaïa
#
# Usage:             ./monitor_chia_full.sh
#
# Requirements:
#   - Chia CLI installed and initialized
#   - Scaphandre built and available locally 
#   - Tools: sysstat (for pidstat), iotop, cargo, rustup
#   - sudo access to install and run services
#
# Logs:
#   - General script log:        script.log
#   - Disk stats log:            chia_io.log
#   - Energy log (Scaphandre):  scaphandre_report.json
#   - I/O logs (iotop):         iotop.log
#   - I/O stats (pidstat):      pidstat.log
#
# Notes:
#   - Adjust DISK_NAME.
#   - CodeCarbon is assumed to be added to the source code of chia plotting before running this script.
###############################################################################



DISK_NAME=""

# Log files
LOG_FILE="chia_io.log"
SCAPHANDRE_LOG="scaphandre_report.json"
SCRIPT_LOG="script.log"
IOTOP_LOG="iotop.log"
PIDSTAT_LOG="pidstat.log"

# Redirect all output to the log file
exec > "$SCRIPT_LOG" 2>&1

# Clear previous logs
> "$LOG_FILE"
> "$SCAPHANDRE_LOG"
> "$CODECARBON_LOG"
> "$IOTOP_LOG"
> "$SCRIPT_LOG"
> "$PIDSTAT_LOG"


# Clean temp directory
dir="/tmp/chia-temp"
[ -d "$dir" ] && rm -rf "$dir"/* || echo "Directory does not exist."

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
initial_stats=$(grep "$DISK_NAME" /proc/diskstats)
echo "Initial stats: $initial_stats" >> "$LOG_FILE"
initial_reads=$(echo "$initial_stats" | awk '{print $4}')
initial_writes=$(echo "$initial_stats" | awk '{print $8}')


# Start scaphandre
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting Scaphandre monitoring" >> "$LOG_FILE"
sudo-g5k scaphandre json -f  "$SCAPHANDRE_LOG" &
SCAPHANDRE_PID=$!

# Start plotting
PLOT_START_TIME=$(date +%s)
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting plotting" >> "$LOG_FILE"
chia plots create -k 32 -n 1 --override-k -d /tmp/chia-temp -t /tmp/chia-temp &
PLOT_PID=$!

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

# Main monitoring loop
while kill -0 "$PLOT_PID" 2>/dev/null; do
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
    
    sleep 30
done

# Final cleanup
PLOT_END_TIME=$(date +%s)
PLOT_DURATION=$((PLOT_END_TIME - PLOT_START_TIME))

[ -n "$IOTOP_PID" ] && kill -SIGINT "$IOTOP_PID" 2>/dev/null
[ -n "$SCAPHANDRE_PID" ] && sudo kill -SIGINT "$SCAPHANDRE_PID"

# Final disk stats
final_stats=$(grep "$DISK_NAME" /proc/diskstats)
echo "Final stats: $final_stats" >> "$LOG_FILE"
final_reads=$(echo "$final_stats" | awk '{print $4}')
final_writes=$(echo "$final_stats" | awk '{print $8}')

# Output summary
echo "----- Monitoring Summary -----"
echo "Duration: $(($PLOT_DURATION / 3600))h $((($PLOT_DURATION % 3600) / 60))m $(($PLOT_DURATION % 60))s"
echo "Total Reads: $((final_reads - initial_reads))"
echo "Total Writes: $((final_writes - initial_writes))"
kill $$
