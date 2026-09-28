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
