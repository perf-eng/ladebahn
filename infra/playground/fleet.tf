variable "cities" {
  type    = list(string)
  default = ["Berlin", "Hamburg", "München"]
}

# count: copies identified by POSITION — [0], [1], [2]
resource "local_file" "by_count" {
  count    = length(var.cities)
  filename = "${path.module}/stations/by-count-${count.index}.txt"
  content  = "${var.cities[count.index]}\n"
}

# for_each: copies identified by NAME — ["Berlin"], ["Hamburg"], ...
resource "local_file" "by_name" {
  for_each = toset(var.cities)
  filename = "${path.module}/stations/by-name-${each.key}.txt"
  content  = "${each.key}\n"
}
