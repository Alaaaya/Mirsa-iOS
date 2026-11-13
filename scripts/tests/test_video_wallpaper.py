import re,pathlib
R=pathlib.Path(__file__).resolve().parents[2]
def test_video_wallpaper_wired():
    tools=(R/'ios-app/Apps/ToolsTab.swift').read_text()
    v=(R/'ios-app/TendiesView.swift').read_text()
    assert 'case .wallpapers: TendiesView()' in tools
    assert 'WallpaperVideoPicker(' in v and '.fileImporter(' in v
    assert 'startAccessingSecurityScopedResource' in v and 'stopAccessingSecurityScopedResource' in v
    for k in ('ckb:','kmr:'):
        assert v.count(k)>=4
