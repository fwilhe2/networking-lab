# Everything that touches the outside world: docker, subprocesses, the lab
# directory. Still GTK-free, so the lifecycle is unit-testable against a stub
# docker from a plain test binary. See PLAN.md 9.1.

netlab_lab_sources = files(
  'paths.vala',
  'engine.vala',
  'compose.vala',
  'session.vala',
)

netlab_lab_lib = static_library('netlab-lab',
  netlab_lab_sources,
  dependencies: [netlab_core_dep],
  vala_header: 'netlab-lab.h',
    vala_vapi: 'netlab-lab.vapi',
      install: false,
)

netlab_lab_dep = declare_dependency(
            link_with: netlab_lab_lib,
  include_directories: include_directories('.'),
         dependencies: [netlab_core_dep],
)
