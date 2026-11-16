MirsaWallpaperRespringView.swift contains the local NeoSpring WebKit document
adapted from frs0n/placard, revision 7f470dd0242f9d69ea5ad17e521566487706c891,
placard/NeoSpringView.swift. Source https://github.com/frs0n/placard

Upstream license is GNU GPL version 3, reproduced in Placard-GPL-3.0.txt.
NeoSpring mechanism credits are rooootdev, skadz108 and neonmodder123.
Mirsa changes retain the local nonpersistent WebKit route and add UTF-8 metadata,
a bounded persistent evidence callback and navigation/lifetime diagnostics.
The confirmed UI action uses Placard's 250ms preparing/respringing sequence.
No network, native file bridge or automatic relaunch trigger is added.
