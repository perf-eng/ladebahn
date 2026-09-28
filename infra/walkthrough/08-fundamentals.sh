#!/usr/bin/env bash
# Session 8 — Terraform fundamentals, steps 8.5b to 8.6.
# Run from anywhere:  bash ~/dev/ladebahn/infra/walkthrough/08-fundamentals.sh
source "$(dirname "$0")/lib.sh"
start_transcript 08-fundamentals
cd "$ROOT/infra/playground" || exit 1

step "Where we start"
explain "Everything in this session happens in infra/playground, on the Mac only. No cloud, no cost. The playground already holds a random name (cunning-buffalo) and a text file, and 8.5a added variables.tf and outputs.tf."
run "pwd"
run "terraform version"
run "terraform state list"
check "state still holds the pet and the file" "terraform state list | grep -qx random_pet.station && terraform state list | grep -qx local_file.hello"
must_pass

# ---------------------------------------------------------------------------
step "8.5b — Save the quote, then build exactly that quote"
explain "Until now, apply made a fresh quote and asked for 'yes'. Here we save the quote to a file with -out, then hand that file to apply. Apply then does exactly what the saved quote says and nothing else, with no second quote and no prompt, because the saved plan IS the approval. This is how careful teams work: the plan that was reviewed is the plan that runs. Plan files are gitignored because they can contain secrets."
run "terraform plan -out=s8.tfplan"
expect_rc 0 "plan saved"
check "the saved quote rebuilds the file: 1 to add, 0 to change, 1 to destroy" \
  "terraform show -no-color s8.tfplan | grep -q 'Plan: 1 to add, 0 to change, 1 to destroy'"
run "terraform apply s8.tfplan"
expect_rc 0 "saved plan applied without a prompt"
run "rm -f s8.tfplan"
must_pass

explain "Now read the handover note (the outputs) three ways: all of it, one value bare for scripts, and where it is stored."
run "cat hello.txt"
run "shasum hello.txt"
check "file fingerprint is 3745b942… (worked out in advance from the new text)" \
  "[ \"\$(shasum hello.txt | cut -d' ' -f1)\" = 3745b942ceeacdee210dad589f4e3b01605c23f8 ]"
run "terraform output"
run "terraform output -raw station_name; echo"
check "output -raw gives the bare name" "[ \"\$(terraform output -raw station_name)\" = cunning-buffalo ]"
run "grep -A10 '\"outputs\"' terraform.tfstate"
explain "Outputs live in the state file too. If an output ever held a password, it would sit in this file in plain text."

# ---------------------------------------------------------------------------
step "8.5c — Validation: rules on what may go in a blank"
explain "A variable's type says what KIND of answer is allowed (text, number). A validation rule says which answers make sense. Here: the city must be one the Ladebahn seeder knows, and the name must have 1 to 4 words. A bad answer is refused while planning, before anything is touched."
cat > variables.tf << 'EOF'
variable "city" {
  description = "City the playground station is in"
  type        = string
  default     = "Berlin"

  validation {
    condition     = contains(["Berlin", "Hamburg", "München"], var.city)
    error_message = "The city must be one the Ladebahn seeder knows: Berlin, Hamburg or München."
  }
}

variable "name_words" {
  description = "How many words in the random station name"
  type        = number
  default     = 2

  validation {
    condition     = var.name_words >= 1 && var.name_words <= 4
    error_message = "The station name needs between 1 and 4 words."
  }
}
EOF
run "cat variables.tf"
explain "-detailed-exitcode makes plan answer with its exit code: 0 = no changes, 2 = changes, 1 = error. Scripts and CI use this instead of reading the text."
run "terraform plan -detailed-exitcode"
expect_rc 0 "defaults pass validation and nothing changes"
run "terraform plan -var city=Paris"
expect_rc 1 "city=Paris refused"
run "terraform plan -var name_words=9"
expect_rc 1 "name_words=9 refused"
check "file untouched by the refused plans" \
  "[ \"\$(shasum hello.txt | cut -d' ' -f1)\" = 3745b942ceeacdee210dad589f4e3b01605c23f8 ]"

