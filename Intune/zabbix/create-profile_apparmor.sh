#!/bin/bash

set -e

echo "🔐 Vytváram AppArmor profily..."

# Zabbix Agent profile
cat <<EOF | sudo tee /etc/apparmor.d/zabbix-agent-profile > /dev/null
#include <tunables/global>

profile zabbix-agent-profile flags=(attach_disconnected) {
  /usr/sbin/zabbix_agent2 ix,
  /etc/zabbix/** r,
  /var/lib/zabbix/** rw,
  /var/log/zabbix/** rw,
  /usr/lib/zabbix/** mr,
  network inet stream,
  capability net_bind_service,
}
EOF

# Grafana profile
cat <<EOF | sudo tee /etc/apparmor.d/grafana-profile > /dev/null
#include <tunables/global>

profile grafana-profile flags=(attach_disconnected) {
  /usr/sbin/grafana