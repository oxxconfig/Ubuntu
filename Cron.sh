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

    # 2. 从当前用户 crontab 中安全移除 geodata 定时任务
    if crontab -l >/dev/null 2>&1; then
        CURRENT_CRON=$(crontab -l 2>/dev/null | grep -v 'geodata\.sh')
        if [ -z "$CURRENT_CRON" ]; then
            # 如果过滤后内容为空，直接清空用户 crontab，避免管道报错
            crontab -r 2>/dev/null || true
        else
            # 重新写入不含 geodata.sh 的内容
            echo "$CURRENT_CRON" | crontab -
        fi
    fi

    # 2.1 补充清理系统级 /etc/cron.d/ 和 /etc/crontab 中的残留
    if [ -d "/etc/cron.d" ]; then
        grep -rl 'geodata\.sh' /etc/cron.d/ 2>/dev/null | xargs rm -f 2>/dev/null || true
    fi
    if [ -f "/etc/crontab" ]; then
        sed -i '/geodata\.sh/d' /etc/crontab
    fi

    # 3. 彻底停用并禁用崩溃报告服务 (apport)
    systemctl stop apport 2>/dev/null || true
    systemctl disable apport 2>/dev/null || true

    # 4. 禁用容易导致网络等待超时的后台服务 (可选增效)
    systemctl disable --now systemd-networkd-wait-online.service 2>/dev/null || true

    echo -e "\033[32m[✓]\033[0m 系统 Cron 任务与后台资源优化完成！"
}
