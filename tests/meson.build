# Unit tests for the core library, in suite `core`. They deliberately do not
# depend on GTK — see PLAN.md.

core_tests = [
  'model',
  'ipv4',
  'names',
  'geometry',
]

foreach name : core_tests
  test(name,
    executable('test-@0@'.format(name),
      files('@0@.vala'.format(name)),
      dependencies: [netlab_core_dep],
           install: false,
    ),
    suite: 'core',
    protocol: 'tap',
    args: ['--tap'],
  )
endforeach
