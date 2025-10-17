#!/usr/bin/env bash

set -euo pipefail

# === CONFIG ===
PEARSON_EXEC=./pearson
DATA_DIR=data
OUT_DIR=output
SIZES=(128 256 512 1024)

# run counts
CALLGRIND_RUNS=3
MASSIF_RUNS=3
NATIVE_RUNS=5

# sampling configuration for native runs
SAMPLE_INTERVAL=0.05   # seconds between samples while process runs (0.05 = 50 ms)
PIDSTAT_INTERVAL=0.1  

PERF_DIR=Performance
TIME_BIN=/usr/bin/time    # used in some places optionally if available
TIME_FORMAT="%e %U %S %P %M"

# verbosity: 0 = quiet (default), 1 = verbose (prints more to console)
VERBOSE=0

mkdir -p "${PERF_DIR}"

# helper prints
vprint() { if [ "${VERBOSE}" -eq 1 ]; then echo "$@"; fi; }
progress() { echo "$@"; }

# Dependency gentle check
for cmd in "${TIME_BIN}" valgrind callgrind_annotate ms_print ps awk getconf; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    vprint "WARN: '${cmd}' not found in PATH (some features may be limited)"
  fi
done

if [ ! -x "${PEARSON_EXEC}" ]; then
  echo "ERROR: executable ${PEARSON_EXEC} not found or not executable" >&2
  exit 1
fi

progress "Measurements starting (quiet). Results -> ${PERF_DIR}/"

# Determine clock ticks per second for /proc stat conversion
CLK_TCK=$(getconf CLK_TCK 2>/dev/null || echo 100)

