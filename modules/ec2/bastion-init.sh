#!/bin/bash
set -e

# Forward SSH
echo "AllowTcpForwarding yes" | sudo tee -a /etc/ssh/sshd_config
echo "PermitTunnel yes" | sudo tee -a /etc/ssh/sshd_config
echo "AllowAgentForwarding yes" | sudo tee -a /etc/ssh/sshd_config
sudo systemctl restart sshd