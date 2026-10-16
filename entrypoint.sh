#!/bin/bash
set -euo pipefail

enable_multica_autostart() {
  # The user requested the official autostart command. In containers it may not
  # be able to create a system service, so keep this idempotent and non-fatal;
  # the foreground daemon below is what keeps Docker PID 1 alive.
  if [ "${MULTICA_DAEMON_AUTOSTART:-1}" = "0" ]; then
    echo "[entrypoint] multica daemon autostart disabled by MULTICA_DAEMON_AUTOSTART=0"
    return 1
  fi

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

case "${1:-daemon}" in
  daemon)
    if enable_multica_autostart; then
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
