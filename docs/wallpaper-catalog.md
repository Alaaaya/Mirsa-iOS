# Wallpaper catalog sources

Catalog-only experimental feature. No bundled third-party feeds or artwork. Add a trusted HTTPS JSON feed in Wallpapers > Wallpaper sources. Only the last entered URL is saved locally. Loading another source replaces the current catalog, it does not import wallpapers.

Schema (all fields required, size is exact downloaded byte count):
```json
{
  "name": "My wallpapers",
  "author": "Creator",
  "wallpapers": [{
    "name": "Original artwork",
    "author": "Creator",
    "preview": "https://example.com/preview.png",
    "category": "Abstract",
    "size": 12345,
    "download": "https://example.com/original.tendies"
  }]
}
```

Limits: 1 MiB JSON, 200 entries, 32 MiB per file, 2 MiB preview, 24 million input pixels, 640 px decoded thumbnail. Preview downloads require a tap. Requests use ephemeral sessions with no cookies, credential store, cache, or redirects. HTTPS only, port 443 only, no userinfo/fragments, local hostnames and numeric IP literals rejected. DNS names are not a guarantee of public addressing: a source operator can control DNS; only load trusted sources. This is a client-side reader, not a server proxy.

Exact-byte-count downloads must have ZIP magic. This is not a compatibility or archive safety certification. Archives are never extracted, interpreted, imported or installed by this feature. ShareSheet is the existing export/open-in surface. Export paths are randomized temporary directories, not feed filenames; files are removed after share dismissal. No Drift integration, device access, privileged operations or changes to the existing apply flow.

Tests use generated synthetic example.com metadata and do not fetch or redistribute artwork. Five locales use the existing AppLanguage values, including Kurmanji and Sorani.
