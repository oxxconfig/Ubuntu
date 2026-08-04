cat << 'EOF' > test_sni.sh
#!/bin/bash

# 候选域名列表（已避开 fandom/apple 等高频滥用域名）
DOMAINS=(
    "www.dell.com"
    "www.microsoft.com"
    "www.lovelive-anime.jp"
    "dl.google.com"
    "images.unsplash.com"
    "www.cisco.com"
    "www.oracle.com"
    "www.samsung.com"
    "www.visa.com"
    "www.spotify.com"
    "www.bloomberg.com"
    "www.qualcomm.com"
    "www.autodesk.com"
    "www.shopify.com"
    "www.twitch.tv"
    "www.nvidia.com"
    "www.target.com"
    "www.amd.com"
)

echo -e "\e[1;34m===============================================================\e[0m"
echo -e "\e[1;34m              REALITY 优质伪装域名自动检测脚本                \e[0m"
echo -e "\e[1;34m===============================================================\e[0m"
printf "%-28s | %-10s | %-10s | %-12s\n" "Domain" "TLS 1.3" "HTTP/2" "Latency (ms)"
echo "---------------------------------------------------------------"

TEMP_FILE=$(mktemp)

for domain in "${DOMAINS[@]}"; do
    # 使用 curl 获取 TLS/HTTP2 信息及建连延迟
    RES=$(curl -ivs "https://${domain}" --connect-timeout 3 \
        -o /dev/null \
        -w "%{time_connect}\n" 2>&1)

    TLS13=false
    H2=false
    
    if echo "$RES" | grep -qE "TLSv1.3|using TLSv1.3"; then
        TLS13=true
    fi
    
    if echo "$RES" | grep -qE "ALPN.*h2|accepted to use h2|HTTP/2 confirmed"; then
        H2=true
    fi

    TIME_CONN=$(echo "$RES" | tail -n1)

    # 验证延时返回值格式
    if [[ "$TIME_CONN" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [ "$(echo "$TIME_CONN > 0" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
        LATENCY_MS=$(awk "BEGIN {printf \"%.2f\", $TIME_CONN * 1000}")
        
        if [ "$TLS13" = true ] && [ "$H2" = true ]; then
            printf "%-28s | \e[32m%-10s\e[0m | \e[32m%-10s\e[0m | \e[36m%-12s\e[0m\n" "$domain" "YES" "YES" "${LATENCY_MS} ms"
            echo "${LATENCY_MS}|${domain}" >> "$TEMP_FILE"
        fi
    fi
done

echo "---------------------------------------------------------------"
echo -e "\e[1;32m[+] 推荐选用（按当前 VPS 物理延时升序排列前 3 名）：\e[0m"

if [ -s "$TEMP_FILE" ]; then
    sort -n -t'|' -k1 "$TEMP_FILE" | head -n 3 | while IFS='|' read -r lat dom; do
        echo -e "  \e[1;33m► $dom\e[0m (延迟: ${lat} ms)"
    done
else
    echo "  未检测到符合条件的域名，请检查网络或扩充域名列表。"
fi

rm -f "$TEMP_FILE"
EOF

chmod +x test_sni.sh
./test_sni.sh
