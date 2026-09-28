output "station_name" {
  description = "The random name Terraform picked and remembers"
  value       = random_pet.station.id
}

output "greeting" {
  description = "What was written to the file"
  value       = local_file.hello.content
}
