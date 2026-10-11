# DST Docker

[![GitHub](https://img.shields.io/badge/GitHub-Source-181717?logo=github&logoColor=white)](https://github.com/TelepathyMaster/dst-docker)

[English](README.md)

Docker Hub：[srtkz/dst-dedicated-server](https://hub.docker.com/r/srtkz/dst-dedicated-server)。本指南对应 **v1.1.0**，镜像地址为 `srtkz/dst-dedicated-server:1.1.0`。

用 Docker 运行饥荒联机版专用服务器，支持地面（Master）和洞穴（Caves）。可以从零生成新世界，也可以搬入已有存档继续玩。由 updater 服务统一下载和更新游戏及 Mod，地面与洞穴只读共用同一份安装文件。

需要 Linux x86_64（`linux/amd64`）、Docker Engine 和 Docker Compose。请为一份游戏安装、共享 Mod 以及各分片存档预留空间。服务器需要能够连接 Steam 和 Klei。

- [第一次开服](#第一次开服)
- [配置 Mod](#配置-mod)
- [迁移已有存档](#迁移已有存档)
- [更新游戏和镜像](#更新游戏和镜像)
- [保存、备份和重新生成世界](#保存备份和重新生成世界)
- [常见问题](#常见问题)

从 `1.1.0` 起，游戏和 Mod 使用共享安装方案。`1.0.0` 镜像采用旧的双数据卷布局，不兼容下面的 Compose 示例。已有部署请按[迁移已有存档](#迁移已有存档)中的说明升级。

## 第一次开服

### 1. 创建部署目录和 Compose 配置

创建一个目录存放 Compose、配置和存档。以下命令都在这个目录中执行：

```bash
mkdir dst-server
cd dst-server
```

新建 `compose.yml`，在 `x-dst` 下直接填写 Docker Hub 镜像地址和标签：

```yaml
x-dst: &dst
  image: srtkz/dst-dedicated-server:1.1.0
  stop_grace_period: 120s
  networks: [dst]
  environment: &dst-environment
    CLUSTER_NAME: Cluster_1

services:
  updater:
    <<: *dst
    restart: "no"
    command: update
    environment:
      <<: *dst-environment
      SHARD: Master
    volumes:
      - dst-game:/opt/dst
      - ./data:/data
      - ./config/dedicated_server_mods_setup.lua:/config/dedicated_server_mods_setup.lua:ro
  master:
    <<: *dst
    restart: unless-stopped
    command: run
    depends_on:
      updater:
        condition: service_completed_successfully
    environment:
      <<: *dst-environment
      SHARD: Master
    volumes:
      - dst-game:/opt/dst:ro
      - ./data:/data
      - ./config/dedicated_server_mods_setup.lua:/config/dedicated_server_mods_setup.lua:ro
    ports:
      - "10999:10999/udp"
  caves:
    <<: *dst
    restart: unless-stopped
    command: run
    depends_on:
      updater:
        condition: service_completed_successfully
    environment:
      <<: *dst-environment
      SHARD: Caves
    volumes:
      - dst-game:/opt/dst:ro
      - ./data:/data
      - ./config/dedicated_server_mods_setup.lua:/config/dedicated_server_mods_setup.lua:ro
    ports:
      - "10998:10998/udp"

volumes:
  dst-game:
networks:
  dst:
    driver: bridge
```

`x-dst` 保存公共服务配置，其中的 `environment` 另设 `&dst-environment` 锚点。各服务通过 `<<: *dst-environment` 合并公共环境变量，再设置自己的 `SHARD`。YAML 的合并不会递归处理嵌套映射：只继承 `*dst` 时，服务自己的 `environment` 会覆盖整个公共环境变量配置。因此，修改集群名只需改公共环境变量中的一处 `CLUSTER_NAME`。

先按自己的部署环境检查这些配置项：

| 配置项 | 用途与修改方式 |
| --- | --- |
| `image` | Docker Hub 镜像地址和标签；三个服务使用同一镜像 |
| `CLUSTER_NAME` | `/data/DoNotStarveTogether/` 下的集群目录名；在 `x-dst.environment` 中统一设置，默认 `Cluster_1` |
| `SHARD` | 对应集群中的分片目录，分别为 `Master` 和 `Caves` |
| `./data:/data` | 将本地配置、Token 和世界存档挂载到容器；三个服务共享同一目录 |
| `dst-game:/opt/dst` | 共用一份游戏和 Mod；updater 可写，两个分片只读挂载 |
| `depends_on` | updater 成功退出后才启动分片，更新失败时阻止启动 |
| `./config/dedicated_server_mods_setup.lua:…:ro` | 将本地 Mod 下载列表只读挂载到三个容器，启动前需创建该文件 |
| `ports` | `宿主机端口:容器端口/udp`；容器端口对应下文 `server.ini` 中的 `server_port` |
| `networks` | 让洞穴通过服务名 `master` 连接地面，对应 `cluster.ini` 的 `master_ip = master` |
| `stop_grace_period` | 正常关闭时等待保存的时间，保留 `120s` |
| `restart` | `unless-stopped` 会在异常退出后重启；手动停服后保持停止 |

下面按默认路径和端口继续。若修改了 `CLUSTER_NAME` 或 `./data` 的挂载来源，后面的文件路径也要对应调整。需要外网玩家加入时，在防火墙和路由器放行两个宿主机 UDP 端口；默认是 `10999` 和 `10998`。分片连接端口 `10888` 只在 Docker 网络内使用。

### 2. 准备世界配置和 Token

已有存档时，按[迁移已有存档](#迁移已有存档)放好整个集群，再回来执行“准备安装并启动”。新世界按下面的结构创建文件：

```bash
mkdir -p data/DoNotStarveTogether/Cluster_1/{Master,Caves} config
printf '%s\n' '-- No Workshop mods configured.' > config/dedicated_server_mods_setup.lua
```

```text
dst-server/
├── compose.yml
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
server_port = 10998

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

### 3. 准备安装并启动

容器默认以 UID/GID `1000:1000` 运行，先准备数据目录权限，再检查 Compose、准备安装并启动：

```bash
sudo chown -R 1000:1000 data
sudo chmod 600 data/DoNotStarveTogether/Cluster_1/cluster_token.txt
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose logs -f
```

首次启动由 updater 安装一份游戏、下载配置的 Mod 后退出；随后两个分片加载共享文件，各自生成世界并连接，需要一些时间。日志中出现 `Secondary Caves(...) ready!`、`secondary shard LUA is now ready!`，表示两个分片已完成连接。按 `Ctrl+C` 只退出日志查看，服务器继续运行。玩家可在游戏中搜索 `cluster_name` 设置的房间名称加入。

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

也可以使用 `ServerModCollectionSetup` 下载 Steam 创意工坊合集中的 Mod，参数是合集页面地址中 `id=` 后面的数字 ID：

```lua
ServerModCollectionSetup("COLLECTION_ID")
```

将 `COLLECTION_ID` 替换为实际的数字合集 ID。同一个文件中可以混用合集和单个 Mod 的下载配置。合集只负责下载，仍需在各分片的 `modoverrides.lua` 中逐个启用并配置 Mod，使用单个 Mod 的 ID，而不是合集 ID。已下载但未配置启用的 Mod 不会运行。合集新增 Mod 后，重新运行 updater 下载，并按需补充启用配置。

上面的 Compose 已经把这个文件挂载到三个容器，无需进入容器编辑游戏安装目录。游戏本体更新后，这份下载列表仍会重新应用。

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

updater 使用 `-only_update_server_mods` 统一准备 Mod 文件；两个分片使用 `-skip_update_server_mods` 和同一个 UGC 目录，不再重复下载。更新游戏或 Mod 前必须停止两个分片，`update` 现在会同时准备游戏和 Mod。

停用某个 Mod 时，将各相关分片中的 `enabled` 改为 `false`，并从下载列表中移除对应行，再重启。缓存文件可以保留，不会因此继续启用。移除会添加物品或生物的 Mod 前，先备份世界存档。

## 迁移已有存档

从旧版双数据卷方案迁移时，先停止旧服务并备份 `data`，再替换 Compose 布局并使用兼容的新镜像。新 `dst-game` 卷由 updater 下载准备一次；存档和配置仍来自原 `data`。旧 `master-game`、`caves-game` 卷不会自动合并或删除，验收通过前保留，之后只清理已确认不用的卷。

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
| `Caves/server.ini` | `[NETWORK]` 的 `server_port = 10998`；`[SHARD]` 的 `is_master = false` |

保留洞穴原有的分片 `id`。如果要使用 `Cluster_3` 这个目录名，可以不重命名，并将 Compose 中 `x-dst.environment` 下的 `CLUSTER_NAME` 改为 `Cluster_3`；后续命令中的数据路径也对应替换。

### 恢复 Mod 并开服

保留原有 `modoverrides.lua`，按[配置 Mod](#配置-mod)补齐下载列表，并检查原有 Token 是否有效，然后执行前面的权限设置和启动命令。

启动日志应显示 `Loading world`，加载复制来的世界；不会因为换了容器而自动重建。迁移后先检查天数、角色和建筑，再让玩家继续游玩。

以上示例针对地面与洞穴都有存档的情况。只有地面存档时，先用 `docker compose up -d master` 启动地面；新增洞穴还需要准备洞穴配置，并确认原地面世界存在洞穴入口。

## 更新游戏和镜像

### 游戏本体如何更新

默认由 Compose 的 updater 在两个分片启动前统一更新游戏和 Mod。正在运行的服务器不会定时更新，也不会自动踢出玩家重启。

有游戏更新时，正常停服再启动即可：

```bash
docker compose stop
docker compose up -d
docker compose logs -f
```

运行 updater 前应先停止两个分片。分片仍在运行时执行 `docker compose up -d` 可能重新启动已退出的 updater；独占锁会拒绝修改正在使用的安装。

想先完成共享游戏和 Mod 更新，再一起开服，可以在停服后只更新一次，再跳过 updater 启动分片：

```bash
docker compose stop
docker compose run --rm --no-deps updater update
docker compose up -d --no-deps master caves
```

更新会保留 `data` 中的存档和配置。若更新失败，服务器会停止启动，修复连接或安装问题后重新更新即可，不需要重建世界。更换游戏版本前建议备份存档。

### 更新 Docker Hub 镜像

此共享安装布局使用 `1.1.0` 或后续兼容版本，不能使用 `1.0.0` 镜像。

升级镜像时，先停服，修改 `compose.yml` 中 `x-dst` 下的 `image`，再拉取并启动：

```bash
docker compose stop
docker compose pull
docker compose up -d --no-build
```

`latest` 跟随最新稳定镜像，`1.1.0` 这样的明确标签固定镜像和启动脚本版本。**游戏本体仍由 SteamCMD 独立更新**，固定镜像标签不等于固定游戏版本，换回旧镜像也不能回滚存档。

需要从源码构建镜像时，参阅[维护者文档](docs/maintainer.md)。

## 保存、备份和重新生成世界

使用下面的命令正常停服，服务器会请求保存并退出；Compose 已预留 120 秒供关闭使用：

```bash
docker compose stop
```

世界存档、Token 和配置都在宿主机的 `data/` 中。重建容器或执行 `docker compose down` 后，它们仍然保留。游戏文件和 Mod 缓存在一个共享 Docker 命名 Volume 中；`docker compose down -v` 会清掉这些缓存，下次启动需要重新下载，但不会删除挂载的宿主机 `data/`。

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
docker compose run --rm --no-deps updater update --validate
docker compose up -d
```

### 地面和洞穴版本不一致

两个分片加载同一游戏卷，因此 Build ID 相同。如仍出现版本差异，检查是否使用相同镜像和数据卷。通过 updater 更新前应停止两个分片。

### 洞穴提示 `CANNOT_RESOLVE_DOMAIN_NAME`

检查洞穴日志中的 `MasterHost`。使用此 Compose 时，实际部署的 `cluster.ini` 中 `[SHARD]` 的 `master_ip` 应为地表服务名 `master`；旧存档中的 `dst_master` 等地址可能无法解析。两个服务也应位于同一 `dst` 网络。先停服，修正副本中的配置，再启动。若此错误后出现退出码 139 的重启循环，应先解决分片连接失败；修正后仍崩溃再检查完整日志。

### 目录权限不足，或者想换一个 UID

默认先执行 `sudo chown -R 1000:1000 data`。容器启动时不会自动提权或修改宿主机目录所有权。

需要自定义用户时，在 `compose.override.yaml` 中为三个服务设置同一组 UID/GID，例如：

```yaml
services:
  updater:
    user: "1234:1234"
  master:
    user: "1234:1234"
  caves:
    user: "1234:1234"
```

停服后，将数据目录和共享游戏 Volume 的所有权一起调整：

```bash
docker compose stop
sudo chown -R 1234:1234 data
docker compose run --rm --no-deps --user 0 --entrypoint chown updater -R 1234:1234 /opt/dst
docker compose up -d
```

这里的 root 命令只用于准备 Volume 权限；游戏和 SteamCMD 仍以指定的普通用户运行。

### 暂时不想更新游戏和 Mod

完成一次准备后，执行 `docker compose up -d --no-deps master caves`，只启动两个分片，使用现有共享游戏和 Mod。需要重新检查更新时，按正常停服再启动流程运行 updater。

---

仓库发布流程、开发测试及实现说明见[维护者文档](docs/maintainer.md)。本项目脚本和文档使用 MIT 许可证；DST、SteamCMD 和 Workshop Mod 遵循各自许可证。
