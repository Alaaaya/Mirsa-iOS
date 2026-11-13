import pathlib,subprocess
R=pathlib.Path(__file__).resolve().parents[2]
def test_tendies_view_is_exact_original():
    cur=(R/'ios-app/TendiesView.swift').read_bytes()
    old=subprocess.check_output(['git','show','3036e03^:ios-app/TendiesView.swift'],cwd=R)
    assert cur==old
def test_engine_files_unchanged_since_removal():
    for f in ('ios-app/VideoWallpaper.swift','ios-app/TendiesEngine.swift','ios-app/TendiesModel.swift'):
        assert subprocess.run(['git','diff','--quiet','3036e03^','HEAD','--',f],cwd=R).returncode==0,f
def test_tools_entry():
    T=(R/'ios-app/Apps/ToolsTab.swift').read_text()
    assert 'case .wallpapers: TendiesView()' in T
