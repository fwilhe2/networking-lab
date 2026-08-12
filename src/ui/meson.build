networking_lab_sources = files(
  'main.vala',
  'application.vala',
  'document.vala',
  'palette.vala',
  'properties.vala',
  'window.vala',
  'canvas.vala',
  'generate-dialog.vala',
  'lab-controller.vala',
  'terminal.vala',
  'shortcuts-dialog.vala',
  'preferences-dialog.vala',
)

networking_lab_deps = [
  netlab_core_dep,
  netlab_lab_dep,
  dependency('gtk4',         version: '>= 4.12'),
  dependency('libadwaita-1', version: '>= 1.5'),
]

networking_lab_vala_args = [
  # Lets valac resolve and type-check [GtkTemplate]/[GtkChild]/[GtkCallback].
  '--gresources=' + meson.current_source_dir() / 'networking-lab.gresource.xml',
]

# VTE is optional on purpose. The GNOME 50 runtime does not carry
# vte-2.91-gtk4, and the Flatpak cannot reach the docker socket anyway
# (PLAN 9.5), so a build without it produces a designer that says it has no
# terminal rather than a build failure. Everything conditional lives behind
# HAVE_VTE inside src/ui/terminal.vala.
#
# Note the floor: vte-2.91-gtk4 requires gtk4 >= 4.14 through pkg-config, above
# this project's own 4.12. On an older GTK the dependency simply is not found,
# which is the intended outcome rather than a configure error.
vte_dep = dependency('vte-2.91-gtk4', version: '>= 0.72', required: false)

if vte_dep.found()
  networking_lab_deps += vte_dep
  networking_lab_vala_args += '--define=HAVE_VTE'
else
  message('vte-2.91-gtk4 not found — building without the embedded terminal')
endif

gresource_xml = files('networking-lab.gresource.xml')

networking_lab_resources = gnome.compile_resources('networking-lab-resources',
  gresource_xml,
  source_dir: meson.current_source_dir(),
      c_name: 'networking_lab',
)

executable('networking-lab',
  networking_lab_sources, config_vapi, networking_lab_resources, config_h,
     dependencies: networking_lab_deps,
       vala_args: networking_lab_vala_args,
          install: true,
      install_dir: get_option('bindir'),
)
