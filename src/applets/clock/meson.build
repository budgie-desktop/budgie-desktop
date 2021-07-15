# Clock Applet build

gnome = import('gnome')

applet_clock_dir = applets_dir + '.clock'

custom_target('plugin-file-clock',
    input : 'ClockApplet.plugin.in',
    output : 'ClockApplet.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : applet_clock_dir)

gresource = join_paths(meson.current_source_dir(), 'plugin.gresource.xml')

# Compile the assets into the binary
applet_clock_resources = gnome.compile_resources(
    'clock-applet-resources',
    gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_Clock',
)

applet_clock_sources = [
    'ClockApplet.vala',
    applet_clock_resources,
]


shared_library(
    'clockapplet',
    applet_clock_sources,
    dependencies: [
        libplugin_vapi,
        dep_gtk3,
        dep_peas,
        link_libplugin,
    ],
    vala_args: [
        '--pkg', 'gtk+-3.0',
        '--pkg', 'glib-2.0',
        '--pkg', 'gio-unix-2.0',
        '--pkg', 'libpeas-1.0',
        # Make gresource work
        '--target-glib=2.38',
        '--gresources=' + gresource,
    ],
    install: true,
    install_dir: applet_clock_dir,
)

install_data(
    'com.solus-project.clock.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)