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
    echo -e "\033[33m[*]\033[0m 备份 Cron 配置到 $BACKUP_DIR ..."
    crontab -l > "$BACKUP_DIR/user_crontab.bak" 2>/dev/null || true
    cp -a /etc/cron* "$BACKUP_DIR/" 2>/dev/null || true

    # ============================================================
    # 2. 安全删除 Xray geodata 自动更新任务
    # ============================================================
    if crontab -l >/dev/null 2>&1; then
        # 提取过滤后的内容
        NEW_CRON=$(crontab -l 2>/dev/null | grep -v 'geodata\.sh' || true)
        
        if [ -z "$NEW_CRON" ]; then
            # 如果过滤后变为空，直接移除当前用户的 crontab，防止管道报错
            crontab -r 2>/dev/null || true
        else
            # 安全写回不带 geodata 的配置
            echo "$NEW_CRON" | crontab -
        fi
    fi

    # 兼顾清理系统级 /etc/cron.d/ 中的配置文件（防止脚本写入过别的地方）
    if [ -d "/etc/cron.d" ]; then
        grep -rl 'geodata\.sh' /etc/cron.d/ 2>/dev/null | xargs rm -f 2>/dev/null || true
    fi

    # ============================================================
    # 3. 禁用 apport 崩溃报告服务
    # ============================================================
    if systemctl list-unit-files | grep -q "^apport.service"; then
        systemctl disable --now apport.service 2>/dev/null || true
    fi

    # ============================================================
    # 4. 禁用 network wait 等待在线服务 (优化开机/重启速度)
    # ============================================================
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
# 执行函数（关键：没有这行，curl | bash 远程调用时不会运作）
# =============================================================================
optimize_system_cron
