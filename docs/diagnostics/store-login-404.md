# 2.3 authentication 404 candidate
Reference protocol studied independently from mengangs/ipadn at 6adae1f, not copied.
Apple bag fetched without credentials advertises native auth under urlBag.
The reference uses that native URL unchanged; GUID is in the signed plist.
Mirsa previously added a GUID query to every auth endpoint. Native requests now preserve the advertised URL/query; legacy MZFinance retains its normalized slash and GUID query suffix.
Use Configurator 2.21 rather than 2.17, matching the on-device protocol generation. Redirects still retain POST, signed plist, cookies and Apple's selected pod; legacy redirected paths are normalized.
Offline request regressions assert URL, method, UA, plist content type, exact six fields and password+2FA.
This corrects observed protocol differences, not proof of the owner's 404 cause. No password or real account used, and no device login verified. Store AMD provisioning remains a separate known gap.
