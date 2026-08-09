# The compiler and the document model, with no GTK dependency, so the whole
# thing can be unit-tested and driven headlessly. See PLAN.md.

netlab_core_sources = files(
  'model.vala',
  'ipv4.vala',
  'names.vala',
  'geometry.vala',
)

netlab_core_deps = [
  # GLib.Math maps straight onto libm, which is not pulled in implicitly.
  meson.get_compiler('c').find_library('m', required: false),
  dependency('glib-2.0',      version: '>= 2.72'),
  dependency('gobject-2.0',   version: '>= 2.72'),
  dependency('gio-2.0',       version: '>= 2.72'),
  dependency('json-glib-1.0', version: '>= 1.6'),
]

netlab_core_lib = static_library('netlab-core',
  netlab_core_sources,
  dependencies: netlab_core_deps,
  vala_header: 'netlab-core.h',
    vala_vapi: 'netlab-core.vapi',
      install: false,
)

netlab_core_dep = declare_dependency(
            link_with: netlab_core_lib,
  include_directories: include_directories('.'),
         dependencies: netlab_core_deps,
)
