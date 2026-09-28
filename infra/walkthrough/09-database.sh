#!/usr/bin/env bash
# Session 9 — Ladebahn's own PostGIS database as code (Docker provider).
# Run from anywhere:  bash ~/dev/ladebahn/infra/walkthrough/09-database.sh
# Resume from a later step after a fix:  START_AT=9.5 bash .../09-database.sh
source "$(dirname "$0")/lib.sh"
start_transcript 09-database
TF_DIR="$ROOT/infra/local-db"
mkdir -p "$TF_DIR" && cd "$TF_DIR" || exit 1

START_AT="${START_AT:-9.0}"
from() { awk -v a="$1" -v b="$START_AT" 'BEGIN{exit !(a+0 >= b+0)}'; }   # run this step?

TF_DB=ladebahn-tf-db          # the container Terraform owns
COMPOSE_DB=ladebahn-db        # the container docker compose owns (untouched except for reseeding)
JAR="$ROOT/build/libs/ladebahn-0.0.1-SNAPSHOT.jar"
NEARBY='/api/v1/sites/nearby?lat=52.5219&lon=13.4132&radiusKm=5&size=20'

sql()    { docker exec "$1" psql -U ladebahn -d ladebahn -tAc "$2"; }
counts() { sql "$1" "select (select count(*) from operator)||' / '||(select count(*) from site)||' / '||(select count(*) from charge_point)||' / '||(select count(*) from connector)"; }
APP_PID=""
start_app() { # start_app <port> <jdbc-url> <label>
  ( cd "$ROOT" && source otel/env.sh && export SERVER_PORT="$1" SPRING_DATASOURCE_URL="$2" && exec java -jar "$JAR" ) > "$LOG_DIR/app-$3.log" 2>&1 &
  APP_PID=$!
  for i in $(seq 1 60); do
    curl -sf "localhost:$1/actuator/health" >/dev/null && return 0
    kill -0 "$APP_PID" 2>/dev/null || return 1
    sleep 2
  done
  return 1
}
stop_app() { [ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null && wait "$APP_PID" 2>/dev/null; APP_PID=""; return 0; }
trap stop_app EXIT

# ---------------------------------------------------------------------------
if from 9.0; then
step "9.0 — Before we start"
explain "This session puts Ladebahn's own database under Terraform: the PostGIS image, a private network, a protected data volume and the tuned Postgres container, on port 5433 next to the compose one on 5432. The compose database stays your daily driver; we only reseed it once to compare. Nothing here touches the server or the cloud."
run "docker info --format 'Docker {{.ServerVersion}} · {{.NCPU}} CPU · {{.MemTotal}} bytes · {{.Architecture}}'"
expect_rc 0 "Docker Desktop is running"
must_pass
explain "Terraform talks to Docker through the same socket the docker command uses. We ask Docker where that is and hand the answer to Terraform as a variable (TF_VAR_docker_host)."
fi
export TF_VAR_docker_host="$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)"
if from 9.0; then
run "echo \"TF_VAR_docker_host=\$TF_VAR_docker_host\""
check "Docker socket found" "[ -n \"\$TF_VAR_docker_host\" ]"
run "lsof -nP -iTCP:5433 -iTCP:8081 -iTCP:8082 -sTCP:LISTEN || echo 'ports 5433, 8081, 8082 are free'"
check "ports 5433, 8081 and 8082 are free" "! lsof -nP -iTCP:5433 -iTCP:8081 -iTCP:8082 -sTCP:LISTEN"
run "cd \"$ROOT\" && ./gradlew bootJar -q; cd \"$TF_DIR\""
check "app jar is built" "[ -f \"$JAR\" ]"
check "the compose image exists (9.1 reads it)" "docker image inspect ladebahn/postgres:16-postgis >/dev/null"
check "otel/env.sh exists (the app reads its settings)" "[ -f \"$ROOT/otel/env.sh\" ]"
must_pass
fi

# ---------------------------------------------------------------------------
if from 9.1; then
step "9.1 — Read before you write: a data source"
explain "A data source lets Terraform LOOK at something it does not own. Here: the image docker compose built back in Session 2. Terraform reads its ID and reports it; it will never change or delete it. The provider block tells Terraform which Docker to talk to."
cat > versions.tf << 'EOF'
terraform {
  required_version = ">= 1.16.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.6"
    }
  }
}

