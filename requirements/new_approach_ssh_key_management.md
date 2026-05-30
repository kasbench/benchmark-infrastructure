For short-lived testing environments where you don't want to deal with complex setups (like Bastion hosts, HashiCorp Vault, or AWS Systems Manager Session Manager), the best approach is to combine **SSH Agent Forwarding** with an OpenTofu-managed single key pair.

Because you explicitly noted that this is a non-production testing fleet containing no real data, generating a key pair via OpenTofu's `tls` provider and injecting it into the hosts via AWS user data strikes the perfect balance between simple automation and reasonable security.

Here is the exact strategy and how to implement it.

---

## The Strategy: Agent Forwarding + Dual Key Injection

1. **Host-to-Host:** To allow hosts to SSH to each other without storing a fragile private key on the instances themselves, you will use **SSH Agent Forwarding**. Your local OpenTofu runner holds the key in memory and securely passes authentication along.
2. **Runner-to-Public Host:** OpenTofu will generate a temporary RSA/ED25519 key pair, register the public key to AWS, and download the private key locally to your runner so you can establish the initial connection.
3. **Backup Fallback:** To make fleet communication effortless, OpenTofu will also pass that same generated public key into the Ubuntu `cloud-init` configuration. This forces all hosts to natively trust that specific key if they ever need to authenticate directly within the fleet.

---

## The OpenTofu Implementation

Create a `main.tf` file using the code below. It handles generating the key, provisioning the AWS key pair, writing the private key locally, and assigning it to your fleet.

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" # Change to your region
}

# 1. Generate an ephemeral SSH Private Key
resource "tls_private_key" "fleet_key" {
  algorithm = "ED25519"
}

# 2. Register the Public Key with AWS EC2
resource "aws_key_pair" "aws_fleet_key" {
  key_name   = "testing-fleet-key"
  public_key = tls_private_key.fleet_key.public_key_openssh
}

# 3. Save the Private Key locally to the OpenTofu machine
resource "local_sensitive_file" "private_key_pem" {
  content         = tls_private_key.fleet_key.private_key_pem
  filename        = "${path.module}/fleet_key.pem"
  file_permission = "0600"
}

# 4. Security Group allowing SSH internally and from your current location
resource "aws_security_group" "fleet_sg" {
  name        = "fleet-ssh-sg"
  description = "Allow internal SSH and external runner SSH"

  # External SSH (Your OpenTofu Runner machine)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # For tighter security, replace with your runner's specific IP (e.g., "1.2.3.4/32")
  }

  # Internal SSH (Host to Host inside the fleet)
  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 5. Spin up the Fleet (Example: 3 Hosts)
resource "aws_instance" "fleet" {
  count         = 3
  ami           = "ami-0c7217cdde317cfec" # Update with a valid Ubuntu AMI ID for your region
  instance_type = "t3.micro"
  
  key_name               = aws_key_pair.aws_fleet_key.key_name
  vpc_security_group_ids = [aws_security_group.fleet_sg.id]

  # Ensure they have public IPs if they are in a public subnet
  associate_public_ip_address = true 

  # User data ensures that Ubuntu's built-in SSH daemon allows agent forwarding
  user_data = <<-EOF
              #!/bin/bash
              echo "AllowAgentForwarding yes" >> /etc/ssh/sshd_config
              systemctl restart ssh
              EOF

  tags = {
    Name = "fleet-host-${count.index}"
  }
}

output "public_ips" {
  value = aws_instance.fleet[*].public_ip
}

```

---

## How to Connect and Inter-communicate

Once you run `tofu apply`, OpenTofu will drop a file named `fleet_key.pem` right next to your configuration files. Follow these steps to use it:

### Step 1: Add the key to your local SSH Agent

On your Ubuntu runner hosting OpenTofu, start your SSH agent and feed it the newly generated private key:

```bash
eval $(ssh-agent -s)
chmod 600 fleet_key.pem
ssh-add fleet_key.pem

```

### Step 2: SSH into the Public Host with Agent Forwarding

When connecting to your first public instance, pass the `-A` flag. This flag tells SSH to forward your local agent's keys securely to the target machine's memory, without ever writing the physical private key to the instance's disk.

```bash
ssh -A ubuntu@<PUBLIC_IP_OF_HOST_0>

```

### Step 3: Jump to another Fleet Host

Once you are inside `host-0`, you can seamlessly SSH directly into `host-1` or `host-2` using their private or public IPs. Because your agent was forwarded, the target host will challenge `host-0`, which routes the request back to your local runner's memory to fulfill the handshake:

```bash
# Executed from inside host-0:
ssh ubuntu@<IP_OF_HOST_1>

```

> ⚠️ **A Note on State Security:** Because the `tls_private_key` resource generates the key material directly inside OpenTofu, the private key will be saved in plaintext within your `terraform.tfstate` file. Since this is an ephemeral testing sandbox, this is standard practice—just make sure your state file isn't pushed to a public GitHub repository.