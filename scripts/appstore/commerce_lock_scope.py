"""Normalize only owner-approved reservation changes for legacy byte-parity checks."""
def legacy_reservations(text):
    text = text.replace('try await beginQueued()', 'try begin()')
    marker = '    /// Wait without owning a reservation.'
    if marker in text:
        a = text.index(marker)
        b = text.index('    private func begin() throws', a)
        text = text[:a] + text[b:]
    a = text.index('    func versionMetadata(')
    b = text.index('\n    }', a)
    body = text[a:b]
    body = body.replace('        try prepare()\n        let run = generation\n        try check(run)',
                        '        let run = try begin(); defer { busy = false }')
    body = body.replace('        return entries', '        try persist(owner)\n        return entries')
    return text[:a] + body + text[b:]
