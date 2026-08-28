#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
SOURCE="$SCRIPT_DIR/record-source.m"
BINARY="/private/tmp/hal-record-source"
PID_FILE="/private/tmp/hal-record-source.pid"
LOG_FILE="/private/tmp/hal-record-source.log"

is_running() {
    [[ -f "$PID_FILE" ]] || return 1
    local pid
    pid="$(<"$PID_FILE")"
    kill -0 "$pid" 2>/dev/null
}

case "${1:-}" in
    start)
        if is_running; then
            echo "Recorder already running (PID $(<"$PID_FILE"))."
            exit 0
        fi
        xcrun clang -fobjc-arc "$SOURCE" \
            -framework AppKit -framework Carbon \
            -o "$BINARY"
        : > "$LOG_FILE"
        nohup "$BINARY" >> "$LOG_FILE" 2>&1 &
        echo $! > "$PID_FILE"
        echo "Recorder started. Log: $LOG_FILE"
        ;;
    stop)
        if ! is_running; then
            echo "Recorder is not running. Log: $LOG_FILE"
            rm -f "$PID_FILE"
            exit 0
        fi
        pid="$(<"$PID_FILE")"
        kill -TERM "$pid"
        for _ in {1..20}; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.05
        done
        rm -f "$PID_FILE"
        echo "Recorder stopped. Log: $LOG_FILE"
        tail -n 5 "$LOG_FILE"
        ;;
    status)
        if is_running; then
            echo "Recorder running (PID $(<"$PID_FILE")). Log: $LOG_FILE"
        else
            echo "Recorder stopped. Log: $LOG_FILE"
        fi
        ;;
    show)
        if [[ -f "$LOG_FILE" ]]; then
            cat "$LOG_FILE"
        else
            echo "No recording yet."
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|status|show}" >&2
        exit 2
        ;;
esac
