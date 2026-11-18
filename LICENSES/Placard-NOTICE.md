The local NeoSpring mechanism was studied in frs0n/placard, revision
7f470dd0242f9d69ea5ad17e521566487706c891, placard/NeoSpringView.swift.
Source https://github.com/frs0n/placard
Upstream license is GNU GPL version 3, reproduced in Placard-GPL-3.0.txt.
Mechanism credits are rooootdev, skadz108 and neonmodder123.

The current MirsaWallpaperRespringView.swift copies the independently authored
PB Probe v26 c1eaf7a view, renaming only its Swift type and provenance comments.
Its local iframe document, native configuration, navigation coordinator and
teardown match Probe v26 exactly. The caller uses Probe's immediate confirmed
full-screen cover, retained presentation model and explicit stop button, not
the earlier Placard-style delayed overlay. Mirsa retains its existing localized
confirmation, standalone action and app-private evidence writer.
No network, native file bridge or automatic relaunch trigger is added.
