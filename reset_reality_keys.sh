cat << 'EOF' > fix_reality_exact.sh
#!/bin/bash

CONFIG_FILE="/usr/local/etc/xray/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="/etc/xray/config.json"
fi

# 1. 运行 /usr/local/bin/xray x25519 并精确解析密钥
KEYS_OUT=$(/usr/local/bin/xray x25519)

NEW_PRIV=$(echo "$KEYS_OUT" | grep "PrivateKey:" | awk '{print $2}')
NEW_PUB=$(echo "$KEYS_OUT" | grep "Password (PublicKey):" | awk '{print $3}')
NEW_SHORT_ID=$(openssl rand -hex 4)

if [ -z "$NEW_PRIV" ] || [ -z "$NEW_PUB" ]; then
    echo "提取密钥失败！输出内容为:"
    echo "$KEYS_OUT"
    exit 1
fi

# 2. 写入配置文件
python3 - << ENDPython
import json

config_path = "$CONFIG_FILE"
new_priv = "$NEW_PRIV"
new_short_id = "$NEW_SHORT_ID"

with open(config_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

for inbound in data.get("inbounds", []):
    stream = inbound.get("streamSettings", {})
    if stream.get("security") == "reality":
        rs = stream.get("realitySettings", {})
        rs["privateKey"] = new_priv
        
        curr_ids = rs.get("shortIds", [])
        if not isinstance(curr_ids, list):
            curr_ids = []
        if new_short_id not in curr_ids:
            curr_ids.append(new_short_id)
        rs["shortIds"] = curr_ids

with open(config_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

ENDPython

# 3. 重启服务
systemctl restart xray

echo "========================================="
if systemctl is-active --quiet xray; then
    echo -e "\e[1;32m[✔] Xray 服务已成功修复并正常运行！\e[0m"
    echo "-----------------------------------------"
    echo "请在客户端中同步更新以下参数："
    echo -e "► 公钥 (PublicKey) : \e[1;33m$NEW_PUB\e[0m"
    echo -e "► ShortID          : \e[1;33m$NEW_SHORT_ID\e[0m"
    echo "========================================="
else
    echo -e "\e[1;31m[-] Xray 启动依然报错，请运行 systemctl status xray 查看原因\e[0m"
fi

rm -f fix_reality_exact.sh
EOF

chmod +x fix_reality_exact.sh
./fix_reality_exact.sh
