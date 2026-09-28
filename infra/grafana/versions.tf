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
