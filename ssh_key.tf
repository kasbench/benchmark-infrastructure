resource "tls_private_key" "fleet_key" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "fleet_key" {
  key_name   = "kasbench-${var.run_id}"
  public_key = tls_private_key.fleet_key.public_key_openssh
}

resource "local_sensitive_file" "fleet_private_key" {
  content         = tls_private_key.fleet_key.private_key_pem
  filename        = "${local.artifact_output_path}fleet_key.pem"
  file_permission = "0600"
}
