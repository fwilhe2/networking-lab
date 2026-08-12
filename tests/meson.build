# Unit tests for the core library, in suite `core`. They deliberately do not
# depend on GTK — see PLAN.md.

core_tests = [
  'model',
  'ipv4',
  'names',
  'geometry',
  'normalize',
  'derive',
  'validate',
  'compile',
  'edit',
]

foreach name : core_tests
  test(name,
    executable('test-@0@'.format(name),
      files('@0@.vala'.format(name), 'helpers.vala'),
      dependencies: [netlab_core_dep],
           install: false,
    ),
    suite: 'core',
    env: { 'NETLAB_TEST_DATA': meson.current_source_dir() / 'data' },
    protocol: 'tap',
    args: ['--tap'],
  )
endforeach

# The end-to-end lab test, in its own suite because it needs docker, pulls three
# images and waits for OSPF to converge. Two test setups keep it out of the way:
# the default one excludes the suite, so a plain `meson test` stays hermetic and
# fast, and `--setup docker` includes it. The script itself exits 77 — meson's
# "skipped" — when docker or a new enough compose plugin is missing.
#
#   meson test -C _build --setup docker --suite integration --print-errorlogs
add_test_setup('default', exclude_suites: ['integration'], is_default: true)
add_test_setup('docker')

test('lab', files('lab.integration.sh'),
       args: [netlab_compile],
    depends: [netlab_compile],
      suite: 'integration',
    timeout: 900,
)
