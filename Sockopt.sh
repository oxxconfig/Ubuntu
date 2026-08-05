#!/usr/bin/env bash

# 1. 查找配置文件
CONFIG_FILE=""
for p in "/usr/local/etc/xray/config.json" "/etc/xray/config.json" "/etc/XrayR/config.json"; do
    if [ -f "$p" ]; then CONFIG_FILE="$p"; break; fi
done

if [ -z "$CONFIG_FILE" ]; then
    echo -e "\033[31m[X] 未找到 Xray 配置文件！\033[0m"
    exit 1
fi

echo -e "\033[33m[*]\033[0m 正在注入 TCP 超时回收与防卡死参数..."

# 2. 修改 Xray 配置：注入 Sockopt 心跳与回收选项
python3 - << ENDPython
import json

config_path = "$CONFIG_FILE"

try:
    with open(config_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    for inbound in data.get("inbounds", []):
        if inbound.get("streamSettings", {}).get("security") == "reality":
            ss = inbound["streamSettings"]
            
            # 注入 Sockopt 强制超时回收
            sockopt = ss.get("sockopt", {})
            sockopt["tcpKeepAliveInterval"] = 10
            sockopt["tcpKeepAliveIdle"] = 15
            sockopt["tcpUserTimeout"] = 10000
            sockopt["tcpFastOpen"] = True
            ss["sockopt"] = sockopt

    with open(config_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print("SUCCESS")
except Exception as e:
    print(f"ERROR: {str(e)}")
ENDPython

# 3. 优化 VPS Linux 系统内核参数 (强制回收 TIME_WAIT 连接)
sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_fin_timeout=15 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_keepalive_time=30 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_keepalive_intvl=10 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_keepalive_probes=3 >/dev/null 2>&1

# 4. 重启 Xray 彻底生效
systemctl restart xray 2>/dev/null || systemctl restart XrayR 2>/dev/null

echo -e "\033[32m[✓]\033[0m 防卡死参数注入完成！TCP 僵死连接将在 15 秒内被系统强制回收。"
