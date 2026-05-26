FROM rust:1-bookworm

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        clang \
        curl \
        gcc \
        libclang-dev \
        lld \
        make \
        pkg-config \
        python3 \
        xz-utils && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/libkrun

COPY ci/os_mode_linux_validate.sh /usr/local/bin/os_mode_linux_validate.sh
COPY ci/os_mode_host_checks.sh /usr/local/bin/os_mode_host_checks.sh

CMD ["/usr/local/bin/os_mode_linux_validate.sh"]
