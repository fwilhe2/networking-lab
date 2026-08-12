# syntax=docker/dockerfile:1
#
# Development image for Networking Lab.
#
# `Containerfile` in the repository root builds a lean image that *runs* the app.
# This one is the environment you *edit* it in: toolchain, debugger, language
# server, plus the GTK runtime pieces the app needs to actually open a window.
#
# Nothing here copies the source — VS Code bind-mounts the workspace at runtime.
# See .devcontainer/devcontainer.json.

ARG DEBIAN_VERSION=trixie

# --------------------------------------------------- vala-language-server ---
# Debian does not package it, so build it once here and copy the binary into
# the dev image. This is what gives the Vala extension completion, go-to-symbol
# and live diagnostics.
FROM debian:${DEBIAN_VERSION}-slim AS vls

ARG VLS_VERSION=0.48.6
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        valac \
        meson \
        ninja-build \
        pkg-config \
        git \
        ca-certificates \
        libglib2.0-dev \
        libgee-0.8-dev \
        libjson-glib-dev \
        libjsonrpc-glib-1.0-dev \
        libvala-0.56-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${VLS_VERSION}" \
        https://github.com/vala-lang/vala-language-server.git /vls \
    && meson setup /vls/_build /vls --prefix=/usr --buildtype=release \
    && meson compile -C /vls/_build \
    && meson install -C /vls/_build --destdir=/stage

# ------------------------------------------------------------------- dev ---
FROM debian:${DEBIAN_VERSION}-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# Three groups, in order: the build toolchain and everything `meson test`
# shells out to; the debugger and shell comforts; and the runtime an app needs
# once it opens a window — the icon theme carries symbolic icons such as
# open-menu-symbolic that window.ui references.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        valac \
        meson \
        ninja-build \
        pkg-config \
        libglib2.0-dev \
        libglib2.0-dev-bin \
        libjson-glib-dev \
        libgtk-4-dev \
        libgtk-4-bin \
        libadwaita-1-dev \
        libvte-2.91-gtk4-dev \
        gettext \
        desktop-file-utils \
        appstream \
        gdb \
        git \
        ca-certificates \
        less \
        nano \
        procps \
        sudo \
        adwaita-icon-theme \
        gsettings-desktop-schemas \
        fonts-dejavu-core \
        dbus \
        dbus-x11 \
        libgee-0.8-2 \
        libjson-glib-1.0-0 \
        libjsonrpc-glib-1.0-1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=vls /stage/usr/bin/vala-language-server /usr/bin/vala-language-server

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid "$USER_GID" "$USERNAME" \
    && useradd --uid "$USER_UID" --gid "$USER_GID" --create-home --shell /bin/bash "$USERNAME" \
    && echo "$USERNAME ALL=(root) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" \
    && chmod 0440 "/etc/sudoers.d/$USERNAME" \
    # Mount point for the host's XDG_RUNTIME_DIR (Wayland socket, session bus).
    # The bind mount replaces this directory, but it has to exist first.
    && mkdir -p "/run/user/$USER_UID" \
    && chown "$USER_UID:$USER_GID" "/run/user/$USER_UID" \
    && chmod 0700 "/run/user/$USER_UID"

USER $USERNAME
