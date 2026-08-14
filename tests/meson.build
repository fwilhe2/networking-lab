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

# The lab layer, in its own suite because it links netlab_lab_dep as well. It
# still needs no docker: the test writes a stub `docker` into a temporary
# directory and puts it earlier on PATH. See PLAN.md 9.1.
test('lab',
  executable('test-lab',
    files('lab.vala'),
    dependencies: [netlab_core_dep, netlab_lab_dep],
         install: false,
  ),
  suite: 'lab',
  protocol: 'tap',
  args: ['--tap'],
)

# The end-to-end lab test, in its own suite because it needs a container engine,
# pulls three images and waits for OSPF to converge. Two test setups keep it out
# of the way: the default one excludes the suite, so a plain `meson test` stays
# hermetic and fast, and `--setup engine` includes it. The script itself exits
# 77 — meson's "skipped" — when no engine or no new enough compose is around.
#
#   meson test -C _build --setup engine --suite integration --print-errorlogs
add_test_setup('default', exclude_suites: ['integration'], is_default: true)
add_test_setup('engine')

test('demo', files('lab.integration.sh'),
       args: [netlab_compile],
    depends: [netlab_compile],
      suite: 'integration',
    timeout: 900,
)