provider "docker" {
  # Docker Desktop's socket; the walkthrough passes the real path in TF_VAR_docker_host
  host = var.docker_host
}
EOF
cat > variables.tf << 'EOF'
variable "docker_host" {
  description = "Docker daemon socket, e.g. unix:///Users/<you>/.docker/run/docker.sock"
  type        = string
  default     = "unix:///var/run/docker.sock"
}
EOF
cat > data.tf << 'EOF'
# Read-only: the image docker compose already built. Terraform looks, never touches.
data "docker_image" "compose_postgres" {
  name = "ladebahn/postgres:16-postgis"
}
EOF
cat > outputs.tf << 'EOF'
output "compose_image_id" {
  description = "ID of the image docker compose built (read-only)"
  value       = data.docker_image.compose_postgres.id
}
EOF
run "terraform init -input=false"
expect_rc 0 "docker provider downloaded"
run "find .terraform/providers -type f -name 'terraform-provider-*'"
check "provider is the native darwin_arm64 build" "find .terraform/providers -path '*darwin_arm64*' -name 'terraform-provider-docker*' | grep -q ."
run "terraform apply -input=false -auto-approve"
expect_rc 0 "data source read; nothing built (a data-source-only apply has nothing to approve)"
run "terraform output compose_image_id"
run "docker image inspect --format '{{.Id}}' ladebahn/postgres:16-postgis"
must_pass
check "Terraform sees the same image ID as docker" \
  "[ \"\$(terraform output -raw compose_image_id)\" = \"\$(docker image inspect --format '{{.Id}}' ladebahn/postgres:16-postgis)\" ]"
fi

# ---------------------------------------------------------------------------
if from 9.2; then
step "9.2 — Build the image from the existing Dockerfile"
explain "Now Terraform OWNS something: an image built from docker/postgres/Dockerfile, the same file compose uses, but under its own tag (16-postgis-tf) so compose's image is never touched. 'triggers' holds a fingerprint of the Dockerfile: change the file and Terraform plans a rebuild. keep_locally means a destroy would leave the image on disk."
cat > image.tf << 'EOF'
# Owned by Terraform: the same Dockerfile compose uses, built under its own tag
resource "docker_image" "postgres" {
  name         = "ladebahn/postgres:16-postgis-tf"
  keep_locally = true # a destroy leaves the image on disk

  build {
    context = abspath("${path.module}/../../docker/postgres")
  }

  # Rebuild whenever the Dockerfile changes
  triggers = {
    dockerfile = filesha1("${path.module}/../../docker/postgres/Dockerfile")
  }
}
EOF
cat >> outputs.tf << 'EOF'

output "terraform_image_id" {
  description = "ID of the image Terraform built"
  value       = docker_image.postgres.image_id
}

output "same_image" {
  description = "Did the same Dockerfile produce the very same image?"
  value       = data.docker_image.compose_postgres.id == docker_image.postgres.image_id
}
EOF
run "terraform plan -input=false -out=s9.tfplan"
check "plan: 1 to add" "terraform show -no-color s9.tfplan | grep -q 'Plan: 1 to add, 0 to change, 0 to destroy'"
run "terraform apply -input=false s9.tfplan"
expect_rc 0 "image built"
run "rm -f s9.tfplan"
run "terraform output"
run "docker image ls ladebahn/postgres"
explain "If same_image is true, Docker reused its build cache: one image, now with two names. If false, the RUN apt-get line fetched newer packages than in Session 2. Either way, it is recorded."
must_pass
fi

