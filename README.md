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
one is podman (or docker) — nothing is installed on your machine except the
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
running a lab needs an engine and compose. A machine that already has podman
satisfies the first half on its own. If you already have Docker CE from
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
engine socket, and it should not be given a hole to it: access to the docker
socket is access to root on the host. The Run button is insensitive there and
says so, and the build has no embedded terminal, because the GNOME runtime does
not ship VTE. Generate the compose file and run it from a terminal instead.

### macOS (Apple silicon)

CI builds a signed, self-contained `Networking Lab.app` on every push. There are
no releases yet, so it comes from the run's artifacts: open the latest green
[CI run](https://github.com/fwilhe2/networking-lab/actions/workflows/ci.yml),
download **networking-lab-macos-arm64**, unzip it and drag the app into
`/Applications`.

The bundle carries GTK, libadwaita and their data with it — Homebrew is not
needed to *run* it, only podman is, and only to boot a lab. It is ad-hoc signed
rather than notarised, so macOS quarantines the download until you say
otherwise:

```sh
xattr -dr com.apple.quarantine "/Applications/Networking Lab.app"
```

Intel Macs are not built; `tools/build-macos-app.sh` produces the same bundle on
one if you have Homebrew.

### From source

Without a container engine, or to hack on it:

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

On macOS the dependencies come from Homebrew — `brew install meson vala gtk4
libadwaita json-glib gettext` — and the build is the same three commands. Only
the lab side has been made macOS-aware on purpose (engine discovery, the
`podman machine` hints below); the GTK build there is not covered by CI, and
there is no packaged `.app`.

## Running a lab

Booting a lab needs **podman or docker**, with **compose v2, 2.23.1 or newer** —
the generated file uses inline `configs`, which older versions cannot read.
Check with `podman compose version` or `docker compose version`. Whichever is
found first is used, **podman before docker**; set `NETLAB_ENGINE=docker` to pin
the choice on a machine that has both. `NETLAB_ENGINE` also takes an absolute
path, for an engine installed somewhere unusual.

The search is `PATH` first, then `/opt/homebrew/bin`, `/usr/local/bin` and
`/opt/podman/bin` — the last three because a windowed application does not
always inherit the `PATH` your shell has.

### Linux

`podman compose` hands the work to the same compose v2 binary docker uses, and
talks to it over the podman socket, which is not running by default:

```sh
systemctl --user start podman.socket        # --now enable to keep it
```

With docker, your user needs to be able to reach the daemon:

```sh
sudo usermod -aG docker "$USER"     # then log out and back in
```

### macOS

podman runs the containers inside a Linux VM, so that VM has to exist and be
running. compose is a separate binary that podman calls out to:

```sh
brew install podman docker-compose
podman machine init          # once
podman machine start         # after each reboot
```

Nothing is shared into the VM: the generated file carries every router's
configuration inline (that is what the compose 2.23.1 floor is for), so no
directory has to be mounted through `podman machine` for a lab to boot. The
three default images — FRR, Alpine and Python — are published for arm64, so
Apple silicon runs them natively rather than emulated.

Docker Desktop works too; its `docker` is in `/usr/local/bin`, which is
searched.

Without an engine the application still designs, generates and exports; only the
Run button is insensitive, with the reason in its tooltip — including the
command to start whatever is not running.

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

**Practising.** `EXERCISES.md` is a set of tasks for the demo topology — count the hops
without traceroute, break the netmask and recognise the symptom, pull a link and time the
OSPF recovery, replace the routing protocol with static routes. Every command in it has been
run against the demo lab.

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
lab is picked up again next time; `podman compose -p <project> down -v` (or
`docker compose …`) stops it from a terminal.

## When something does not work

- **The Run button is insensitive.** Its tooltip says why: no engine installed,
  the engine not reachable (start `podman.socket`, or add yourself to the
  `docker` group), compose older than 2.23.1, or the Flatpak sandbox.
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