for size in "${SIZES[@]}"; do
  perf_file="${PERF_DIR}/${size}_performance.txt"
  : > "${perf_file}"  # truncate summary

  progress "Measuring size=${size} ..."

  echo "========== Measuring size=${size} ==========" >> "${perf_file}"
  echo "Data: ${DATA_DIR}/${size}.data -> ${OUT_DIR}/output_${size}.txt" >> "${perf_file}"
  echo "" >> "${perf_file}"

  # 1) CALLGRIND runs
  callgrind_out="${PERF_DIR}/callgrind.${size}.out"
  callgrind_txt="${PERF_DIR}/callgrind.${size}.annotate.txt"
  rm -f "${callgrind_out}" "${callgrind_txt}" "${PERF_DIR}/callgrind.${size}.valgrind.log"

  for ((c=1; c<=CALLGRIND_RUNS; c++)); do
    tmp_out="${PERF_DIR}/callgrind.${size}.run${c}.out"
    vprint "Callgrind run ${c} -> ${tmp_out}"
    valgrind --tool=callgrind --callgrind-out-file="${tmp_out}" \
      "${PEARSON_EXEC}" "${DATA_DIR}/${size}.data" "${OUT_DIR}/output_${size}.txt" \
      >/dev/null 2> "${PERF_DIR}/callgrind.${size}.valgrind.log" || true
    mv -f "${tmp_out}" "${callgrind_out}" || true
  done

  if command -v callgrind_annotate >/dev/null 2>&1 && [ -f "${callgrind_out}" ]; then
    callgrind_annotate --auto=yes "${callgrind_out}" > "${callgrind_txt}" 2> "${PERF_DIR}/callgrind.${size}.annotate.log" || true
    echo "Callgrind top candidate functions (heuristic):" >> "${perf_file}"
    awk '/^[[:space:]]*[0-9]/ { print $0 }' "${callgrind_txt}" | head -n 10 | sed 's/^/    /' >> "${perf_file}" || true
  else
    echo "Callgrind output missing or callgrind_annotate not available." >> "${perf_file}"
  fi

  echo "" >> "${perf_file}"

  # 2) MASSIF runs (heap peak)
  massif_out="${PERF_DIR}/massif.${size}.out"
  massif_txt="${PERF_DIR}/massif.${size}.txt"
  rm -f "${massif_out}" "${massif_txt}" "${PERF_DIR}/massif.${size}.valgrind.log"

  for ((m=1; m<=MASSIF_RUNS; m++)); do
    tmp_massif="${PERF_DIR}/massif.${size}.run${m}.out"
    vprint "Massif run ${m} -> ${tmp_massif}"
    valgrind --tool=massif --massif-out-file="${tmp_massif}" \
      "${PEARSON_EXEC}" "${DATA_DIR}/${size}.data" "${OUT_DIR}/output_${size}.txt" \
      >/dev/null 2> "${PERF_DIR}/massif.${size}.valgrind.log" || true
    mv -f "${tmp_massif}" "${massif_out}" || true
  done

  peak_heap_bytes=0
  peak_heap_kb=0
  if [ -f "${massif_out}" ]; then
    if command -v ms_print >/dev/null 2>&1; then
      ms_print "${massif_out}" > "${massif_txt}" 2> "${PERF_DIR}/massif.${size}.ms_print.log" || true
    fi
    peak_heap_bytes=$(awk -F= '/mem_heap_B=/ { if($2+0>max) max=$2 } END{print (max+0)}' "${massif_out}" || echo 0)
    if [ "${peak_heap_bytes}" -gt 0 ]; then
      peak_heap_kb=$(( (peak_heap_bytes + 1023) / 1024 ))
    fi
    echo "Massif peak heap (bytes): ${peak_heap_bytes}" >> "${perf_file}"
    echo "Massif peak heap (KB): ${peak_heap_kb}" >> "${perf_file}"
  else
    echo "No massif output" >> "${perf_file}"
  fi

  echo "" >> "${perf_file}"


  # 3) sampling via ps + /proc/<pid>/stat
  total_wall=0; total_user=0; total_sys=0; total_maxrss=0
  total_avgcpu=0; global_maxcpu=0

  for ((n=1; n<=NATIVE_RUNS; n++)); do
    cpu_samples_sum=0
    cpu_samples_count=0
    run_max_cpu=0
    run_max_rss_kb=0
    last_utime_ticks=0
    last_stime_ticks=0

    # start program (stdout redirected to output file)
    "${PEARSON_EXEC}" "${DATA_DIR}/${size}.data" "${OUT_DIR}/output_${size}.txt" &
    prog_pid=$!
    start_ts=$(date +%s.%N)
    sleep 0.002

    # sample while process alive
    while kill -0 "${prog_pid}" 2>/dev/null; do
      # CPU% via ps (portable); remove commas
      cpu_now=$(ps -p "${prog_pid}" -o %cpu= 2>/dev/null | awk '{gsub(",","",$1); print ($1+0)}' || echo 0)
      # RSS via ps (KB)
      rss_now=$(ps -p "${prog_pid}" -o rss= 2>/dev/null | awk '{print ($1+0)}' || echo 0)

      # /proc/<pid>/stat utime (14) and stime (15)
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

    # fallback final rss if none sampled
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

  {
    echo "===== Final summary for size=${size} ====="
    echo "Execution time (avg over ${NATIVE_RUNS} native runs):"
    echo "  Avg_Wall_seconds: ${avg_wall}"
    echo "  Avg_User_seconds: ${avg_user}"
    echo "  Avg_Sys_seconds: ${avg_sys}"
    echo "Memory (massif & sampled):"
    echo "  Massif_peak_heap_bytes: ${peak_heap_bytes:-0}"
    echo "  Massif_peak_heap_kB: ${peak_heap_kb:-0}"
    echo "  Avg_MaxRSS_kB (sampled): ${avg_maxrss_kb}"
    echo "CPU utilization (sampling):"
    echo "  Avg_CPU_percent_from_sampling: ${avg_cpu_pct_from_samples}%"
    echo "  Max_CPU_percent_observed_from_sampling: ${global_maxcpu}%"
    echo ""
    echo "Callgrind outputs: ${callgrind_out}, ${callgrind_txt}"
    echo "Massif outputs: ${massif_out}, ${massif_txt}"
    echo "Native per-run logs are visible in ${PERF_DIR}/"
  } >> "${perf_file}"

  progress "Done size=${size}"
done

progress "All sizes measured. Check ${PERF_DIR}/ for summaries and raw outputs."

# End of script

