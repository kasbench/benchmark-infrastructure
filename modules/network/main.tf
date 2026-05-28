resource "aws_vpc" "benchmark" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = "kasbench-vpc" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.benchmark.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = local.selected_az
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = "kasbench-public" })
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.benchmark.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = local.selected_az
  tags              = merge(var.tags, { Name = "kasbench-private" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.benchmark.id
  tags   = merge(var.tags, { Name = "kasbench-igw" })
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "kasbench-nat-eip" })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = merge(var.tags, { Name = "kasbench-nat-gw" })
  depends_on    = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.benchmark.id
  tags   = merge(var.tags, { Name = "kasbench-public-rt" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.benchmark.id
  tags   = merge(var.tags, { Name = "kasbench-private-rt" })
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
