#!/usr/bin/env python3
"""Compile and exercise the production public-chart adapter, offline."""
from pathlib import Path
import subprocess, tempfile
r=Path(__file__).resolve().parents[2]
source=(r/'ios-app/AppStore/StoreDiscovery.swift').read_text()
tests=r'''
@main struct Tests {
    static func main() throws {
        let countryURL = try StoreDiscovery.url(country:"TR",genre:nil)
        precondition(countryURL.absoluteString == "https://itunes.apple.com/tr/rss/topfreeapplications/limit=12/json")
        for genre in [6014,6007,6017,6011,6016,6013] {
            let u = try StoreDiscovery.url(country:"de",genre:genre)
            precondition(u.path.contains("/genre=\(genre)/"))
        }
        for cc in ["","tur","../us","u1","üa","us?","US/"] {
            do { _ = try StoreDiscovery.url(country:cc,genre:nil); fatalError("accepted country") } catch {}
        }
        do { _ = try StoreDiscovery.url(country:"tr",genre:9999); fatalError("accepted genre") } catch {}
        func data(country: String = "tr", genre: Int? = nil, entries: Any = []) throws -> Data {
            let url = try StoreDiscovery.url(country:country,genre:genre)
            return try JSONSerialization.data(withJSONObject:["feed":["id":["label":url.absoluteString],"entry":entries]])
        }
        let app: [String:Any] = ["id":["attributes":["im:id":"123"]],"im:name":["label":"Real fixture"],
            "im:image":[["label":"https://is1-ssl.mzstatic.com/icon.png"]]]
        let payload = try data(entries:[app,app,["id":["attributes":["im:id":"-1"]]]])
        let decoded = try StoreDiscovery.decode(payload,country:"tr",genre:nil)
        precondition(decoded.count == 1 && decoded[0].id == 123 && decoded[0].name == "Real fixture")
        precondition(decoded[0].artworkURL?.host == "is1-ssl.mzstatic.com")
        let single = try StoreDiscovery.decode(data(entries:app),country:"tr",genre:nil)
        precondition(single == decoded)
        let empty = try StoreDiscovery.decode(data(),country:"tr",genre:nil)
        precondition(empty.isEmpty)
        for (cc,genre) in [("de",nil),("tr",6014)] as [(String,Int?)] {
            do { _ = try StoreDiscovery.decode(payload,country:cc,genre:genre); fatalError("mislabeled chart") } catch {}
        }
        for malformed in [Data("{}".utf8),Data("invalid".utf8),Data(repeating:32,count:2_000_001)] {
            do { _ = try StoreDiscovery.decode(malformed,country:"tr",genre:nil); fatalError("bad feed") } catch {}
        }
        var hostile = app
        hostile["im:image"] = [["label":"http://evil.invalid/a"],["label":"https://mzstatic.com.evil.invalid/a"]]
        let noImage = try StoreDiscovery.decode(data(entries:[hostile]),country:"tr",genre:nil)
        precondition(noImage[0].artworkURL == nil)
        print("PASS production chart URLs, six genres, selected-country/genre identity, dedup, singleton/empty, malformed/oversize and artwork safety")
    }
}
'''
view=(r/'ios-app/Apps/AppStoreAccountView.swift').read_text()
assert '.task(id: discoveryKey)' in view
assert 'key == discoveryKey' in view and 'Task.checkCancellation()' in view
assert 'chartLoadedKey != discoveryKey' in view
assert 'StoreRecentSearches.removing(recent, from: recentSearchData)' in view
assert 'let country = effectiveCountry' in view and 'client.search(term: String(chart.id), country: country' in view
assert 'accountAvailable.formUnion(available)' in view
assert '.onSubmit { search() }' in view
assert 'selected = app' in view
assert 'config.httpCookieStorage = nil' in source and 'config.urlCache = nil' in source
with tempfile.TemporaryDirectory(prefix='store-discovery-') as d:
    p=Path(d)/'test.swift';p.write_text(source+tests)
    subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(p),'-o',str(Path(d)/'test')],check=True)
    subprocess.run([str(Path(d)/'test')],check=True,timeout=20)
