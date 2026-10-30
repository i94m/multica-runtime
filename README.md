# Debian 13 OpenCode + Multica + MySQL MCP 镜像

这个目录是一个全新的、独立的简单镜像定义。GitHub Actions 打包时使用官方 `debian:13-slim`；本地如需调试构建，可通过 `BASE_IMAGE` 覆盖。

Dockerfile 使用多阶段构建：`tools` 阶段负责下载/安装 Node.js、uv、opencode、multica 和 MySQL MCP，最终 `runtime` 阶段只保留运行所需工具与配置。

镜像只内置运行工具，不包含任何业务项目目录或代码：

- `multica` CLI
- `opencode` CLI
- Node.js / npm（并启用 corepack，便于使用 pnpm/yarn）
- Python / pip / venv
- `uv` / `uvx`
- MySQL MCP：`@benborla29/mcp-server-mysql`
- 常用排障/轻量开发工具：`rg`、`jq`、`git`、`ssh`、`curl`、`wget`、`openssl`、`ping`、`nslookup`、`nc`、`rsync`、`vim-tiny`

默认工作目录是 `/workspace`；使用 compose 时会挂载到 Docker named volume `workspace`，避免容器重建后丢失工作文件，同时不在宿主机目录下创建 `./workspace`。

`entrypoint.sh` 在 daemon 未运行时启动它（并清理上次容器残留的 pid/lock），然后跟随 `/root/.multica/daemon.log` 保持容器存活，`docker logs` 可直接看到 daemon 输出。

## 镜像发布

默认由 GitHub Actions 打包并推送多架构镜像到 GHCR：

```text
ghcr.io/i94m/multica-runtime:<MULTICA_VERSION>
ghcr.io/i94m/multica-runtime:latest
```

触发方式：

- push 到 `main`：使用 `Dockerfile` 中的 `ARG MULTICA_VERSION` 作为版本标签
- push tag `v*`，例如 `v0.7.2`：使用 tag 去掉 `v` 后的版本号
- 手动运行 workflow：可输入 `multica_version`

workflow 文件：`.github/workflows/package.yml`。

检查远端镜像架构：

```bash
MULTICA_VERSION=0.7.2
docker buildx imagetools inspect ghcr.io/i94m/multica-runtime:${MULTICA_VERSION}
```

## 本地调试构建（可选）

正常发布不需要本地打包。如需本地临时验证 Dockerfile，可通过 build args 覆盖工具版本，例如：

```bash
docker build \
  --build-arg BASE_IMAGE=docker.m.daocloud.io/library/debian:13-slim \
  --build-arg NODE_VERSION=24.21.0 \
  --build-arg UV_VERSION=0.13.6 \
  --build-arg MULTICA_VERSION=0.7.2 \
  --build-arg OPENCODE_VERSION=2.2.2 \
  --build-arg MYSQL_MCP_VERSION=2.0.9 \
  -t ghcr.io/i94m/multica-runtime:0.7.2 .
```

## 运行

```bash
cp docker-compose.yml.example docker-compose.yml
cp .env.example .env
export MULTICA_VERSION=0.7.2
docker compose pull
docker compose up -d
```

进入容器 shell：

```bash
docker compose exec multica bash
```

确认内置工具：

```bash
node -v
npm -v
corepack --version
python --version
python3 --version
pip3 --version
uv --version
uvx --version
rg --version
jq --version
openssl version
opencode --version
multica version
mcp-server-mysql --help
```

首次运行后配置 multica：

```bash
docker compose exec multica multica setup self-host \
  --server-url <server-url> \
  --app-url    <app-url>
```

完成 setup 后重启容器，然后确认 daemon 状态：

```bash
docker compose restart multica
docker compose exec multica multica daemon status
```

## 配置 opencode 与 MySQL MCP

`docker-compose.yml.example` 已经把 opencode 的配置和运行数据挂载到宿主机目录：

```yaml
- ./opencode-config:/root/.config/opencode
- ./opencode-data:/root/.local/share/opencode
```

