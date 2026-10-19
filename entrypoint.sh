#!/bin/bash
set -euo pipefail

STATE_DIR="${HOME}/.multica"
LOG_FILE="${STATE_DIR}/daemon.log"
PID_FILE="${STATE_DIR}/daemon.pid"

daemon_running() {
  local pid
  [ -s "${PID_FILE}" ] || return 1
  pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
  [ -n "${pid}" ] || return 1
  kill -0 "${pid}" 2>/dev/null
}

case "${1:-daemon}" in
  daemon)
    mkdir -p "${STATE_DIR}" || true

    # State is persisted on a bind mount, so a pid/lock left by a previous
    # container makes multica think the daemon is still running.
    if ! daemon_running; then
      rm -f "${PID_FILE}" "${STATE_DIR}/daemon.lock" "${STATE_DIR}/daemon.port"
      multica daemon start || echo "[entrypoint] warning: multica daemon start failed"
    fi

    [ -e "${LOG_FILE}" ] || : > "${LOG_FILE}" 2>/dev/null || true
    exec tail -n 100 -F "${LOG_FILE}"
    ;;
  shell|bash)
    exec bash
    ;;
  *)
    exec "$@"
    ;;
esac
