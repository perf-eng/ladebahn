# Read-only: the image docker compose already built. Terraform looks, never touches.
data "docker_image" "compose_postgres" {
  name = "ladebahn/postgres:16-postgis"
}
