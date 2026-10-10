FROM debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f

ARG TARGETARCH
RUN test "$TARGETARCH" = amd64 \
    && dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       bash ca-certificates curl tini util-linux locales lib32gcc-s1 lib32stdc++6 \
       libcurl4t64 libcurl3t64-gnutls libstdc++6 libgcc-s1 \
    && rm -rf /var/lib/apt/lists/* \
    && localedef -i en_US -f UTF-8 en_US.UTF-8 \
    && groupadd --gid 1000 steam \
    && useradd --uid 1000 --gid 1000 --no-create-home --home-dir /opt/dst/.home steam \
    && mkdir -p /usr/local/share/steamcmd /opt/dst /data /config \
    && curl --fail --show-error --location --retry 3 \
       https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
       | tar -xz -C /usr/local/share/steamcmd \
    && chmod -R a+rX /usr/local/share/steamcmd \
    && chmod a+rx /usr/local/share/steamcmd/steamcmd.sh /usr/local/share/steamcmd/linux32/steamcmd \
    && chown steam:steam /opt/dst /data

COPY --chmod=755 scripts/common.sh scripts/entrypoint.sh scripts/update.sh scripts/run.sh /usr/local/lib/dst/
ENV CLUSTER_NAME=Cluster_1 SHARD=Master HOME=/opt/dst/.home LANG=en_US.UTF-8
USER 1000:1000
WORKDIR /opt/dst
VOLUME ["/opt/dst", "/data"]
EXPOSE 10999/udp 11000/udp
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/lib/dst/entrypoint.sh"]
CMD ["start"]
