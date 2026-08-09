networking_lab_sources = files(
  'config.vapi',
  'main.vala',
  'application.vala',
  'window.vala',
  'preferences-dialog.vala',
)

networking_lab_deps = [
  dependency('glib-2.0',      version: '>= 2.72'),
  dependency('gobject-2.0',   version: '>= 2.72'),
  dependency('gio-2.0',       version: '>= 2.72'),
  dependency('gtk4',          version: '>= 4.12'),
  dependency('libadwaita-1',  version: '>= 1.5'),
]

gresource_xml = files('networking-lab.gresource.xml')

networking_lab_resources = gnome.compile_resources('networking-lab-resources',
  gresource_xml,
  source_dir: meson.current_source_dir(),
      c_name: 'networking_lab',
)

executable('networking-lab',
  networking_lab_sources, networking_lab_resources, config_h,
     dependencies: networking_lab_deps,
       vala_args: [
         # Lets valac resolve and type-check [GtkTemplate]/[GtkChild]/[GtkCallback].
         '--gresources=' + meson.current_source_dir() / 'networking-lab.gresource.xml',
       ],
          install: true,
      install_dir: get_option('bindir'),
)
