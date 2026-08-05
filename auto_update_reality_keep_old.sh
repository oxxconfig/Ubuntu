#!/bin/bash

# =============================================================================
# Xray REALITY 动态优选与配置修复脚本 (精细化检测修正版)
# =============================================================================

if [ "$EUID" -ne 0 ]; then
  echo -e "\e[1;31m[-] 请使用 root 权限运行此脚本！\e[0m"
  exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo -e "\e[1;33m[*] 未检测到 python3，正在尝试自动安装...\e[0m"
    if command -v apt-get &> /dev/null; then
        apt-get update -y && apt-get install -y python3
    elif command -v yum &> /dev/null; then
        yum install -y python3
    elif command -v dnf &> /dev/null; then
        dnf install -y python3
    fi
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
    echo -e "\e[1;31m[-] 未自动检测到 Xray config.json 配置文件！\e[0m"
    exit 1
fi

# 精选优质 REALITY 伪装域名池
DOMAINS=(
    "mora.jp"
    "www.lovelive-anime.jp"
    "tidal.com"
    "www.sky.com"
    "mxj.myanimelist.net"
    "images.unsplash.com"
    "dl.acm.org"
)

TARGET_SHORT_ID="67d93779"
TEMP_FILE=$(mktemp)
QUALIFIED_COUNT=0

echo -e "\e[1;34m[*] 正在测速并检测域名 TLS1.3 / H2 连接状态...\e[0m"

for domain in "${DOMAINS[@]}"; do
    CURL_LOG=$(curl -ivs "https://${domain}" --connect-timeout 2 --max-time 3 -o /dev/null 2>&1)
    TIME_CONN=$(curl -s -o /dev/null -w "%{time_connect}" "https://${domain}" --connect-timeout 2 --max-time 3)

    TLS13=false
    H2=false
    BLOCK_CDN=false

    # 1. 检查 TLS 1.3
    if echo "$CURL_LOG" | grep -qE "TLSv1.3|using TLSv1.3"; then TLS13=true; fi
    
    # 2. 检查 HTTP/2
    if echo "$CURL_LOG" | grep -qE "ALPN.*h2|accepted to use h2|HTTP/2 confirmed"; then H2=true; fi

    # 3. 修正 CDN 检测逻辑：仅剔除 Cloudflare 拦截屏障或安全硬拦截标头（不再误伤 Akamai）
    if echo "$CURL_LOG" | grep -iE "cf-ray|cloudflare|imperva|server: Denial" >/dev/null; then
        BLOCK_CDN=true
    fi

    # 计算延迟并筛选
    if [[ "$TIME_CONN" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [ "$(awk "BEGIN {print ($TIME_CONN > 0)?1:0}")" -eq 1 ]; then
        LATENCY_MS=$(awk "BEGIN {printf \"%.2f\", $TIME_CONN * 1000}")
        
        if [ "$TLS13" = true ] && [ "$H2" = true ] && [ "$BLOCK_CDN" = false ]; then
            echo "${LATENCY_MS}|${domain}" >> "$TEMP_FILE"
            echo -e "   [+] \e[1;32m$domain\e[0m - 延迟: ${LATENCY_MS}ms (TLS1.3: Yes, H2: Yes, 状态: 正常)"
            
            QUALIFIED_COUNT=$((QUALIFIED_COUNT + 1))
            if [ "$QUALIFIED_COUNT" -ge 3 ]; then
                break
            fi
        else
            echo -e "   [-] \e[1;31m$domain\e[0m - 淘汰 (TLS1.3:$TLS13, H2:$H2, 阻断标头:$BLOCK_CDN)"
        fi
    fi
done

if [ ! -s "$TEMP_FILE" ]; then
    echo -e "\e[1;33m[!] 未检测到可用域名，保底恢复使用: mora.jp\e[0m"
    BEST_DOMAIN="mora.jp"
else
    # 优先在通过检测的域名中随机选 1 个
    BEST_DOMAIN=$(sort -n -t'|' -k1 "$TEMP_FILE" | head -n 3 | shuf -n 1 | cut -d'|' -f2)
fi
rm -f "$TEMP_FILE"

# 覆盖重置 JSON 配置
BACKUP_FILE="${CONFIG_FILE}.bak_$(date +%Y%m%d%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"

PY_RES=$(python3 - << ENDPython
import json, sys

config_path = "$CONFIG_FILE"
new_sni = "$BEST_DOMAIN"
target_short_id = "$TARGET_SHORT_ID"

try:
    with open(config_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    modified = False
    if "inbounds" in data:
        for inbound in data["inbounds"]:
            stream_settings = inbound.get("streamSettings", {})
            if stream_settings.get("security") == "reality":
                reality_settings = stream_settings.get("realitySettings", {})
                
                reality_settings["dest"] = f"{new_sni}:443"
                reality_settings["serverNames"] = [new_sni]
                reality_settings["shortIds"] = [target_short_id]
                
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
else
    systemctl restart xray 2>/dev/null || true
fi

echo -e "\e[1;34m===============================================================\e[0m"
echo -e "\e[1;32m[✔] Xray REALITY 配置文件更新完成！\e[0m"
echo -e "    ► 优选 SNI 域名 : \e[1;33m$BEST_DOMAIN\e[0m"
echo -e "    ► 目标端口 (dest): \e[1;33m${BEST_DOMAIN}:443\e[0m"
echo -e "    ► 锁定 ShortID  : \e[1;33m$TARGET_SHORT_ID\e[0m"
echo -e "\e[1;34m===============================================================\e[0m"
