# Agent Notes

## Scope
- This repo is a Docker image definition only; it does not contain an application workspace. The built container uses `/workspace` as an empty default workdir.
- Main files: `Dockerfile`, `entrypoint.sh`, `docker-compose.yml.example`, `opencode.example.json`, `README.md`.

## Build and run
- Releases are built by GitHub Actions in `.github/workflows/package.yml`, not by local packaging. It publishes `linux/amd64` and `linux/arm64` images to `ghcr.io/i94m/multica-runtime`.
- Local compose defaults to pulling `ghcr.io/i94m/multica-runtime:${MULTICA_VERSION:-0.6.3}`; run `cp .env.example .env`, `cp docker-compose.yml.example docker-compose.yml`, then `docker compose pull && docker compose up -d`.
- For Dockerfile debugging only, local builds can use `docker build --build-arg BASE_IMAGE=docker.m.daocloud.io/library/debian:13-slim -t ghcr.io/i94m/multica-runtime:dev .`.
- Base image and tool versions can be overridden with build args: `BASE_IMAGE`, `NODE_VERSION`, `UV_VERSION`, `MULTICA_VERSION`, `OPENCODE_VERSION`, `MYSQL_MCP_VERSION`.
- After first start, run Multica setup in the container, then restart the service and check daemon status:
  - `docker compose exec developer multica setup self-host --server-url <url> --app-url <url>`
  - `docker compose restart developer`
  - `docker compose exec developer multica daemon status`
- There is no in-repo test/lint/typecheck config; `docker build --check .` and `docker compose --env-file .env.example -f docker-compose.yml.example config` are the practical config checks.

## Runtime behavior and gotchas
- `entrypoint.sh` starts the daemon when it is not running (removing pid/lock files left behind by a previous container first) and then follows `/root/.multica/daemon.log` with `tail -F` to keep the container alive.
- `docker-compose.yml.example` persists runtime state in `./.multica`, `./multica-workspaces`, `./opencode-config`, and `./opencode-data`; these paths are ignored and should not be committed.
- Compose persists `/workspace` with the Docker named volume `workspace`, not a host `./workspace` bind mount. Playwright MCP writes output to host `./playwright-output/`, mounted at `/root/playwright-output`; the multica container mounts that path read-only. Playwright uses the browser bundled in its own image.
- `opencode.example.json` is a template for `/root/.config/opencode/opencode.json`; real values may contain DB credentials.
- The MySQL MCP template sets `ALLOW_INSERT_OPERATION`, `ALLOW_UPDATE_OPERATION`, and `ALLOW_DELETE_OPERATION` to `false`; preserve read-only defaults unless explicitly asked otherwise.

## Dockerfile maintenance
- Dockerfile is multi-stage: `tools` downloads/installs Node, uv, opencode, multica, and MySQL MCP; `runtime` installs OS runtime packages and copies `/usr/local` from `tools`.
- Version pins are Docker build args near the top of `Dockerfile`: base image `docker.m.daocloud.io/library/debian:13-slim`, Node `24.21.0`, uv `latest`, Multica `0.6.3`, OpenCode `2.0.32`, MySQL MCP `2.0.9`.
- The image supports `linux/amd64` and `linux/arm64`; buildx passes `TARGETARCH` and the Dockerfile maps it for Node, OpenCode, and Multica.
- Node is installed from upstream tarballs, npm is included, and `corepack enable` is run so pnpm/yarn shims are available.
- System Python is installed from Debian packages: `python-is-python3`, `python3`, `python3-pip`, and `python3-venv`.
- uv is installed with Astral's standalone installer into `/usr/local/bin` for managed Python/project workflows.
- Runtime is intentionally lightweight: it includes common agent/troubleshooting tools (`ripgrep`, `jq`, `openssl`, network tools, `rsync`, `vim-tiny`) but not native build dependencies such as `build-essential`, `python3-dev`, or `pkg-config`.
- OpenCode is installed with `npm install -g --ignore-scripts` and the platform binary is wired manually because the package postinstall is fragile in multi-arch builds.
- Multica download intentionally tries the `ghfast.top` GitHub mirror before the direct GitHub release URL.
