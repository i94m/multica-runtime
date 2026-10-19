#!/bin/bash
set -euo pipefail

enable_multica_autostart() {
  # The user requested the official autostart command. In containers it may not
  # be able to create a system service, so keep this idempotent and non-fatal;
  # the foreground daemon below is what keeps Docker PID 1 alive.
  if [ ! -f "${HOME}/.multica/config.json" ]; then
    echo "[entrypoint] multica autostart skipped: no ${HOME}/.multica/config.json"
    echo "[entrypoint] run setup first, for example:"
    echo "[entrypoint]   docker exec -it <container> multica setup self-host --server-url <url> --app-url <url>"
    return 1
  fi

  echo "[entrypoint] enabling multica daemon autostart"
  (cd / && multica daemon autostart enable) || \
    echo "[entrypoint] warning: multica daemon autostart enable failed; continuing with foreground daemon"
  return 0
}

stop_existing_multica_daemon() {
  # Runtime state is persisted across container recreates. If the previous
  # container left daemon state behind, `multica daemon start --foreground` may
  # fail with "already running or starting" and Docker will restart-loop. Stop is
  # intentionally best-effort: a clean first boot usually has nothing to stop.
  echo "[entrypoint] stopping any existing multica daemon state"
  (cd / && multica daemon stop) || \
    echo "[entrypoint] no existing multica daemon stopped; continuing"
}

case "${1:-daemon}" in
  daemon)
    if enable_multica_autostart; then
      stop_existing_multica_daemon
      echo "[entrypoint] starting multica daemon in foreground"
      cd /
      exec multica daemon start --foreground
    fi

    echo "[entrypoint] container is kept alive for initial configuration"
    exec sleep infinity
    ;;
  shell|bash)
    exec bash
    ;;
  *)
    exec "$@"
    ;;
esac
