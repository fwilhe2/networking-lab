# Everything that touches the outside world: the container engine, subprocesses,
# the lab directory. Still GTK-free, so the lifecycle is unit-testable against a
# stub engine from a plain test binary. See PLAN.md 9.1.

netlab_lab_sources = files(
  'paths.vala',
  'engine.vala',
  'compose.vala',
  'session.vala',
)

# The only platform-dependent thing in the library: what to tell someone whose
# podman is not answering — `podman machine start` on macOS, the socket unit on
# Linux. One define, read in one place, in engine.vala's hint ().
netlab_lab_vala_args = []
if host_machine.system() == 'darwin'
  netlab_lab_vala_args += '--define=MACOS'
endif

netlab_lab_lib = static_library('netlab-lab',
  netlab_lab_sources,
  dependencies: [netlab_core_dep],
    vala_args: netlab_lab_vala_args,
  vala_header: 'netlab-lab.h',
    vala_vapi: 'netlab-lab.vapi',
      install: false,
)

netlab_lab_dep = declare_dependency(
            link_with: netlab_lab_lib,
  include_directories: include_directories('.'),
         dependencies: [netlab_core_dep],
)
