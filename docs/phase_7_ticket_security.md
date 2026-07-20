# Phase 7 — ticket credential and scanner security

## Chosen admission model

Dunda uses the recommended **venue-local edge coordinator** model. Scanners
connect to a signed event manifest and a coordinator on the venue LAN. The
coordinator serialises admission writes and uploads an append-only audit stream
to the primary PostgreSQL service. A scanner that loses coordinator connectivity
may cryptographically verify a proof and queue it, but it must display `HOLD`
or `DEGRADED` rather than claim globally unique admission. Independent offline
scanners would otherwise be unable to guarantee uniqueness under partition.

## Protocol v2

The legacy JWT+TOTP credential is retained only for historical records and is
never accepted by `Dunda.Ticketing.Admission`. Protocol v2 has three proofs:

1. The server signs an entitlement containing the ticket/event identifiers,
   validity window, protocol version, credential epoch, and the attendee
   device's Ed25519 public key.
2. The device signs a dynamic proof over a canonical, versioned byte sequence
   containing ticket ID, event ID, 30-second time step, nonce, and public key.
3. The coordinator verifies the server entitlement, the device signature,
   validity window, manifest version, ticket status, and nonce uniqueness before
   recording admission.
4. The registered scanner device separately signs the admission envelope. A
   stolen operator bearer token without the scanner's private key cannot submit
   an admission record.

Private keys remain in the platform secure key store. Scanners receive public
verification material only. Transfers and device recovery increment the
credential epoch and mint a distinct entitlement; re-binding an already-bound
ticket requires a short-lived `ticket_credential_rebind` step-up capability.
Refunds/revocation invalidate the prior ticket before any replacement or
inventory action.

The canonical vector is [ticket_proof_v2.json](vectors/ticket_proof_v2.json).
Elixir, TypeScript, and Kotlin implementations must reproduce it byte-for-byte.

## Threat model and decisions

| Threat | Control | Residual condition |
|---|---|---|
| Screenshot/forwarded QR | Per-device Ed25519 proof, nonce, 30-second step | A stolen unlocked device can still present its live credential |
| Ticket transfer | New credential epoch and replacement entitlement | Binding/recovery requires authenticated user flow and step-up for rebind |
| Refund/revocation | Ticket status and manifest revocation state | Revocation reaches scanners only after manifest sync |
| Scanner theft | Registered device key, operator membership, revocation | LAN coordinator must reject revoked devices |
| Clock drift | ±1 time-step policy plus explicit `HOLD` state | Large drift requires operator correction |
| Multi-gate partition | Coordinator serialisation and degraded mode | No global uniqueness claim while partitioned |
| Replay | Ticket admission uniqueness plus `(ticket, nonce)` uniqueness | Queued offline records require coordinator reconciliation |

## Operational requirements

- Generate and store `SCANNER_MANIFEST_PRIVATE_KEY` and the matching
  `SCANNER_MANIFEST_PUBLIC_KEY` in a managed secret/KMS system.
- Build the Expo custom client/native scanner with the Keychain/Keystore
  adapters in `frontend/src/native`; the JS signer interface intentionally
  fails closed when no native signer is installed.
- Distribute manifests over authenticated TLS/LAN channels and verify the
  signature and validity window before accepting them.
- Provision scanners through an active organisation membership; revoke device
  keys immediately on loss or compromise.
- Monitor coordinator queue age, clock drift, duplicate proofs, rejected
  credentials, manifest age, and admission-upload lag.
- Run the cross-language vector, rooted-device, screenshot, transfer, refund,
  replay, clock-drift, and partition tests before lifting containment.

The production guarantee is therefore precise: **cryptographic authenticity is
offline-verifiable; globally unique admission is coordinator-consistent and is
not claimed during a coordinator partition.**
