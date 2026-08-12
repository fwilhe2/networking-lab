# RPM packaging for Fedora 44, the current release. Fedora carries GTK 4.20,
# libadwaita 1.8, Vala 0.56 and VTE 0.82 there, all above the floors in
# meson.build.
#
# Build it with tools/build-rpm.sh, which runs rpmbuild inside a Fedora
# container so the host needs nothing but docker.

Name:           networking-lab
Version:        0.1.0
Release:        1%{?dist}
Summary:        Design and run container network labs

License:        GPL-3.0-or-later
URL:            https://github.com/fwilhe2/networking-lab
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  meson >= 1.0.0
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  vala
BuildRequires:  pkgconfig(glib-2.0) >= 2.72
BuildRequires:  pkgconfig(gobject-2.0) >= 2.72
BuildRequires:  pkgconfig(gio-2.0) >= 2.72
BuildRequires:  pkgconfig(json-glib-1.0) >= 1.6
BuildRequires:  pkgconfig(gtk4) >= 4.12
BuildRequires:  pkgconfig(libadwaita-1) >= 1.5
BuildRequires:  pkgconfig(vte-2.91-gtk4)
BuildRequires:  gettext
# The data test suite shells out to both of these, so they are needed for
# %%check as well as for the usual packaging validation.
BuildRequires:  desktop-file-utils
BuildRequires:  appstream

Requires:       adwaita-icon-theme
Requires:       hicolor-icon-theme

# Docker is located at run time and done without: the designer, the compiler
# and the export all work with no container runtime present, and the run
# controls explain why they are insensitive. Hence Recommends, and hence no
# hard dependency on a particular engine — moby-engine and docker-ce both
# provide `docker`, and podman's docker shim is a third possibility.
Recommends:     docker-compose

%description
Networking Lab draws a network of routers, switches, PCs and servers, compiles
it to a docker compose file and boots it, so a topology can be sketched,
started and logged into without leaving the window.

Routers run FRR, giving a vtysh CLI reachable from an embedded terminal;
switches become docker bridge networks, and the addressing, gateways and
point-to-point subnets are worked out from the drawing.

The compose file it produces is an ordinary one, so a lab is equally usable
from a terminal, in CI, or on a machine that has never seen this application.

%prep
%autosetup

%build
%meson
%meson_build

%install
%meson_install

%check
# The data, core and lab suites. The integration suite needs docker and is
# excluded by the default test setup in tests/meson.build, so this never tries
# to start containers.
%meson_test

%files
%license LICENSE
%doc README.md
%{_bindir}/networking-lab
%{_datadir}/applications/io.github.fwilhe2.NetworkingLab.desktop
%{_datadir}/glib-2.0/schemas/io.github.fwilhe2.NetworkingLab.gschema.xml
%{_datadir}/icons/hicolor/scalable/apps/io.github.fwilhe2.NetworkingLab.svg
%{_datadir}/icons/hicolor/symbolic/apps/io.github.fwilhe2.NetworkingLab-symbolic.svg
%{_metainfodir}/io.github.fwilhe2.NetworkingLab.metainfo.xml

# No %%find_lang: po/LINGUAS is empty, so nothing installs into %%{_datadir}/locale.
# Adding the first translation means adding %%find_lang here and %%{name}.lang to
# %%files, or rpmbuild will fail on unpackaged files.

%changelog
* Wed Aug 12 2026 Florian Wilhelm <fwilhelm.wgt@gmail.com> - 0.1.0-1
- Initial package.
