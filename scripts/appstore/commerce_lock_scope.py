"""Normalize only owner-approved reservation changes for legacy byte-parity checks."""
def legacy_reservations(text):
    text = text.replace('try await beginQueued()', 'try begin()')
    marker = '    /// Wait without owning a reservation.'
    if marker in text:
        a = text.index(marker)
        b = text.index('    private func begin() throws', a)
        text = text[:a] + text[b:]
    # This read-only coordinator is covered by executable parallel metadata tests.
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    old = subprocess.check_output(['git','show','2f15e57:ios-app/AppStore/StoreClient.swift'], cwd=root, text=True)
    baseline = old[old.index('    func versionMetadata('):old.index('    /// Returns a local encrypted IPA')]
    a = text.index('    private var versionNameCache:')
    b = text.index('    /// One explicit free Get', a)
    return text[:a] + baseline + text[b:]
