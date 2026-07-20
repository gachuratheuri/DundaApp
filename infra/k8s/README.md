# Kubernetes release controls

`deployment.yaml` is the single source of truth for the `dunda-api`
Deployment, headless discovery Service, and PodDisruptionBudget.
`dunda-api-hpa.yaml` contains only the HPA; applying both files therefore
cannot create competing Deployments with different probes or images.
`networkpolicy.yaml` is the default-deny API boundary; its PostgreSQL, Redis,
DNS, and ingress labels must match the managed cluster services.
For externally managed PostgreSQL/Redis, replace the example pod selectors with
approved private `ipBlock` CIDRs and keep provider egress limited to HTTPS.

Before applying a release, the CI/CD system must replace the digest sentinel
with the digest of the signed image that passed the
Phase 4 approval evidence. The deployment deliberately uses `/livez` for
liveness and `/readyz` for dependency readiness. A readiness failure removes a
pod from service without restarting a healthy BEAM process.

The pod runs as non-root, drops Linux capabilities, uses a read-only root
filesystem and runtime-default seccomp profile, exposes a fixed BEAM
distribution port in addition to EPMD, spreads replicas across hosts where
possible, and marks itself unready before a 20-second graceful drain period.
Phoenix PubSub is started explicitly as `Dunda.PubSub` and participates in the
BEAM cluster only after the fixed distribution ports are available.

The termination grace period is 60 seconds: the pre-stop hook drains for 20
seconds and the BEAM/Oban supervisor has a bounded 30-second shutdown budget.
The pod does not mount a service-account token. The HPA includes an external
`oban_queue_depth` signal; the cluster metrics adapter must publish that metric
from queue depth/latency telemetry before queue-driven autoscaling is enabled.
