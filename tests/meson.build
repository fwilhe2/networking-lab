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
