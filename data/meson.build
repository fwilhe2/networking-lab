desktop_file = i18n.merge_file(
        input: '@0@.desktop.in'.format(application_id),
       output: '@0@.desktop'.format(application_id),
         type: 'desktop',
       po_dir: '../po',
      install: true,
  install_dir: get_option('datadir') / 'applications',
)

desktop_file_validate = find_program('desktop-file-validate', required: false)
if desktop_file_validate.found()
  test('validate-desktop-file', desktop_file_validate,
    args: [desktop_file],
    suite: 'data',
  )
endif

metainfo_file = i18n.merge_file(
        input: '@0@.metainfo.xml.in'.format(application_id),
       output: '@0@.metainfo.xml'.format(application_id),
       po_dir: '../po',
      install: true,
  install_dir: get_option('datadir') / 'metainfo',
)

appstreamcli = find_program('appstreamcli', required: false)
if appstreamcli.found()
  test('validate-metainfo-file', appstreamcli,
    args: ['validate', '--no-net', '--explain', metainfo_file],
    suite: 'data',
  )
endif

install_data('@0@.gschema.xml'.format(application_id),
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas',
)

# Compiles the schema into the build tree so `meson devenv` can run the app
# uninstalled.
gnome.compile_schemas(depend_files: files('@0@.gschema.xml'.format(application_id)))

glib_compile_schemas = find_program('glib-compile-schemas', required: false)
if glib_compile_schemas.found()
  test('validate-gschema', glib_compile_schemas,
    args: ['--strict', '--dry-run', meson.current_source_dir()],
    suite: 'data',
  )
endif

subdir('icons')
