#!/usr/bin/env bash
# Session 10 — Observability as code (Grafana provider).
# Run from anywhere:  bash ~/dev/ladebahn/infra/walkthrough/10-grafana.sh
# Resume after a fix:  START_AT=10.5 bash .../10-grafana.sh
# Takes about 15 minutes: the alert proof in 10.6 needs real traffic and real time.
source "$(dirname "$0")/lib.sh"
start_transcript 10-grafana
TF_DIR="$ROOT/infra/grafana"
mkdir -p "$TF_DIR" && cd "$TF_DIR" || exit 1
START_AT="${START_AT:-10.1}"
from() { awk -v a="$1" -v b="$START_AT" 'BEGIN{exit !(a+0 >= b+0)}'; }
JAR="$ROOT/build/libs/ladebahn-0.0.1-SNAPSHOT.jar"
PROM_UID=grafanacloud-prom
export TF_VAR_docker_host="$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)"

# ---------------------------------------------------------------------------
step "10.1 — Credentials, supplied through the environment only"
explain "Terraform needs your Grafana stack's address and the service account token. The token is read with hidden input into this run only. It never appears on screen, in the transcript, in a file, or in the state file (provider settings are not stored in state)."
if [ -z "${GRAFANA_URL:-}" ]; then read -r -p "  Grafana URL (https://<stack>.grafana.net): " GRAFANA_URL; fi
if [ -z "${GRAFANA_AUTH:-}" ]; then read -r -s -p "  Grafana service account token (hidden): " GRAFANA_AUTH; echo; fi
GRAFANA_URL="${GRAFANA_URL%/}"
export GRAFANA_URL GRAFANA_AUTH
gapi() { local p="$1"; shift; curl -sf -g -H "Authorization: Bearer $GRAFANA_AUTH" "$@" "$GRAFANA_URL$p"; }
prom() { gapi "/api/datasources/proxy/uid/$PROM_UID/api/v1/query" -G --data-urlencode "query=$1" | python3 -c '
import json,sys
r=json.load(sys.stdin)["data"]["result"]
print(" ".join("%.3f" % float(x["value"][1]) for x in r) if r else "no data")'; }
run "echo \"GRAFANA_URL=\$GRAFANA_URL\"; echo \"GRAFANA_AUTH is set: \$([ -n \"\$GRAFANA_AUTH\" ] && echo yes, \${#GRAFANA_AUTH} characters)\""
run "gapi /api/org >/dev/null"
expect_rc 0 "token accepted by Grafana"
must_pass

# ---------------------------------------------------------------------------
if from 10.2; then
step "10.2 — The first Grafana resource: a Ladebahn folder"
explain "Same blueprint language, a different provider. Terraform now manages something in Grafana Cloud instead of on the Mac. We start with the smallest thing: the folder the dashboards and the alert will live in."
cat > versions.tf << 'EOF'
terraform {
  required_version = ">= 1.16.0"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.46"
    }
  }
}

# The stack address and token come from the environment (GRAFANA_URL, GRAFANA_AUTH),
# never from a file, so they are not in the repo and not in the state.
provider "grafana" {}
EOF
cat > folder.tf << 'EOF'
resource "grafana_folder" "ladebahn" {
  uid   = "ladebahn"
  title = "Ladebahn"
}
EOF
run "terraform init -input=false"
expect_rc 0 "grafana provider downloaded"
check "provider is the native darwin_arm64 build" "find .terraform/providers -path '*darwin_arm64*' -name 'terraform-provider-grafana*' | grep -q ."
run "terraform plan -input=false -out=s10.tfplan"
check "plan: 1 to add" "terraform show -no-color s10.tfplan | grep -q 'Plan: 1 to add, 0 to change, 0 to destroy'"
run "terraform apply -input=false s10.tfplan"
expect_rc 0 "folder created"
run "rm -f s10.tfplan"
run "gapi /api/folders/ladebahn; echo"
expect_rc 0 "Grafana confirms the folder exists"
must_pass
fi