# ---------------------------------------------------------------------------
step "8.5d — Locals: give an expression a name"
explain "A local is a named calculation inside the blueprint. It is not a blank anyone fills in; it just saves repeating yourself. We move the greeting text into a local. The text it produces is identical, so the plan must say No changes. A refactor that plans 'No changes' is a refactor proven safe."
cat > locals.tf << 'EOF'
locals {
  # A named expression: worked out once, usable anywhere in this folder
  greeting = "Ladebahn playground: station ${random_pet.station.id} in ${var.city}\n"
}
EOF
cat > main.tf << 'EOF'
terraform {
  required_version = ">= 1.16.0"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# Something Terraform creates and must remember: a random name
resource "random_pet" "station" {
  length    = var.name_words
  separator = "-"
}

# A real object on disk that depends on the name above
resource "local_file" "hello" {
  filename = "${path.module}/hello.txt"
  content  = local.greeting
}
EOF
run "cat locals.tf"
run "grep -n 'content' main.tf"
run "terraform plan -detailed-exitcode"
expect_rc 0 "refactor to a local changes nothing"

# ---------------------------------------------------------------------------
step "8.5e — Who wins when a blank is filled in several places"
explain "A variable can get its answer from: the default in variables.tf, an environment variable named TF_VAR_<name>, a .tfvars file, or -var on the command line. When several are given, the more specific one wins: default < environment variable < .tfvars file < -var. (A file named terraform.tfvars or *.auto.tfvars is loaded automatically without any flag.) We only PLAN here and read which city the quote would write."
cat > muenchen.tfvars << 'EOF'
city = "München"
EOF
run "git check-ignore -v muenchen.tfvars"
expect_rc 0 "the .tfvars file is gitignored"
city_in_plan() { # prints the city the plan would write, or "Berlin (no change)"
  terraform plan -no-color "$@" 2>&1 | sed -nE 's/^ +\+ Ladebahn playground: station [a-z-]+ in (.*)$/\1/p' | tail -1 | grep . || echo "Berlin (no change)"
}
run "city_in_plan"
check "default only → Berlin" "[ \"\$(city_in_plan)\" = 'Berlin (no change)' ]"
run "TF_VAR_city=Hamburg city_in_plan"
check "environment variable beats the default → Hamburg" "[ \"\$(TF_VAR_city=Hamburg city_in_plan)\" = Hamburg ]"
run "TF_VAR_city=Hamburg city_in_plan -var-file=muenchen.tfvars"
check ".tfvars file beats the environment variable → München" "[ \"\$(TF_VAR_city=Hamburg city_in_plan -var-file=muenchen.tfvars)\" = München ]"
run "TF_VAR_city=Hamburg city_in_plan -var-file=muenchen.tfvars -var city=Berlin"
check "-var on the command line beats everything → Berlin" "[ \"\$(TF_VAR_city=Hamburg city_in_plan -var-file=muenchen.tfvars -var city=Berlin)\" = 'Berlin (no change)' ]"
run "rm muenchen.tfvars"

# ---------------------------------------------------------------------------
step "8.6a — fmt: one agreed layout for every .tf file"
explain "terraform fmt rewrites .tf files into the standard layout (indentation, aligned = signs). It never changes meaning, only whitespace. We write the next file deliberately messy, let fmt -check spot it, then let fmt fix it. In CI, fmt -check is the gate that fails a badly formatted change."
cat > fleet.tf << 'EOF'
variable "cities" {
type = list(string)
    default = ["Berlin","Hamburg","München"]
}

# count: copies identified by POSITION — [0], [1], [2]
resource "local_file" "by_count" {
  count = length(var.cities)
      filename="${path.module}/stations/by-count-${count.index}.txt"
  content = "${var.cities[count.index]}\n"
}

# for_each: copies identified by NAME — ["Berlin"], ["Hamburg"], ...
resource "local_file" "by_name" {
for_each = toset(var.cities)
  filename = "${path.module}/stations/by-name-${each.key}.txt"
  content  =   "${each.key}\n"
}
EOF
run "terraform fmt -check -diff"
check "fmt -check flags the messy file" "[ \"\$RC\" -ne 0 ]"
run "terraform fmt"
run "terraform fmt -check"
expect_rc 0 "everything is now in the standard layout"
run "cat fleet.tf"

# ---------------------------------------------------------------------------
step "8.6b — validate: is the blueprint itself sound?"
explain "validate checks the blueprint on its own: spelling of references, types, required arguments. It reads no state, touches no reality and needs no network, so it is fast enough to run on every save. To see it work, we add a file with a typo (var.cty instead of var.city), let validate catch it, then remove the file."
run "terraform validate"
expect_rc 0 "blueprint is valid"
printf 'output "typo" {\n  value = var.cty\n}\n' > typo.tf
run "terraform validate"
expect_rc 1 "validate catches the undeclared variable"
run "rm typo.tf"
run "terraform validate"
expect_rc 0 "valid again"
must_pass

# ---------------------------------------------------------------------------
step "8.6c — console: a calculator that knows your blueprint and state"
explain "terraform console evaluates any expression against this folder's variables, locals and state, and changes nothing. It is the quickest way to test a function or a for-expression before putting it in a file."
run "echo 'var.city' | terraform console"
run "echo 'upper(var.city)' | terraform console"
run "echo 'random_pet.station.id' | terraform console"
run "echo 'length(var.cities)' | terraform console"
run "echo 'toset(var.cities)' | terraform console"
run "echo '[for c in var.cities : lower(c)]' | terraform console"
check "console reads state: the pet is cunning-buffalo" "[ \"\$(echo 'random_pet.station.id' | terraform console)\" = '\"cunning-buffalo\"' ]"

# ---------------------------------------------------------------------------
step "8.6d — count vs for_each: making several copies"
explain "Both build several copies from one block. count numbers them by position: [0], [1], [2]. for_each names them by key: [\"Berlin\"], [\"Hamburg\"]. We build three cities both ways, then ask what happens if Hamburg, the middle one, is removed."
run "terraform plan -out=s8-fleet.tfplan"
check "6 files to add, nothing else" "terraform show -no-color s8-fleet.tfplan | grep -q 'Plan: 6 to add, 0 to change, 0 to destroy'"
run "terraform apply s8-fleet.tfplan"
expect_rc 0 "six files built"
run "rm -f s8-fleet.tfplan"
run "ls stations"
run "terraform state list"
explain "Now only a quote, never applied: remove Hamburg from the list."
run "terraform plan -no-color -var 'cities=[\"Berlin\",\"München\"]' | grep -E '^  # |^Plan:'"
check "removing the middle city: 1 to add, 0 to change, 3 to destroy" \
  "terraform plan -no-color -var 'cities=[\"Berlin\",\"München\"]' | grep -q 'Plan: 1 to add, 0 to change, 3 to destroy'"
explain "Read those lines. The for_each copies lose exactly one: by_name[\"Hamburg\"]. The count copies lose two and rebuild one: München slides from position 2 to position 1, so by_count[1] is rewritten from Hamburg to München and by_count[2] is destroyed. Nothing about München changed, yet count rebuilds it. With files that is harmless; with dashboards or databases it is not. That is why Session 10 uses for_each for one dashboard per environment."

# ---------------------------------------------------------------------------
step "End of Session 8 — everything matches"
run "terraform plan -detailed-exitcode"
expect_rc 0 "blueprint, state and reality agree"
run "git -C \"$ROOT\" status --short --untracked-files=all"
check "no state, tfvars, plan files or generated files visible to git" \
  "! git -C \"$ROOT\" status --short --untracked-files=all | grep -E 'tfstate|tfvars|tfplan|hello.txt|stations/|walkthrough/logs'"
summary
