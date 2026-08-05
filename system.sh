#!/usr/bin/env bash

# =============================================================================
# VPS 综合系统优化脚本
# 1. 优化系统 Cron 与后台服务
# 2. 禁用 IPv6 并应用配置
# =============================================================================

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[31m[错误]\033[0m 请使用 root 权限运行此脚本！"
    exit 1
fi

# =============================================================================
# 模块一：系统 Cron 与服务清理优化
# =============================================================================
function optimize_system_cron() {
    echo -e "\033[33m[*]\033[0m 正在优化系统 Cron 与后台服务..."

    BACKUP_DIR="/root/system_cron_backup_$(date +%Y%m%d_%H%M%S)"
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

    if [ -d "/etc/cron.d" ]; then
        grep -rl 'geodata\.sh' /etc/cron.d/ 2>/dev/null | xargs rm -f 2>/dev/null || true
    fi

    # 3. 禁用 apport 崩溃报告服务
    if systemctl list-unit-files | grep -q "^apport.service"; then
        systemctl disable --now apport.service 2>/dev/null || true
    fi

    # 4. 禁用 network wait 等待在线服务 (优化开机/重启速度)
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
# 模块二：禁用 IPv6 配置
# =============================================================================
function disable_ipv6() {
    echo -e "\033[33m[*]\033[0m 正在配置并禁用 IPv6..."

    cat > /etc/sysctl.d/99-disable-ipv6.conf << "CONF"
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
CONF

    # 刷新 sysctl 配置
    sysctl --system > /dev/null 2>&1

    # 检查结果
    local STATUS=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
    if [ "$STATUS" = "1" ]; then
        echo -e "\033[32m[成功] IPv6 已成功禁用！\033[0m"
    else
        echo -e "\033[31m[失败] IPv6 禁用未生效，请检查系统环境。\033[0m"
    fi
}

# =============================================================================
# 主执行流程
# =============================================================================
main() {
    echo "=========================================="
    echo "       开始执行 VPS 系统综合优化         "
    echo "=========================================="
    
    optimize_system_cron
    echo "------------------------------------------"
    disable_ipv6
    
    echo "=========================================="
    echo -e "\033[32m[✓] 所有优化任务已执行完毕！\033[0m"
    echo "=========================================="
}

# 执行主函数
main
