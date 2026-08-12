# Networking Lab

Draw a network, boot it, log into it.

Networking Lab is a GNOME application for building small container-based network
labs. You place routers, switches, PCs and servers on a canvas and connect them;
the application works out the addressing, compiles the topology to a
`docker-compose.yml`, starts it, and gives you a terminal on any device — without
leaving the window.

Routers run [FRR](https://frrouting.org/), so a router's terminal is a `vtysh`
prompt with OSPF, BGP, RIP and IS-IS available. Switches become docker bridge
networks. The generated compose file is an ordinary one: a lab is equally usable
from a terminal, in CI, or on a machine that has never seen this application.

## Install

There are no tagged releases yet, so a package has to be built. Each build runs
inside a container of the target distribution, so the only thing needed to build
one is docker (or podman) — nothing is installed on your machine except the
finished package.

### Debian 13 (trixie)

```sh
git clone https://github.com/fwilhe2/networking-lab.git
cd networking-lab
tools/build-deb.sh
sudo apt install ./dist/networking-lab_0.1.0_amd64.deb
```

Debian 13 is what the package targets: it carries GTK 4.18, libadwaita 1.7 and
VTE 0.80, which is what the application needs. Debian 12 is too old. Other
Debian-derived systems with GTK ≥ 4.12, libadwaita ≥ 1.5 and `libvte-2.91-gtk4-0`
will probably work but are not tested.

`apt` will offer to install `docker.io` and `docker-compose` alongside, because
running a lab needs them. If you already have Docker CE from
`download.docker.com`, apt leaves it alone — the recommendation is satisfied by
either.

### Fedora 44

```sh
git clone https://github.com/fwilhe2/networking-lab.git
cd networking-lab
tools/build-rpm.sh
sudo dnf install ./dist/networking-lab-0.1.0-1.fc44.x86_64.rpm
```

### Flatpak

```sh
flatpak install flathub org.gnome.Platform//50 org.gnome.Sdk//50
flatpak-builder --user --install --force-clean _flatpak io.github.fwilhe2.NetworkingLab.json
flatpak run io.github.fwilhe2.NetworkingLab
```

The Flatpak **draws and generates but does not run**. A sandbox cannot reach the
docker socket, and it should not be given a hole to it: access to the docker
socket is access to root on the host. The Run button is insensitive there and
says so, and the build has no embedded terminal, because the GNOME runtime does
not ship VTE. Generate the compose file and run it from a terminal instead.

### From source

Without docker, or to hack on it:

```sh
# Debian 13 — the same list debian/control builds against
sudo apt install build-essential meson ninja-build pkgconf valac \
    libglib2.0-dev libglib2.0-dev-bin libjson-glib-dev libgtk-4-dev \
    libadwaita-1-dev libvte-2.91-gtk4-dev gettext desktop-file-utils appstream

# Fedora 44 — dnf reads the build dependencies out of the spec file
sudo dnf install 'dnf-command(builddep)'
sudo dnf builddep networking-lab.spec

meson setup _build
meson compile -C _build
meson devenv -C _build networking-lab
```

`meson devenv` is needed to run from the build tree: it puts the compiled
GSettings schema where the application looks for it. `meson install -C _build`
installs properly.

## Running a lab

Booting a lab needs docker with the **compose v2 plugin, 2.23.1 or newer** — the
generated file uses inline `configs`, which older versions cannot read. Check
with `docker compose version`. Your user also needs to be able to reach the
daemon:

```sh
sudo usermod -aG docker "$USER"     # then log out and back in
```

Without any of that the application still designs, generates and exports; only
the Run button is insensitive, with the reason in its tooltip.

## Using it

Start from **Load Demo** in the main menu: two routers running OSPF, two
switches, a PC and a server. It is the fastest way to see what the application
does.

**Drawing.** Drag a device from the palette onto the canvas. Shift-click two
devices to connect them, or press `L` for link mode and click them in turn.
Select a device to edit its name, addresses, gateway or extra FRR configuration
in the panel on the right; invalid input is rejected and reverted rather than
quietly corrected.

**Addressing.** Every switch gets a subnet, every point-to-point link between two
routers gets one of its own, and interfaces are numbered `eth0`, `eth1`, … in
link order. A PC or server placed on a segment with a router gets that router as
its default gateway. All of it can be overridden.

**Generating.** **Generate** shows the compose file with any problems listed
above it, and offers Copy and Save As. Warnings never block: a half-drawn lab
still compiles.

**Running.** **Run** boots the lab. Devices that are up get a green dot; a
container that died gets a red one. **Stop** removes the containers and their
networks, and asks first, because anything you configured inside a router and did
not save goes with them.

**Terminals.** Double-click a running device — or press `T`, or use the buttons
in the properties panel — to open a session on it: `vtysh` for a router, a shell
for anything else. Sessions live in tabs under the canvas and survive clicking
elsewhere. **Logs** follows a device's output in the same way.

Press `?` for the full list of shortcuts.

## Where your files go

| What | Where |
| --- | --- |
| The session you were last working on | `~/.local/share/networking-lab/autosave.netlab.json` |
| A lab's generated compose file | `~/.local/share/networking-lab/labs/<project>/docker-compose.yml` |
| Preferences and window geometry | GSettings, under `io.github.fwilhe2.NetworkingLab` |

The autosave is restored at startup, so the application picks up where you left
off. Both files are plain text and meant to be readable; **Export** and **Import**
move a topology around as `.netlab.json`.

A running lab is addressed by its project name, which is the *Project name* field
in the panel. Closing the window does **not** stop the lab — that is deliberate,
so a reboot of the application does not tear down what you are working on. The
lab is picked up again next time; `docker compose -p <project> down -v` stops it
from a terminal.

## When something does not work

- **The Run button is insensitive.** Its tooltip says why: docker not installed,
  the daemon not reachable (add yourself to the `docker` group), a compose plugin
  older than 2.23.1, or the Flatpak sandbox.
- **A lab starts but devices cannot reach each other.** Give it a minute: OSPF
  adjacencies form in about 45 seconds and routes appear after the next SPF run.
  The demo's `pc1` can ping `10.0.2.10` after roughly 90 seconds.
- **`ping 1.1.1.1` fails from a device.** That is the *Isolated networks* setting,
  which is on by default and marks every network `internal: true`. Turn it off if
  a lab needs the internet.
- **A terminal says the session ended.** The container is gone — the lab was
  stopped, or that device exited. The scrollback stays readable.

## Development

`HACKING.md` covers the build, the dev container, the test suites, driving the UI
for visual checks, the container image and the CI jobs. `RELEASING.md` is the
release checklist. `PLAN.md` is the implementation plan the port followed.

## License

GPL-3.0-or-later. The full text is in [`LICENSE`](LICENSE), and every source file
carries an `SPDX-License-Identifier: GPL-3.0-or-later` header.
