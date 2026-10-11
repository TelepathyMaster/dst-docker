# 维护与发布

这份文档面向仓库维护者。开服、Mod 和存档操作请参阅 [中文用户指南](../README.zh-CN.md)（[English](../README.md)）。

## 从源码构建并开服

Docker Hub 镜像用户直接按 README 创建部署目录即可。仓库根目录的 `compose.yaml` 面向本地构建，默认使用 `dst:local`，Mod 下载列表挂载来源为 `examples/dedicated_server_mods_setup.lua`。

```bash
git clone https://github.com/TelepathyMaster/dst-docker.git
cd dst-docker
mkdir -p data/DoNotStarveTogether/Cluster_1
cp -a examples/cluster/. data/DoNotStarveTogether/Cluster_1/
```

按 README 填写 Token、房间信息、随机 `cluster_key`、世界生成和 Mod 配置。使用仓库 Compose 时，在 `examples/dedicated_server_mods_setup.lua` 中维护下载列表。准备好配置后启动：

```bash
sudo chown -R 1000:1000 data
sudo chmod 600 data/DoNotStarveTogether/Cluster_1/cluster_token.txt
docker compose up -d --build
docker compose logs -f
```

取得新版源码后，正常停服，再执行 `docker compose up -d --build` 重新构建并启动。存档和配置仍在 `data/` 中。

## 镜像与运行接口

基础镜像使用 `debian:trixie-slim`，固定 digest；升级基础镜像时需要同时验证 SteamCMD 的 32 位依赖与 DST 的 64 位运行依赖。镜像只提供安装工具及脚本，游戏和 Mod 在运行时下载，不随镜像分发。

| 命令 | 行为 |
| --- | --- |
| `start`（默认） | 单容器更新游戏和 Mod，再转为共享锁运行；Compose 使用独立 updater |
| `update` | 持独占锁，安装或更新游戏和共享 Mod，然后退出；需要集群配置和 Token |
| `update --validate` | 更新并校验安装文件 |
| `run` | 持共享锁，跳过游戏及 Mod 更新，运行已准备的安装 |

环境变量为 `CLUSTER_NAME=Cluster_1`、`SHARD=Master`，首版支持 `Master` 与 `Caves`。`/opt/dst` 保存游戏安装和 Mod 缓存，`/data` 保存集群配置、Token 和存档，`/config/dedicated_server_mods_setup.lua` 为可选的只读下载列表。

默认 UID/GID 为 `1000:1000`，支持指定用户运行，权限不足时报错。安装目录采用读写锁：updater 独占，两个运行分片共享；分片自身另持独占锁。更新失败留下标记，Mod 下载列表变化也会拒绝直接运行。Compose 仅 updater 可写游戏卷，分片只读挂载。运行时 HOME 是每进程的临时目录，Steam 运行文件不会写进共享安装。

Mod 统一使用 `-only_update_server_mods -ugc_directory /opt/dst/ugc_mods` 准备，分片使用 `-skip_update_server_mods` 和相同 UGC 目录。Klei 开发者对共享 Mod 的说明见[此帖](https://kleiforums.com/forums/topic/128054-questions-regarding-mod-management-post-qol/)；旧版 V1 Mod 文件仍位于共享 `mods/` 中。已发布 `1.0.0` 不支持此布局，必须使用当前源码构建的新镜像。

Tini 作为 PID 1。监督脚本在游戏阶段收到 TERM/INT 后，通过控制台发送 `c_shutdown()` 并关闭输入，等待游戏保存退出；超时才终止进程。更新阶段收到停止信号则终止更新进程组。验证关闭行为时需要同时检查保存日志、退出状态及重启后的世界恢复。

## GitHub Actions 与 Docker Hub

将此目录提交到 GitHub 的 `main` 分支。在 Docker Hub 创建公开仓库，在 GitHub 仓库 Actions 配置：

| 类型 | 名称 | 内容 |
| --- | --- | --- |
| Variable | `DOCKERHUB_USERNAME` | 具有推送权限的 Docker Hub 用户名 |
| Variable | `DOCKERHUB_REPOSITORY` | `namespace/repository` |
| Secret | `DOCKERHUB_TOKEN` | Docker Hub 访问令牌 |

PR、main 提交、手动触发只检查与构建，不访问发布凭据或推送。发布稳定标签：

```bash
git tag v1.0.0
git push origin v1.0.0
```

发布流程验证通过后生成 `1.0.0`、`sha-<完整commit>`，以及适用的 `latest`。`latest` 只随最高稳定版本前进；补发旧版本不会回退。预发布及非法 SemVer 标签不会发布。版本与 SHA 标签存在时拒绝覆盖，因此不同版本需有各自提交，修复用新版本发布。所有 Actions 固定完整 SHA，基础镜像固定 digest。

发布任务串行执行，并查询公开 Docker Hub 标签。如果标签查询失败则中止发布。请通过本工作流管理发布标签；外部手动推送不会受到该保护。Docker Hub 推送并非多标签原子事务，部分推送失败后应检查已创建标签，修复用新提交、新版本发布。

工作流采用 [Docker 官方 GitHub Actions 工具](https://docs.docker.com/build/ci/github-actions/manage-tags-labels/)。镜像配置路径依据 [Klei 命令行文档](https://support.klei.com/hc/en-us/articles/360029556192-Dedicated-Server-Command-Line-Options-Guide)，控制台关闭依据 [Klei 论坛说明](https://kleiforums.com/forums/topic/51535-stopping-dedicated-server-gracefully/)。

## 检查与发布前验收

本地检查需要 Bash、ShellCheck、ripgrep（`rg`）、Docker Engine 和 Docker Compose。CI 会显式安装 ShellCheck 和 ripgrep；测试脚本使用 `rg` 检查日志与配置。

```bash
for script in scripts/*.sh tests/*.sh; do bash -n "$script"; done
shellcheck -x scripts/*.sh tests/*.sh
tests/runtime.sh
tests/release.sh
docker compose config --quiet
docker build --platform linux/amd64 -t dst:local .
tests/docker.sh dst:local
```

替身测试覆盖安装与修复、失败标记、命令分流、锁冲突、进程组退出、存档请求、退出码及发布版本策略。Docker 测试通过真实 Tini 转发 TERM/INT，并检查 UID 1000 和自定义 UID 1234。CI 不使用真实 Token。

首次公开发布前仍需有效 Token 和客户端进行实机验收：Master/Caves 联通、进入洞穴、实际 Workshop Mod 下载启用、正常停服保存、容器重建后恢复世界，以及发布镜像拉取运行。

本项目的脚本及文档使用 MIT 许可证。DST、SteamCMD 和 Workshop Mod 遵循各自许可证。
