import requests
import json

# 🔧 Konfigurácia
ZBX_URL = "http://zabbix-frontend:8080/api_jsonrpc.php"
ZBX_USER = "Admin"
ZBX_PASS = "zabbix"

# 📡 API požiadavka
def zabbix_api(method, params, auth=None, id=1):
    payload = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
        "auth": auth,
        "id": id
    }
    headers = {"Content-Type": "application/json-rpc"}
    response = requests.post(ZBX_URL, headers=headers, data=json.dumps(payload))
    return response.json()

# 🔐 Login
auth_response = zabbix_api("user.login", {
    "user": ZBX_USER,
    "password": ZBX_PASS
})
auth_token = auth_response.get("result")
print(f"Auth token: {auth_token}")

# 📦 Získaj groupid pre 'Linux servers'
group_resp = zabbix_api("hostgroup.get", {
    "filter": {"name": ["Linux servers"]}
}, auth=auth_token)
group_id = group_resp["result"][0]["groupid"]
print(f"Group ID: {group_id}")

# 🧩 Získaj templateid pre 'Template OS Linux by Zabbix agent'
template_resp = zabbix_api("template.get", {
    "filter": {"host": ["Template OS Linux by Zabbix agent"]}
}, auth=auth_token)
template_id = template_resp["result"][0]["templateid"]
print(f"Template ID: {template_id}")

# 🖥️ Vytvor hosta
create_resp = zabbix_api("host.create", {
    "host": "zabbix-agent",
    "interfaces": [{
        "type": 1,
        "main": 1,
        "useip": 1,
        "ip": "zabbix-agent",
        "dns": "",
        "port": "10050"
    }],
    "groups": [{"groupid": group_id}],
    "templates": [{"templateid": template_id}]
}, auth=auth_token)

print("✅ Host vytvorený:", create_resp)