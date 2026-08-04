cat << 'EOF' > auto_update_reality.sh
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

# 筛选出的优质、绝无 Cloudflare 5秒盾的自建/大厂域名列表
DOMAINS=(
    "swdist.apple.com"
    "updates-http.cdn-apple.com"
    "dl.google.com"
    "www.microsoft.com"
    "www.dell.com"
    "www.samsung.com"
    "www.cisco.com"
    "www.oracle.com"
    "www.visa.com"
    "www.qualcomm.com"
    "www.autodesk.com"
)

TEMP_FILE=$(mktemp)

echo -e "\e[1;34m[*] 正在测速并检测域名 TLS1.3 / H2 支持情况...\e[0m"

for domain in "${DOMAINS[@]}"; do
    # 1. 抓取 TLS 调试日志到变量
    CURL_LOG=$(curl -ivs "https://${domain}" --connect-timeout 2 -o /dev/null 2>&1)
    
    # 2. 抓取连接时间
    TIME_CONN=$(curl -s -o /dev/null -w "%{time_connect}" "https://${domain}" --connect-timeout 2)

    TLS13=false
    H2=false
    
    if echo "$CURL_LOG" | grep -qE "TLSv1.3|using TLSv1.3"; then TLS13=true; fi
    if echo "$CURL_LOG" | grep -qE "ALPN.*h2|accepted to use h2|HTTP/2 confirmed"; then H2=true; fi

    if [[ "$TIME_CONN" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [ "$(awk "BEGIN {print ($TIME_CONN > 0)?1:0}")" -eq 1 ]; then
        LATENCY_MS=$(awk "BEGIN {printf \"%.2f\", $TIME_CONN * 1000}")
        if [ "$TLS13" = true ] && [ "$H2" = true ]; then
            echo "${LATENCY_MS}|${domain}" >> "$TEMP_FILE"
            echo -e "  [+] \e[1;32m$domain\e[0m - 延迟: ${LATENCY_MS}ms (TLS1.3: Yes, H2: Yes)"
        fi
    fi
done

if [ ! -s "$TEMP_FILE" ]; then
    echo -e "\e[1;31m[-] 未检测到合格的伪装域名，请检查 VPS 外网连接！\e[0m"
    rm -f "$TEMP_FILE"
    exit 1
fi

BEST_DOMAIN=$(sort -n -t'|' -k1 "$TEMP_FILE" | head -n 3 | shuf -n 1 | cut -d'|' -f2)
rm -f "$TEMP_FILE"

NEW_SHORT_ID=$(openssl rand -hex 4)
BACKUP_FILE="${CONFIG_FILE}.bak_$(date +%Y%m%d%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"

# 调用 Python 修改 JSON 配置
PY_RES=$(python3 - << ENDPython
import json, sys

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
)

if [ "$PY_RES" != "SUCCESS" ]; then
    echo -e "\e[1;31m[-] 修改 JSON 失败！错误信息: $PY_RES\e[0m"
    exit 1
fi

if systemctl is-active --quiet xray; then
    systemctl restart xray
elif systemctl is-active --quiet XrayR; then
    systemctl restart XrayR
fi

echo -e "\e[1;34m===============================================================\e[0m"
echo -e "\e[1;32m[✔] 配置文件更新完成（已自动追加新 ShortID 并保留旧 ID）！\e[0m"
echo -e "    ► 优选 SNI 域名 : \e[1;33m$BEST_DOMAIN\e[0m"
echo -e "    ► 新增 ShortID  : \e[1;33m$NEW_SHORT_ID\e[0m"
echo -e "    ► 配置备份文件  : \e[1;30m$BACKUP_FILE\e[0m"
echo -e "\e[1;34m===============================================================\e[0m"

rm -f auto_update_reality_keep_old.sh
EOF

chmod +x auto_update_reality_keep_old.sh
./auto_update_reality_keep_old.sh
