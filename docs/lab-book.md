# Ladebahn — Lab Book

Every performance experiment gets an entry, written as I go.

## Environment baseline

- Local: MacBook Pro (Apple Silicon), macOS 26 Tahoe, arm64
- Java: Temurin 21.0.5+11 LTS (aarch64)
- Docker: 29.8.0, Compose v5.5.1, 6 GB / 4 CPU
- k6: v2.2.0 (darwin/arm64)
- Postgres: custom image, postgres:16-bookworm + postgresql-16-postgis-3
- Remote: Oracle Ampere A1 (arm64), Frankfurt
- No emulation anywhere — local and remote are both arm64

## Template

**Lab NN — name**
- Hypothesis:
- Setup: scale / VUs / duration / hardware
- Baseline: p50 / p95 / p99 / RPS / errors
- With lab enabled: p50 / p95 / p99 / RPS / errors
- First signal:
- Time to diagnose:
- Root cause:
- Fix:
- Surprise:

---

## Log

### 2026-09-18 — Environment setup

Official `postgis/postgis` images publish amd64 only (verified via `buildx imagetools`
on tags 16-3.4 and 17-3.5). Chose to build a custom image on `postgres:16-bookworm`
with Debian's arm64 PostGIS packages rather than use a third-party multi-arch build.
Emulation was rejected outright: QEMU-emulated Postgres would make every timing in
this project a measurement of the emulator.


### Baseline — nearby query, LARGE scale, index present

Query: sites within 5 km of Alexanderplatz (13.4132, 52.5219)
Data: 20,000 sites / 91,381 charge points / 141,694 connectors, seed=42

- Plan: Bitmap Index Scan on idx_site_location → Bitmap Heap Scan
- Index produced 1,249 candidates; filter removed 244; 1,005 rows returned
- Buffers: index 19 shared hit, heap 743 shared hit
- Planning Time: 6.250 ms
- **Execution Time: 5.567 ms**

Note: planner estimated 2 rows, actual 1,005 — a 500x underestimate.
Spatial selectivity estimation is poor. Watch this once joins are added;
a nested loop chosen on the strength of "2 rows" would be very wrong.

### Session 4 — observability pipeline live

Spring Boot → OTel Java agent 2.31.1 → Grafana Cloud OTLP → Prometheus/Tempo.
1,052 requests at http_route="/health/slow", status 200, visible end to end.

Three failures on the way, all of the same type — a step that silently didn't happen:
1. Agent jar download produced no file. `ls` would have caught it.
2. `build.gradle` bootRun block never saved. `grep` would have caught it.
3. HealthLabController didn't exist, so k6 ran 1,510 requests that all 404'd —
   and k6 reported them as passing, because http_req_failed counts transport
   failures, not status codes. Only the check() on status 200 catches this.

Also: `rate(...[1m])` returns nothing when the OTel export interval is 60s.
rate() needs >=2 samples in its window. Rule: rate window >= 4x export interval.

Takeaway: verify each step produced what it claimed before building on it.
A green k6 summary measuring 404s is worse than a red one.

### Incident — credentials committed to a public repo

`otel/env.sh` containing the Grafana Cloud OTLP token was pushed to a public repo.

Root cause: the `.gitignore` entry was added *after* the file had already been staged.
Git only ignores untracked files — once a file is tracked, `.gitignore` has no effect
on it. Adding the rule later appears to work (the file stops showing as modified) while
the file remains fully tracked and published.

Response: rotated the token, rewrote history, force-pushed.

Rule going forward: a secret goes in a path that was .gitignore'd BEFORE the file
was ever created. Verify with `git check-ignore -v <path>` — it must print a matching
rule, not nothing.

### Finding — OTLP auth: "no credentials" vs "invalid credentials"

Grafana Cloud's newer connection-details page issues a bare token with no header
name. OTEL_EXPORTER_OTLP_HEADERS expects name=value pairs, so a bare token means
the agent sends no Authorization header at all.

The two 401 bodies are diagnostically distinct and worth knowing:
- "no credentials provided"      -> header absent or malformed (not name=value)
- "invalid authentication ..."   -> header well-formed, contents wrong

Fix: Authorization=Basic $(echo -n "INSTANCE_ID:TOKEN" | base64). The -n matters;
a trailing newline gets encoded and is rejected.

Contrast with earlier tonight: four silent no-ops cost ~30 min each. This one
announced the exact endpoint, status and reason every five seconds, and the
error *text* narrowed it from "auth is broken" to "the header isn't being sent".
That distinction is the whole argument for good error messages.
