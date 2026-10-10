#!/usr/bin/env bash
set -Eeuo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
image=${1:-dst:local}
test_root=$(mktemp -d)
test_image="dst-runtime-test:$$"
container=
cleanup() {
    [[ -z $container ]] || docker rm -f -v "$container" >/dev/null 2>&1 || true
    docker image rm "$test_image" >/dev/null 2>&1 || true
    rm -rf "$test_root"
}
trap cleanup EXIT
mkdir -p "$test_root/game/bin64" "$test_root/game/steamapps" "$test_root/data/DoNotStarveTogether/Cluster_1"
cp -a "$repo/examples/cluster/." "$test_root/data/DoNotStarveTogether/Cluster_1/"
printf 'fixture-token-not-real\n' >"$test_root/data/DoNotStarveTogether/Cluster_1/cluster_token.txt"
cat >"$test_root/game/steamapps/appmanifest_343050.acf" <<'EOF_MANIFEST'
"AppState"
{
    "appid" "343050"
    "StateFlags" "4"
    "buildid" "12345"
}
EOF_MANIFEST
cat >"$test_root/game/bin64/dontstarve_dedicated_server_nullrenderer_x64" <<'EOF_GAME'
#!/usr/bin/env bash
set -eu
trap 'echo BAD_SIGNAL; exit 99' TERM INT
printf 'FIXTURE_READY\n'
while IFS= read -r command; do
    if [[ $command == 'c_shutdown()' ]]; then
        # Model DST joining its console input thread before process exit.
        while IFS= read -r ignored; do :; done
        printf 'fixture-save\n' >/data/saved
        printf 'FIXTURE_SAVED\n'
        exit 17
    fi
done
exit 98
EOF_GAME
chmod +x "$test_root/game/bin64/dontstarve_dedicated_server_nullrenderer_x64"
cat >"$test_root/Dockerfile" <<'EOF_DOCKER'
ARG DST_IMAGE
FROM ${DST_IMAGE}
ARG FIXTURE_UID=1000
USER root
COPY game/ /opt/dst/
COPY data/ /data/
RUN chown -R ${FIXTURE_UID}:${FIXTURE_UID} /opt/dst /data
USER ${FIXTURE_UID}:${FIXTURE_UID}
EOF_DOCKER
for fixture_uid in 1000 1234; do
    docker build --quiet --build-arg "DST_IMAGE=$image" --build-arg "FIXTURE_UID=$fixture_uid" -t "$test_image" "$test_root" >/dev/null
    for signal in TERM INT; do
        container=$(docker run -d "$test_image" run)
        ready=false
        for (( attempt=0; attempt<100; attempt++ )); do
            if docker logs "$container" 2>&1 | rg -q FIXTURE_READY; then ready=true; break; fi
            sleep 0.05
        done
        [[ $ready == true ]] || { docker logs "$container"; exit 1; }
        docker kill --signal "$signal" "$container" >/dev/null
        status=$(timeout 15 docker wait "$container")
        [[ $status == 17 ]] || { docker logs "$container"; echo "Unexpected exit $status" >&2; exit 1; }
        docker logs "$container" >"$test_root/log" 2>&1
        rg -q FIXTURE_SAVED "$test_root/log"
        if rg -q BAD_SIGNAL "$test_root/log"; then echo 'Raw signal reached game' >&2; exit 1; fi
        docker cp "$container:/data/saved" "$test_root/saved"
        rg -q fixture-save "$test_root/saved"
        docker rm -v "$container" >/dev/null
        container=
        printf 'PASS Docker %s shutdown saves with UID %s and preserves exit code\n' "$signal" "$fixture_uid"
    done
done
