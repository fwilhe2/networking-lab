networking_lab_sources = files(
  'main.vala',
  'application.vala',
  'document.vala',
  'palette.vala',
  'properties.vala',
  'window.vala',
  'canvas.vala',
  'preferences-dialog.vala',
)

networking_lab_deps = [
  netlab_core_dep,
  dependency('gtk4',         version: '>= 4.12'),
  dependency('libadwaita-1', version: '>= 1.5'),
]

gresource_xml = files('networking-lab.gresource.xml')

networking_lab_resources = gnome.compile_resources('networking-lab-resources',
  gresource_xml,
  source_dir: meson.current_source_dir(),
      c_name: 'networking_lab',
)

executable('networking-lab',
  networking_lab_sources, config_vapi, networking_lab_resources, config_h,
     dependencies: networking_lab_deps,
       vala_args: [
         # Lets valac resolve and type-check [GtkTemplate]/[GtkChild]/[GtkCallback].
         '--gresources=' + meson.current_source_dir() / 'networking-lab.gresource.xml',
       ],
          install: true,
      install_dir: get_option('bindir'),
)