# ---------------------------------------------------------------------------
if from 10.3; then
step "10.3 — A dashboard made by hand, then adopted by Terraform"
explain "Discovery found no saved Ladebahn dashboard in the stack: the Session 5 panel was built but never saved. So first a dashboard is created OUTSIDE Terraform, with the same API call the Save button makes, the way a colleague would by hand. Then Terraform ADOPTS it: an import block says 'this real thing belongs to this address', and -generate-config-out makes Terraform write the matching blueprint itself (generated.tf). Success is a plan that says No changes."
render() { python3 -c 'import sys; print(open(sys.argv[1], encoding="utf-8").read().replace("${environment}", sys.argv[2]))' dashboards/ladebahn.json.tftpl "$1"; }
if ! gapi /api/dashboards/uid/ladebahn-local >/dev/null; then
  run "render local | python3 -c 'import json,sys; print(json.dumps({\"dashboard\": json.load(sys.stdin), \"folderUid\": \"\", \"overwrite\": False, \"message\": \"made by hand, before Terraform\"}))' | gapi /api/dashboards/db -X POST -H 'Content-Type: application/json' --data-binary @-; echo"
  expect_rc 0 "dashboard created by hand (outside Terraform)"
fi
check "Grafana has the dashboard ladebahn-local" "gapi /api/dashboards/uid/ladebahn-local >/dev/null"
run "terraform state list"
explain "Terraform's state does not mention it: Terraform does not know it exists yet."
must_pass
cat > import.tf << 'EOF'
# Adopt the hand-made dashboard into Terraform
import {
  to = grafana_dashboard.ladebahn
  id = "ladebahn-local"
}
EOF
rm -f generated.tf
run "terraform plan -input=false -generate-config-out=generated.tf"
check "Terraform wrote generated.tf" "[ -s generated.tf ]"
run "head -c 900 generated.tf; echo; echo '…'; wc -c generated.tf"
run "terraform plan -input=false -out=s10.tfplan"
check "plan: 1 to import, nothing to add, change or destroy" "terraform show -no-color s10.tfplan | grep -q 'Plan: 1 to import, 0 to add, 0 to change, 0 to destroy'"
must_pass   # never apply an unexpected change to the real dashboard
run "terraform apply -input=false s10.tfplan"
expect_rc 0 "dashboard adopted"
run "rm -f s10.tfplan"
run "terraform state list"
run "terraform plan -input=false -detailed-exitcode"
expect_rc 0 "after import: No changes"
must_pass
fi

# ---------------------------------------------------------------------------
if from 10.4; then
step "10.4 — From generated config to a template file"
explain "generated.tf holds the dashboard as one huge string, hard to read and impossible to reuse. We replace it with the JSON in its own file (dashboards/ladebahn.json.tftpl), loaded with templatefile() and the environment name as a parameter. The import block has done its job and goes too. Because the rendered text is identical, the only change the plan may show is the folder: the dashboard moves from General into Ladebahn."
rm -f import.tf generated.tf
cat > variables.tf << 'EOF'
variable "environments" {
  description = "deployment.environment values the app reports (local = the Mac, server = the demo VM)"
  type        = list(string)
  default     = ["local"]

  validation {
    condition     = alltrue([for e in var.environments : contains(["local", "server"], e)])
    error_message = "Environments must be local and/or server — the values in OTEL_RESOURCE_ATTRIBUTES."
  }
}

variable "p95_threshold_seconds" {
  description = "Alert when the nearby-search p95 stays above this many seconds"
  type        = number
  default     = 0.2

  validation {
    condition     = var.p95_threshold_seconds > 0 && var.p95_threshold_seconds < 10
    error_message = "Use a threshold between 0 and 10 seconds."
  }
}
EOF
cat > dashboards.tf << 'EOF'
resource "grafana_dashboard" "ladebahn" {
  folder      = grafana_folder.ladebahn.uid
  config_json = templatefile("${path.module}/dashboards/ladebahn.json.tftpl", { environment = "local" })
}
EOF
run "ls"
run "terraform plan -input=false -out=s10.tfplan"
run "terraform show -no-color s10.tfplan | grep -E '^  # |folder|config_json|^Plan:'"
check "only the folder moves: 0 to add, 1 to change, 0 to destroy" "terraform show -no-color s10.tfplan | grep -q 'Plan: 0 to add, 1 to change, 0 to destroy'"
check "the dashboard JSON itself is unchanged" "! terraform show -no-color s10.tfplan | grep -q 'config_json'"
must_pass
run "terraform apply -input=false s10.tfplan"
expect_rc 0 "dashboard moved into the Ladebahn folder"
run "rm -f s10.tfplan"
check "Grafana shows it in the Ladebahn folder" "gapi /api/dashboards/uid/ladebahn-local | grep -q '\"folderUid\":\"ladebahn\"'"
must_pass
fi

