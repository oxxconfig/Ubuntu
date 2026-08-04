#!/usr/bin/env bash

# =============================================================================
# 系统 Cron 与服务清理函数 (提升 VPS 稳定性 & 释放资源)
# =============================================================================
function optimize_system_cron() {
    echo -e "\033[33m[*]\033[0m 正在清理冗余系统 Cron 任务与服务..."

    # 1. 清理无用的系统 Cron 日常/周日常维护任务
    rm -f /etc/cron.daily/apport \
          /etc/cron.daily/apt-compat \
          /etc/cron.daily/man-db \
          /etc/cron.weekly/man-db

    # 2. 从用户 crontab 中移除 geodata 定时更新
    if crontab -l >/dev/null 2>&1; then
        crontab -l | grep -v 'geodata.sh' | crontab - 2>/dev/null || true
    fi

    # 3. 彻底停用并禁用崩溃报告服务 (apport)
    systemctl stop apport 2>/dev/null || true
    systemctl disable apport 2>/dev/null || true

    # 4. 禁用容易导致网络等待超时的后台服务 (可选增效)
    systemctl disable --now systemd-networkd-wait-online.service 2>/dev/null || true

    echo -e "\033[32m[✓]\033[0m 系统 Cron 任务与后台资源优化完成！"
}
