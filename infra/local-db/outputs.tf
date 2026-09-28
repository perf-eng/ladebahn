output "compose_image_id" {
  description = "ID of the image docker compose built (read-only)"
  value       = data.docker_image.compose_postgres.id
}

output "terraform_image_id" {
  description = "ID of the image Terraform built"
  value       = docker_image.postgres.image_id
}

output "same_image" {
  description = "Did the same Dockerfile produce the very same image?"
  value       = data.docker_image.compose_postgres.id == docker_image.postgres.image_id
}

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
