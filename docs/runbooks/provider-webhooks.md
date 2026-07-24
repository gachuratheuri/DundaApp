# Provider webhook trust boundary

Provider callbacks are accepted only after their durable provider event can be
authenticated at the application edge. TLS alone authenticates Dunda to the
provider; it does not authenticate the caller to Dunda.

## Daraja

Safaricom Daraja does not attach arbitrary Dunda headers. Production must use
exactly one reviewed ingress pattern:

1. Configure the registered Daraja result URL with a high-entropy
   `?token=<DARAJA_CALLBACK_SECRET>` query value. The provider calls that exact
   URL and `Dunda.Security.Webhook` compares it in constant time.
2. Put the API behind a provider-IP/TLS allow-listed edge proxy. The proxy
   removes every inbound `x-dunda-webhook-secret` value and injects the trusted
   value only after its own checks pass.

Do not expose query strings in load-balancer, ingress, application, APM, or WAF
logs. Rotate a callback secret by registering a new result URL before removing
the previous route. A lost callback is not a settlement failure:
`Dunda.Workers.PaymentReconciliationWorker` queries the provider and converges
the payment intent independently.

## Pesapal

Use the registered IPN endpoint and configured secret/edge verification. Store
the event durably before acknowledging it. Duplicate event IDs are accepted
idempotently and processed once.

## Verification

- An absent or incorrect secret returns `401`.
- A valid provider event returns `202` only after the event and worker intent
  commit together.
- Callback payloads are encrypted at rest; the public JSON column contains
  only an encryption marker.
- Access-log query capture is disabled and verified after each ingress change.
