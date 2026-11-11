# Store AMD authentication correction

The tested 3302b1c build posted a Configurator-shaped payload to the bag's
account-service /auth/v1/native endpoint with an ActionSignature. The device
returned HTTP 200 with customerMessage AMD-Action::SP. This is not evidence
of a verification-code challenge and must not be interpreted as one.

Use the Configurator commerce service /auth/v1/native/fast/ (including the
trailing slash), Configurator/2.17 UA and plist content type. That route
does not need SAP/AMD/anisette headers. Retain signing only for legacy
endpoints. No third-party anisette servers or secrets are introduced.

Protocol evidence (read as documentation, no implementation copied)
https://github.com/majd/ipatool/issues/485
k1rp14, June 10 2026, and ricky0603, June 12 2026 describe successful
Configurator fast authentication without signatures, and password+code
with attempt=2 when MZFinance.BadLogin.Configurator_message is returned.

Existing code-entry UI and challenge classification are retained. AMD
itself remains an authentication error, never a fake two-factor prompt.
New offline request tests cover route normalization, no signer dependency,
absence of ActionSignature, UA and both initial and code-appended bodies.
Actual owner-device authentication remains to be tested after IPA delivery.
