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
