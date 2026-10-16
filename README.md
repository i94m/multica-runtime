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

默认工作目录是 `/workspace`；使用 compose 时会挂载到宿主机 `./workspace`，避免容器重建后丢失工作文件。

容器启动时会在检测到 `/root/.multica/config.json` 后执行：

```bash
multica daemon autostart enable
```

随后以前台模式启动 daemon，让 Docker 可以管理容器生命周期：

```bash
multica daemon start --foreground
```

如果还没有执行过 `multica setup`，容器会保持运行，方便你进入容器完成初始化。

## 镜像发布

默认由 GitHub Actions 打包并推送多架构镜像到 GHCR：

```text
ghcr.io/i94m/multica-runtime:<MULTICA_VERSION>
ghcr.io/i94m/multica-runtime:latest
```

触发方式：

- push 到 `main`：使用 `Dockerfile` 中的 `ARG MULTICA_VERSION` 作为版本标签
- push tag `v*`，例如 `v0.6.2`：使用 tag 去掉 `v` 后的版本号
- 手动运行 workflow：可输入 `multica_version`

workflow 文件：`.github/workflows/package.yml`。

检查远端镜像架构：

```bash
MULTICA_VERSION=0.6.2
docker buildx imagetools inspect ghcr.io/i94m/multica-runtime:${MULTICA_VERSION}
```

## 本地调试构建（可选）

正常发布不需要本地打包。如需本地临时验证 Dockerfile，可通过 build args 覆盖工具版本，例如：

```bash
docker build \
  --build-arg BASE_IMAGE=docker.m.daocloud.io/library/debian:13-slim \
  --build-arg NODE_VERSION=24.21.0 \
  --build-arg UV_VERSION=latest \
  --build-arg MULTICA_VERSION=0.6.2 \
  --build-arg OPENCODE_VERSION=2.0.28 \
  --build-arg MYSQL_MCP_VERSION=2.0.9 \
  -t ghcr.io/i94m/multica-runtime:0.6.2 .
```

## 运行

```bash
cp docker-compose.yml.example docker-compose.yml
cp .env.example .env
export MULTICA_VERSION=0.6.2
docker compose pull
docker compose up -d
```

进入容器 shell：

```bash
docker exec -it multica-opencode-mysql-mcp bash
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
docker exec -it multica-opencode-mysql-mcp multica setup self-host \
  --server-url http://210.74.156.242:3456 \
  --app-url    http://210.74.156.242:3456
```

完成 setup 后重启容器，入口脚本会执行 `multica daemon autostart enable` 并启动 daemon：

```bash
docker restart multica-opencode-mysql-mcp
docker exec -it multica-opencode-mysql-mcp multica daemon status
```

## 配置 opencode 与 MySQL MCP

模型服务/API Key 仍建议通过 opencode 自己配置：

```bash
docker exec -it multica-opencode-mysql-mcp opencode
```

MySQL MCP 示例配置在 `opencode.example.json`。如需使用：

```bash
mkdir -p opencode-config
cp opencode.example.json opencode-config/opencode.json
```

然后编辑 `opencode-config/opencode.json` 中的 `MYSQL_HOST`、`MYSQL_USER`、`MYSQL_PASS`、`MYSQL_DB` 等连接参数。

> `opencode-config/opencode.json` 可能包含密钥，不要提交到仓库。

## 在容器中使用 SSH 拉取 Git 仓库

推荐挂载指定 SSH 密钥，而不是把私钥写进镜像。编辑 `docker-compose.yml`，取消注释并按需调整：

```yaml
      - ~/.ssh/id_ed25519:/root/.ssh/id_ed25519:ro
      - ~/.ssh/id_ed25519.pub:/root/.ssh/id_ed25519.pub:ro
      - ~/.ssh/known_hosts:/root/.ssh/known_hosts:ro
```

宿主机上确认权限：

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub ~/.ssh/known_hosts
```

重启并测试：

```bash
docker compose up -d
docker exec -it multica-opencode-mysql-mcp ssh -T git@github.com
```
