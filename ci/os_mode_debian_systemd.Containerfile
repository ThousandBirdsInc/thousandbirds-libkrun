FROM debian:bookworm-slim

ENV container=oci

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        dbus \
        iproute2 \
        isc-dhcp-client \
        kmod \
        procps \
        systemd \
        systemd-sysv \
        udhcpc \
        udev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

STOPSIGNAL SIGRTMIN+3