# ---------------------------------------------------------------------------
if from 10.5; then
step "10.5 — for_each: one dashboard per environment from one template"
explain "The app reports two environments: local (the Mac) and server (the demo VM). One template, for_each over the list, and each copy is named by its environment. The existing dashboard must not be rebuilt just because its address changes from grafana_dashboard.ladebahn to grafana_dashboard.ladebahn[\"local\"]; a moved block tells Terraform it is the same thing under a new name."
cat > dashboards.tf << 'EOF'
# One dashboard per environment, all from the same template
resource "grafana_dashboard" "ladebahn" {
  for_each = toset(var.environments)

  folder      = grafana_folder.ladebahn.uid
  config_json = templatefile("${path.module}/dashboards/ladebahn.json.tftpl", { environment = each.key })
}

# Same dashboard, new address: do not destroy and recreate it
moved {
  from = grafana_dashboard.ladebahn
  to   = grafana_dashboard.ladebahn["local"]
}
EOF
python3 - "$TF_DIR/variables.tf" << 'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('default     = ["local"]', 'default     = ["local", "server"]', 1)
open(p, "w", encoding="utf-8").write(s)
PYEOF
run "grep -n -A4 'variable \"environments\"' variables.tf"
check "variables.tf now lists local and server" "grep -q 'default     = \\[\"local\", \"server\"\\]' variables.tf"
run "terraform plan -input=false -out=s10.tfplan"
run "terraform show -no-color s10.tfplan | grep -E '^  # |moved|^Plan:'"
check "plan: 1 to add (server), nothing changed or destroyed" "terraform show -no-color s10.tfplan | grep -q 'Plan: 1 to add, 0 to change, 0 to destroy'"
check "the local dashboard is moved, not rebuilt" "terraform show -no-color s10.tfplan | grep -q 'has moved to grafana_dashboard.ladebahn\\[\"local\"\\]'"
must_pass
run "terraform apply -input=false s10.tfplan"
expect_rc 0 "server dashboard created"
run "rm -f s10.tfplan"
run "terraform state list"
check "Grafana has ladebahn-server" "gapi /api/dashboards/uid/ladebahn-server >/dev/null"
must_pass
fi

# ---------------------------------------------------------------------------
if from 10.6; then
step "10.6 — The alert rule as code"
explain "One rule per environment, from a dynamic block: when the nearby-search p95 (5-minute window) stays above the threshold for 1 minute, the alert fires. It is linked to panel 1 of the matching dashboard, so the alert shows up on the graph that explains it. With no traffic at all (the server is stopped) the rule stays quiet instead of alarming."
cat > alerts.tf << 'EOF'
resource "grafana_rule_group" "latency" {
  name             = "ladebahn-latency"
  folder_uid       = grafana_folder.ladebahn.uid
  interval_seconds = 60

  dynamic "rule" {
    for_each = toset(var.environments)

    content {
      name      = "Nearby search p95 too slow (${rule.value})"
      condition = "THRESHOLD"
      for       = "1m"

      no_data_state  = "OK" # no traffic is not an incident
      exec_err_state = "Error"

      labels = {
        service     = "ladebahn"
        environment = rule.value
      }

      annotations = {
        summary          = "p95 of /api/v1/sites/nearby above ${var.p95_threshold_seconds}s for 1 minute (${rule.value})"
        __dashboardUid__ = "ladebahn-${rule.value}"
        __panelId__      = "1"
      }

      # A: the p95 over the last 5 minutes
      data {
        ref_id         = "P95"
        datasource_uid = "grafanacloud-prom"

        relative_time_range {
          from = 600
          to   = 0
        }

        model = jsonencode({
          refId         = "P95"
          expr          = "histogram_quantile(0.95, sum by (le) (rate(http_server_request_duration_seconds_bucket{deployment_environment=\"${rule.value}\", http_route=\"/api/v1/sites/nearby\"}[5m])))"
          instant       = true
          range         = false
          intervalMs    = 1000
          maxDataPoints = 43200
        })
      }

      # B: is it above the threshold?
      data {
        ref_id         = "THRESHOLD"
        datasource_uid = "__expr__"

        relative_time_range {
          from = 0
          to   = 0
        }

        model = jsonencode({
          refId         = "THRESHOLD"
          type          = "threshold"
          expression    = "P95"
          conditions    = [{ evaluator = { type = "gt", params = [var.p95_threshold_seconds] } }]
          datasource    = { type = "__expr__", uid = "__expr__" }
          intervalMs    = 1000
          maxDataPoints = 43200
        })
      }
    }
  }
}
EOF
run "terraform fmt"
run "terraform fmt -check"
expect_rc 0 "files are in the standard layout"
run "terraform validate"
expect_rc 0 "blueprint is valid"
run "terraform plan -input=false -out=s10.tfplan"
check "plan: 1 to add (the rule group)" "terraform show -no-color s10.tfplan | grep -q 'Plan: 1 to add, 0 to change, 0 to destroy'"
must_pass
run "terraform apply -input=false s10.tfplan"
expect_rc 0 "alert rules created"
run "rm -f s10.tfplan"
run "terraform plan -input=false -detailed-exitcode"
expect_rc 0 "stable: Grafana stored exactly what the blueprint says"
must_pass
fi

