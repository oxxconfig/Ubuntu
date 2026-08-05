#!/bin/bash

# =============================================================================
# Xray REALITY 动态优选与配置修复脚本 (修复版)
# =============================================================================

# 1. 检查 root 权限
if [ "$EUID" -ne 0 ]; then
  echo -e "\e[1;31m[-] 请使用 root 权限运行此脚本！\e[0m"
  exit 1
fi

# 2. 检查并自动安装 python3 依赖
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

if ! command -v python3 &> /dev/null; then
    echo -e "\e[1;31m[-] python3 安装失败，请手动安装后重试！\e[0m"
    exit 1
fi

# 3. 自动匹配 config.json 路径
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

# 4. 精选优质 REALITY 伪装域名池 (剔除大厂 CDN 阻断域名及敏感域名)
DOMAINS=(
    "mora.jp"
    "www.lovelive-anime.jp"
    "tidal.com"
    "www.sky.com"
    "mxj.myanimelist.net"
    "images.unsplash.com"
    "dl.acm.org"
)

# 固定的 ShortID (必须与客户端配置保持一致)
TARGET_SHORT_ID="67d93779"

TEMP_FILE=$(mktemp)
QUALIFIED_COUNT=0

echo -e "\e[1;34m[*] 正在测速并检测域名 TLS1.3 / H2 及 CDN 特征...\e[0m"

for domain in "${DOMAINS[@]}"; do
    CURL_LOG=$(curl -ivs "https://${domain}" --connect-timeout 2 --max-time 3 -o /dev/null 2>&1)
    TIME_CONN=$(curl -s -o /dev/null -w "%{time_connect}" "https://${domain}" --connect-timeout 2 --max-time 3)

    TLS13=false
    H2=false
    IS_CDN=false

    # 判断 TLS 1.3
    if echo "$CURL_LOG" | grep -qE "TLSv1.3|using TLSv1.3"; then TLS13=true; fi
    
    # 判断 HTTP/2
    if echo "$CURL_LOG" | grep -qE "ALPN.*h2|accepted to use h2|HTTP/2 confirmed"; then H2=true; fi

    # 判断是否命中大厂 CDN 标头 (Akamai, Cloudflare, Fastly, CloudFront, Imperva)
    if echo "$CURL_LOG" | grep -iE "ak_p|cf-ray|cloudflare|cloudfront|fastly|imperva|server: Denial" >/dev/null; then
        IS_CDN=true
    fi

    # 计算延迟并筛选
    if [[ "$TIME_CONN" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [ "$(awk "BEGIN {print ($TIME_CONN > 0)?1:0}")" -eq 1 ]; then
        LATENCY_MS=$(awk "BEGIN {printf \"%.2f\", $TIME_CONN * 1000}")
        
        if [ "$TLS13" = true ] && [ "$H2" = true ] && [ "$IS_CDN" = false ]; then
            echo "${LATENCY_MS}|${domain}" >> "$TEMP_FILE"
            echo -e "   [+] \e[1;32m$domain\e[0m - 延迟: ${LATENCY_MS}ms (TLS1.3: Yes, H2: Yes, CDN: 无)"
            
            QUALIFIED_COUNT=$((QUALIFIED_COUNT + 1))
            if [ "$QUALIFIED_COUNT" -ge 3 ]; then
                break
            fi
        else
            echo -e "   [-] \e[1;31m$domain\e[0m - 淘汰 (TLS1.3:$TLS13, H2:$H2, CDN:$IS_CDN)"
        fi
    fi
done

if [ ! -s "$TEMP_FILE" ]; then
    echo -e "\e[1;33m[!] 未通过动态检测选出新域名，保底使用已验证域名: mora.jp\e[0m"
    BEST_DOMAIN="mora.jp"
else
    # 从响应最快的前 3 个合格域名中随机选择 1 个
    BEST_DOMAIN=$(sort -n -t'|' -k1 "$TEMP_FILE" | head -n 3 | shuf -n 1 | cut -d'|' -f2)
fi
rm -f "$TEMP_FILE"

# 备份当前配置文件
BACKUP_FILE="${CONFIG_FILE}.bak_$(date +%Y%m%d%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"

# 5. 调用 Python 安全精准更新配置
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
                
                # 强行重置与覆盖 dest 和 serverNames
                reality_settings["dest"] = f"{new_sni}:443"
                reality_settings["serverNames"] = [new_sni]
                
                # 重置 ShortID 为固定值，防止无限追加
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

# 6. 重启服务
if systemctl is-active --quiet xray; then
    systemctl restart xray
elif systemctl is-active --quiet XrayR; then
    systemctl restart XrayR
else
    systemctl restart xray 2>/dev/null || true
fi

echo -e "\e[1;34m===============================================================\e[0m"
echo -e "\e[1;32m[✔] Xray REALITY 配置文件重置并更新成功！\e[0m"
echo -e "    ► 优选 SNI 域名 : \e[1;33m$BEST_DOMAIN\e[0m"
echo -e "    ► 目标端口 (dest): \e[1;33m${BEST_DOMAIN}:443\e[0m"
echo -e "    ► 锁定 ShortID  : \e[1;33m$TARGET_SHORT_ID\e[0m"
echo -e "\e[1;34m===============================================================\e[0m"
if [ "$BEST_DOMAIN" != "mora.jp" ]; then
    echo -e "\e[1;33m[!] 注意：当前优选选中了新域名 [$BEST_DOMAIN]，若客户端SNI固定为mora.jp请同步修改客户端，或直接锁定mora.jp使用。\e[0m"
fi
