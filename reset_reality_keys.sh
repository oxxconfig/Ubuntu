cat << 'EOF' > reset_reality_keys.sh
#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行！"
  exit 1
fi

CONFIG_FILE="/usr/local/etc/xray/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="/etc/xray/config.json"
fi

# 生成新密钥对
KEYS=$(xray x25519)
NEW_PRIV=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
NEW_PUB=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')
NEW_SHORT_ID=$(openssl rand -hex 4)

python3 - << ENDPython
import json

config_path = "$CONFIG_FILE"
new_priv = "$NEW_PRIV"
new_short_id = "$NEW_SHORT_ID"

with open(config_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

for inbound in data.get("inbounds", []):
    stream_settings = inbound.get("streamSettings", {})
    if stream_settings.get("security") == "reality":
        rs = stream_settings.get("realitySettings", {})
        rs["privateKey"] = new_priv
        rs["shortIds"] = [new_short_id]

with open(config_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

ENDPython

systemctl restart xray

echo "========================================="
echo "REALITY 状态已彻底重置！"
echo "请将以下新参数更新至客户端："
echo "► Public Key (公钥) : $NEW_PUB"
echo "► Short ID           : $NEW_SHORT_ID"
echo "========================================="

rm -f reset_reality_keys.sh
EOF

chmod +x reset_reality_keys.sh
./reset_reality_keys.sh
