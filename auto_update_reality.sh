cat << 'EOF' > auto_update_reality_keep_old.sh
#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo -e "\e[1;31m[-] 请使用 root 权限运行此脚本！\e[0m"
  exit 1
fi

CONFIG_FILE=""
POSSIBLE_PATHS=(
    "/usr/local/etc/xray/config.json"
    "/etc/xray/config.json"
    "/etc/XrayR/config.json"
)

for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        CONFIG_FILE="$path"
        break
    fi
done

if [ -z "$CONFIG_FILE" ]; then
    echo -e "\e[1;31m[-] 未自动检测到 config.json 路径！\e[0m"
    exit 1
fi

DOMAINS=(
    "images.unsplash.com"
    "www.lovelive-anime.jp"
    "www.nvidia.com"
    "www.twitch.tv"
    "www.spotify.com"
    "www.autodesk.com"
    "www.target.com"
    "www.amd.com"
    "www.dell.com"
    "www.qualcomm.com"
    "www.shopify.com"
    "www.cisco.com"
)

TEMP_FILE=$(mktemp)

for domain in "${DOMAINS[@]}"; do
    RES=$(curl -ivs "https://${domain}" --connect-timeout 2 \
        -o /dev/null \
        -w "%{time_connect}\n" 2>&1)

    TLS13=false
    H2=false
    
    if echo "$RES" | grep -qE "TLSv1.3|using TLSv1.3"; then TLS13=true; fi
    if echo "$RES" | grep -qE "ALPN.*h2|accepted to use h2|HTTP/2 confirmed"; then H2=true; fi

    TIME_CONN=$(echo "$RES" | tail -n1)

    if [[ "$TIME_CONN" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [ "$(echo "$TIME_CONN > 0" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
        LATENCY_MS=$(awk "BEGIN {printf \"%.2f\", $TIME_CONN * 1000}")
        if [ "$TLS13" = true ] && [ "$H2" = true ]; then
            echo "${LATENCY_MS}|${domain}" >> "$TEMP_FILE"
        fi
    fi
done

BEST_DOMAIN=$(sort -n -t'|' -k1 "$TEMP_FILE" | head -n 3 | shuf -n 1 | cut -d'|' -f2)
rm -f "$TEMP_FILE"

if [ -z "$BEST_DOMAIN" ]; then
    echo -e "\e[1;31m[-] 未检测到合格的伪装域名，请检查网络！\e[0m"
    exit 1
fi

NEW_SHORT_ID=$(openssl rand -hex 4)
BACKUP_FILE="${CONFIG_FILE}.bak_$(date +%Y%m%d%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"

# Python 精确合并 shortIds 数组
python3 - << ENDPython
import json

config_path = "$CONFIG_FILE"
new_sni = "$BEST_DOMAIN"
new_short_id = "$NEW_SHORT_ID"

try:
    with open(config_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    modified = False
    if "inbounds" in data:
        for inbound in data["inbounds"]:
            stream_settings = inbound.get("streamSettings", {})
            if stream_settings.get("security") == "reality":
                reality_settings = stream_settings.get("realitySettings", {})
                
                # 仅更新域名
                reality_settings["dest"] = f"{new_sni}:443"
                reality_settings["serverNames"] = [new_sni]
                
                # 读取已有的 shortIds 并追加新的，保持旧 ID 不丢失
                existing_short_ids = reality_settings.get("shortIds", [])
                if not isinstance(existing_short_ids, list):
                    existing_short_ids = []
                
                # 确保空字符串或重复项被过滤
                if new_short_id not in existing_short_ids:
                    existing_short_ids.append(new_short_id)
                
                reality_settings["shortIds"] = existing_short_ids
                stream_settings["realitySettings"] = reality_settings
                modified = True

    if modified:
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print("SUCCESS")
    else:
        print("NO_REALITY")

except Exception as e:
    print(f"ERROR: {str(e)}")
ENDPython

if systemctl is-active --quiet xray; then
    systemctl restart xray
elif systemctl is-active --quiet XrayR; then
    systemctl restart XrayR
fi

echo -e "\e[1;34m===============================================================\e[0m"
echo -e "\e[1;32m[✔] 配置文件更新完成（已保留所有旧 ShortID）！\e[0m"
echo -e "    ► 最新选定 SNI : \e[1;33m$BEST_DOMAIN\e[0m"
echo -e "\e[1;34m===============================================================\e[0m"

rm -f auto_update_reality_keep_old.sh
EOF

chmod +x auto_update_reality_keep_old.sh
./auto_update_reality_keep_old.sh
