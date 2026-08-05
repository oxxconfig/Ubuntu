cat > check_SNI_reality.sh <<'EOF'
#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

IP=$(curl -4 -s ipv4.icanhazip.com)
PORT=443
CONFIG_FILE="/usr/local/etc/xray/config.json"

echo "================================"
echo -e "${BLUE} Xray Reality 及 SNI 综合检测${NC}"
echo "================================"

echo -e "\n服务器IP:"
echo -e "${GREEN}$IP${NC}"

echo -e "\n[1] 检查443端口"
ss -lntp | grep ":$PORT" || echo -e "${RED}443端口未被监听${NC}"

echo -e "\n[2] 检查Xray运行状态"
systemctl is-active xray

echo -e "\n[3] Reality配置 (serverNames)"
if [ -f "$CONFIG_FILE" ]; then
    grep -A8 serverNames "$CONFIG_FILE"
    # 自动提取 config.json 中的第一个 serverName / SNI 值
    TARGET_SNI=$(grep -i "serverNames" "$CONFIG_FILE" -A 2 | grep -oE '"[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"' | head -n 1 | tr -d '"')
else
    echo -e "${RED}配置文件不存在: $CONFIG_FILE${NC}"
fi

echo -e "\n[4] Reality目标 (dest)"
if [ -f "$CONFIG_FILE" ]; then
    grep dest "$CONFIG_FILE"
fi

echo -e "\n[5] 自动提取 SNI 并进行 TLS 握手与连通性测试"
if [ -z "$TARGET_SNI" ]; then
    echo -e "${YELLOW}[!] 未能自动从配置中解析出 serverName，尝试手动指定。${NC}"
    read -p "请输入要测试的 SNI / 域名: " TARGET_SNI
    TARGET_SNI=${TARGET_SNI:-"www.cloudflare.com"}
fi

echo -e "目标 SNI: ${GREEN}$TARGET_SNI${NC}"

# 1. 测试 TLS 握手与 SNI 响应
echo -e "  -> 正在进行 TLS 握手测试..."
CERT_INFO=$(echo | openssl s_client -connect "$IP:443" -servername "$TARGET_SNI" 2>/dev/null)

if [ $? -eq 0 ]; then
    echo -e "  -> ${GREEN}[成功] TLS 握手成功！${NC}"
    ISSUED_TO=$(echo "$CERT_INFO" | openssl x509 -noout -subject 2>/dev/null | sed 's/subject=//')
    EXPIRE_DATE=$(echo "$CERT_INFO" | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')
    echo -e "     - 证书主体: ${YELLOW}$ISSUED_TO${NC}"
    echo -e "     - 到期时间: ${YELLOW}$EXPIRE_DATE${NC}"
else
    echo -e "  -> ${RED}[失败] TLS 握手失败，可能该域名被阻断或回落异常。${NC}"
fi

# 2. 测试 HTTPS 访问延迟与状态码
echo -e "  -> 正在测试 HTTPS 访问延迟..."
HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --connect-timeout 5 --resolve "$TARGET_SNI:443:$IP" "https://$TARGET_SNI")
TIME_TOTAL=$(curl -o /dev/null -s -w "%{time_total}" --connect-timeout 5 --resolve "$TARGET_SNI:443:$IP" "https://$TARGET_SNI")

if [ "$HTTP_CODE" -gt 0 ]; then
    echo -e "  -> ${GREEN}[成功] HTTP 状态码: $HTTP_CODE${NC}"
    echo -e "     - 请求总耗时: ${YELLOW}${TIME_TOTAL} 秒${NC}"
else
    echo -e "  -> ${RED}[失败] 无法通过 HTTPS 获取响应。${NC}"
fi

echo "================================"
EOF

chmod +x check_SNI_reality.sh
./check_SNI_reality.sh
