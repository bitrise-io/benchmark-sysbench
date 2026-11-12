#!/usr/bin/env bash
# CPU (all vCPUs + single thread), memory write, sequential disk write (port of Bitrise sysbench_suite).
set -eo pipefail
source "$(dirname "$0")/lib.sh"
LOGS="$BENCH_OUT/logs"; mkdir -p "$LOGS"
THREADS=$(sysctl -n hw.ncpu); echo "Using $THREADS threads (all vCPUs)"
echo "project,metric_key,machine_key,threads,run,value,unit" > "$BENCH_OUT/results.csv"
for m in cpu_all_threads cpu_single_thread memory_write fileio_seqwrite; do : > "$BENCH_OUT/$m.txt"; done
record() { # $1 metric, $2 label, $3 value, $4 unit
  if [ -z "$3" ]; then echo "❌ Could not parse $1 on $2"; exit 1; fi
  echo "$1: $3 $4"
  echo "${BENCHMARK_PROJECT},$1,${MACHINE_KEY},${THREADS},$2,$3,$4" >> "$BENCH_OUT/results.csv"
  if [ "$MEASURED" = 1 ]; then echo "$3" >> "$BENCH_OUT/$1.txt"; fi
}
WORK=$(mktemp -d "$RUNNER_TEMP/sb.XXXX"); cd "$WORK"
sysbench fileio prepare --file-total-size="$FILEIO_TOTAL_SIZE" > "$LOGS/fileio-prepare.log"
for i in $(seq 1 $(( WARMUP_RUNS + BENCHMARK_RUNS ))); do
  run_label "$i"; echo "=== $LABEL ==="
  sysbench cpu run --threads="$THREADS" --time="$CPU_SECONDS" --cpu-max-prime=20000 > "$LOGS/$LABEL-cpu_all.log"
  record cpu_all_threads "$LABEL" "$(awk '/events per second:/ {print $4}' "$LOGS/$LABEL-cpu_all.log")" events/s
  sysbench cpu run --threads=1 --time="$CPU_SECONDS" --cpu-max-prime=20000 > "$LOGS/$LABEL-cpu_single.log"
  record cpu_single_thread "$LABEL" "$(awk '/events per second:/ {print $4}' "$LOGS/$LABEL-cpu_single.log")" events/s
  sysbench memory run --threads="$THREADS" --time=600 --memory-oper=write --memory-total-size="$MEMORY_TOTAL_SIZE" --memory-block-size="$MEMORY_BLOCK_SIZE" --memory-scope=local > "$LOGS/$LABEL-memory.log"
  record memory_write "$LABEL" "$(sed -n -E 's/.*transferred \(([0-9.]+) MiB\/sec\).*/\1/p' "$LOGS/$LABEL-memory.log")" MiB/s
  sysbench fileio run --file-test-mode=seqwr --file-total-size="$FILEIO_TOTAL_SIZE" --threads="$THREADS" --time="$FILEIO_SECONDS" > "$LOGS/$LABEL-fileio.log"
  record fileio_seqwrite "$LABEL" "$(awk '/^ *write: IOPS=/ {print $3}' "$LOGS/$LABEL-fileio.log")" MiB/s
done
sysbench fileio cleanup --file-total-size="$FILEIO_TOTAL_SIZE" > /dev/null

cat > "$BENCH_OUT/summary.json" <<JSON
{
$(summary_common),
  "sysbench": "$(sysbench --version)",
  "sysbench_source": "${GITHUB_REPOSITORY}@${SYSBENCH_COMMIT:-unknown}",
  "threads": ${THREADS},
  "cpu_all_threads_events_per_sec": $(stats "$BENCH_OUT/cpu_all_threads.txt"),
  "cpu_single_thread_events_per_sec": $(stats "$BENCH_OUT/cpu_single_thread.txt"),
  "memory_write_mib_per_sec": $(stats "$BENCH_OUT/memory_write.txt"),
  "fileio_seqwrite_mib_per_sec": $(stats "$BENCH_OUT/fileio_seqwrite.txt")
}
JSON
(cd "$BENCH_OUT" && rm -f cpu_all_threads.txt cpu_single_thread.txt memory_write.txt fileio_seqwrite.txt)
finish
