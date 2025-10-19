#!/usr/bin/env bash

set -euo pipefail

# === CONFIG ===
PEARSON_EXEC=./pearson_par 
DATA_DIR=data
OUT_DIR=output
SIZES=(128 256 512 1024)
THREADS=(1 2 4 8 16 32) 

# run counts
CALLGRIND_RUNS=0
MASSIF_RUNS=0
NATIVE_RUNS=5

SAMPLE_INTERVAL=0.05
PERF_DIR=Performance_Parallel
TIME_BIN=/usr/bin/time
TIME_FORMAT="%e %U %S %P %M"
VERBOSE=0

progress() {
echo "$@"
}

mkdir -p "${PERF_DIR}"

if [ ! -x "${PEARSON_EXEC}" ]; then
  echo "ERROR: Parallel executable ${PEARSON_EXEC} not found or not executable" >&2
  echo "Please ensure you have run 'make pearson_par' and the file exists." >&2
  exit 1
fi

progress "Parallel Measurements starting. Results -> ${PERF_DIR}/"
progress "Testing Threads: ${THREADS[*]}"

# Determine clock ticks per second for /proc stat conversion
CLK_TCK=$(getconf CLK_TCK 2>/dev/null || echo 100)

for size in "${SIZES[@]}"; do
    
    for num_threads in "${THREADS[@]}"; do

        perf_file="${PERF_DIR}/${size}_T${num_threads}_performance.txt"
        : > "${perf_file}"  # truncate summary

        progress "Measuring size=${size}, T=${num_threads} ..."

        echo "========== Measuring size=${size}, T=${num_threads} ==========" >> "${perf_file}"
        echo "Data: ${DATA_DIR}/${size}.data -> ${OUT_DIR}/output_${size}_T${num_threads}.txt" >> "${perf_file}"
        echo "Threads: ${num_threads}" >> "${perf_file}"
        echo "" >> "${perf_file}"

        if [ "${CALLGRIND_RUNS}" -gt 0 ] || [ "${MASSIF_RUNS}" -gt 0 ]; then
            echo "WARNING: Callgrind/Massif is disabled for parallel runs (NATIVE_RUNS only)." >> "${perf_file}"
            echo "" >> "${perf_file}"
        fi

        total_wall=0; total_user=0; total_sys=0; total_maxrss=0
        total_avgcpu=0; global_maxcpu=0

        for ((n=1; n<=NATIVE_RUNS; n++)); do
            cpu_samples_sum=0
            cpu_samples_count=0
            run_max_cpu=0
            run_max_rss_kb=0
            last_utime_ticks=0
            last_stime_ticks=0

            output_file="${OUT_DIR}/output_${size}_T${num_threads}.txt"
            
            "${PEARSON_EXEC}" "${DATA_DIR}/${size}.data" "${output_file}" "${num_threads}" &
            prog_pid=$!
            start_ts=$(date +%s.%N)
            sleep 0.002

            # sample while process alive
            while kill -0 "${prog_pid}" 2>/dev/null; do
                cpu_now=$(ps -p "${prog_pid}" -o %cpu= 2>/dev/null | awk '{gsub(",","",$1); print ($1+0)}' || echo 0)
                rss_now=$(ps -p "${prog_pid}" -o rss= 2>/dev/null | awk '{print ($1+0)}' || echo 0)

                if [ -r "/proc/${prog_pid}/stat" ]; then
                    statline=$(cat "/proc/${prog_pid}/stat" 2>/dev/null || true)
                    if [ -n "${statline}" ]; then
                        utime_ticks=$(echo "${statline}" | awk '{print $14}')
                        stime_ticks=$(echo "${statline}" | awk '{print $15}')
                        [ -n "${utime_ticks}" ] && last_utime_ticks=${utime_ticks}
                        [ -n "${stime_ticks}" ] && last_stime_ticks=${stime_ticks}
                    fi
                fi

                cpu_samples_sum=$(awk -v a="${cpu_samples_sum}" -v b="${cpu_now}" 'BEGIN{printf "%.6f", a+b}')
                cpu_samples_count=$((cpu_samples_count+1))
                run_max_cpu=$(awk -v a="${run_max_cpu}" -v b="${cpu_now}" 'BEGIN{print (b>a?b:a)}')
                run_max_rss_kb=$(( run_max_rss_kb > rss_now ? run_max_rss_kb : rss_now ))

                sleep "${SAMPLE_INTERVAL}"
            done

            end_ts=$(date +%s.%N)
            wall=$(awk -v a="${start_ts}" -v b="${end_ts}" 'BEGIN{printf "%.6f", b-a}')

            user_sec=$(awk -v t="${last_utime_ticks}" -v h="${CLK_TCK}" 'BEGIN{ if(h>0) printf "%.6f", t/h; else print "0"}')
            sys_sec=$(awk -v t="${last_stime_ticks}" -v h="${CLK_TCK}" 'BEGIN{ if(h>0) printf "%.6f", t/h; else print "0"}')

            if [ "${cpu_samples_count}" -gt 0 ]; then
                avg_cpu_for_run=$(awk -v s="${cpu_samples_sum}" -v c="${cpu_samples_count}" 'BEGIN{printf "%.6f", s/c}')
            else
                avg_cpu_for_run=0
            fi

            if [ "${run_max_rss_kb}" -eq 0 ]; then
                run_max_rss_kb=$(ps -p "${prog_pid}" -o rss= 2>/dev/null | awk '{print ($1+0)}' || echo 0)
            fi

            printf "  parsed run %d: Wall=%.6f User=%.6f Sys=%.6f AvgCPU=%.6f%% MaxCPU=%.6f%% MaxRSS=%dKB\n" \
              "${n}" "${wall}" "${user_sec}" "${sys_sec}" "${avg_cpu_for_run}" "${run_max_cpu}" "${run_max_rss_kb}" >> "${perf_file}"

            total_wall=$(awk -v a="${total_wall}" -v b="${wall}" 'BEGIN{printf "%.6f", a+b}')
            total_user=$(awk -v a="${total_user}" -v b="${user_sec}" 'BEGIN{printf "%.6f", a+b}')
            total_sys=$(awk -v a="${total_sys}" -v b="${sys_sec}" 'BEGIN{printf "%.6f", a+b}')
            total_maxrss=$(awk -v a="${total_maxrss}" -v b="${run_max_rss_kb}" 'BEGIN{printf "%.0f", a+b}')
            total_avgcpu=$(awk -v a="${total_avgcpu}" -v b="${avg_cpu_for_run}" 'BEGIN{printf "%.6f", a+b}')

            if (( $(echo "${run_max_cpu} > ${global_maxcpu}" | bc -l) )); then
                global_maxcpu=${run_max_cpu}
            fi

        done # native runs

        # compute averages
        avg_wall=$(awk -v t="${total_wall}" -v n="${NATIVE_RUNS}" 'BEGIN{printf "%.6f", t/n}')
        avg_user=$(awk -v t="${total_user}" -v n="${NATIVE_RUNS}" 'BEGIN{printf "%.6f", t/n}')
        avg_sys=$(awk -v t="${total_sys}" -v n="${NATIVE_RUNS}" 'BEGIN{printf "%.6f", t/n}')
        avg_maxrss_kb=$(awk -v t="${total_maxrss}" -v n="${NATIVE_RUNS}" 'BEGIN{printf "%.0f", t/n}')
        avg_cpu_pct_from_samples=$(awk -v t="${total_avgcpu}" -v n="${NATIVE_RUNS}" 'BEGIN{printf "%.6f", t/n}')

        # write final summary for this size
        {
            echo "===== Final summary for size=${size}, T=${num_threads} ====="
            echo "Execution time (avg over ${NATIVE_RUNS} native runs):"
            echo "  Avg_Wall_seconds: ${avg_wall}"
            echo "  Avg_User_seconds: ${avg_user}"
            echo "  Avg_Sys_seconds: ${avg_sys}"
            echo "Memory (sampled):"
            echo "  Avg_MaxRSS_kB (sampled): ${avg_maxrss_kb}"
            echo "CPU utilization (sampling):"
            echo "  Avg_CPU_percent_from_sampling: ${avg_cpu_pct_from_samples}%"
            echo "  Max_CPU_percent_observed_from_sampling: ${global_maxcpu}%"
        } >> "${perf_file}"

        progress "Done size=${size}, T=${num_threads}"
    done # threads
done # sizes

progress "All parallel measurements complete. Check ${PERF_DIR}/ for reports."
