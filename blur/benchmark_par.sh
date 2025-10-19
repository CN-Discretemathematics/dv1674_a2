#!/bin/bash

# ==============================================================================
# performance test script
# Use: ./benchmark.sh ./filename
# ==============================================================================

# --- config ---
NUM_RUNS=10
RADIUS=15
DATA_DIR="data"
OUTPUT_DIR="output"

# --- settings ---
if [ -z "$1" ] || [ ! -x "$1" ] || [ -z "$2" ]; then
    echo "Err: Please offer a validation file。"
    echo "Use: $0 ./your file"
    exit 1
fi
EXECUTABLE_TO_TEST=$1
NUM_THREADS=$2

# --- main logic ---
mkdir -p "$OUTPUT_DIR"

echo "start test on[$EXECUTABLE_TO_TEST]"
echo "test count : $NUM_RUNS"
echo "======================================================================================================="
printf "%-15s | %-22s | %-45s | %-23s\n" "image file" "avg user time (s)" "avg memory (maximum resident set size) (KB)" "avg CPU utilization (%)"
echo "======================================================================================================="

for image_path in "$DATA_DIR"/*.ppm; do
    image_name=$(basename "$image_path")
    output_path="$OUTPUT_DIR/temp_${image_name}"

    total_user_time=0.0
    total_mem_kb=0
    total_cpu_util=0

    printf "%-15s | running..." "$image_name"

    for (( i=1; i<=NUM_RUNS; i++ )); do
        time_output=$( { /usr/bin/time -v "$EXECUTABLE_TO_TEST" "$RADIUS" "$image_path" "$output_path" "NUM_THREADS" > /dev/null; } 2>&1 )

        user_time=$(echo "$time_output" | grep 'User time' | awk '{print $4}')
        mem_kb=$(echo "$time_output" | grep 'Maximum resident set size' | awk '{print $6}')
        # *** FIX IS HERE: Changed awk '{print $6}' to awk '{print $7}' ***
        cpu_util=$(echo "$time_output" | grep 'Percent of CPU' | awk '{print $7}' | sed 's/%//')

        # Defensive check in case parsing fails for some reason
        if [[ -z "$user_time" || -z "$mem_kb" || -z "$cpu_util" ]]; then
            echo -e "\nError parsing time output for $image_name. Skipping run."
            continue
        fi

        total_user_time=$(echo "$total_user_time + $user_time" | bc)
        total_mem_kb=$((total_mem_kb + mem_kb))
        total_cpu_util=$((total_cpu_util + cpu_util))
    done

    avg_user_time=$(echo "scale=4; $total_user_time / $NUM_RUNS" | bc)
    avg_mem_kb=$(echo "scale=2; $total_mem_kb / $NUM_RUNS" | bc)
    avg_cpu_util=$(echo "scale=2; $total_cpu_util / $NUM_RUNS" | bc)

    printf "\r%-15s | %-22.4f | %-45.2f | %-23.2f\n" "$image_name" "$avg_user_time" "$avg_mem_kb" "$avg_cpu_util"
done

rm -f "$OUTPUT_DIR"/temp_*.ppm
echo "======================================================================================================="
echo "test completed"