因此通过 `opencode` 写入的模型服务、API Key、MCP 配置、本地状态等会持久化在 `./opencode-config` 和 `./opencode-data` 中。升级镜像、重建容器或重新 `docker compose up -d` 时，只要不删除这两个目录，opencode 配置就会保留。

如果你已经从旧版示例复制过 `docker-compose.yml`，请确认自己的文件中也包含上面两条挂载配置。

模型服务/API Key 仍建议通过 opencode 自己配置：

```bash
docker compose exec multica opencode
```

MySQL MCP 示例配置在 `opencode.example.json`。如需使用：

```bash
mkdir -p opencode-config
cp opencode.example.json opencode-config/opencode.json
```

然后编辑 `opencode-config/opencode.json` 中的 `MYSQL_HOST`、`MYSQL_USER`、`MYSQL_PASS`、`MYSQL_DB` 等连接参数。

> `opencode-config/` 和 `opencode-data/` 可能包含密钥、登录状态或其它敏感信息，不要提交到仓库。

## Playwright MCP 输出目录

`docker-compose.yml.example` 中的 Playwright MCP 服务会把截图、trace 等输出写入宿主机目录：

```text
./playwright-output/
```

该目录在 Playwright 容器内对应 `/root/playwright-output`；主容器把同一个宿主机目录只读挂载到相同路径，因此 opencode/Multica 可以读取但不能修改。

Playwright 使用镜像自带的 Chromium，不依赖宿主机浏览器。`--no-sandbox`、`--allow-unrestricted-file-access`、`--allowed-hosts '*'` 是为容器内调试放宽的选项，仅建议在内网或本地使用。

`./playwright-output/` 已加入 `.gitignore` / `.dockerignore`，不要提交到仓库。

## 在容器中使用 SSH 拉取 Git 仓库

推荐挂载项目内单独生成的 SSH 密钥，而不是把私钥写进镜像，也不需要复用宿主机 `~/.ssh`。先把公钥分别添加到 GitHub/Gitee，然后编辑 `docker-compose.yml`，取消注释并按需调整：

```yaml
      - ./ssh-keys/id_ed25519:/root/.ssh/id_ed25519:ro
      - ./ssh-keys/id_ed25519.pub:/root/.ssh/id_ed25519.pub:ro
      - ./ssh-keys/known_hosts:/root/.ssh/known_hosts:ro
      - ./gitconfig:/root/.gitconfig:ro
```

`gitconfig.example` 会把 HTTPS 仓库地址自动改写为 SSH 地址：

```ini
[url "git@gitee.com:"]
    insteadOf = https://gitee.com/

[url "git@github.com:"]
    insteadOf = https://github.com/
```

首次使用时复制一份本地配置：

```bash
cp gitconfig.example gitconfig
```

这样即使 Multica 后台任务拿到的是 `https://gitee.com/owner/repo.git`，容器内 Git 也会自动按 `git@gitee.com:owner/repo.git` 走 SSH key，避免非交互环境下出现 `could not read Username for 'https://gitee.com'`。

宿主机上确认权限，并生成 `known_hosts`：

```bash
chmod 700 ssh-keys
chmod 600 ssh-keys/id_ed25519
chmod 644 ssh-keys/id_ed25519.pub ssh-keys/known_hosts
ssh-keyscan github.com gitee.com >> ssh-keys/known_hosts
```

> `known_hosts` 文件必须先存在。如果宿主机上没有该文件，Docker 会把它创建成同名目录，ssh 会直接报错。

重启并测试 GitHub/Gitee SSH 连接：

```bash
docker compose up -d
docker compose exec multica ssh -T git@github.com
docker compose exec multica ssh -T git@gitee.com
docker compose exec multica git config --global --get-regexp '^url\.'
```

之后在容器内使用 SSH 地址拉取代码，例如：

```bash
git clone git@github.com:owner/repo.git
git clone git@gitee.com:owner/repo.git
```
