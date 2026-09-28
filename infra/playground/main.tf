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
