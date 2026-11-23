# SerStars/Nugget-Wallpapers rights review
Date checked: 2026-11-22
Scope: public repo and official project page; research only. No files or feature code edited.

## Finding
The repo is public and has a usable JSON catalog, but permission for an independent third-party app to copy/catalog the manifest, hotlink previews, or provide in-app downloads is **not established by the materials reviewed**. Do not treat “publicly accessible” or the repository-wide GPL-3.0 label as blanket artwork permission. Recommendation: hold integration of artwork previews and in-app source downloads until SerStars and, where needed, individual creators confirm those uses. Safest fallback before permission is an outbound link to the official Cowabunga wallpaper page/repository, without embedding/hotlinking artwork or presenting the files as Mirsa-hosted.

## Sources and exact catalog URLs
The repository describes itself as “The official wallpaper collection repo for Cowabun.ga/Wallpapers!” and links the official page. Root files include LICENSE, README, CONTRIBUTING, and four JSON manifests:
- Custom: https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/main/wallpapers-custom.json (111 entries)
- Apple: https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/main/wallpapers-apple.json (32 entries)
- Pass themes: https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/main/wallpapers-passthemes.json (27 entries)
- Templates: https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/main/wallpapers-template.json (3 entries)

Total in those four manifests: 173 entries. Each manifest carries relative asset paths; the URL base used by the official site is the repo's raw GitHub path. Example from custom catalog, “Cipher” by @mightycooldude12:
Manifest: https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/main/wallpapers-custom.json
Package: https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/main/wallpapers/custom/Cipher.tendies
Preview: https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/main/previews/custom/gifs/Cipher.gif
GitHub file pages checked and present: https://github.com/SerStars/Nugget-Wallpapers/blob/main/wallpapers/custom/Cipher.tendies and https://github.com/SerStars/Nugget-Wallpapers/blob/main/previews/custom/gifs/Cipher.gif. The official site itself renders the preview and links its download to the same raw repo asset.

Official site: https://cowabun.ga/wallpapers
Repository: https://github.com/SerStars/Nugget-Wallpapers

## License and terms evidence
- README says “LICENSE: GPL-3.0”: https://github.com/SerStars/Nugget-Wallpapers/blob/main/README.md
- Root GPL-3.0 license: https://github.com/SerStars/Nugget-Wallpapers/blob/main/LICENSE
- The repo page identifies GPL-3.0 as the repository license. This is a repo-level assertion, with no per-entry license field in the manifests.
- CONTRIBUTING directs submitters to contribute their own wallpaper and says “Copyrighted wallpapers without permission” are not accepted and “Make sure you have the right to share”: https://github.com/SerStars/Nugget-Wallpapers/blob/main/CONTRIBUTING.md
- The official Cowabunga page currently displays catalog previews, creator labels, and download links itself. The page/repo text reviewed gives no explicit third-party app/API reuse or hotlink terms and no explicit permission for other apps to do the same.
- Catalog entries name third-party properties and artwork (examples include Super Mario Bros., Frieren, Animal Crossing, Playboi Carti, and Zelda). Thus a blanket assumption that every uploader has cleared all underlying art rights is unsafe. The contribution rule is a submission requirement, not item-by-item proof or an independent license/authorization to Mirsa.

## Attribution and no-rehost
The custom manifest exposes an authors string (examples include @mightycooldude12 and @c4ndyf1sh), but provides neither a standardized creator profile URL nor per-item license/permission metadata. Attribution could be displayed verbatim with a link to the upstream repo/item, but attribution alone does not establish permission.

If express permission is obtained, a low-risk technical arrangement would keep manifests, previews, and .tendies files on upstream GitHub; attribute the listed creator and Nugget-Wallpapers, link back to the source, and have the app fetch the original asset directly for the user's existing import flow. Do not mirror/cache/rehost previews or packages. Confirm separately whether hotlinking previews is allowed, because the official site's own embedding does not itself authorize another app to embed them.

## Recommendation
Do not approve broad Mirsa catalog integration based solely on the GPL-3.0 badge. Ask SerStars in writing whether Mirsa may consume and display the manifests, display/hotlink each entry's preview, and link/download .tendies or other files directly from the repo for user-initiated import. Ask whether that permission covers the catalog as a whole or only works SerStars controls, and what attribution is required. For third-party artwork, require a clear representation that contributors have authorized these specific third-party app uses, or obtain permission item-by-item. Until answered, use only an outbound link to the official catalog page/repository; no artwork previews, in-app package downloads, or rehosting.
