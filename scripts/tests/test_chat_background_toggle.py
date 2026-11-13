import pathlib
S=(pathlib.Path(__file__).resolve().parents[2]/'ios-app/Apps/ForgeChat.swift').read_text()
def test_default_is_original_gradient():
    assert '@AppStorage(MirsaChatBackground.key) private var blackChatBackground = false' in S
    assert 'if blackChatBackground { Color.black' in S and 'AuroraBackground()' in S
def test_persist_key_unique_and_toggle():
    assert S.count('mirsa.chat.blackBackground.v1')==1 and 'blackChatBackground.toggle()' in S
def test_five_labels_and_hit_target():
    for k in ('.english','.german','.arabic','.kurmanji','.sorani'): assert 'case '+k+': return on' in S
    assert 'frame(width: 28, height: 28)' in S and 'frame(width: 44, height: 44)' in S
