# DST Docker

[简体中文](README.zh-CN.md)

Run a Don't Starve Together dedicated server with Docker, including the surface (Master) and caves (Caves). Start a new world or bring your existing saves. The server downloads the game on first startup and checks for updates on subsequent starts; no separate updater container is required.

You need Linux x86_64 (`linux/amd64`), Docker Engine, and Docker Compose. Each shard keeps its own game installation, so allow at least 10 GB of disk space, plus room for saves and mods. The server must be able to reach Steam and Klei.

- [Start your first server](#start-your-first-server)
- [Configure mods](#configure-mods)
- [Migrate an existing world](#migrate-an-existing-world)
- [Update the game and image](#update-the-game-and-image)
- [Save, back up, and regenerate worlds](#save-back-up-and-regenerate-worlds)
- [Troubleshooting](#troubleshooting)

## Start your first server

### 1. Create a deployment directory and Compose configuration

Create a directory for Compose, configuration, and saves. Run all following commands from this directory:

```bash
mkdir dst-server
cd dst-server
```

Create `.env` with the Docker Hub image and tag you want to use:

```dotenv
DST_IMAGE=your-namespace/your-image:1.0.0
```

This address is a placeholder. Replace it with an actual published image and tag. Then create `compose.yml`:

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

Check these settings for your deployment:

| Setting | Purpose and how to change it |
| --- | --- |
| `image` / `DST_IMAGE` in `.env` | Docker Hub image and tag; use the same version for both services |
| `CLUSTER_NAME` | Cluster directory under `/data/DoNotStarveTogether/`; must match in both services, defaults to `Cluster_1` |
| `SHARD` | Shard directory within the cluster: `Master` or `Caves` |
| `./data:/data` | Mounts local configuration, token, and saves; both services share this directory |
| `master-game:/opt/dst`, `caves-game:/opt/dst` | Store game installations and mod caches in separate volumes for each shard |
| `./config/dedicated_server_mods_setup.lua:…:ro` | Mounts the local mod download list read-only into both containers; create the file before startup |
| `ports` | `host-port:container-port/udp`; container ports match `server_port` in the `server.ini` files below |
| `networks` | Lets caves reach the surface by service name `master`, matching `master_ip = master` in `cluster.ini` |
| `stop_grace_period` | Time allowed for saving during shutdown; keep `120s` |
| `restart` | `unless-stopped` restarts containers after unexpected exits and keeps them stopped after a manual stop |

The following steps use the default paths and ports. If you change `CLUSTER_NAME` or the source of the `./data` mount, adjust the file paths below. For internet players, allow both host UDP ports through your firewall and router: `10999` and `11000` by default. Shard communication on port `10888` stays within the Docker network.

### 2. Prepare world configuration and a token

For existing saves, follow [Migrate an existing world](#migrate-an-existing-world), then return to “Pull the image and start.” For a new world, create the files below:

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

Create `data/DoNotStarveTogether/Cluster_1/cluster.ini` with:

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

Set your server name (`cluster_name`), join password (`cluster_password`), and player limit (`max_players`). Replace `cluster_key` with your own random string. `cluster_password` is for players joining; `cluster_key` connects the surface and caves. `game_mode = survival` uses survival mode, which starts a world reset countdown when all players die.

Get a dedicated server token from your [Klei account](https://accounts.klei.com/) and put it in `cluster_token.txt` in the same directory. Include only the token, without quotes. This is not your Steam password.

Set the surface port and shard identity in `Master/server.ini`:

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

Create `Caves/server.ini` with:

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

Create `Master/worldgenoverride.lua` with:

```lua
return {
    override_enabled = true,
    preset = "SURVIVAL_TOGETHER",
    overrides = {},
}
```

Create `Caves/worldgenoverride.lua` with:

```lua
return {
    override_enabled = true,
    preset = "DST_CAVE",
    overrides = {},
}
```

No mods are enabled by default. Create `modoverrides.lua` in each shard directory with:

```lua
return {}
```

To customize map size, resources, or other generation options, edit each shard's `worldgenoverride.lua` **before the first startup**. You can also use world configuration exported from the game. See the [Klei world configuration guide](https://kleiforums.com/forums/topic/67039-dedicated-server-world-overrides-guide/) for the format. For mods, complete the download list and shard settings in [Configure mods](#configure-mods).

### 3. Pull the image and start

The containers run as UID/GID `1000:1000` by default. Prepare data directory permissions, validate Compose, then pull and start:

```bash
sudo chown -R 1000:1000 data
sudo chmod 600 data/DoNotStarveTogether/Cluster_1/cluster_token.txt
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose logs -f
```

The first startup installs the game, downloads configured mods, generates the worlds, and connects the shards. This takes some time. Messages such as `Secondary Caves(...) ready!` and `secondary shard LUA is now ready!` indicate that the shards have connected. Pressing `Ctrl+C` exits the log viewer; the server keeps running. Players can search for the name set in `cluster_name` in the game.

When no world saves exist, DST generates worlds from the configuration and writes them to `Master/save/` and `Caves/save/`. Later starts load those saves. Prepare configuration files and a token before starting; an empty data directory does not produce a complete server setup.

## Configure mods

Server mods need two separate settings: **which mods to download, and which mods each shard should enable.** Complete both steps.

### 1. Add mods to the download list

Find the numeric ID after `id=` in the mod's Steam Workshop URL. For example, `id=123456789` identifies mod `123456789`. The IDs below are placeholders; replace them with real mod IDs.

Edit `config/dedicated_server_mods_setup.lua` in your deployment directory, adding one line per mod:

```lua
ServerModSetup("123456789")
ServerModSetup("987654321")
```

The Compose configuration above mounts this file into both containers. You do not need to edit files inside the game installation. The download list is reapplied after game updates.

### 2. Enable mods and configure their options

Edit `data/DoNotStarveTogether/Cluster_1/Master/modoverrides.lua`:

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

The download list uses numeric strings; the keys here need the `workshop-` prefix. An empty `configuration_options = {}` uses the mod's default options. Available option names and values depend on the mod.

Configure `Caves/modoverrides.lua` as well, enabling the mods needed in the caves. If both shards should use exactly the same settings, copy the surface configuration:

```bash
cp data/DoNotStarveTogether/Cluster_1/Master/modoverrides.lua \
   data/DoNotStarveTogether/Cluster_1/Caves/modoverrides.lua
```

To keep options you selected in the game's UI, copy each shard's original `modoverrides.lua`, then add the required Workshop IDs to the download list. The image does not generate a download list from `modoverrides.lua`. Players install client-only mods themselves; those do not belong in the server configuration.

See the [Klei mod configuration guide](https://kleiforums.com/forums/topic/96433-dedicated-server-mod-setup-guide/) for more details.

### 3. Restart to apply changes

```bash
docker compose stop
docker compose up -d
docker compose logs -f
```

DST downloads mods and checks for mod updates during game startup. It does not reload them automatically while running. The `update` command updates only the game itself; it does not download mods in advance.

To disable a mod, set `enabled = false` in each relevant shard, remove its line from the download list, and restart. Cached files can remain without enabling the mod. Back up your world before removing mods that add items or creatures.

## Migrate an existing world

Stop the original server first. Copy the **entire cluster directory**, including `cluster.ini`, the token, Master/Caves configuration, and their `save/` directories. Do not copy just an individual world snapshot. Keep the original as a backup.

This example imports an existing `Cluster_3` as the default `Cluster_1`. Renaming the directory preserves the world progress and player data inside it.

```bash
docker compose stop
mkdir -p data/DoNotStarveTogether
mkdir data/DoNotStarveTogether/Cluster_1 &&
  cp -a /path/to/Cluster_3/. data/DoNotStarveTogether/Cluster_1/
```

Replace `/path/to/Cluster_3` with your source path. The command deliberately refuses to merge into an existing `Cluster_1`. If that directory already exists, back it up and move it aside before copying, so two different worlds' saves do not get mixed together.

Check the resulting structure:

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

Also preserve existing `leveldataoverride.lua`, `worldgenoverride.lua`, administrator lists, and other cluster files. Do not overwrite them with the new-world templates.

### Adjust shard connections

A server running both shards directly on one machine may use `127.0.0.1`. Here the shards run in separate containers, so adjust the connection settings in your copied configuration.

Check these settings in `cluster.ini`:

```ini
[SHARD]
shard_enabled = true
bind_ip = 0.0.0.0
master_ip = master
master_port = 10888
cluster_key = YOUR_SHARED_SHARD_KEY
```

You can keep your original `cluster_key`. Both shards read the same `cluster.ini`, so they share the key.

| File | Settings to check |
| --- | --- |
| `Master/server.ini` | `server_port = 10999` under `[NETWORK]`; `is_master = true` under `[SHARD]` |
| `Caves/server.ini` | `server_port = 11000` under `[NETWORK]`; `is_master = false` under `[SHARD]` |

Keep the caves' original shard `id`. To retain the directory name `Cluster_3`, leave it unchanged and set `CLUSTER_NAME: Cluster_3` for **both services** in Compose. Adjust the data paths in subsequent commands accordingly.

### Restore mods and start

Keep your original `modoverrides.lua` files, complete the download list as described in [Configure mods](#configure-mods), and check that your token is valid. Then follow the permission and startup steps above.

The startup logs should show `Loading world` as DST loads your copied saves. Moving to a container does not regenerate the world. Check the day count, characters, and buildings before players resume playing.

This example assumes you have both surface and cave saves. If you only have a surface world, start just that shard with `docker compose up -d master`. Adding caves requires cave configuration and entrances in the existing surface world.

## Update the game and image

### How game updates work

By default, every container startup checks for and installs game server updates through SteamCMD. A running server does not update on a schedule or automatically disconnect players and restart.

To apply a game update, stop and start the server:

```bash
docker compose stop
docker compose up -d
docker compose logs -f
```

Running `docker compose up -d` while the containers are already running does not force a restart or another update check.

To finish downloading the game for both shards before bringing them online, update them separately after stopping:

```bash
docker compose stop
docker compose run --rm --no-deps master update
docker compose run --rm --no-deps caves update
docker compose up -d
```

Updates preserve saves and configuration in `data`. If an update fails, the server refuses to start. Fix the connection or installation problem and retry the update; you do not need to regenerate the world. Back up saves before game version changes.

### Update the Docker Hub image

To upgrade the image, stop the server, change the tag in `.env`, then pull and start again:

```bash
docker compose stop
docker compose pull
docker compose up -d --no-build
```

`latest` follows the newest stable image release. An explicit tag such as `1.0.0` pins the image and startup scripts. **SteamCMD updates the game independently:** pinning the image does not pin the game version, and switching to an older image does not roll back saves.

For builds from source, see the [maintainer guide (Chinese)](docs/maintainer.md).

## Save, back up, and regenerate worlds

Stop the server normally to request a save and shutdown. Compose allows 120 seconds for shutdown:

```bash
docker compose stop
```

World saves, the token, and configuration are stored in the host's `data/` directory. They survive container recreation and `docker compose down`. Game installations and mod caches live in two Docker named volumes. `docker compose down -v` deletes those volumes, requiring another download next time, but does not delete the bind-mounted host `data/` directory.

Automatic backups are not included. To make a backup, stop the server and archive the entire `data` directory outside the deployment directory:

```bash
docker compose stop
tar -czf "../dst-backup-$(date +%Y%m%d-%H%M%S).tar.gz" data
docker compose up -d
```

**Changing world generation settings does not rebuild an existing map.** To start a fresh world, stop the server, back up the complete cluster, move both `Master/save/` and `Caves/save/` aside, adjust the generation settings, and start again. Handle both shards together to avoid mixing old and new worlds.

## Troubleshooting

### Mods download but do not load

Check that the affected shard's `modoverrides.lua` contains the correct `workshop-ID`, has `enabled = true`, and uses valid Lua syntax. If a mod works on the surface but not in the caves, check the cave configuration. The download list does not replace the enablement configuration.

### SteamCMD reports `Missing configuration` or an update fails

Keep the game volume and retry `update`. This error can occur with an empty SteamCMD cache on first use. If it persists, check connectivity to Steam and the errors in `docker compose logs master caves`.

To validate and repair the game installation:

```bash
docker compose stop
docker compose run --rm --no-deps master update --validate
docker compose run --rm --no-deps caves update --validate
docker compose up -d
```

### Surface and caves have different game versions

This can happen if Steam releases an update between the two shards' update checks. Stop both shards and update each one. Their logged `Steam Build ID` values should match. After stopping and updating, you can compare the recorded IDs directly:

```bash
docker compose run --rm --no-deps --entrypoint cat master /opt/dst/.build-id
docker compose run --rm --no-deps --entrypoint cat caves /opt/dst/.build-id
```

### Permission errors or a custom UID

For the default user, run `sudo chown -R 1000:1000 data`. Startup does not automatically elevate privileges or change ownership of host directories.

To use another user, set the same UID/GID for both services in `compose.override.yaml`, for example:

```yaml
services:
  master:
    user: "1234:1234"
  caves:
    user: "1234:1234"
```

Stop the server, then adjust ownership of both the data directory and game volumes:

```bash
docker compose stop
sudo chown -R 1234:1234 data
docker compose run --rm --no-deps --user 0 --entrypoint chown master -R 1234:1234 /opt/dst
docker compose run --rm --no-deps --user 0 --entrypoint chown caves -R 1234:1234 /opt/dst
docker compose up -d
```

These root commands only prepare volume permissions. The game and SteamCMD still run as the specified non-root user.

### Temporarily skip game updates

Once the game is fully installed, set `command: ["run"]` for both services in `compose.override.yaml` to skip SteamCMD on startup. DST still checks for mod updates. To restore automatic game updates, remove that setting and recreate the containers.

---

For publishing, development checks, and implementation details, see the [maintainer guide (Chinese)](docs/maintainer.md). Project scripts and documentation are MIT licensed; DST, SteamCMD, and Workshop mods retain their respective licenses.
