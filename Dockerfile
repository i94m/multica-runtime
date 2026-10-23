ARG BASE_IMAGE=docker.m.daocloud.io/library/debian:13-slim

FROM ${BASE_IMAGE} AS tools

ARG DEBIAN_FRONTEND=noninteractive
ARG BUILDARCH
ARG TARGETARCH

ARG NODE_VERSION=24.21.0
ARG UV_VERSION=0.13.5
ARG MULTICA_VERSION=0.7.0
ARG OPENCODE_VERSION=2.1.3
ARG MYSQL_MCP_VERSION=2.0.9

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Build/download tools only; this stage is not shipped as the final image.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        xz-utils; \
    rm -rf /var/lib/apt/lists/*

# Node.js 24, arch-aware for docker buildx and plain docker build.
RUN set -eux; \
    ARCH="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "${ARCH}" in \
      amd64) NODE_ARCH=x64 ;; \
      arm64) NODE_ARCH=arm64 ;; \
      *) echo "unsupported arch: ${ARCH}" >&2; exit 1 ;; \
    esac; \
    curl --connect-timeout 15 --retry 3 --retry-delay 5 --retry-all-errors -fSL \
      "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" \
      -o /tmp/node.tar.xz; \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --no-same-owner; \
    rm -f /tmp/node.tar.xz; \
    rm -rf /usr/local/include/node /usr/local/share/doc /usr/local/share/man \
           /usr/local/CHANGELOG.md /usr/local/LICENSE; \
    corepack enable; \
    if [ "${BUILDARCH:-${ARCH}}" = "${ARCH}" ]; then \
      node -v; \
      npm -v; \
    else \
      test -x /usr/local/bin/node; \
      test -x /usr/local/bin/npm; \
    fi

# uv and uvx for Python project workflows.
RUN set -eux; \
    if [ "${UV_VERSION}" = "latest" ]; then \
      UV_INSTALL_URL="https://astral.sh/uv/install.sh"; \
    else \
      UV_INSTALL_URL="https://astral.sh/uv/${UV_VERSION}/install.sh"; \
    fi; \
    curl --connect-timeout 15 --retry 3 --retry-delay 5 --retry-all-errors -fSL \
      "${UV_INSTALL_URL}" -o /tmp/uv-install.sh; \
    UV_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh /tmp/uv-install.sh; \
    rm -f /tmp/uv-install.sh; \
    ARCH="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    if [ "${BUILDARCH:-${ARCH}}" = "${ARCH}" ]; then \
      uv --version; \
      uvx --version; \
    else \
      test -x /usr/local/bin/uv; \
      test -x /usr/local/bin/uvx; \
    fi

# MySQL MCP is installed globally so opencode can run it without fetching it at runtime.
RUN --mount=type=cache,target=/root/.npm \
    set -eux; \
    npm install -g "@benborla29/mcp-server-mysql@${MYSQL_MCP_VERSION}"; \
    rm -f /usr/local/lib/node_modules/@benborla29/mcp-server-mysql/assets/*.gif; \
    find /usr/local/lib/node_modules -type f \
        \( -name '*.map' -o -name '*.md' -o -name '*.d.ts' \) -delete; \
    command -v mcp-server-mysql

# opencode v2. Its postinstall executes the target binary, which is fragile in
# multi-arch builds, so install with --ignore-scripts and wire the platform binary.
RUN --mount=type=cache,target=/root/.npm \
    set -eux; \
    ARCH="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "${ARCH}" in \
      amd64) OPENCODE_PLATFORM=linux-x64 ;; \
      arm64) OPENCODE_PLATFORM=linux-arm64 ;; \
      *) echo "unsupported arch: ${ARCH}" >&2; exit 1 ;; \
    esac; \
    npm install -g --ignore-scripts "@opencode/cli@${OPENCODE_VERSION}"; \
    CLI_DIR=/usr/local/lib/node_modules/@opencode/cli; \
    SRC="${CLI_DIR}/node_modules/@opencode/cli-${OPENCODE_PLATFORM}/bin/opencode"; \
    test -x "${SRC}"; \
    ln -f "${SRC}" "${CLI_DIR}/bin/opencode.exe" 2>/dev/null || \
        cp "${SRC}" "${CLI_DIR}/bin/opencode.exe"; \
    chmod 0755 "${CLI_DIR}/bin/opencode.exe"; \
    grep -q ELF "${CLI_DIR}/bin/opencode.exe"

# multica CLI pinned binary install.
RUN set -eux; \
    ARCH="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "${ARCH}" in \
      amd64) MULTICA_ARCH=amd64 ;; \
      arm64) MULTICA_ARCH=arm64 ;; \
      *) echo "unsupported arch: ${ARCH}" >&2; exit 1 ;; \
    esac; \
    for url in \
      "https://ghfast.top/https://github.com/multica-ai/multica/releases/download/v${MULTICA_VERSION}/multica-cli-${MULTICA_VERSION}-linux-${MULTICA_ARCH}.tar.gz" \
      "https://github.com/multica-ai/multica/releases/download/v${MULTICA_VERSION}/multica-cli-${MULTICA_VERSION}-linux-${MULTICA_ARCH}.tar.gz" \
    ; do \
      if curl --connect-timeout 15 --retry 3 --retry-delay 5 --retry-all-errors -fSL "${url}" -o /tmp/multica.tar.gz; then \
        break; \
      fi; \
      rm -f /tmp/multica.tar.gz; \
    done; \
    test -s /tmp/multica.tar.gz; \
    tar -xzf /tmp/multica.tar.gz -C /tmp multica; \
    install -m 0755 /tmp/multica /usr/local/bin/multica; \
    rm -f /tmp/multica.tar.gz /tmp/multica; \
    if [ "${BUILDARCH:-${ARCH}}" = "${ARCH}" ]; then \
      multica version || true; \
    else \
      test -x /usr/local/bin/multica; \
    fi

FROM ${BASE_IMAGE} AS runtime

LABEL author="rt.wadewang" \
      description="Debian 13 slim runtime with opencode, multica, Node.js/npm, Python, uv, and MySQL MCP."

ARG DEBIAN_FRONTEND=noninteractive
ARG BUILDARCH
ARG TARGETARCH

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    UV_LINK_MODE=copy

# Lightweight runtime and common agent/troubleshooting tools.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bash-completion \
        ca-certificates \
        curl \
        dnsutils \
        file \
        git \
        iproute2 \
        iputils-ping \
        jq \
        less \
        netcat-openbsd \
        openssl \
        openssh-client \
        procps \
        python-is-python3 \
        python3 \
        python3-pip \
        python3-venv \
        ripgrep \
        rsync \
        tini \
        unzip \
        vim-tiny \
        wget \
        xz-utils; \
    rm -rf /var/lib/apt/lists/*

COPY --from=tools /usr/local/ /usr/local/

# Verify shipped tools in the final image. In cross-platform buildx runs, avoid
# executing target-architecture binaries under QEMU; existence checks are enough
# and runtime verification should happen on a matching host.
RUN set -eux; \
    python --version; \
    python3 --version; \
    pip3 --version; \
    rg --version; \
    jq --version; \
    openssl version; \
    command -v mcp-server-mysql; \
    ARCH="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    if [ "${BUILDARCH:-${ARCH}}" = "${ARCH}" ]; then \
      node -v; \
      npm -v; \
      corepack --version; \
      uv --version; \
      uvx --version; \
      opencode --version; \
      multica version || true; \
    else \
      test -x /usr/local/bin/node; \
      test -x /usr/local/bin/npm; \
      test -x /usr/local/bin/corepack; \
      test -x /usr/local/bin/uv; \
      test -x /usr/local/bin/uvx; \
      test -x /usr/local/bin/opencode; \
      test -x /usr/local/bin/multica; \
    fi

COPY entrypoint.sh /usr/local/bin/multica-container-entrypoint
RUN chmod +x /usr/local/bin/multica-container-entrypoint; \
    mkdir -p \
      /workspace \
      /root/.multica \
      /root/.config/opencode \
      /root/.local/share/opencode \
      /root/multica_workspaces

WORKDIR /workspace

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/multica-container-entrypoint"]
CMD ["daemon"]
