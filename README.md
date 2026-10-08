# DST Docker

饥荒联机版（Don't Starve Together）专用服务器镜像，仅支持 `linux/amd64`。同一镜像分别运行 Master/Caves；首次启动下载 Steam App `343050`，以后每次启动检查更新。游戏文件和 Mod 缓存不打包到公开镜像，保存在每个分片的独立 Volume 中。

## 快速开始

需要 Linux x86_64、Docker Engine 与 Docker Compose。两个安装目录需要预留约 10 GB 以上磁盘空间，另加存档和 Mod 空间。首次安装需要能够连接 Steam。

```bash
docker compose build
mkdir -p data/DoNotStarveTogether/Cluster_1
cp -a examples/cluster/. data/DoNotStarveTogether/Cluster_1/
```

编辑 `data/DoNotStarveTogether/Cluster_1/cluster.ini`，修改集群名称、密码和 `cluster_key`。通过 [Klei 账号页面](https://accounts.klei.com/) 获取服务器 Token，用编辑器写入该目录的 `cluster_token.txt`，文件只包含 Token；不要提交到 Git。

```bash
sudo chown -R 1000:1000 data
sudo chmod 600 data/DoNotStarveTogether/Cluster_1/cluster_token.txt
# 首次先完成两个分片的安装；不需要常驻 updater。
docker compose run --rm --no-deps master update
docker compose run --rm --no-deps caves update

master_build=$(docker compose run --rm --no-deps --entrypoint cat master /opt/dst/.build-id)
caves_build=$(docker compose run --rm --no-deps --entrypoint cat caves /opt/dst/.build-id)
test "$master_build" = "$caves_build"
# 仅在上面的比较成功后启动。
docker compose up -d
docker compose logs -f
```

Compose 通过 `master` 服务名连接分片；UDP `10999`、`11000` 分别用于地面和洞穴玩家连接，需要在主机防火墙及路由器放行。分片通信 UDP `10888` 仅在 Docker 网络内使用，不发布到主机。Steam 内部端口在两个容器中也各自不同。

运行已发布的镜像时，在 `.env` 设置 `DST_IMAGE=你的命名空间/镜像名:1.0.0`，然后执行 `docker compose pull` 和上述初始化步骤。启动时可使用 `docker compose up -d --no-build`。

## 命令与数据

| 命令 | 行为 |
| --- | --- |
| `start`（默认） | 检查配置，安装/更新游戏，启动分片 |
| `update` | 仅安装/更新游戏；首次安装或上次失败时执行 validate |
| `update --validate` | 强制校验并修复游戏文件 |
| `run` | 跳过 SteamCMD，启动已有完整安装；DST 仍自行更新 Mod |

公开配置变量只有 `CLUSTER_NAME`（默认 `Cluster_1`）和 `SHARD`（默认 `Master`，可选 `Caves`）。集群名只接受字母、数字、`_` 和 `-`。

| 容器路径 | 内容 |
| --- | --- |
| `/opt/dst` | 游戏安装、SteamCMD 可写副本与缓存、Mod、`.build-id` |
| `/data/DoNotStarveTogether/<cluster>` | `cluster.ini`、`cluster_token.txt`、分片配置与世界存档、游戏日志 |
| `/data/.locks` | 防止同一集群分片重复运行的锁 |
| `/config/dedicated_server_mods_setup.lua` | 可选只读 Mod 下载列表 |

默认用户 UID/GID 为 `1000:1000`。脚本不会提权或自动修改用户配置；缺文件、目录无写权限、安装被占用时会明确报错。命名 Volume 初始权限由镜像提供；宿主机 bind mount 必须自行准备所有权。

安装目录锁在容器更新和运行期间始终持有。共享集群目录中的分片锁阻止另一安装目录重复启动相同分片；锁依赖文件系统对 `flock` 的支持，推荐使用本地磁盘。

更新失败或中断会留下 `.update-incomplete`；`run` 不允许绕过它。再次运行 `update` 修复后才会解除标记。SteamCMD 首次使用空缓存时可能返回 `Missing configuration`；保留 Volume 并重新执行 `update`，不要删除标记后强行运行。如果持续失败，检查 Steam 连接及容器日志。

### 自定义 UID/GID

可使用 `docker run --user UID:GID`。Compose 可在 `compose.override.yaml` 中为两个服务设置 `user: "1234:1234"`。设置前停止服务，并准备所有权：

```bash
docker compose stop
sudo chown -R 1234:1234 data
# 以下一次性 root 命令只准备 Volume 权限，不运行 SteamCMD 或游戏。
docker compose run --rm --no-deps --user 0 --entrypoint chown master -R 1234:1234 /opt/dst
docker compose run --rm --no-deps --user 0 --entrypoint chown caves -R 1234:1234 /opt/dst
```

SteamCMD 的 HOME 位于游戏 Volume 内，因此自定义 UID 不需要写入镜像的系统目录。两个分片应使用相同 UID/GID 访问共享数据。

## Workshop Mod

在 `examples/dedicated_server_mods_setup.lua` 添加下载列表：

```lua
ServerModSetup("WORKSHOP_ID")
```

再分别编辑持久化目录中 Master 和 Caves 的 `modoverrides.lua`，启用需要的 Mod：

```lua
return {
    ["workshop-WORKSHOP_ID"] = {
        enabled = true,
        configuration_options = {},
    },
}
```

下载列表与启用配置是两个步骤。更新游戏后，脚本将挂载的 Lua 文件复制到游戏 `mods/`；由 DST 自身处理 Workshop 下载，不由脚本解析 Lua。未挂载列表时使用空列表；不会自动删除已下载的缓存。`modoverrides.lua` 决定哪些 Mod 实际启用。

Mod 在 DST 启动阶段更新；`update` 命令只更新服务端本体。首次 Mod 下载时间较长，参考日志等待。修改世界生成配置只影响新世界，不会自动重建现有世界。

## 更新与退出

```bash
docker compose stop
docker compose run --rm --no-deps master update
docker compose run --rm --no-deps caves update
# 使用快速开始中的命令比较两个 .build-id，确认相同后启动。
docker compose up -d
```

镜像版本升级先修改 `DST_IMAGE` 并拉取镜像，然后执行上述停服更新流程。版本标签固定镜像与脚本，不固定 Volume 中的游戏版本；切换旧镜像无法回滚游戏或存档。首次安装和更新可能恰逢 Steam 发布新版本，启动日志也会打印 Build ID；若两个分片不一致，停止后再次协调更新。

Tini 为 PID 1，监督进程接收 `SIGTERM`/`SIGINT`，向游戏控制台发送 `c_shutdown()`，等待保存退出。Compose 保留 120 秒；110 秒未退出时发送 TERM，5 秒后仍未退出则 KILL。退出码保留游戏返回值。更新阶段收到停止信号会终止 SteamCMD 进程组并保留不完整标记。

```bash
docker compose stop
# docker run 用户也应显式给予足够时间：
docker stop --time 120 CONTAINER
```

只有正常完成控制台关闭才能验收为优雅退出；超时强制退出不能保证最后一次保存。镜像不提供自动备份，维护前可自行备份 `data`。

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

## 验证

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
