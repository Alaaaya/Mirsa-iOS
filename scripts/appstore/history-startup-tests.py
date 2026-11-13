#!/usr/bin/env python3
"""Cold-start fatal-path regression, checks production call ordering."""
from pathlib import Path
r = Path(__file__).resolve().parents[2]
c = (r/'ios-app/AppStore/StoreClient.swift').read_text()
h = (r/'ios-app/AppStore/StorePurchaseHistory.swift').read_text()
e = (r/'ios-app/AppStore/StoreEngine.swift').read_text()
u = (r/'ios-app/Apps/AppStoreSection.swift').read_text()
history = c[c.index('    func purchaseHistory() async throws'):c.index('    private func loadAccount()')]
assert 'let historyGUID = machineGUID' in history
assert 'MirsaStoreGUIDLease.shared.run(guid: historyGUID) {' in history
assert history.index('MirsaStoreGUIDLease.shared.run') < history.index('MirsaStorePurchaseHistory.fetch(owner: owner, guid: historyGUID)')
assert '"X-Guid": guid' in h and '"X-Guid": Configuration.deviceIdentifier' not in h
lease = e[e.index('actor MirsaStoreGUIDLease'):e.index('final class ApplePackageStoreEngine')]
assert lease.index('Configuration.deviceIdentifier = guid') < lease.index('return try await operation()')
assert 'defer { busy = false }' in lease and 'while busy' in lease
assert 'self.purchases()' in u and 'MirsaPurchaseHistory' in u
print('PASS cold-launch history leases GUID before SAP/TLS, explicit account header, cache/prefetch preserved')
