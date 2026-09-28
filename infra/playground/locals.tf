locals {
  # A named expression: worked out once, usable anywhere in this folder
  greeting = "Ladebahn playground: station ${random_pet.station.id} in ${var.city}\n"
}
