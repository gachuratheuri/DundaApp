# Phase 10 — frontend reliability and secure client behaviour

The mobile/web client is now fail-closed at the trust boundary. Production
builds receive an explicit HTTPS API origin from EAS, derive REST and Phoenix
socket endpoints from that same origin, and reject missing, non-HTTPS,
credential-bearing, or path-containing origins. Emulator and demo settings are
restricted to the development profile.

## Implemented controls

- Bearer and refresh credentials use SecureStore on native platforms. Web
  credentials are memory-only because localStorage is not a secure credential
  store; a reload requires authentication again.
- Access-token expiry uses a single-flight refresh attempt with a bounded
  timeout. Concurrent 401 responses cannot hang indefinitely or trigger a
  refresh storm. Failed refresh clears the session and emits a session-expired
  event.
- Critical quote, checkout, and payment-status responses are validated before
  the UI treats them as authoritative. Checkout sends only `quote_id`, phone,
  and an idempotency key; price, quantity, beneficiary, and user identity are
  not client authority.
- Payment polling distinguishes confirmed, failed, manual-review, and unknown
  states. A timeout is displayed as “still processing”, never as a successful
  purchase and never as permission to retry blindly.
- Ticket credentials are not cached in AsyncStorage. Offline ticket views do
  not fabricate tickets or QR proofs; the wallet displays an explicit
  unavailable state until server data is revalidated.
- Production event routes fetch by server ID and do not fall back to bundled
  mock events. Development-only demo data is visibly labelled.
- Resale uses the server contract field `asking_price_kes`, derives the maximum
  from the immutable server-provided face value, and rejects invalid prices
  before submission.
- Private ticket routes are guarded by an access-token check. Organiser links
  derive their origin from the validated API configuration rather than a
  localhost literal.

## Required backend/build contract

The API must expose a rotating `/api/auth/refresh` endpoint returning a new
short-lived access token and, where applicable, a rotated refresh token. Until
that endpoint is deployed, the client deliberately fails closed and logs the
user out on access-token expiry. EAS preview and production profiles must point
to real HTTPS services and must not enable demo data.

The frontend verification baseline is:

```text
npm run typecheck
npm run lint
npx expo config --type public
```

Native device tests must additionally cover concurrent 401s, refresh-token
reuse, revoked sessions, offline wallet behaviour, slow provider responses,
and production builds with an absent or non-HTTPS API origin.
