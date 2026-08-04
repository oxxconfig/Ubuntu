#!/usr/bin/env bash

# =============================================================================
# 1. Xray REALITY 配置优化与同步函数
# =============================================================================
function fix_xray_reality_config() {
    echo -e "\033[33m[*]\033[0m 正在清洗与重置 Xray REALITY 配置..."

    python3 -c '
import json, os

paths = ["/usr/local/etc/xray/config.json", "/etc/xray/config.json"]
target_path = None

for p in paths:
    if os.path.exists(p):
        target_path = p
        break

if not target_path:
    print("\033[31m[X] 未找到 Xray 配置文件！\033[0m")
    exit(1)

with open(target_path, "r") as f:
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
    with open(target_path, "w") as f:
        json.dump(d, f, indent=2)
    print(f"\033[32m[✓]\033[0m 已覆盖更新: {target_path} (SNI: mora.jp, ShortID: 67d93779)")
else:
    print("\033[31m[!] 配置文件中未找到 REALITY 配置入站项。\033[0m")
'

    if [ $? -eq 0 ]; then
        echo -e "\033[33m[*]\033[0m 重启 Xray 服务中..."
        systemctl restart xray 2>/dev/null || systemctl restart xray.service 2>/dev/null
        echo -e "\033[32m[✓]\033[0m Xray REALITY 配置优化完成！"
    fi
}

# =============================================================================
# 2. 系统 Cron 与服务清理函数
# =============================================================================
function optimize_system_cron() {
    echo -e "\033[33m[*]\033[0m 正在优化系统 Cron 与后台服务..."

    BACKUP_DIR="/root/system_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    # 1. 备份当前 Cron
    echo -e "\033[33m[*]\033[0m 备份 Cron 配置到 $BACKUP_DIR ..."
    crontab -l > "$BACKUP_DIR/user_crontab.bak" 2>/dev/null || true
    cp -a /etc/cron* "$BACKUP_DIR/" 2>/dev/null || true

    # 2. 安全删除 Xray geodata 自动更新任务
    if crontab -l >/dev/null 2>&1; then
        NEW_CRON=$(crontab -l 2>/dev/null | grep -v 'geodata\.sh' || true)
        
        if [ -z "$NEW_CRON" ]; then
            crontab -r 2>/dev/null || true
        else
            echo "$NEW_CRON" | crontab -
        fi
    fi

    # 清理 /etc/cron.d/ 中残留任务
    if [ -d "/etc/cron.d" ]; then
        grep -rl 'geodata\.sh' /etc/cron.d/ 2>/dev/null | xargs rm -f 2>/dev/null || true
    fi

    # 3. 禁用 apport 崩溃报告服务
    if systemctl list-unit-files | grep -q "^apport.service"; then
        systemctl disable --now apport.service 2>/dev/null || true
    fi

    # 4. 禁用 network wait 等待在线服务
    for svc in \
        systemd-networkd-wait-online.service \
        NetworkManager-wait-online.service
    do
        if systemctl list-unit-files | grep -q "^${svc}"; then
            systemctl disable --now "$svc" 2>/dev/null || true
        fi
    done

    echo -e "\033[32m[✓]\033[0m 系统 Cron 与后台服务优化完成！"
    echo -e "\033[36m备份位置:\033[0m $BACKUP_DIR"
}

# =============================================================================
# 主入口执行
# =============================================================================
fix_xray_reality_config
echo "---------------------------------------------------------------"
optimize_system_cron
