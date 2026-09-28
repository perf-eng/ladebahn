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
