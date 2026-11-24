# Production Readiness

SimFleet is not yet a production-certified service. A successful image deployment is
not proof that access control, recovery, or the real simulation engine is ready.

## Implemented Safeguards

- Non-root containers, HTTPS ingress, security headers, API-key authentication.
- Optional RS256 bearer authentication with required issuer, audience, expiry,
  issued-at, subject, and `SimFleet.Reader` role validation.
- Per-process rate limiting with HTTP 429 responses and `Retry-After`.
- Structured audit events with timestamp, request ID, status, duration, and a
  hashed caller fingerprint. Credentials and query strings are excluded.
- Infrastructure configuration for 30-day Log Analytics retention and Azure
  alerts for five API server errors or twenty authentication failures in five minutes.
- Container secrets separated by service; the dashboard does not need database access.
- Deployment builds all images before changing apps. Placeholder images are not used.
- Automatic production deployment follows successful main-branch CI and deploys
  the tested commit. Manual dispatch is an operator override.
- Desktop/mobile browser tests cover populated rendering, same-origin API calls,
  authentication errors, and horizontal overflow.
- A scratch-database dump/restore rehearsal runs in CI.

Local validation is not evidence that these changes have been deployed. Confirm the
GitHub workflow result, deployed image SHA, rendered dashboard, and Azure log ingestion
after each release. The Express environment does not provide a verified zero-downtime
revision-switching guarantee; removing placeholders eliminates deliberate downtime,
not every possible restart interruption.

## Microsoft Entra Activation

The current Azure user received `Insufficient privileges to complete the operation`
when attempting to create the SimFleet application registration. A tenant administrator
or permitted application owner must complete this setup.

1. Register a single-tenant web application with callback
   `https://simfleet-dashboard.calmsmoke-b8e7a24a.northcentralus.azurecontainerapps.io/.auth/login/aad/callback`.
2. Enable ID tokens for the web application and create a time-limited client secret.
   Keep that secret outside source control and chat.
3. Configure GitHub production environment variables `ENTRA_TENANT_ID`,
   `ENTRA_CLIENT_ID`, and `ENTRA_ALLOWED_USER_IDS`. The last value must be a non-empty
   JSON array of tenant user **object IDs**, not email addresses or application IDs.
4. Configure production environment secret `ENTRA_CLIENT_SECRET`. Enter it directly
   in GitHub or the terminal prompt from `gh secret set ENTRA_CLIENT_SECRET --env production`.
5. For direct bearer API clients, expose an API using version-2 access tokens, define
   app role `SimFleet.Reader`, and assign that role to permitted callers. An ID token
   intended only for the dashboard is not an API access token.
6. Deploy, then verify an anonymous request to both `/` and `/api/versions` on the
   dashboard redirects to Entra, an allowed user can load all data, and an unlisted
   tenant user is denied. Direct API requests without credentials must still return 401.

Entra protection is enabled only when the complete registration is configured.
Until then, the dashboard and its API proxy remain publicly accessible. API-key
protection on the direct API host alone does not close that gap.

The API audit fingerprint identifies the proxy service when its shared API key is
used; it is not a per-user Entra audit trail. Use Entra sign-in logs for individual
sign-in evidence. Add trusted user-identity propagation before requiring per-user
API attribution.

## Monitoring

Log Analytics ingestion is usage-billed. Monitor the `simfleet-logs` workspace for
cost and capacity. The configured alert rules create Azure alerts but have no
email action group until an operator supplies a recipient and configures delivery.

After deploying, run this query in the workspace and confirm recent events exist:

```kusto
ContainerAppConsoleLogs_CL
| extend Event = parse_json(Log_s)
| where Event.event == "api_request"
| project TimeGenerated, ContainerAppName_s, Event
| order by TimeGenerated desc
```

Test each alert with controlled requests in a non-production environment. Log
retention is not an immutable compliance archive. This deployment also needs an
independent availability probe and a verified on-call notification path.

## Backup And Recovery

The PostgreSQL template retains managed backups for seven days. The local/CI
rehearsal proves logical dump restoration and checks counts for drivers, scenarios,
batches, runs, metrics, and verdicts. Pause writers when running it against a shared
development database so source counts cannot change during the dump.

```powershell
docker cp scripts/verify-restore.sh infra-db-1:/tmp/simfleet-verify-restore.sh
docker compose -f infra/docker-compose.yml exec -T db sh /tmp/simfleet-verify-restore.sh
```

The script creates a uniquely named scratch database and never restores over the
source. It requires permission to create/drop that scratch database.

Before production sign-off, rehearse Azure point-in-time recovery to a **new** server:

```powershell
az postgres flexible-server restore --resource-group "<resource-group>" --name "<new-recovery-server>" --source-server "<source-server-id>" --restore-time "<UTC-timestamp>"
```

This creates a billable server. Isolate its network, verify schema and data, point a
separate test API at it, and record the recovery duration and recovered timestamp.
Agree recovery-time and recovery-point objectives before sign-off. Do not change
production connection strings or delete the source server during the drill.

## External Blockers And Follow-Up

- **DriveBench:** no actual package, bindings, documentation, or scenario assets were
  supplied. The `pydrivebench` adapter is not proof of real-engine integration. Supply
  those artifacts and validate reproducibility, failure handling, and real outputs.
- **Private networking:** migrate the existing public PostgreSQL/Express setup to
  an approved VNet-integrated environment and database network. This is a separate
  migration, not an in-place toggle verified for the current environment.
- **Managed identity and Key Vault:** the Express fallback still uses ACR admin
  credentials and PostgreSQL password authentication. Do not disable them until
  managed-identity image pulls, secret resolution, and database connections have
  been verified on the replacement platform.
- **Edge protection:** WAF, externally enforced distributed rate limits, and
  independent uptime checks are not configured. In-process rate limits are not
  distributed across replicas and are not DDoS protection.
- **Operational acceptance:** configure alert delivery, perform the cloud recovery
  drill, verify log ingestion, and exercise allowed/denied Entra users before calling
  this deployment production-ready.