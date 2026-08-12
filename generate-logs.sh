#!/usr/bin/env bash
#
# Append log lines of the form "yyyy-mm-dd HH:MM:SS.mmm LOGLEVEL MSG" to
# ./logs/generated.log so you can watch Fluent Bit pick them up live.
#
# Usage:
#   ./generate-logs.sh            # emit one line per second forever (Ctrl-C to stop)
#   ./generate-logs.sh 20         # emit 20 lines then exit
#   ./generate-logs.sh 20 0.2     # 20 lines, one every 0.2 seconds
set -euo pipefail

count="${1:-0}"      # 0 means run forever
interval="${2:-1}"   # seconds between lines

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_file="${script_dir}/logs/generated.log"
mkdir -p "${script_dir}/logs"

levels=(INFO DEBUG WARN ERROR)
messages=(
    "Service started successfully"
    "Loaded configuration from /etc/app/config.yml"
    "Cache miss for key user:42, falling back to database"
    "Failed to connect to upstream service after 3 retries"
    "Recovered connection to upstream service"
    "Processed batch of 128 records in 42ms"
    "User admin logged in from 10.0.0.5"
)

emit_line() {
    # Millisecond-precision UTC timestamp to match the parser.
    local ts
    ts="$(date -u +'%Y-%m-%d %H:%M:%S.%3N')"
    local level="${levels[RANDOM % ${#levels[@]}]}"
    local msg="${messages[RANDOM % ${#messages[@]}]}"
    echo "${ts} ${level} ${msg}" >> "${log_file}"
}

echo "Appending to ${log_file} (Ctrl-C to stop)..."
i=0
while true; do
    emit_line
    i=$((i + 1))
    if [ "${count}" -ne 0 ] && [ "${i}" -ge "${count}" ]; then
        break
    fi
    sleep "${interval}"
done
echo "Wrote ${i} line(s)."
