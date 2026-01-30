#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 清屏
clear

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          CloudGuardian 流量监控 - 使用情况报告            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 检查 data.json 是否存在
if [ ! -f /root/CloudGuardian/data.json ]; then
    echo -e "${RED}❌ 错误: data.json 不存在${NC}"
    exit 1
fi

# 读取配置
if [ -f /root/CloudGuardian/.env ]; then
    source /root/CloudGuardian/.env
else
    echo -e "${YELLOW}⚠️  警告: .env 文件不存在，使用默认值${NC}"
    TX_BYTES_LIMIT=6442450944  # 6GB
fi

# 读取流量数据
ADDUP=$(cat /root/CloudGuardian/data.json | jq -r '.addup | tonumber')
CURRENT=$(cat /root/CloudGuardian/data.json | jq -r '.current | tonumber')
LAST_UPDATE=$(cat /root/CloudGuardian/data.json | jq -r '.last_update | tonumber')

# 计算各种单位
ADDUP_MB=$(echo "scale=2; $ADDUP / 1024 / 1024" | bc)
ADDUP_GB=$(echo "scale=3; $ADDUP / 1024 / 1024 / 1024" | bc)
LIMIT_MB=$(echo "scale=2; $TX_BYTES_LIMIT / 1024 / 1024" | bc)
LIMIT_GB=$(echo "scale=2; $TX_BYTES_LIMIT / 1024 / 1024 / 1024" | bc)
REMAIN_MB=$(echo "scale=2; ($TX_BYTES_LIMIT - $ADDUP) / 1024 / 1024" | bc)
REMAIN_GB=$(echo "scale=3; ($TX_BYTES_LIMIT - $ADDUP) / 1024 / 1024 / 1024" | bc)
PERCENT=$(echo "scale=1; $ADDUP * 100 / $TX_BYTES_LIMIT" | bc)

# 格式化时间
LAST_UPDATE_TIME=$(date -d @$LAST_UPDATE "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -r $LAST_UPDATE "+%Y-%m-%d %H:%M:%S")
CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")

# 显示基本信息
echo -e "${BLUE}📅 当前时间:${NC} $CURRENT_TIME"
echo -e "${BLUE}🕒 上次更新:${NC} $LAST_UPDATE_TIME"
echo ""

# 显示流量信息
echo -e "${PURPLE}━━━━━━━━━━━━━━━ 流量使用情况 ━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}📊 今日已用流量:${NC}"
echo -e "   ${YELLOW}${ADDUP_MB} MB${NC} (${ADDUP_GB} GB)"
echo ""
echo -e "${GREEN}📈 每日流量限额:${NC}"
echo -e "   ${YELLOW}${LIMIT_MB} MB${NC} (${LIMIT_GB} GB)"
echo ""
echo -e "${GREEN}📉 剩余可用流量:${NC}"
echo -e "   ${YELLOW}${REMAIN_MB} MB${NC} (${REMAIN_GB} GB)"
echo ""

# 使用百分比和进度条
echo -e "${GREEN}📊 使用百分比:${NC} ${YELLOW}${PERCENT}%${NC}"
echo ""

# 绘制进度条
BAR_LENGTH=50
FILLED=$(echo "$PERCENT / 2" | bc | cut -d'.' -f1)
FILLED=${FILLED:-0}

# 根据使用率选择颜色
if (( $(echo "$PERCENT < 50" | bc -l) )); then
    BAR_COLOR=$GREEN
elif (( $(echo "$PERCENT < 80" | bc -l) )); then
    BAR_COLOR=$YELLOW
else
    BAR_COLOR=$RED
fi

echo -n -e "${BAR_COLOR}["
for i in $(seq 1 $BAR_LENGTH); do
    if [ $i -le $FILLED ]; then
        echo -n "█"
    else
        echo -n "░"
    fi
done
echo -e "]${NC} ${PERCENT}%"
echo ""

# 显示 sing-box 状态
echo -e "${PURPLE}━━━━━━━━━━━━━━━ 服务状态 ━━━━━━━━━━━━━━━━${NC}"
echo ""

SINGBOX_STATUS=$(systemctl is-active sing-box 2>/dev/null)
SINGBOX_PID=$(pgrep -f "/etc/s-box/sing-box run")

if [ "$SINGBOX_STATUS" == "active" ]; then
    echo -e "${GREEN}✅ sing-box 状态:${NC} 运行中 ${GREEN}(PID: $SINGBOX_PID)${NC}"
else
    echo -e "${RED}❌ sing-box 状态:${NC} 已停止"
fi

# 检查是否在 cgroup 中
if [ -n "$SINGBOX_PID" ] && grep -q "^$SINGBOX_PID$" /sys/fs/cgroup/singbox_traffic/cgroup.procs 2>/dev/null; then
    echo -e "${GREEN}✅ 流量监控:${NC} 已启用"
else
    echo -e "${YELLOW}⚠️  流量监控:${NC} 未启用或 PID 不匹配"
fi

# 检查 cron 状态
CRON_STATUS=$(systemctl is-active cron 2>/dev/null)
if [ "$CRON_STATUS" == "active" ]; then
    echo -e "${GREEN}✅ 自动监控:${NC} 运行中"
else
    echo -e "${RED}❌ 自动监控:${NC} 未运行"
fi

echo ""

# 流量警告
if (( $(echo "$PERCENT >= 90" | bc -l) )); then
    echo -e "${RED}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ⚠️  警告: 流量使用已超过 90%，即将被限制！  ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════╝${NC}"
    echo ""
elif (( $(echo "$PERCENT >= 80" | bc -l) )); then
    echo -e "${YELLOW}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠️  提示: 流量使用已超过 80%，请注意使用！  ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════╝${NC}"
    echo ""
fi

# 显示 iptables 统计
echo -e "${PURPLE}━━━━━━━━━━━━━━━ iptables 统计 ━━━━━━━━━━━━━━━${NC}"
echo ""
IPTABLES_BYTES=$(iptables -L SINGBOX_TRAFFIC -n -v -x 2>/dev/null | awk '/ACCEPT.*cgroup/ {print $2}' | head -1)
IPTABLES_BYTES=${IPTABLES_BYTES:-0}
IPTABLES_MB=$(echo "scale=2; $IPTABLES_BYTES / 1024 / 1024" | bc)
echo -e "${GREEN}📊 iptables 计数器:${NC} ${IPTABLES_MB} MB (${IPTABLES_BYTES} bytes)"
echo ""

# 底部提示
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}提示: 每日 0 点自动重置流量并恢复服务${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
EOF

# 设置执行权限
chmod +x /root/CloudGuardian/status.sh

# 创建快捷命令
sudo ln -sf /root/CloudGuardian/status.sh /usr/local/bin/cgstatus

echo "✅ 监控脚本创建成功！"
echo ""
echo "使用方法："
echo "  方法1: /root/CloudGuardian/status.sh"
echo "  方法2: cgstatus (快捷命令)"
echo ""