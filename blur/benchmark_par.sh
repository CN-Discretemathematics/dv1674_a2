#!/bin/bash

# ==============================================================================
# Multi-threaded performance test script
# Use: ./benchmark_par.sh ./filename num_threads
# ==============================================================================

# --- config ---
NUM_RUNS=10
RADIUS=15
DATA_DIR="data"
OUTPUT_DIR="output"

# --- settings ---
if [ -z "$1" ] || [ ! -x "$1" ] || [ -z "$2" ]; then
    echo "Error: Please provide a valid executable file and thread count."
    echo "Usage: $0 ./executable num_threads"
    exit 1
fi
EXECUTABLE_TO_TEST=$1
NUM_THREADS=$2

# --- main logic ---
mkdir -p "$OUTPUT_DIR"

echo "Start testing [$EXECUTABLE_TO_TEST] with $NUM_THREADS threads"
echo "Test runs: $NUM_RUNS"
echo "======================================================================================================="
printf "%-15s | %-22s | %-45s | %-23s\n" "Image File" "Avg Elapsed Time (s)" "Avg Memory (Max Resident Set, KB)" "Avg CPU Utilization (%)"
echo "======================================================================================================="

for image_path in "$DATA_DIR"/*.ppm; do
    image_name=$(basename "$image_path")
    output_path="$OUTPUT_DIR/temp_${image_name}"

    total_elapsed_time=0.0
    total_mem_kb=0
    total_cpu_util=0

    printf "%-15s | running..." "$image_name"

    for (( i=1; i<=NUM_RUNS; i++ )); do
        # *** FIX 1: Changed "NUM_THREADS" to "$NUM_THREADS" ***
        # *** FIX 2: Use wall clock time instead of user time for parallel benchmarking ***
        time_output=$( { /usr/bin/time -v "$EXECUTABLE_TO_TEST" "$RADIUS" "$image_path" "$output_path" "$NUM_THREADS" > /dev/null; } 2>&1 )

        # Extract elapsed (wall clock) time - this is the correct metric for parallel performance
        # Format can be: "h:mm:ss.ss" or "m:ss.ss" or "s.ss"
        elapsed_raw=$(echo "$time_output" | grep 'Elapsed (wall clock) time' | awk '{print $8}')
        
        # Convert h:mm:ss or mm:ss to seconds
        if [[ "$elapsed_raw" =~ ^([0-9]+):([0-9]+):([0-9.]+)$ ]]; then
            # Format: h:mm:ss
            h=${BASH_REMATCH[1]}
            m=${BASH_REMATCH[2]}
            s=${BASH_REMATCH[3]}
            elapsed_time=$(echo "$h * 3600 + $m * 60 + $s" | bc)
        elif [[ "$elapsed_raw" =~ ^([0-9]+):([0-9.]+)$ ]]; then
            # Format: mm:ss
            m=${BASH_REMATCH[1]}
            s=${BASH_REMATCH[2]}
            elapsed_time=$(echo "$m * 60 + $s" | bc)
        else
            # Format: ss.ss (seconds only)
            elapsed_time="$elapsed_raw"
        fi
        
        mem_kb=$(echo "$time_output" | grep 'Maximum resident set size' | awk '{print $6}')
        cpu_util=$(echo "$time_output" | grep 'Percent of CPU' | awk '{print $7}' | sed 's/%//')

        # Defensive check
        if [[ -z "$elapsed_time" || -z "$mem_kb" || -z "$cpu_util" ]]; then
            echo -e "\nError: Failed to parse time output for $image_name (run $i)"
            echo "Debug output:"
            echo "$time_output" | head -20
            continue
        fi

        total_elapsed_time=$(echo "$total_elapsed_time + $elapsed_time" | bc)
        total_mem_kb=$((total_mem_kb + mem_kb))
        total_cpu_util=$((total_cpu_util + cpu_util))
    done

    avg_elapsed_time=$(echo "scale=4; $total_elapsed_time / $NUM_RUNS" | bc)
    avg_mem_kb=$(echo "scale=2; $total_mem_kb / $NUM_RUNS" | bc)
    avg_cpu_util=$(echo "scale=2; $total_cpu_util / $NUM_RUNS" | bc)

    printf "\r%-15s | %-22.4f | %-45.2f | %-23.2f\n" "$image_name" "$avg_elapsed_time" "$avg_mem_kb" "$avg_cpu_util"
done

rm -f "$OUTPUT_DIR"/temp_*.ppm
echo "======================================================================================================="
echo "Test completed"
echo ""
echo "Note: Elapsed time is wall clock time (actual runtime)."
