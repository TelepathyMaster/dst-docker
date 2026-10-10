# DST Docker

[English](README.md)
用 Docker 运行饥荒联机版专用服务器，支持地面（Master）和洞穴（Caves）。可以从零生成新世界，也可以搬入已有存档继续玩。首次启动会下载游戏服务端，以后每次启动都会检查更新，无需另外运行一个更新容器。

需要 Linux x86_64（`linux/amd64`）、Docker Engine 和 Docker Compose。地面、洞穴各自保存一份游戏文件，请预留约 10 GB 以上空间，另加存档和 Mod 的空间。服务器需要能够连接 Steam 和 Klei。

- [第一次开服](#第一次开服)
- [配置 Mod](#配置-mod)
- [迁移已有存档](#迁移已有存档)
- [更新游戏和镜像](#更新游戏和镜像)
- [保存、备份和重新生成世界](#保存备份和重新生成世界)
- [常见问题](#常见问题)

## 第一次开服

### 1. 创建部署目录和 Compose 配置

创建一个目录存放 Compose、配置和存档。以下命令都在这个目录中执行：

```bash
mkdir dst-server
cd dst-server
```

新建 `.env`，填写要使用的 Docker Hub 镜像及标签：

```dotenv
DST_IMAGE=your-namespace/your-image:1.0.0
```

这里的地址是占位值，需替换为实际已发布的镜像和标签。然后新建 `compose.yml`：

```yaml
x-dst: &dst
  image: ${DST_IMAGE:?Set DST_IMAGE in .env}
  platform: linux/amd64
  restart: unless-stopped
  stop_grace_period: 120s
  networks: [dst]

services:
  master:
    <<: *dst
    environment:
      CLUSTER_NAME: Cluster_1
      SHARD: Master
    volumes:
      - master-game:/opt/dst
      - ./data:/data
      - ./config/dedicated_server_mods_setup.lua:/config/dedicated_server_mods_setup.lua:ro
    ports:
      - "10999:10999/udp"
  caves:
    <<: *dst
    environment:
      CLUSTER_NAME: Cluster_1
      SHARD: Caves
    volumes:
      - caves-game:/opt/dst
      - ./data:/data
      - ./config/dedicated_server_mods_setup.lua:/config/dedicated_server_mods_setup.lua:ro
    ports:
      - "11000:11000/udp"

volumes:
  master-game:
  caves-game:
networks:
  dst:
    driver: bridge
```

先按自己的部署环境检查这些配置项：

| 配置项 | 用途与修改方式 |
| --- | --- |
| `image` / `.env` 中的 `DST_IMAGE` | Docker Hub 镜像地址和标签；两个服务使用同一版本 |
| `CLUSTER_NAME` | `/data/DoNotStarveTogether/` 下的集群目录名；两个服务必须一致，默认 `Cluster_1` |
| `SHARD` | 对应集群中的分片目录，分别为 `Master` 和 `Caves` |
| `./data:/data` | 将本地配置、Token 和世界存档挂载到容器；两个服务共享同一目录 |
| `master-game:/opt/dst`、`caves-game:/opt/dst` | 各自保存游戏安装和 Mod 缓存，两个分片使用独立 Volume |
| `./config/dedicated_server_mods_setup.lua:…:ro` | 将本地 Mod 下载列表只读挂载到两个容器，启动前需创建该文件 |
| `ports` | `宿主机端口:容器端口/udp`；容器端口对应下文 `server.ini` 中的 `server_port` |
| `networks` | 让洞穴通过服务名 `master` 连接地面，对应 `cluster.ini` 的 `master_ip = master` |
| `stop_grace_period` | 正常关闭时等待保存的时间，保留 `120s` |
| `restart` | `unless-stopped` 会在异常退出后重启；手动停服后保持停止 |

下面按默认路径和端口继续。若修改了 `CLUSTER_NAME` 或 `./data` 的挂载来源，后面的文件路径也要对应调整。需要外网玩家加入时，在防火墙和路由器放行两个宿主机 UDP 端口；默认是 `10999` 和 `11000`。分片连接端口 `10888` 只在 Docker 网络内使用。

### 2. 准备世界配置和 Token

已有存档时，按[迁移已有存档](#迁移已有存档)放好整个集群，再回来执行“拉取镜像并启动”。新世界按下面的结构创建文件：

```bash
mkdir -p data/DoNotStarveTogether/Cluster_1/{Master,Caves} config
printf '%s\n' '-- No Workshop mods configured.' > config/dedicated_server_mods_setup.lua
```

```text
dst-server/
├── compose.yml
├── .env
├── config/
│   └── dedicated_server_mods_setup.lua
└── data/DoNotStarveTogether/Cluster_1/
    ├── cluster.ini
    ├── cluster_token.txt
    ├── Master/
    │   ├── server.ini
    │   ├── worldgenoverride.lua
    │   └── modoverrides.lua
    └── Caves/
        ├── server.ini
        ├── worldgenoverride.lua
        └── modoverrides.lua
```

在 `data/DoNotStarveTogether/Cluster_1/cluster.ini` 中填写：

```ini
[GAMEPLAY]
game_mode = survival
max_players = 6
pvp = false
pause_when_empty = true

[NETWORK]
cluster_name = My DST Server
cluster_description = Docker dedicated server
cluster_password =
cluster_intention = cooperative

[MISC]
console_enabled = true

[SHARD]
shard_enabled = true
bind_ip = 0.0.0.0
master_ip = master
master_port = 10888
cluster_key = CHANGE_ME_TO_A_SHARED_RANDOM_VALUE
```

修改房间名称 `cluster_name`、加入密码 `cluster_password` 和人数 `max_players`，将 `cluster_key` 换成自己生成的随机字符串。`cluster_password` 是玩家加入密码；`cluster_key` 是地面和洞穴的连接密钥。`game_mode = survival` 使用生存模式，全员死亡后会进入世界重置倒计时。

从 [Klei 账号页面](https://accounts.klei.com/) 获取专用服务器 Token，写入同目录的 `cluster_token.txt`。文件只包含 Token 本身，不加引号，也不要使用 Steam 密码代替。

在 `Master/server.ini` 中填写地面端口和分片身份：

```ini
[NETWORK]
server_port = 10999

[SHARD]
is_master = true
name = Master

[STEAM]
authentication_port = 8766
master_server_port = 27016
```

在 `Caves/server.ini` 中填写洞穴配置：

```ini
[NETWORK]
server_port = 11000

[SHARD]
is_master = false
name = Caves
id = 2

[STEAM]
authentication_port = 8767
master_server_port = 27017
```

在 `Master/worldgenoverride.lua` 中填写：

```lua
return {
    override_enabled = true,
    preset = "SURVIVAL_TOGETHER",
    overrides = {},
}
```

在 `Caves/worldgenoverride.lua` 中填写：

```lua
return {
    override_enabled = true,
    preset = "DST_CAVE",
    overrides = {},
}
```

默认不启用 Mod，在两个分片中各创建一个 `modoverrides.lua`，内容均为：

```lua
return {}
```

想调整地图大小、资源等选项，在**第一次启动之前**修改对应的 `worldgenoverride.lua`，也可以使用游戏导出的世界配置。格式可参考 [Klei 世界设置指南](https://kleiforums.com/forums/topic/67039-dedicated-server-world-overrides-guide/)。需要 Mod 时，按[配置 Mod](#配置-mod)填写下载列表和各分片的启用配置。

### 3. 拉取镜像并启动

容器默认以 UID/GID `1000:1000` 运行，先准备数据目录权限，再检查 Compose、拉取镜像并启动：

```bash
sudo chown -R 1000:1000 data
sudo chmod 600 data/DoNotStarveTogether/Cluster_1/cluster_token.txt
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose logs -f
```

首次启动会依次安装游戏、下载配置的 Mod、生成世界，再连接地面和洞穴，需要一些时间。日志中出现 `Secondary Caves(...) ready!`、`secondary shard LUA is now ready!`，表示两个分片已完成连接。按 `Ctrl+C` 只退出日志查看，服务器继续运行。玩家可在游戏中搜索 `cluster_name` 设置的房间名称加入。

没有世界存档时，DST 根据配置生成世界，写入 `Master/save/` 和 `Caves/save/`；以后启动继续加载这些存档。配置和 Token 需提前准备，空的数据目录不会自动生成完整开服配置。

## 配置 Mod

配置一个服务器 Mod，需要完成两件事：**告诉服务器下载什么，再告诉每个分片启用什么。** 只改其中一处并不完整。

### 1. 添加下载列表

从 Steam 创意工坊页面地址的 `id=` 后面取得数字 ID。例如地址中的 `id=123456789`，对应的 ID 就是 `123456789`。以下数字仅作示例，请替换为实际 Mod ID。

编辑部署目录中的 `config/dedicated_server_mods_setup.lua`，每个 Mod 写一行：

```lua
ServerModSetup("123456789")
ServerModSetup("987654321")
```

上面的 Compose 已经把这个文件挂载到两个容器，无需进入容器编辑游戏安装目录。游戏本体更新后，这份下载列表仍会重新应用。

### 2. 在分片中启用并设置选项

编辑 `data/DoNotStarveTogether/Cluster_1/Master/modoverrides.lua`：

```lua
return {
    ["workshop-123456789"] = {
        enabled = true,
        configuration_options = {},
    },
    ["workshop-987654321"] = {
        enabled = true,
        configuration_options = {},
    },
}
```

下载列表里使用纯数字字符串；这里的键要加上 `workshop-` 前缀。`configuration_options = {}` 表示使用 Mod 的默认选项，具体可填的选项名和值由 Mod 决定。

洞穴也需要相应配置：编辑 `Caves/modoverrides.lua`，启用需要在洞穴运行的 Mod。如果两个分片使用完全相同的设置，可以复制地面的配置：

```bash
cp data/DoNotStarveTogether/Cluster_1/Master/modoverrides.lua \
   data/DoNotStarveTogether/Cluster_1/Caves/modoverrides.lua
```

想保留在游戏界面中调好的 Mod 选项，直接复制原世界对应分片的 `modoverrides.lua` 即可，再把其中需要使用的 Workshop ID 补到下载列表。镜像不会自动从 `modoverrides.lua` 生成下载列表。客户端专用 Mod 由玩家自行安装，不需要加入服务器配置。

下载与启用的关系也可参考 [Klei Mod 配置指南](https://kleiforums.com/forums/topic/96433-dedicated-server-mod-setup-guide/)。

### 3. 重启使配置生效

```bash
docker compose stop
docker compose up -d
docker compose logs -f
```

Mod 会在 DST 启动阶段下载和检查更新，服务器运行期间不会自动重新加载。`update` 命令只更新游戏本体，不会提前完成 Mod 下载。

停用某个 Mod 时，将各相关分片中的 `enabled` 改为 `false`，并从下载列表中移除对应行，再重启。缓存文件可以保留，不会因此继续启用。移除会添加物品或生物的 Mod 前，先备份世界存档。

## 迁移已有存档

先停止原服务器，复制**整个集群目录**，包括 `cluster.ini`、Token、Master/Caves 配置和各自的 `save/`，不要只复制单个世界快照。建议保留原存档作为备份。

下面以已有的 `Cluster_3` 为例，将它作为本项目默认的 `Cluster_1` 使用。目录名称变了，里面的世界进度和玩家数据仍然来自原存档。

```bash
docker compose stop
mkdir -p data/DoNotStarveTogether
mkdir data/DoNotStarveTogether/Cluster_1 &&
  cp -a /path/to/Cluster_3/. data/DoNotStarveTogether/Cluster_1/
```

将 `/path/to/Cluster_3` 替换为实际路径。这里故意不覆盖已有的 `Cluster_1`：如果提示目录已存在，先备份并移走当前集群，再重新复制，避免把两个世界的存档混在一起。

复制后检查目录结构：

```text
data/DoNotStarveTogether/Cluster_1/
├── cluster.ini
├── cluster_token.txt
├── Master/
│   ├── server.ini
│   ├── modoverrides.lua
│   └── save/
└── Caves/
    ├── server.ini
    ├── modoverrides.lua
    └── save/
```

原有的 `leveldataoverride.lua`、`worldgenoverride.lua`、管理员名单等文件也应一并保留。不要再用新世界模板覆盖这些文件。

### 调整分片连接地址

原服务器如果在同一台机器上运行两个进程，可能使用 `127.0.0.1`。本项目将它们放在两个容器中，迁移后需要调整副本中的分片连接设置：

在 `cluster.ini` 中确认：

```ini
[SHARD]
shard_enabled = true
bind_ip = 0.0.0.0
master_ip = master
master_port = 10888
cluster_key = 你自己的分片连接密钥
```

保留原有 `cluster_key` 也可以。两个分片读取同一份 `cluster.ini`，密钥自然一致。

| 文件 | 需要确认的设置 |
| --- | --- |
| `Master/server.ini` | `[NETWORK]` 的 `server_port = 10999`；`[SHARD]` 的 `is_master = true` |
| `Caves/server.ini` | `[NETWORK]` 的 `server_port = 11000`；`[SHARD]` 的 `is_master = false` |

保留洞穴原有的分片 `id`。如果要使用 `Cluster_3` 这个目录名，可以不重命名，并将 Compose 中**两个服务**的 `CLUSTER_NAME` 都改为 `Cluster_3`；后续命令中的数据路径也对应替换。

### 恢复 Mod 并开服

保留原有 `modoverrides.lua`，按[配置 Mod](#配置-mod)补齐下载列表，并检查原有 Token 是否有效，然后执行前面的权限设置和启动命令。

启动日志应显示 `Loading world`，加载复制来的世界；不会因为换了容器而自动重建。迁移后先检查天数、角色和建筑，再让玩家继续游玩。

以上示例针对地面与洞穴都有存档的情况。只有地面存档时，先用 `docker compose up -d master` 启动地面；新增洞穴还需要准备洞穴配置，并确认原地面世界存在洞穴入口。

## 更新游戏和镜像

### 游戏本体如何更新

默认模式下，每次容器启动都会通过 SteamCMD 检查并更新游戏服务端。正在运行的服务器不会定时更新，也不会自动踢出玩家重启。

有游戏更新时，正常停服再启动即可：

```bash
docker compose stop
docker compose up -d
docker compose logs -f
```

只在服务器已经运行时再次执行 `docker compose up -d`，不会强制重启，也不会重新检查更新。

想先完成两个分片的游戏下载，再一起开服，可以在停服后单独更新：

```bash
docker compose stop
docker compose run --rm --no-deps master update
docker compose run --rm --no-deps caves update
docker compose up -d
```

更新会保留 `data` 中的存档和配置。若更新失败，服务器会停止启动，修复连接或安装问题后重新更新即可，不需要重建世界。更换游戏版本前建议备份存档。

### 更新 Docker Hub 镜像

升级镜像时，先停服，修改 `.env` 中的标签，再拉取并启动：

```bash
docker compose stop
docker compose pull
docker compose up -d --no-build
```

`latest` 跟随最新稳定镜像，`1.0.0` 这样的明确标签固定镜像和启动脚本版本。**游戏本体仍由 SteamCMD 独立更新**，固定镜像标签不等于固定游戏版本，换回旧镜像也不能回滚存档。

需要从源码构建镜像时，参阅[维护者文档](docs/maintainer.md)。

## 保存、备份和重新生成世界

使用下面的命令正常停服，服务器会请求保存并退出；Compose 已预留 120 秒供关闭使用：

```bash
docker compose stop
```

世界存档、Token 和配置都在宿主机的 `data/` 中。重建容器或执行 `docker compose down` 后，它们仍然保留。地面、洞穴的游戏文件和 Mod 缓存在两个 Docker 命名 Volume 中；`docker compose down -v` 会清掉这些缓存，下次启动需要重新下载，但不会删除挂载的宿主机 `data/`。

项目不提供自动备份。可以停服后打包整个 `data`，将备份放在部署目录外：

```bash
docker compose stop
tar -czf "../dst-backup-$(date +%Y%m%d-%H%M%S).tar.gz" data
docker compose up -d
```

**改世界生成配置不会自动重建已有地图。** 想重新开一个世界，先停服并备份完整集群，再移走 `Master/save/` 与 `Caves/save/`，修改世界生成配置后启动。两个分片应一起处理，避免新旧世界混用。

## 常见问题

### Mod 下载了却没有生效

检查对应分片的 `modoverrides.lua` 是否有正确的 `workshop-ID` 和 `enabled = true`，以及 Lua 格式是否正确。地面生效、洞穴不生效时，检查洞穴的那一份配置。下载列表不会替代启用配置。

### SteamCMD 提示 `Missing configuration` 或更新失败

保留游戏 Volume，重新执行 `update`。首次使用空 SteamCMD 缓存时可能出现这个错误。持续失败则检查能否连接 Steam，以及 `docker compose logs master caves` 中的错误。

需要校验和修复游戏安装时：

```bash
docker compose stop
docker compose run --rm --no-deps master update --validate
docker compose run --rm --no-deps caves update --validate
docker compose up -d
```

### 地面和洞穴版本不一致

Steam 恰好在两个分片更新之间发布新版时，可能出现这种情况。先停止两个分片，再分别更新；日志中的 `Steam Build ID` 应一致。需要精确比较时，可在停服更新后查看：

```bash
docker compose run --rm --no-deps --entrypoint cat master /opt/dst/.build-id
docker compose run --rm --no-deps --entrypoint cat caves /opt/dst/.build-id
```

### 目录权限不足，或者想换一个 UID

默认先执行 `sudo chown -R 1000:1000 data`。容器启动时不会自动提权或修改宿主机目录所有权。

需要自定义用户时，在 `compose.override.yaml` 中为两个服务设置同一组 UID/GID，例如：

```yaml
services:
  master:
    user: "1234:1234"
  caves:
    user: "1234:1234"
```

停服后，将数据目录和游戏 Volume 的所有权一起调整：

```bash
docker compose stop
sudo chown -R 1234:1234 data
docker compose run --rm --no-deps --user 0 --entrypoint chown master -R 1234:1234 /opt/dst
docker compose run --rm --no-deps --user 0 --entrypoint chown caves -R 1234:1234 /opt/dst
docker compose up -d
```

这里的 root 命令只用于准备 Volume 权限；游戏和 SteamCMD 仍以指定的普通用户运行。

### 暂时不想更新游戏本体

已完整安装游戏后，可以在 `compose.override.yaml` 中为两个服务设置 `command: ["run"]`，以后启动跳过 SteamCMD。Mod 仍由 DST 在启动时检查更新。恢复默认自动更新时，移除这项设置并重新创建容器。

---

仓库发布流程、开发测试及实现说明见[维护者文档](docs/maintainer.md)。本项目脚本和文档使用 MIT 许可证；DST、SteamCMD 和 Workshop Mod 遵循各自许可证。
