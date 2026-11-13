import re,pathlib
R=pathlib.Path(__file__).resolve().parents[2]
V=(R/'ios-app/TendiesView.swift').read_text()
T=(R/'ios-app/Apps/ToolsTab.swift').read_text()
def calls(src):
    out=[];i=0
    while True:
        i=src.find('wtr(',i)
        if i<0:return out
        if src[i-1].isalnum() or src[i-1]=='_':i+=4;continue
        d=0;j=i+3
        while True:
            c=src[j]
            if c=='(':d+=1
            elif c==')':
                d-=1
                if d==0:break
            j+=1
        out.append(src[i:j+1]);i=j
def test_every_wtr_has_all_five():
    cs=[c for c in calls(V)+calls(T) if not c.startswith('wtr(_ en')]
    assert len(cs)>=8
    for c in cs:
        for k in ('de:','ckb:','kmr:'): assert k in c,c
        assert len(re.findall(r'"(?:[^"\\\\]|\\\\.)*"',c))>=5,c
def test_no_plain_tr_in_screen():
    assert not re.search(r'(?<![A-Za-z_])tr\(',V)
    assert not re.search(r'(?<![A-Za-z_])tr\(',T[T.index('wallpapers'):T.index('wallpapers')+3000]) or 'wtr("Video wallpaper"' in T
def test_wiring_and_validation():
    assert 'case .wallpapers: TendiesView()' in T
    assert 'WallpaperVideoPicker(' in V and '.fileImporter(' in V
    assert 'startAccessingSecurityScopedResource' in V and 'stopAccessingSecurityScopedResource' in V
    assert 'conforms(to: .movie)' in V and '.userCancelled' in V and '@MainActor' in V
