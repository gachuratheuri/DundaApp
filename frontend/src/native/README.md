# Gate scanner native boundary

`GateScannerActivity.kt` is the protocol boundary for the dedicated Android
scanner/custom client. Hardware adapters (DataWedge, Zebra, Honeywell, or
camera) must call `onBarcodeScanned`; they cannot bypass `GateScannerSession`,
`ManifestVerifier`, or `TicketProofVerifier`. The signed application must
provision a scanner device key with `DeviceKeyStore`, install a signed and
time-bounded event manifest through `GateScannerSession.installManifest`, and
submit a scanner-signed admission envelope to `/api/scanner/admissions`.

The JavaScript wallet uses the same canonical proof bytes through the injected
`DeviceSigner` interface. No JS or AsyncStorage fallback is permitted for
private key material. A build without the native signer displays an inactive
credential and cannot generate an admission QR.
