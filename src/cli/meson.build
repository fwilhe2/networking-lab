# Headless driver for the core library. Not installed while it is still a stub;
# it earns its keep in phase 4, where it produces the golden compose file.

executable('netlab-compile',
  files('netlab-compile.vala'), config_vapi, config_h,
  dependencies: [netlab_core_dep],
       install: false,
)
