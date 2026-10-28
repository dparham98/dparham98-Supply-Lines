# Reproducible headless Godot environment for Supply Lines (Codespaces / Dev Containers).
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl unzip git git-lfs libfontconfig1 \
 && rm -rf /var/lib/apt/lists/*
COPY .godot-version ci/install_godot.sh /tmp/godot/
RUN mkdir -p /tmp/godot/ci && mv /tmp/godot/install_godot.sh /tmp/godot/ci/ \
 && bash /tmp/godot/ci/install_godot.sh /opt/godot \
 && ln -s /opt/godot/Godot_v$(tr -d '[:space:]' < /tmp/godot/.godot-version)_linux.x86_64 /usr/local/bin/godot \
 && rm -rf /tmp/godot