if from 10.61; then
step "10.6 proof — make it fire with lab 03"
explain "A rule nobody has seen fire is a guess. We run the app on the Mac with the OTel agent (deployment.environment=local), start the k6 lab demo with slow_response (250 ms extra per request, switched on at 2 minutes, off at 4), and watch the rule's state: inactive → pending → firing. Grafana will also send its default notification email when it fires."
APP_PID=""; STARTED_APP=no
stop_app() { [ "$STARTED_APP" = yes ] && [ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null && wait "$APP_PID" 2>/dev/null; STARTED_APP=no; return 0; }
trap stop_app EXIT
if curl -sf localhost:8080/actuator/health >/dev/null; then
  explain "An app is already running on port 8080 — using it."
else
  run "docker compose -f \"$ROOT/compose.yaml\" up -d --wait"
  ( cd "$ROOT" && source otel/env.sh && exec java -javaagent:otel/opentelemetry-javaagent.jar -jar "$JAR" ) > "$LOG_DIR/app-alert-proof.log" 2>&1 &
  APP_PID=$!; STARTED_APP=yes
  for i in $(seq 1 60); do curl -sf localhost:8080/actuator/health >/dev/null && break; sleep 2; done
fi
check "app answers on 8080" "curl -sf localhost:8080/actuator/health"
must_pass
alert_state() { gapi /api/prometheus/grafana/api/v1/rules | python3 -c '
import json,sys
for g in json.load(sys.stdin)["data"]["groups"]:
    if g["name"] == "ladebahn-latency":
        for r in g["rules"]:
            if r["name"].endswith("(local)"): print(r.get("state", "?"))'; }
P95Q='histogram_quantile(0.95, sum by (le) (rate(http_server_request_duration_seconds_bucket{deployment_environment="local", http_route="/api/v1/sites/nearby"}[5m])))'
run "( cd \"$ROOT\" && BASE_URL=http://localhost:8080 LAB=slow_response k6 run -q k6/lab-demo.js ) > \"$LOG_DIR/k6-alert-proof.log\" 2>&1 & K6_PID=\$!; echo \"k6 started (pid \$K6_PID): 5 VUs for 5 min, slow_response on at 2:00, off at 4:00\""
T0=$(date +%s); SEEN_PENDING=""; SEEN_FIRING=""
printf '\n  %-7s %-10s %s\n' "t" "state" "p95 (s)"
while [ $(( $(date +%s) - T0 )) -lt 780 ]; do
  S="$(alert_state)"; E=$(( $(date +%s) - T0 ))
  printf '  %-7s %-10s %s\n' "$((E/60))m$((E%60))s" "$S" "$(prom "$P95Q")"
  [ "$S" = pending ] && [ -z "$SEEN_PENDING" ] && SEEN_PENDING=$E
  [ "$S" = firing ] && [ -z "$SEEN_FIRING" ] && SEEN_FIRING=$E
  [ -n "$SEEN_FIRING" ] && [ "$E" -ge 330 ] && break
  sleep 20
done
wait "$K6_PID" 2>/dev/null
run "tail -25 \"$LOG_DIR/k6-alert-proof.log\""
run "echo \"pending after: \${SEEN_PENDING:-never}s · firing after: \${SEEN_FIRING:-never}s (from k6 start; lab switched on at 120s)\" | tee \"$LOG_DIR/alert-proof.txt\""
check "the alert fired" "[ -n \"$SEEN_FIRING\" ]"
stop_app
fi

# ---------------------------------------------------------------------------
if from 10.7; then
step "Checkpoint — delete the dashboard by hand, one apply restores it"
explain "The Session 10 checkpoint, and step 3 of the demo: the dashboard is deleted outside Terraform (the same API call as the Delete button). Terraform notices it is gone and puts it back, identical, from the template."
run "gapi /api/dashboards/uid/ladebahn-local -X DELETE; echo"
expect_rc 0 "dashboard deleted outside Terraform"
T0=$(date +%s)
run "terraform plan -input=false -out=s10.tfplan"
check "plan: 1 to add (the missing dashboard)" "terraform show -no-color s10.tfplan | grep -q 'Plan: 1 to add, 0 to change, 0 to destroy'"
run "terraform apply -input=false s10.tfplan"
expect_rc 0 "dashboard restored"
T_RESTORE=$(( $(date +%s) - T0 ))
run "rm -f s10.tfplan"
check "Grafana has ladebahn-local again, in the Ladebahn folder" "gapi /api/dashboards/uid/ladebahn-local | grep -q '\"folderUid\":\"ladebahn\"'"

step "10.7 — Timing the Stage 2 demo steps"
explain "Each step of the Stage 2 scene, run once and timed, so the demo script can say how long each part takes."
TIMES="$LOG_DIR/demo-timings.txt"; : > "$TIMES"
timed() { local t0=$(date +%s); eval "$2"; RC=$?; local t=$(( $(date +%s) - t0 )); printf '%-58s %3ss  (exit %s)\n' "$1" "$t" "$RC" | tee -a "$TIMES"; }
cd "$ROOT/infra/local-db"
timed "database: plan says No changes" "terraform plan -input=false -detailed-exitcode >/dev/null"
timed "database: destroy refused by prevent_destroy" "terraform destroy -input=false >/dev/null 2>&1"
timed "database: work_mem 16MB -> 32MB (plan + apply)" "terraform plan -input=false -var work_mem=32MB -out=demo.tfplan >/dev/null && terraform apply -input=false demo.tfplan >/dev/null"
timed "database: back to 16MB (plan + apply)" "terraform plan -input=false -out=demo.tfplan >/dev/null && terraform apply -input=false demo.tfplan >/dev/null"
rm -f demo.tfplan
cd "$TF_DIR"
printf '%-58s %3ss\n' "grafana: deleted dashboard restored (plan + apply)" "$T_RESTORE" | tee -a "$TIMES"
[ -f "$LOG_DIR/alert-proof.txt" ] && sed 's/^/alert: /' "$LOG_DIR/alert-proof.txt" | tee -a "$TIMES"
check "database ended back on work_mem=16MB" "[ \"\$(docker exec ladebahn-tf-db psql -U ladebahn -d ladebahn -tAc 'show work_mem')\" = 16MB ]"

step "End of Session 10 — everything matches"
run "terraform plan -input=false -detailed-exitcode"
expect_rc 0 "Grafana: blueprint, state and reality agree"
run "(cd \"$ROOT/infra/local-db\" && terraform plan -input=false -detailed-exitcode >/dev/null); echo \"database plan exit: \$?\""
run "git -C \"$ROOT\" status --short --untracked-files=all"
check "no state, tfvars or plan files visible to git" \
  "! git -C \"$ROOT\" status --short --untracked-files=all | grep -E 'tfstate|tfvars|tfplan|walkthrough/logs'"
fi
summary
