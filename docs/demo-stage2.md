# Stage 2 demo — Ladebahn's infrastructure as code

Everything runs on the Mac: no cloud server, no cost. About 7 minutes if you start
the load first and talk through steps 1–4 while it runs.

Every time below was measured on 28 Sep 2026 (`infra/walkthrough/10-grafana.sh`, step 10.7).

## Before you start

- Docker Desktop running; both databases up: `docker ps` shows `ladebahn-db` (compose, 5432)
  and `ladebahn-tf-db` (Terraform, 127.0.0.1:5433)
- The app running on 8080 with the OTel agent (the usual local command in the build log)
- In the terminal you will use for Grafana:
  ```
  export GRAFANA_URL=https://<stack>.grafana.net
  read -rs GRAFANA_AUTH && export GRAFANA_AUTH      # paste the token; nothing is shown
  export TF_VAR_docker_host=$(docker context inspect --format '{{.Endpoints.docker.Host}}')
  ```
- Grafana open on **Dashboards → Ladebahn → Ladebahn — local**, last 30 minutes

## Running order

| # | Step | Time |
|---|---|---|
| 0 | Start the load (it switches lab 03 on at 2:00 and off at 4:00) | 5 min in the background |
| 1 | The database is code | 2 s |
| 2 | Try to demolish it | 3 s |
| 3 | Turn a tuning knob, and turn it back | 8 s + 9 s |
| 4 | Delete the dashboard by hand, one apply restores it | 1 s |
| 5 | The alert fires | ~2¾ min after the lab goes on |

### 0 — Start the load

```
cd ~/dev/ladebahn && BASE_URL=http://localhost:8080 LAB=slow_response k6 run k6/lab-demo.js
```

Say: *"Five simulated users on the nearby search. At two minutes, a switch adds 250 ms to
every search. Keep an eye on the dashboard while I show you the rest."*

### 1 — The database is code

```
cd ~/dev/ladebahn/infra/local-db && ls && terraform plan
```

Show `variables.tf` (the tuning knobs, each with a type and a validation rule) and
`database.tf` (the flags built from those knobs).
Expect: **No changes.**
Say: *"The image, the private network, the data volume and the tuned Postgres container
are all in these files. The plan says reality matches them exactly."*

### 2 — Try to demolish it

```
terraform destroy
```

Expect: `Error: Instance cannot be destroyed … docker_volume.pgdata has lifecycle.prevent_destroy set`.
Nothing is touched.
Say: *"The data volume is protected in code. This is Terraform's version of
'never run docker compose down -v'."*

### 3 — Turn a tuning knob

```
terraform apply -var work_mem=32MB
docker exec ladebahn-tf-db psql -U ladebahn -d ladebahn -tAc 'show work_mem'
docker exec ladebahn-tf-db psql -U ladebahn -d ladebahn -tAc 'select count(*) from site'
terraform apply          # back to the default, 16MB
```

Read the plan out before typing `yes`: `docker_container.db must be replaced`,
`# forces replacement` on the `command` line, and **no `docker_volume` in the plan**.
Expect: `32MB`, then `20000`: the container was rebuilt, and every row survived.
Say: *"A performance experiment on a database setting is now a reviewed, one-line change
that anyone can reproduce, and it can't take the data with it."*

### 4 — Delete the dashboard by hand

In Grafana, delete **Ladebahn — local** from the dashboard's settings (Edit → Settings → Delete dashboard). Then:

```
cd ../grafana && terraform apply
```

Expect: `Plan: 1 to add` → apply → refresh the browser: the dashboard is back, identical,
in the Ladebahn folder.
Say: *"Dashboards and alerts can't quietly drift or vanish. The template is the source of truth,
and one template produces both the local and the server dashboard."*

### 5 — The alert fires

On **Ladebahn — local**, panel 1: the lab line steps to 1 and the p95 line climbs from
about 0.05 s to about 0.47 s. Open **Alerting → Alert rules → Ladebahn**:
*Nearby search p95 too slow (local)* goes Normal → **Pending** (≈ 1¾ min after the switch)
→ **Firing** (≈ 2¾ min). It is linked to panel 1, so the alert marker shows on the graph that
explains it.
Say: *"The alert rule is code too, and it was proven by making it fire, not just by creating it."*

Close with `terraform plan` in `infra/grafana` and `infra/local-db`: **No changes** in both.

## If something goes wrong

- `terraform` asks for `docker_host`, or can't reach Docker: the `TF_VAR_docker_host` line wasn't exported in this terminal.
- Grafana `401`: the token wasn't exported in this terminal, or it has expired.
- The alert stays Normal: the app must run **with** the OTel agent, or no metrics reach Grafana.
  Metrics arrive once a minute, and the alert needs a full minute above the threshold, so allow 3 minutes.
- Someone ran `docker stop ladebahn-tf-db`: `terraform apply` rebuilds the container; the data is in the volume.
