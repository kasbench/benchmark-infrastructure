# modules/compute/user_data.tf

locals {
  cloud_init_script = <<-EOF
    #!/bin/bash
    set -euo pipefail

    # Inject fleet public key into authorized_keys for the default user
    AUTHORIZED_KEYS_FILE="/home/ubuntu/.ssh/authorized_keys"
    mkdir -p "$(dirname "$AUTHORIZED_KEYS_FILE")"
    echo "${var.fleet_public_key}" >> "$AUTHORIZED_KEYS_FILE"
    chmod 600 "$AUTHORIZED_KEYS_FILE"
    chown ubuntu:ubuntu "$AUTHORIZED_KEYS_FILE"

    # Enable SSH agent forwarding
    echo "AllowAgentForwarding yes" >> /etc/ssh/sshd_config

    # Restart SSH to apply changes
    systemctl restart ssh
  EOF
}
