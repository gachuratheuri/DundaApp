# Data inventory and classification

This is the authoritative map from every personal-data-bearing column in the
schema (`backend/priv/repo/migrations/`, cross-checked against the live Ecto
schemas in `backend/lib/dunda/**/*.ex`) to its category, sensitivity,
encryption status, lawful basis, purpose, retention rule, and processor. It is
the artifact `docs/phase_3_compliance_continuity.md:53` and
`docs/phase_11_privacy_governance.md` refer to as "the data inventory." Every
row was verified against the actual schema file at the time of writing — this
is not an aspirational document. Re-run the audit in
`docs/phase_11_privacy_governance.md` § "Keeping this document honest"
whenever a migration adds or removes a personal-data column.

Categories follow the plan's taxonomy: **Identity**, **Contact**, **Payment**,
**Ticket**, **Location**, **Device**, **Analytics**.

## Legend

- **Encryption**: `AES-256-GCM` (`Dunda.Encrypted.Binary`, via `Dunda.Vault`), `HMAC blind index` (`Dunda.Hashed.HMAC`, deterministic, lookup-only), `bcrypt` (one-way, password), `plaintext` (not encrypted — sensitivity and rationale given), `n/a` (not personal data).
- **Lawful basis** (Kenya ODPC / GDPR-aligned): `contract` (necessary to perform the ticket-purchase contract), `legal obligation` (financial/tax/audit retention), `legitimate interest` (fraud prevention, security, service operation), `consent` (only where [[phase_11_privacy_governance]] §11.6 consent records apply).

## `users` (`Dunda.Accounts.User`, `backend/lib/dunda/accounts/user.ex`)

| Field | Category | Sensitivity | Encryption | Lawful basis | Purpose | Retention |
|---|---|---|---|---|---|---|
| `phone_msisdn` | Contact | High | AES-256-GCM | contract | M-Pesa checkout, account identity | Retained with account; pseudonymised on erasure (`Dunda.Accounts.Privacy.anonymise_user/1`) |
| `phone_msisdn_hash` | Contact (derived) | High | HMAC blind index | contract | Deterministic lookup for phone-based login/dedup | Same as `phone_msisdn` |
| `device_fingerprint` | Device | Medium | AES-256-GCM | legitimate interest | Fraud/abuse detection | Pseudonymised on erasure |
| `email` | Identity/Contact | Medium | plaintext | contract | Email/OAuth login, receipts | Pseudonymised (replaced with a `deleted-<uuid>@dunda.invalid` sentinel) on erasure |
| `name` | Identity | Medium | plaintext | contract | Display name, ticket holder name | Replaced with `"Deleted user"` on erasure |
| `avatar_url` | Identity | Low | plaintext | contract | Profile display | Cleared on erasure |
| `auth_provider` / `provider_uid` | Identity | Medium | plaintext | contract | OAuth identity linkage | `provider_uid` cleared on erasure |
| `hashed_password` | Identity (credential) | High | bcrypt (one-way) | contract | Email/password login | Cleared on erasure |
| `kyc_status` | Identity | Medium | plaintext | legal obligation | KYC/AML posture | Retained (compliance record) |
| `confirmed_at` | Analytics | Low | plaintext | contract | Email verification state | Cleared on erasure |

## `orders` (`Dunda.Billing.Order`) and `payment_intents` (`Dunda.Checkout.PaymentIntent`)

| Field | Category | Sensitivity | Encryption | Lawful basis | Purpose | Retention |
|---|---|---|---|---|---|---|
| `phone` | Contact | High | **`phone_encrypted`, AES-256-GCM as of Phase 11 §11.2** (was plaintext) | contract | STK push / checkout contact | Never automated-delete (financial evidence); pseudonymisation is out of scope for financial rows per `docs/phase_3_compliance_continuity.md` retention table |
| `amount_cents`, `currency`, `quantity` | Payment | Medium | plaintext | contract, legal obligation | Settlement amount | Never automated-delete |
| `merchant_reference`, `order_tracking_id`, `provider_checkout_id`, `provider_receipt` | Payment | Medium | plaintext | legal obligation | Provider correlation, financial audit | Never automated-delete |
| `idempotency_key` | Analytics | Low | plaintext | contract | Duplicate-submission protection | Never automated-delete |
| `redirect_url` | n/a | Low | plaintext | contract | Post-payment redirect | Never automated-delete |

## `organisations` / `payouts` (`Dunda.Organisations.{Organisation,Payout}`)

| Field | Category | Sensitivity | Encryption | Lawful basis | Purpose | Retention |
|---|---|---|---|---|---|---|
| `mpesa_phone_encrypted` (organisations, payouts) | Payment | High | AES-256-GCM | contract | B2C payout destination | Never automated-delete (financial evidence); step-up auth required to change (`Dunda.Security.StepUp`) |
| `support_email` | Contact | Low | plaintext (intentional) | contract | **Deliberately public** — displayed to attendees on the event page as an organiser support contact | Retained with organisation |
| `owner_user_id` | Identity | Medium | plaintext (FK) | contract | Organisation ownership | Retained |
| `mpesa_till_number` | Payment | Low | plaintext | contract | Organisation's own public till (not a secret) | Retained |

