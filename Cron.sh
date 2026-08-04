#!/usr/bin/env bash

# =============================================================================
# 系统 Cron 与服务清理函数
# 提升 VPS 稳定性，避免误删系统组件
# =============================================================================

function optimize_system_cron() {

echo -e "\033[33m[*]\033[0m 正在优化系统 Cron 与后台服务..."

BACKUP_DIR="/root/system_backup_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$BACKUP_DIR"


# ============================================================
# 1. 备份当前 Cron
# ============================================================

echo -e "\033[33m[*]\033[0m 备份 Cron 配置..."

crontab -l > "$BACKUP_DIR/user_crontab.bak" 2>/dev/null || true

cp -a /etc/cron* "$BACKUP_DIR/" 2>/dev/null || true


# ============================================================
# 2. 删除 Xray geodata 自动更新任务
# ============================================================

if crontab -l >/dev/null 2>&1; then

    crontab -l \
    | grep -v '/usr/local/xray-script/tool/geodata.sh' \
    | crontab -

fi


# ============================================================
# 3. 禁用 apport 崩溃报告
# ============================================================

if systemctl list-unit-files | grep -q "^apport.service"; then

    systemctl disable --now apport.service 2>/dev/null || true

fi


# ============================================================
# 4. 禁用 network wait 服务
# ============================================================

for svc in \
systemd-networkd-wait-online.service \
NetworkManager-wait-online.service
do

    if systemctl list-unit-files | grep -q "^${svc}"; then

        systemctl disable --now "$svc" 2>/dev/null || true

    fi

done


echo -e "\033[32m[✓]\033[0m 系统优化完成"
echo -e "\033[36m备份位置:\033[0m $BACKUP_DIR"

}
