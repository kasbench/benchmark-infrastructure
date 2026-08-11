output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.benchmark.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "selected_availability_zone" {
  description = "The availability zone selected for all resources"
  value       = local.selected_az
}

output "igw_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "route_table_ids" {
  description = "Map of route table IDs"
  value = {
    public = aws_route_table.public.id
  }
}