## `tickets` (`Dunda.Ticketing.Ticket`)

| Field | Category | Sensitivity | Encryption | Lawful basis | Purpose | Retention |
|---|---|---|---|---|---|---|
| `holder_name` | Identity | Medium | plaintext | contract | Printed/displayed on the ticket | Never automated-delete (entitlement/fraud evidence) |
| `credential_public_key` | Device | High (cryptographic material, not secret) | plaintext (public key only — the matching private key never leaves the holder's device Keystore/Keychain, see `docs/phase_7_ticket_security.md`) | contract | Admission proof verification | Never automated-delete |
| `jwt`, `fulfillment_key`, `transaction_id` | Ticket | Medium | plaintext | contract | Entitlement/settlement correlation | Never automated-delete |

## `scanner_devices` (`Dunda.Ticketing.ScannerDevice`)

| Field | Category | Sensitivity | Encryption | Lawful basis | Purpose | Retention |
|---|---|---|---|---|---|---|
| `device_public_key`, `key_fingerprint` | Device | Medium (public key material) | plaintext | legitimate interest | Gate-scanner authentication | Retained; revoked (not deleted) on device loss |
| `operator_user_id` | Identity | Medium | plaintext (FK) | legitimate interest | Accountable gate-staff identity | Retained |

## `events` (`Dunda.Events.Event`)

| Field | Category | Sensitivity | Encryption | Lawful basis | Purpose | Retention |
|---|---|---|---|---|---|---|
| `venue`, `latitude`, `longitude`, `city` | Location | Low (public event metadata, not personal location tracking) | plaintext | legitimate interest | Catalogue discovery | Retained |
| `source`, `external_id`, `source_url`, `source_payload_hash` | Analytics | Low | plaintext | legitimate interest | Scraper provenance | Retained |

## `resale_listings` (`Dunda.Market.Listing`)

| Field | Category | Sensitivity | Encryption | Lawful basis | Purpose | Retention |
|---|---|---|---|---|---|---|
| `seller_id`, `buyer_id` | Identity | Medium | plaintext (FK) | contract | Resale provenance/ledger | Never automated-delete |

## `audit_events` (`Dunda.Audit.Event`)

| Field | Category | Sensitivity | Encryption | Lawful basis | Purpose | Retention |
|---|---|---|---|---|---|---|
| `metadata` | Analytics (mixed) | Medium | plaintext, **redacted at write time** (`Dunda.Audit.record/1` strips `@sensitive_keys` and truncates long values before insert; extended by `Dunda.Logging.Redactor`, [[phase_11_privacy_governance]] §11.4) | legal obligation, legitimate interest | Security/financial audit trail | Never automated-delete (append-only, immutability trigger) |
| `actor_user_id`, `request_id` | Identity/Analytics | Low | plaintext | legal obligation | Attribution, correlation | Never automated-delete |

## `provider_events` (`Dunda.Checkout.ProviderEvent`)

| Field | Category | Sensitivity | Encryption | Lawful basis | Purpose | Retention |
|---|---|---|---|---|---|---|
| `payload` | Payment (mixed, contains raw provider callback body — phone/receipt) | High | plaintext today; bounded and access-controlled at the DB layer, **not yet field-level encrypted** — tracked as an open item below | legal obligation | Provider reconciliation evidence | Never automated-delete |

**Open item** (recorded honestly, not silently omitted): `provider_events.payload`
is a raw JSON capture of the provider callback body and can transiently
contain a phone number or receipt. It is not exposed by any read API, is
never logged in full (`Dunda.Logging.redact/1` is applied wherever it is
`inspect`-ed for diagnostics, [[phase_11_privacy_governance]] §11.4), and is
restricted at the database layer to operator/service-role access. Field-level
encryption of a `:map` column is a larger schema change (requires flattening
or JSON-blob `Dunda.Encrypted.Binary` with loss of queryability) deferred to a
follow-up phase and listed in the findings table in
`docs/phase_12_verification_observability_rollout.md` §"Findings and pen-test
tracking" rather than silently left off this inventory.

## Processor register

| Processor | Data shared | Purpose | Basis for transfer |
|---|---|---|---|
| Safaricom Daraja (M-Pesa) | Phone (MSISDN), amount | STK push checkout, B2C payout | Contract necessity; Kenyan domestic processor |
| Pesapal | Phone, email, amount | Hosted checkout, IPN | Contract necessity; Kenyan-licensed payment processor |
| Google (OAuth) | Email, name, avatar URL, OIDC subject | Sign-in | Contract necessity; user-initiated |
| SMS/OTP provider | Phone (MSISDN) | OTP delivery | Contract necessity — provider is pluggable behind `Dunda.Auth.Otp`'s adapter behaviour; the specific vendor is an operational/procurement decision external to this codebase and must have its own DPA before production use |
| Cloud/hosting provider | All of the above, at rest and in transit | Infrastructure | Legal obligation (processor agreement required); provider unnamed in-repo — see `docs/phase_9_infrastructure_resilience.md` |

Each processor requires a signed Data Processing Agreement before production
traffic flows to it. Confirming those agreements exist is external evidence
(see `docs/phase_11_privacy_governance.md` § Required external evidence) —
this table records what the code sends, not that a DPA has been countersigned.
