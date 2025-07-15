#!/bin/bash
###############################################################################
# Script Name:       bladebit_cudaplot_plotting.sh
# Description:       This script runs BladeBit CUDA plotting for the Chia
#                    blockchain while monitoring system metrics including:
#                    - Energy consumption using Scaphandre
#                    - Disk I/O per process using iotop
#                    - Process-level disk usage using pidstat
#                    - Global disk stats from /proc/diskstats
#
#                    The script ensures all dependencies are installed and
#                    handles BladeBit and CMake installation if missing.
#
# Author:            Soraya Djerrab
# Date:              July 2025
# Institution:       INSA Lyon / ESTIN Béjaïa
#
# Usage:             ./bladebit_cudaplot_plotting.sh
#
# Requirements:
#   - a GPU with CUDA support
#   - sudo access
#   - Tools: scaphandre, iotop, pidstat, Rust toolchain, CMake ≥ 3.27
#   - Chia installed and pre-configured Chia keys (farmer/pool public keys) 
#
# Notes:
#   - Adapt disk name and directories (e.g. TMP_DIR, PLOT_DIR) to your setup
#   - BladeBit is assumed to be built locally in /tmp/bladebit-build/
#
# Logs:
#   - chia_io.log          → Disk stats and progress
#   - scaphandre_report.json → Energy report from Scaphandre
#   - pidstat.log          → Per-process I/O activity
#   - iotop.log            → Real-time disk I/O
#   - script.log           → All standard output from this script
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
TMP_DIR=""
PLOT_DIR=""
mkdir -p "$PLOT_DIR"
echo "TMP_DIR is $TMP_DIR"
# Install dependencies
sudo-g5k apt update
sudo-g5k apt install -y sysstat iotop unzip curl

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

# Install BladeBit
if ! command -v bladebit &>/dev/null; then
    echo "[INFO] BladeBit not found. Installing dependencies..."
    module load cuda/12.2
    sudo-g5k apt update
    sudo-g5k apt install -y build-essential cmake libgmp-dev libnuma-dev git
    
    echo "[INFO] Installing CMake 3.27.9..."
    cd /tmp
    # Remove existing CMake if present
    [ -d "cmake-3.27.9-linux-x86_64" ] && rm -rf cmake-3.27.9-linux-x86_64
    wget -q https://github.com/Kitware/CMake/releases/download/v3.27.9/cmake-3.27.9-linux-x86_64.tar.gz
    tar -xzf cmake-3.27.9-linux-x86_64.tar.gz
    export PATH="/tmp/cmake-3.27.9-linux-x86_64/bin:$PATH"
    
    echo "[INFO] Building BladeBit..."
    # Clean up any previous bladebit installation
    [ -d "/tmp/bladebit" ] && rm -rf /tmp/bladebit
    
    cd /tmp
    git clone https://github.com/Chia-Network/bladebit.git
    cd bladebit
    
    # Create build directory outside source tree
    mkdir -p ../bladebit-build
    cd ../bladebit-build
    
    /tmp/cmake-3.27.9-linux-x86_64/bin/cmake ../bladebit
    /tmp/cmake-3.27.9-linux-x86_64/bin/cmake --build . --target bladebit --config Release -j $(nproc)
    /tmp/cmake-3.27.9-linux-x86_64/bin/cmake --build . --target bladebit_cuda --config Release -j $(nproc)
    # Verify build
    if [ -f "bladebit" ]; then
        echo "[SUCCESS] BladeBit built successfully"
        # Install to system path
        sudo cp bladebit /usr/local/bin/
    else
        echo "[ERROR] Bladebit build failed!"
        exit 1
    fi
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

# Start BladeBit plotting
echo "[$(date)] Starting BladeBit plotting..." >> "$LOG_FILE"
START_TIME=$(date +%s)
sudo-g5k /tmp/bladebit-build/bladebit_cuda -f "$FARMER_KEY" -p "$POOL_KEY" -n 17 cudaplot "$PLOT_DIR" &
PLOT_PID=$!
echo "This is plot_pid $PLOT_PID"


# Monitor while plotting
while kill -0 "$PLOT_PID" 2>/dev/null; do
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