# ---------------------------------------------------------------------------
if from 9.3; then
step "9.3 — A private network and a protected data volume"
explain "The volume is where Postgres keeps its files. The container can be thrown away and rebuilt; the volume must survive. 'prevent_destroy' makes Terraform refuse ANY plan that would delete it — Terraform's version of 'never docker compose down -v'."
cat > storage.tf << 'EOF'
resource "docker_network" "ladebahn" {
  name = "ladebahn-tf"
}

resource "docker_volume" "pgdata" {
  name = "ladebahn-tf-pgdata"

  # The data lives here. Terraform refuses any plan that would destroy it.
  lifecycle {
    prevent_destroy = true
  }
}
EOF
run "terraform plan -input=false -out=s9.tfplan"
check "plan: 2 to add" "terraform show -no-color s9.tfplan | grep -q 'Plan: 2 to add, 0 to change, 0 to destroy'"
run "terraform apply -input=false s9.tfplan"
expect_rc 0 "network and volume created"
run "rm -f s9.tfplan"
run "docker network ls --filter name=ladebahn-tf"
run "docker volume ls --filter name=ladebahn-tf-pgdata"
must_pass
fi

# ---------------------------------------------------------------------------
if from 9.4; then
step "9.4 — The tuned Postgres container, knobs as typed variables"
explain "Same flags as compose.yaml, but every tuning knob is now a variable with a type and a validation rule, so a typo like '512M' is refused before anything happens. The flags are built from a map with a 'for' expression. Port 5433 is bound to 127.0.0.1 only. wait = true makes apply finish only once the healthcheck says healthy."
cat > variables.tf << 'EOF'
variable "docker_host" {
  description = "Docker daemon socket, e.g. unix:///Users/<you>/.docker/run/docker.sock"
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "host_port" {
  description = "Port on the Mac for the Terraform database (compose owns 5432)"
  type        = number
  default     = 5433

  validation {
    condition     = var.host_port >= 1024 && var.host_port <= 65535 && var.host_port != 5432
    error_message = "Use a port from 1024 to 65535, and not 5432, which the compose database owns."
  }
}

variable "shared_buffers" {
  description = "Postgres shared_buffers — the database's own page cache"
  type        = string
  default     = "512MB"

  validation {
    condition     = can(regex("^[0-9]+(kB|MB|GB)$", var.shared_buffers))
    error_message = "Use a whole number with kB, MB or GB, e.g. 512MB."
  }
}

variable "work_mem" {
  description = "Postgres work_mem — memory per sort or hash step before spilling to disk"
  type        = string
  default     = "16MB"

  validation {
    condition     = can(regex("^[0-9]+(kB|MB|GB)$", var.work_mem))
    error_message = "Use a whole number with kB, MB or GB, e.g. 16MB."
  }
}

variable "effective_cache_size" {
  description = "Postgres effective_cache_size — planner's estimate of total cache available"
  type        = string
  default     = "1536MB"

  validation {
    condition     = can(regex("^[0-9]+(kB|MB|GB)$", var.effective_cache_size))
    error_message = "Use a whole number with kB, MB or GB, e.g. 1536MB."
  }
}

variable "max_connections" {
  description = "Postgres max_connections"
  type        = number
  default     = 100

  validation {
    condition     = var.max_connections >= 10 && var.max_connections <= 500
    error_message = "Keep max_connections between 10 and 500."
  }
}
EOF
cat > database.tf << 'EOF'
locals {
  # The same settings as compose.yaml, with the tuning knobs as variables
  postgres_settings = {
    shared_preload_libraries   = "pg_stat_statements"
    "pg_stat_statements.track" = "all"
    shared_buffers             = var.shared_buffers
    work_mem                   = var.work_mem
    effective_cache_size       = var.effective_cache_size
    max_connections            = var.max_connections
    log_min_duration_statement = 200
  }

  # ["postgres", "-c", "key=value", "-c", "key=value", ...]
  postgres_command = concat(
    ["postgres"],
    flatten([for key, value in local.postgres_settings : ["-c", "${key}=${value}"]])
  )
}

resource "docker_container" "db" {
  name    = "ladebahn-tf-db"
  image   = docker_image.postgres.image_id
  command = local.postgres_command

  env = [
    "POSTGRES_DB=ladebahn",
    "POSTGRES_USER=ladebahn",
    "POSTGRES_PASSWORD=ladebahn", # local lab only, same as compose.yaml
  ]

  ports {
    internal = 5432
    external = var.host_port
    ip       = "127.0.0.1"
  }

  volumes {
    volume_name    = docker_volume.pgdata.name
    container_path = "/var/lib/postgresql/data"
  }

  networks_advanced {
    name = docker_network.ladebahn.name
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U ladebahn -d ladebahn"]
    interval = "5s"
    timeout  = "3s"
    retries  = 10
  }

  # apply only finishes once the healthcheck reports healthy
  wait         = true
  wait_timeout = 120
}
EOF
cat >> outputs.tf << 'EOF'

output "container_name" {
  value = docker_container.db.name
}

output "jdbc_url" {
  description = "Point the app here with SPRING_DATASOURCE_URL"
  value       = "jdbc:postgresql://localhost:${var.host_port}/ladebahn"
}

output "postgres_command" {
  description = "The flags Postgres was started with"
  value       = join(" ", local.postgres_command)
}
EOF
run "terraform fmt -check"
expect_rc 0 "files are in the standard layout"
run "terraform validate"
expect_rc 0 "blueprint is valid"
run "terraform plan -input=false -var shared_buffers=512M"
expect_rc 1 "a typo'd knob (512M) is refused before anything happens"
run "terraform plan -input=false -out=s9.tfplan"
check "plan: 1 to add (the container)" "terraform show -no-color s9.tfplan | grep -q 'Plan: 1 to add, 0 to change, 0 to destroy'"
run "terraform apply -input=false s9.tfplan"
expect_rc 0 "container created and healthy"
run "rm -f s9.tfplan"
run "terraform output"
run "docker ps --filter name=$TF_DB --format '{{.Names}}  {{.Status}}  {{.Ports}}'"
check "container reports healthy" "docker inspect --format '{{.State.Health.Status}}' $TF_DB | grep -qx healthy"
for s in shared_buffers work_mem effective_cache_size max_connections shared_preload_libraries; do
  run "sql $TF_DB 'show $s'"
done
check "Postgres is really running with shared_buffers=512MB" "[ \"\$(sql $TF_DB 'show shared_buffers')\" = 512MB ]"
check "and work_mem=16MB" "[ \"\$(sql $TF_DB 'show work_mem')\" = 16MB ]"
must_pass
fi

# ---------------------------------------------------------------------------
if from 9.5; then
step "9.5 — Point the app at it, seed, and compare with the compose database"
explain "The proof that the Terraform database is a real replacement: run the app against it, let Flyway create the schema, seed large with seed 42, and compare with the compose database seeded the same way. Row counts and the nearby search result must be identical. The app runs on 8081 and 8082 without the OTel agent, so no test traffic reaches Grafana."
run "start_app 8081 jdbc:postgresql://localhost:5433/ladebahn tf"
expect_rc 0 "app started against the Terraform database (port 5433)"
must_pass
run "curl -s -X POST -H 'X-Lab-Token: local-dev-token' 'localhost:8081/admin/seed?scale=large&randomSeed=42'; echo"
expect_rc 0 "seeded large / seed 42"
run "curl -s 'localhost:8081$NEARBY' | sed -E 's/\"queryTimeMs\":[0-9]+,//' > '$LOG_DIR/nearby-tf.json'; head -c 300 '$LOG_DIR/nearby-tf.json'; echo"
run "stop_app"

explain "Now the same with the compose database (port 5432). This reseeds it to large / seed 42, the standard state in 'Resume here'."
run "docker compose -f \"$ROOT/compose.yaml\" up -d --wait"
expect_rc 0 "compose database up and healthy"
run "start_app 8082 jdbc:postgresql://localhost:5432/ladebahn compose"
expect_rc 0 "app started against the compose database (port 5432)"
must_pass
run "curl -s -X POST -H 'X-Lab-Token: local-dev-token' 'localhost:8082/admin/seed?scale=large&randomSeed=42'; echo"
expect_rc 0 "seeded large / seed 42"
run "curl -s 'localhost:8082$NEARBY' | sed -E 's/\"queryTimeMs\":[0-9]+,//' > '$LOG_DIR/nearby-compose.json'"
run "stop_app"

explain "operators / sites / charge points / connectors:"
run "echo \"terraform: \$(counts $TF_DB)\"; echo \"compose:   \$(counts $COMPOSE_DB)\""
check "row counts are identical" "[ \"\$(counts $TF_DB)\" = \"\$(counts $COMPOSE_DB)\" ]"
check "20,000 sites in the Terraform database" "counts $TF_DB | grep -q ' / 20000 / '"
run "shasum '$LOG_DIR/nearby-tf.json' '$LOG_DIR/nearby-compose.json'"
check "nearby search returns byte-identical results" "cmp -s '$LOG_DIR/nearby-tf.json' '$LOG_DIR/nearby-compose.json'"
run "echo \"terraform: \$(sql $TF_DB \"select split_part(version(),' ',2)||' · PostGIS '||postgis_lib_version()\")\"; echo \"compose:   \$(sql $COMPOSE_DB \"select split_part(version(),' ',2)||' · PostGIS '||postgis_lib_version()\")\""
must_pass
fi

# ---------------------------------------------------------------------------
if from 9.6; then
step "9.6 — Turn a tuning knob and read what the plan will do"
explain "We raise work_mem from 16MB to 32MB for one plan. Postgres reads its flags only at startup, and the Docker provider cannot change a running container's command, so the plan must say the container will be REPLACED (-/+). The question that matters: is the volume in the plan? It must not be. Then the data survives the rebuild."
BEFORE="$(counts $TF_DB)"
run "terraform plan -input=false -var work_mem=32MB -out=s9-tune.tfplan"
run "terraform show -no-color s9-tune.tfplan | grep -E '^  # |forces replacement|work_mem|^Plan:'"
check "the container is replaced" "terraform show -no-color s9-tune.tfplan | grep -q 'docker_container.db must be replaced'"
check "the volume is not in the plan" "! terraform show -no-color s9-tune.tfplan | grep -q 'docker_volume.pgdata'"
check "plan: 1 to add, 0 to change, 1 to destroy" "terraform show -no-color s9-tune.tfplan | grep -q 'Plan: 1 to add, 0 to change, 1 to destroy'"
must_pass
run "terraform apply -input=false s9-tune.tfplan"
expect_rc 0 "container rebuilt with work_mem=32MB"
run "rm -f s9-tune.tfplan"
run "sql $TF_DB 'show work_mem'"
check "Postgres now runs with work_mem=32MB" "[ \"\$(sql $TF_DB 'show work_mem')\" = 32MB ]"
check "every row survived the rebuild" "[ \"\$(counts $TF_DB)\" = \"$BEFORE\" ]"
explain "Without -var, the blueprint's default (16MB) is back in charge: the next plan wants to rebuild again. We apply it, so the database ends as the blueprint says."
run "terraform plan -input=false -out=s9-revert.tfplan"
run "terraform apply -input=false s9-revert.tfplan"
expect_rc 0 "back to the default"
run "rm -f s9-revert.tfplan"
check "work_mem back to 16MB" "[ \"\$(sql $TF_DB 'show work_mem')\" = 16MB ]"
check "rows still intact" "[ \"\$(counts $TF_DB)\" = \"$BEFORE\" ]"
must_pass
fi

# ---------------------------------------------------------------------------
if from 9.7; then
step "9.7 — terraform destroy, refused"
explain "We ask Terraform to demolish everything. Because the volume carries prevent_destroy, Terraform refuses while planning, before a single thing is touched. -input=false is a second safety net: Terraform cannot ask for 'yes', so even without prevent_destroy it would stop."
BEFORE="$(counts $TF_DB)"
run "terraform destroy -input=false"
expect_rc 1 "destroy refused"
check "the refusal names prevent_destroy" "terraform plan -destroy -input=false -no-color 2>&1 | grep -q 'prevent_destroy'"
check "container still running" "docker inspect --format '{{.State.Running}}' $TF_DB | grep -qx true"
check "rows untouched" "[ \"\$(counts $TF_DB)\" = \"$BEFORE\" ]"
must_pass
fi

# ---------------------------------------------------------------------------
if from 9.8; then
step "9.8 — Drift: stop the container behind Terraform's back"
explain "Someone runs 'docker stop' by hand. The blueprint says the container must run (the Docker provider's must_run defaults to true). We watch what plan reports, and what Docker shows before and after the plan, then let apply repair it."
BEFORE="$(counts $TF_DB)"
run "docker stop $TF_DB"
run "docker ps -a --filter name=$TF_DB --format '{{.Names}}  {{.Status}}'"
run "terraform plan -input=false -detailed-exitcode"
expect_rc 2 "plan spots the drift"
run "docker ps -a --filter name=$TF_DB --format '{{.Names}}  {{.Status}}'"
explain "Compare the two docker ps lines above: did merely PLANNING change anything? That tells you what this provider does when it refreshes a stopped container."
run "terraform plan -input=false -out=s9-drift.tfplan"
run "terraform apply -input=false s9-drift.tfplan"
expect_rc 0 "drift repaired"
run "rm -f s9-drift.tfplan"
check "container running and healthy again" "docker inspect --format '{{.State.Health.Status}}' $TF_DB | grep -qx healthy"
check "rows untouched" "[ \"\$(counts $TF_DB)\" = \"$BEFORE\" ]"
fi

# ---------------------------------------------------------------------------
if from 9.9; then
step "9.2 follow-up — same Dockerfile, different image ID: what differs?"
explain "In 9.2 the build took 1 second (Docker's build cache) yet produced a different image ID from compose's. An image ID is a fingerprint of the image's layers PLUS its metadata. We compare the two separately."
run "docker image inspect --format '{{json .RootFS.Layers}}' ladebahn/postgres:16-postgis | shasum"
run "docker image inspect --format '{{json .RootFS.Layers}}' ladebahn/postgres:16-postgis-tf | shasum"
check "the filesystem layers are identical" \
  "[ \"\$(docker image inspect --format '{{json .RootFS.Layers}}' ladebahn/postgres:16-postgis)\" = \"\$(docker image inspect --format '{{json .RootFS.Layers}}' ladebahn/postgres:16-postgis-tf)\" ]"
run "docker image inspect --format '{{.Created}}  {{.Architecture}}  {{json .Config.Labels}}' ladebahn/postgres:16-postgis ladebahn/postgres:16-postgis-tf"

step "Checkpoint — the dependency graph"
explain "Terraform works out the build order from the references between resources. terraform graph prints that map. Each line 'A -> B' means A needs B first."
run "terraform graph | grep -- '->' | grep -v 'provider\\|root\\|meta\\|close' | sed -E 's/\"//g; s/\\[root\\] //g; s/ \\(expand\\)//g'"
step "End of Session 9 — everything matches"
run "terraform plan -input=false -detailed-exitcode"
expect_rc 0 "blueprint, state and reality agree"
run "git -C \"$ROOT\" status --short --untracked-files=all"
check "no state, tfvars or plan files visible to git" \
  "! git -C \"$ROOT\" status --short --untracked-files=all | grep -E 'tfstate|tfvars|tfplan|walkthrough/logs'"
explain "Both databases are left running: ladebahn-db (compose, 5432) and ladebahn-tf-db (Terraform, 5433). To pause the compose one, use docker compose stop as usual. Do not docker stop the Terraform one; as 9.8 showed, Terraform treats that as drift."
fi
summary
