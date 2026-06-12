#!/bin/bash
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限或 sudo 运行此脚本！"
  exit 1
fi

echo "开始清理 Ubuntu 系统日志..."

# 1. 停止日志服务，防止清理时文件被占用或持续写入
systemctl stop syslog.service 2>/dev/null
systemctl stop rsyslog.service 2>/dev/null
systemctl stop systemd-journald.service 2>/dev/null

# 2. 清理 systemd 没收的二进制日志 (Journal)
if command -v journalctl >/dev/null 2>&1; then
    # 清理所有 journal 日志
    journalctl --vacuum-time=1s
    # 彻底清空 journal 目录
    find /var/log/journal/ -type f -exec rm -rf {} + 2>/dev/null
fi

# 3. 清理 /var/log 下的文本日志、登录日志、SSH 日志
# 包括：auth.log(SSH/登录), syslog(系统), wtmp(登录历史), btmp(失败尝试), utmp(当前登录)
LOG_FILES=(
    "/var/log/auth.log"
    "/var/log/syslog"
    "/var/log/wtmp"
    "/var/log/btmp"
    "/var/log/utmp"
    "/var/log/lastlog"
    "/var/log/secure"
    "/var/log/dpkg.log"
    "/var/log/kern.log"
)

for file in "${LOG_FILES[@]}"; do
    if [ -f "$file" ]; then
        # 使用 > 截断文件，保留文件结构和权限，避免直接 rm 导致服务报错
        echo -n "" > "$file"
    fi
done

# 4. 循环清理所有历史压缩日志 (.gz 和 .1 后缀的历史轮替日志)
find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.1" -delete

# 5. 清理当前用户的 Bash/Zsh 操作历史 (防止留下执行此脚本的记录)
echo "正在清理当前会话的操作历史..."
history -c              # 清空当前内存中的 history
echo -n "" > ~/.bash_history  # 清空常规 Bash 历史文件
echo -n "" > ~/.zsh_history   # 清空 Zsh 历史文件 (如果存在)

# 6. 重启日志服务恢复系统正常运行
systemctl start systemd-journald.service 2>/dev/null
systemctl start rsyslog.service 2>/dev/null
systemctl start syslog.service 2>/dev/null

echo "系统日志与操作记录清理完成！"
