data "aws_availability_zones" "available" {
  state = "available"
}

resource "random_shuffle" "az" {
  count        = var.availability_zone_mode == "random" ? 1 : 0
  input        = data.aws_availability_zones.available.names
  result_count = 1
}

locals {
  selected_az = (
    var.availability_zone_mode == "explicit"
    ? var.availability_zone
    : random_shuffle.az[0].result[0]
  )
}
