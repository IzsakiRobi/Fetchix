project('fetchix', 'vala', 'c', version: '1.0.0')

dependencies = [
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('gtk4'),
    dependency('libadwaita-1'),
    dependency('libsoup-3.0'),
    dependency('json-glib-1.0')
]

sources = files('fetchix.flatpak.vala')

executable('fetchix', sources, dependencies: dependencies, install: true)
