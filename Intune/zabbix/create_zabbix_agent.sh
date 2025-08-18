#!/bin/bash

# 🔧 Nastavenie
ZBX_URL="http://zabbix-frontend:8080/api_jsonrpc.php"
ZBX_USER="Admin"
ZBX_PASS="zabbix"

# 🧪 Získaj API token
AUTH_TOKEN=$(curl -s -X POST -H 'Content-Type: application/json-rpc' \
  -d '{
    "jsonrpc": "2.0",
    "method": "user.login",
    "params": {
      "user": "'"$ZBX_USER"'",
      "password": "'"$ZBX_PASS"'"
    },
    "id": 1,
    "auth": null
  }' "$ZBX_URL" | jq -r .result)

echo "🔐 Auth token: $AUTH_TOKEN"

# 🔍 Získaj ID skupiny (napr. Linux servers)
GROUP_ID=$(curl -s -X POST -H 'Content-Type: application/json-rpc' \
  -d '{
    "jsonrpc": "2.0",
    "method": "hostgroup.get",
    "params": {
      "filter": {
        "name": ["Linux servers"]
      }
    },
    "auth": "'"$AUTH_TOKEN"'",
    "id": 2
  }' "$ZBX_URL" | jq -r '.result[0].groupid')

echo "📦 Group ID: $GROUP_ID"

# 🖥️ Vytvor hosta `zabbix-agent`
curl -s -X POST -H 'Content-Type: application/json-rpc' \
  -d '{
    "jsonrpc": "2.0",
    "method": "host.create",
    "params": {
      "host": "zabbix-agent",
      "interfaces": [
        {
          "type": 1,
          "main": 1,
          "useip": 1,
          "ip": "zabbix-agent",
          "dns": "",
          "port": "10050"
        }
      ],
      "groups": [
        {
          "groupid": "'"$GROUP_ID"'"
        }
      ],
      "templates": [
        {
          "templateid": "10001"
        }
      ]
    },
    "auth": "'"$AUTH_TOKEN"'",
    "id": 3
  }' "$ZBX_URL" | jq .
