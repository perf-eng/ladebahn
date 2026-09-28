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

### Lab 01 — n_plus_one

Native path: one SQL query with joins and aggregates.
Naive path: one query for sites, then lazy-loaded chargePoints, connectors and
operator per site. Same endpoint, same response, switched by the lab flag.

| Page | native | naive | ratio |
|---|---|---|---|
| size=20, Alexanderplatz | ~0.012 s | ~0.019 s | 1.6x |
| size=100, hub-dense origin (52.5136, 13.4001) | ~0.012 s | ~0.068 s | **5.7x** |

The native path cost the SAME at size=20 and size=100. The naive path scales with
both row count and fan-out, because each extra site means more round trips.

Surprise: the severity of the identical bug varied 3.5x depending only on which rows
the page contained. Berlin's nearest 20 sites are mostly 2-charge-point sites; widen
to 100 near a 40-point hub and the round trips multiply. In production this shows up
as a p99 problem, not a p50 one — anyone measuring with one fixed request would call
it minor.

Method note: the first attempt at this measurement was invalid. The lab was left
enabled, so both "native" and "naive" runs used the naive path, and the apparent
improvement was JIT warm-up. Each path needs its own warm-up, and the flag state must
be verified before each set.

### Finding — the map exposed a seeder bug

Rendering 50 Berlin sites on a map showed every marker stacked in a tight blob at
the city centre rather than spread across the 5 km radius.

Cause: the seeder uses `Math.abs(rnd.nextGaussian()) * 8.0` for the offset from a
city centre. abs() of a Gaussian is a half-normal — heavily weighted toward zero —
so most sites land within 1-2 km of the exact centre coordinate.

Invisible in JSON, in EXPLAIN output, and in every timing taken so far. One glance
at a map made it obvious.

Why it matters beyond looks: GIST index performance depends on how points distribute
across bounding boxes. A single dense heap is an unrealistically easy shape, so
lab 02 (drop_index) is being measured against a friendlier distribution than reality.

Takeaway: visualise your test data. Statistical checks confirm what you thought to
check; a picture shows what you did not.

### Testcontainers — real PostGIS in tests

Initializr's generated config used `postgres:latest`, which has no PostGIS — V1
migration would fail on CREATE EXTENSION. Pointed it at the project's own image
(`ladebahn/postgres:16-postgis`) with `.asCompatibleSubstituteFor("postgres")`, so
tests run against byte-identical Postgres to dev and prod.

Five tests cover what the type system can't: spatial ordering, radius correctness,
pagination without overlap, filter narrowing, connector count sanity. H2 would have
passed none of these honestly — no PostGIS, no ST_DWithin, no GIST, different planner.

`withReuse(true)` plus `testcontainers.reuse.enable=true` in ~/.testcontainers.properties
keeps the container alive between runs: 5 tests in 0.193 s. Without reuse each run
pays container startup.

Gotcha: Initializr generates TestcontainersConfiguration as package-private, so tests
in sub-packages can't @Import it. Needs `public`.

### 2026-09-28 — Stage 2: Terraform takes over the local database and Grafana

Three Terraform configurations, all run from the Mac (`infra/`): a playground for the
fundamentals, Ladebahn's own PostGIS database (Docker provider 4.6.0), and the Grafana
folder, dashboards and alert rules (Grafana provider 4.46.0). Every step was run by a
walkthrough script with checks: 27 + 53 + 35 passed.

**Twin check.** The Terraform database (5433) against the compose database (5432), both
seeded large / seed 42: identical row counts (50 / 20,000 / 91,314 / 141,565), a
byte-identical nearby-search response, and the same PG 16.15 · PostGIS 3.6.4.

### Finding — same Dockerfile, different image ID, identical content

Terraform built the Postgres image from the same Dockerfile in 1 second (Docker's build
cache), yet it got a different image ID from the compose-built one
(`7c93932b…` vs `ffbb5016…`). The filesystem layers were identical (same RootFS
digest list) and so was the creation timestamp. The only difference was compose's labels
(`com.docker.compose.project`, `.service`, `.version`).

An image ID fingerprints the layers *and* the metadata. To ask "is this the same
Postgres?", compare layers or versions, not IDs.

Side note: the image is only identical because of the cache. `apt-get install
postgresql-16-postgis-3` is unpinned, so a build without cache could pull a newer PostGIS.

### Finding — `docker stop` turns into a full container rebuild

After `docker stop ladebahn-tf-db`, the plan wanted to **replace** the container rather
than start it. `must_run` read back as false, and the `ports` block was marked
`# forces replacement`, because a stopped container reports no published ports.
Planning itself changed nothing (still `Exited` after the plan). Apply rebuilt the
container, and all rows survived because the data lives in the volume.

Drift repair is whatever the provider can express. Here, it can only rebuild.

### Finding — tuning a knob rebuilds the container, never the data

`-var work_mem=32MB`: `command` forces replacement of the container (Postgres reads its
flags only at startup). The volume never appeared in the plan. 8 s, rows intact, `show
work_mem` = 32MB, and back to 16MB in 9 s. `prevent_destroy` on the volume refused
`terraform destroy` before anything was touched.

### Finding — the dashboard that was never saved

Before importing "the Session 5 self-narrating dashboard", the stack was listed through
the API: no Ladebahn dashboard existed. The panel had been built but never saved.
The dashboard was rewritten as a template (`infra/grafana/dashboards/ladebahn.json.tftpl`),
created once outside Terraform, then adopted with an `import` block and
`-generate-config-out`. After adoption the plan said No changes. Then: template file (only the
folder move showed in the plan), and `for_each` for `local` and `server`, with a `moved`
block so the adopted dashboard wasn't rebuilt. Deleting it in the UI and running one
apply restored it (1 s).

Takeaway: look before you import. "It exists" was a memory, not a fact.

### Finding — the alert is right, the p95 number is not

Alert: p95 of `/api/v1/sites/nearby` (5-min window) > 0.2 s for 1 min. Proven with lab 03
(slow_response, +250 ms) via `k6/lab-demo.js`: lab on at 120 s, **Pending at 224 s,
Firing at 285 s**.

| | p95 |
|---|---|
| k6, client side (all requests, incl. baseline) | 0.282 s |
| Prometheus `histogram_quantile(0.95, …)` during the lab | 0.470–0.479 s |

The slow requests took about 0.28 s, but Prometheus reported about 0.47 s. OTel's default
duration buckets are `… 0.1, 0.25, 0.5, 0.75 …`. When most requests fall in one bucket,
`histogram_quantile` interpolates linearly inside it: 0.25 + 0.95 × (0.5 − 0.25) = **0.4875**.

That is exactly Stage 1's "p95 0.4875 s @ 400 ms". The Stage 1 conclusion that the stack
adds ~20% overhead above the artificial delay was a bucket artefact, not overhead.
When nearly every request lands in the 0.25–0.5 s bucket, any true p95 in that range reads as ~0.47–0.49 s.

Takeaway: percentiles from a histogram have the histogram's resolution. Cross-check with
k6's client-side numbers, and don't quote a server-side p95 finer than its bucket width.
