# syntax=docker/dockerfile:1
#
# Multi-stage build for Starter.
#
# The builder stage compiles, runs the validation tests and stages an install;
# the runtime stage carries only what is needed to run the binary.
#
# Build:  podman build -f Containerfile -t starter .
#         docker build -f Containerfile -t starter .
#
# Debian trixie ships GTK 4.18, libadwaita 1.7 and Vala 0.56, which satisfy the
# versions required in meson.build.

ARG DEBIAN_VERSION=trixie

# ---------------------------------------------------------------- builder ---
FROM debian:${DEBIAN_VERSION}-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        valac \
        meson \
        ninja-build \
        pkg-config \
        libglib2.0-dev \
        libglib2.0-dev-bin \
        libgtk-4-dev \
        libgtk-4-bin \
        libadwaita-1-dev \
        gettext \
        desktop-file-utils \
        appstream \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .

RUN meson setup _build --prefix=/usr --buildtype=release \
    && meson compile -C _build \
    && meson test -C _build --print-errorlogs \
    && meson install -C _build --destdir=/stage

# gnome.post_install() skips these when DESTDIR is set, so do them by hand
# against the staged tree — the runtime stage then needs no build tooling.
RUN glib-compile-schemas /stage/usr/share/glib-2.0/schemas \
    && gtk4-update-icon-cache -f -t /stage/usr/share/icons/hicolor

# ---------------------------------------------------------------- runtime ---
FROM debian:${DEBIAN_VERSION}-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive

# adwaita-icon-theme is required: the UI references symbolic icons such as
# open-menu-symbolic that only ship in that theme.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgtk-4-1 \
        libadwaita-1-0 \
        adwaita-icon-theme \
        fonts-dejavu-core \
        dbus \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /stage/usr /usr

RUN useradd --create-home --uid 1000 app
USER app
WORKDIR /home/app

ENV GDK_BACKEND=wayland,x11

ENTRYPOINT ["/usr/bin/starter"]
