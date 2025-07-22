#!/bin/bash

set -e
echo "🔧 Nasadzujem Zabbix stack s AppArmor, volume a Docker Compose..."

# 📁 1. Vytvorenie adresárov pre trvalé volume
echo "📦 Vytváram adresáre pre volume..."
sudo mkdir -p /zabbixvol/mysql /zabbixvol/server /zabbixvol/web /zabbixvol/agent /zabbixvol/grafana/plugins
sudo chown -R 1000:1000 /zabbixvol
sudo chmod -R 755 /zabbixvol
sudo chown -R 472:472 /zabbixvol/grafana
sudo chmod -R 755 /zabbixvol/grafana


# 🔐 2. Vytvorenie AppArmor profilov
echo "🔐 Generujem AppArmor profily..."

declare -A profiles=(
  [zabbix-agent-profile]="
#include <tunables/global>
profile zabbix-agent-profile flags=(attach_disconnected) {
  /usr/sbin/zabbix_agent2 ix,
  /var/lib/zabbix/** rw,
  /etc/zabbix/** r,
  /usr/lib/zabbix/** mr,
  network inet stream,
  capability net_bind_service,
}
"
  [grafana-profile]="
#include <tunables/global>
profile grafana-profile flags=(attach_disconnected) {
  /usr/sbin/grafana-server ix,
  /etc/grafana/** r,
  /var/lib/grafana/** rw,
  /usr/share/grafana/** r,
  network inet stream,
  capability net_bind_service,
}
"
  [mysql-profile]="
#include <tunables/global>
profile mysql-profile flags=(attach_disconnected) {
  /usr/sbin/mysqld ix,
  /var/lib/mysql/** rwk,
  /etc/mysql/** r,
  /tmp/** rw,
  capability dac_override,
  capability sys_resource,
  capability setuid,
  capability setgid,
  network inet stream,
}
"
  [zabbix-server-profile]="
#include <tunables/global>
profile zabbix-server-profile flags=(attach_disconnected) {
  /usr/sbin/zabbix_server ix,
  /var/lib/zabbix/** rw,
  /etc/zabbix/** r,
  network inet stream,
  capability net_bind_service,
}
"
  [zabbix-web-profile]="
#include <tunables/global>
profile zabbix-web-profile flags=(attach_disconnected) {
  /usr/sbin/nginx ix,
  /usr/share/zabbix/** r,
  /etc/nginx/** r,
  /tmp/** rw,
  network inet stream,
  capability net_bind_service,
}
"
)

for name in "${!profiles[@]}"; do
  echo "${profiles[$name]}" | sudo tee "/etc/apparmor.d/$name" > /dev/null
  sudo apparmor_parser -r "/etc/apparmor.d/$name"
done

# 📄 3. Vytvorenie .env súboru
echo "📄 Generujem .env súbor..."
cat <<EOF > .env
MYSQL_DATABASE=zabbix
MYSQL_USER=zabbix
MYSQL_PASSWORD=Z@bbixUser
MYSQL_ROOT_PASSWORD=R@@tUser

ZBX_SERVER_HOST=zabbix-server
ZBX_HOSTNAME=docker-agent

PHP_TZ=Europe/Bratislava
EOF

# 🛠️ 4. Vytvorenie docker-compose.yml
echo "📄 Generujem docker-compose.yml..."
cat <<EOF > docker-compose.yml
services:
  mysql:
    image: mysql:5.7
    container_name: zabbix-mysql
    environment:
      MYSQL_DATABASE: \${MYSQL_DATABASE}
      MYSQL_USER: \${MYSQL_USER}
      MYSQL_PASSWORD: \${MYSQL_PASSWORD}
      MYSQL_ROOT_PASSWORD: \${MYSQL_ROOT_PASSWORD}
    volumes:
      - /zabbixvol/mysql:/var/lib/mysql
    restart: always
    security_opt:
      - apparmor=mysql-profile

  zabbix-server:
    image: zabbix/zabbix-server-mysql:latest
    container_name: zabbix-server
    depends_on:
      - mysql
    environment:
      DB_SERVER_HOST: mysql
      MYSQL_DATABASE: \${MYSQL_DATABASE}
      MYSQL_USER: \${MYSQL_USER}
      MYSQL_PASSWORD: \${MYSQL_PASSWORD}
    volumes:
      - /zabbixvol/server:/var/lib/zabbix
    ports:
      - "10061:10051"
    restart: always
    security_opt:
      - apparmor=zabbix-server-profile

  zabbix-web:
    image: zabbix/zabbix-web-nginx-mysql:latest
    container_name: zabbix-web
    depends_on:
      - mysql
      - zabbix-server
    environment:
      DB_SERVER_HOST: mysql
      ZBX_SERVER_HOST: \${ZBX_SERVER_HOST}
      MYSQL_DATABASE: \${MYSQL_DATABASE}
      MYSQL_USER: \${MYSQL_USER}
      MYSQL_PASSWORD: \${MYSQL_PASSWORD}
      PHP_TZ: \${PHP_TZ}
    volumes:
      - /zabbixvol/web:/usr/share/zabbix
    ports:
      - "8090:8080"
    restart: always
    security_opt:
      - apparmor=zabbix-web-profile

  zabbix-agent:
    image: zabbix/zabbix-agent2:latest
    container_name: zabbix-agent
    environment:
      ZBX_SERVER_HOST: \${ZBX_SERVER_HOST}
      ZBX_HOSTNAME: \${ZBX_HOSTNAME}
    volumes:
      - /zabbixvol/agent:/var/lib/zabbix
    ports:
      - "10060:10050"
    restart: always
    security_opt:
      - apparmor=zabbix-agent-profile

  grafana:
    image: grafana/grafana:latest
    container_name: zabbix-grafana
    ports:
      - "3010:3000"
    volumes:
      - /zabbixvol/grafana:/var/lib/grafana
      - /zabbixvol/grafana/plugins:/var/lib/grafana/plugins
    restart: always
    security_opt:
      - apparmor=grafana-profile
EOF

echo "✅ Hotovo! Spusti stack pomocou: docker-compose up -d"
