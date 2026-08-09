starter_sources = files(
  'config.vapi',
  'main.vala',
  'application.vala',
  'window.vala',
  'preferences-dialog.vala',
)

starter_deps = [
  dependency('glib-2.0',      version: '>= 2.72'),
  dependency('gobject-2.0',   version: '>= 2.72'),
  dependency('gio-2.0',       version: '>= 2.72'),
  dependency('gtk4',          version: '>= 4.12'),
  dependency('libadwaita-1',  version: '>= 1.5'),
]

gresource_xml = files('starter.gresource.xml')

starter_resources = gnome.compile_resources('starter-resources',
  gresource_xml,
  source_dir: meson.current_source_dir(),
      c_name: 'starter',
)

executable('starter',
  starter_sources, starter_resources, config_h,
     dependencies: starter_deps,
       vala_args: [
         # Lets valac resolve and type-check [GtkTemplate]/[GtkChild]/[GtkCallback].
         '--gresources=' + meson.current_source_dir() / 'starter.gresource.xml',
       ],
          install: true,
      install_dir: get_option('bindir'),
)
