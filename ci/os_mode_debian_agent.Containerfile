FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV container=oci

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        chromium \
        curl \
        dbus \
        fonts-dejavu-core \
        git \
        iproute2 \
        kmod \
        less \
        nodejs \
        npm \
        procps \
        python3 \
        ripgrep \
        sudo \
        systemd \
        systemd-sysv \
        udhcpc \
        udev \
        vim-tiny \
        xdg-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash agent \
    && mkdir -p /workspace/react-app \
    && chown -R agent:agent /workspace \
    && printf 'agent ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/agent \
    && chmod 0440 /etc/sudoers.d/agent

USER agent
ENV NPM_CONFIG_PREFIX=/home/agent/.npm-global
ENV PATH=/home/agent/.npm-global/bin:$PATH
RUN mkdir -p "$NPM_CONFIG_PREFIX" \
    && npm install -g @anthropic-ai/claude-code \
    && claude --version

USER root
ENV PATH=/home/agent/.npm-global/bin:$PATH

RUN cat > /usr/local/bin/agent-demo-enter <<'EOF' \
    && chmod 0755 /usr/local/bin/agent-demo-enter
#!/bin/sh
set -eu

mkdir -p /workspace/react-app
if ! mountpoint -q /workspace/react-app; then
    mount -t virtiofs react-app /workspace/react-app
fi
chown agent:agent /workspace /workspace/react-app 2>/dev/null || true

cat <<'MSG'
Mounted the host React app at /workspace/react-app.

Run:
  su - agent
  cd /workspace/react-app
  chromium --headless --no-sandbox --disable-gpu --dump-dom file://$PWD/index.html
  claude auth login --console
  claude

Use the URL/code printed by Claude Code to authenticate with your own account.
MSG
EOF

RUN cat > /etc/profile.d/agent-demo.sh <<'EOF'
export PATH=/home/agent/.npm-global/bin:$PATH
EOF

STOPSIGNAL SIGRTMIN+3
