#!/bin/bash
###############################################################################
# Script Name:       madmax_plotting.sh
# Description:       This script performs Chia plotting using the MadMax plotter
#                    while simultaneously monitoring system performance and
#                    energy usage with the following tools:
#                    - Scaphandre: energy consumption (JSON format)
#                    - iotop: real-time disk I/O (per process)
#                    - pidstat: process-level I/O stats
#                    - /proc/diskstats: global disk read/write counters
#
# Author:            Soraya Djerrab
# Date:              July 2025
# Institution:       INSA Lyon / ESTIN Béjaïa
#
# Usage:             ./madmax_plotting.sh
#
# Requirements:
#   - Chia MadMax plotter compiled and available locally
#   - Grid5000 environment with sudo-g5k rights
#   - Tools: scaphandre, iotop, pidstat, curl, cmake, Rust
#   - Chia must be installed
#   - Farmer and pool public keys must be provided manually in the script
#
# Notes:
#   - This script installs missing dependencies (Rust, BladeBit, etc.)
#   - Adjust `TMP_DIR`, `PLOT_DIR`, and `DISK_NAME` to match your setup
#
# Output Logs:
#   - chia_io.log           → Disk stats and plotting events
#   - script.log            → Full script stdout/stderr
#   - scaphandre_report.json→ Energy data in JSON
#   - iotop.log             → Disk I/O per process
#   - pidstat.log           → Process-level disk I/O
###############################################################################


DISK_NAME=""
FARMER_KEY=""
POOL_KEY=""

# Log files
LOG_DIR=""
LOG_FILE="$LOG_DIR/chia_io.log"
SCAPHANDRE_LOG="$LOG_DIR/scaphandre_report.json"
CODECARBON_LOG="$LOG_DIR/codecarbon/emissions.csv"
SCRIPT_LOG="$LOG_DIR/script.log"
IOTOP_LOG="$LOG_DIR/iotop.log"
PIDSTAT_LOG="$LOG_DIR/pidstat.log"

exec > "$SCRIPT_LOG" 2>&1

# Clear previous logs
> "$LOG_FILE" && > "$SCAPHANDRE_LOG" && > "$CODECARBON_LOG" && > "$IOTOP_LOG" && > "$SCRIPT_LOG" && > "$PIDSTAT_LOG"

# Prepare directories
TMP_DIR="/tmp/chia_plot/"
PLOT_DIR="/tmp/chia_plot/"
mkdir -p "$PLOT_DIR"
echo "TMP_DIR is $TMP_DIR"
# Install dependencies
sudo-g5k apt update
sudo-g5k apt install -y sysstat iotop unzip curl
sudo-g5k apt install -y libsodium-dev cmake g++ git build-essential

# Install Rust and Scaphandre
if ! command -v cargo &>/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

if ! command -v scaphandre &>/dev/null; then
    cd "$LOG_DIR/../scaphandre"
    cargo build --release
    sudo-g5k cp target/release/scaphandre /usr/local/bin/scaphandre
    cd -
fi

# Record initial disk stats
initial_stats=$(grep '^ *8' /proc/diskstats)
initial_reads=$(echo "$initial_stats" | awk '{print $4}')
initial_writes=$(echo "$initial_stats" | awk '{print $8}')
echo "Initial stats: $initial_stats" >> "$LOG_FILE"

# Start monitoring tools
sudo-g5k scaphandre json -f "$SCAPHANDRE_LOG" &
SCAPHANDRE_PID=$!

pidstat -d 1 >> "$PIDSTAT_LOG" &
PIDSTAT_PID=$!

sudo-g5k iotop -o -b >> "$IOTOP_LOG" &
IOTOP_PID=$!

# Start MadMax plotting
echo "[$(date)] Starting madmax plotting..." >> "$LOG_FILE"
START_TIME=$(date +%s)
chia-plotter/build/chia_plot -f "$FARMER_KEY" -p "POOL_KEY" -k 32 -t "$PLOT_DIR" -2 "$PLOT_DIR" -d "$PLOT_DIR" -s "$PLOT_DIR" &
PLOT_PID=$!
echo "This is plot_pid $PLOT_PID"


# Monitor while plotting
while kill -0 "$PLOT_PID" 2>/dev/null; do
    #if grep -q "Completed Plot 1" "$SCRIPT_LOG"; then
        #echo "[INFO] 'Completed Plot 1' found in script.log. Killing BladeBit PID $PLOT_PID..."
        #kill "$PLOT_PID"
        #break
    #fi
    for pid in $SCAPHANDRE_PID $PIDSTAT_PID $IOTOP_PID; do
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "[WARNING] Monitoring PID $pid stopped." >> "$LOG_FILE"
        fi
    done
    sleep 5
done

# Stop monitors
[ -n "$SCAPHANDRE_PID" ] && sudo kill -SIGINT "$SCAPHANDRE_PID"
[ -n "$IOTOP_PID" ] && kill -SIGINT "$IOTOP_PID"
[ -n "$PIDSTAT_PID" ] && kill -SIGINT "$PIDSTAT_PID"

# Final stats
END_TIME=$(date +%s)
final_stats=$(grep '^ *8' /proc/diskstats)
final_reads=$(echo "$final_stats" | awk '{print $4}')
final_writes=$(echo "$final_stats" | awk '{print $8}')
echo "[$(date)] Final stats: $final_stats" >> "$LOG_FILE"

# Summary
DURATION=$((END_TIME - START_TIME))
echo "----- Monitoring Summary -----"
echo "Duration: $((DURATION / 3600))h $(((DURATION % 3600) / 60))m $((DURATION % 60))s"
echo "Total Reads: $((final_reads - initial_reads))"
echo "Total Writes: $((final_writes - initial_writes))"
kill $$
