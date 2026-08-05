#!/usr/bin/env bash

# =============================================================================
# Xray REALITY 配置清洗与强制重置脚本 (精简纯净版)
# =============================================================================

function fix_xray_reality_config() {
    echo -e "\033[33m[*]\033[0m 正在清洗与重置 Xray REALITY 配置..."

    python3 -c '
import json, os

paths = ["/usr/local/etc/xray/config.json", "/etc/xray/config.json", "/etc/XrayR/config.json"]
target_path = None

for p in paths:
    if os.path.exists(p):
        target_path = p
        break

if not target_path:
    print("\033[31m[X] 未找到 Xray 配置文件！\033[0m")
    exit(1)

try:
    with open(target_path, "r", encoding="utf-8") as f:
        d = json.load(f)

    updated = False
    for ib in d.get("inbounds", []):
        if ib.get("streamSettings", {}).get("security") == "reality":
            rs = ib["streamSettings"]["realitySettings"]
            rs["dest"] = "mora.jp:443"
            rs["serverNames"] = ["mora.jp"]
            rs["shortIds"] = ["67d93779"]
            updated = True

    if updated:
        with open(target_path, "w", encoding="utf-8") as f:
            json.dump(d, f, indent=2, ensure_ascii=False)
        print(f"\033[32m[✓]\033[0m 已覆盖更新: {target_path} (SNI: mora.jp, ShortID: 67d93779)")
    else:
        print("\033[31m[!] 配置文件中未找到 REALITY 入站配置。 \033[0m")
        exit(1)

except Exception as e:
    print(f"\033[31m[X] 解析或写入配置文件失败: {str(e)}\033[0m")
    exit(1)
'

    if [ $? -eq 0 ]; then
        echo -e "\033[33m[*]\033[0m 重启 Xray 服务中..."
        if systemctl is-active --quiet xray 2>/dev/null; then
            systemctl restart xray
        elif systemctl is-active --quiet XrayR 2>/dev/null; then
            systemctl restart XrayR
        else
            systemctl restart xray 2>/dev/null || systemctl restart xray.service 2>/dev/null || true
        fi
        echo -e "\033[32m[✓]\033[0m Xray REALITY 配置重置与服务重启完成！"
    fi
}

# 执行主函数
fix_xray_reality_config
