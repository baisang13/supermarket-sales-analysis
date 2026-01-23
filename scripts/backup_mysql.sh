#!/bin/bash
#
# 超市销售分析库 · MySQL 逻辑备份
#
# 做的事：
#   1. mysqldump 全库导出，gzip 压缩
#   2. 文件名带时间戳，按天归档
#   3. 只保留最近 7 天
#   4. 每步写日志，失败立即退出
#
# 用法：
#   ./backup_mysql.sh
#
# 部署：
#   install -m 755 backup_mysql.sh /usr/local/bin/
#   (crontab -l; echo "0 2 * * * /usr/local/bin/backup_mysql.sh >> /var/log/mysql_backup.log 2>&1") | crontab -

set -euo pipefail

DB_NAME="sales_analysis"
DB_USER="root"
BACKUP_DIR="/var/backups/mysql"
KEEP_DAYS=7

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${DATE}.sql.gz"
LOG_FILE="${BACKUP_DIR}/backup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

mkdir -p "$BACKUP_DIR"
log "开始备份 ${DB_NAME}"

if mysqldump -u "$DB_USER" --single-transaction --routines --triggers \
    --default-character-set=utf8mb4 "$DB_NAME" 2>>"$LOG_FILE" | gzip > "$BACKUP_FILE"
then
    SIZE=$(du -k "$BACKUP_FILE" | cut -f1)
    if [ "$SIZE" -lt 1 ]; then
        log "失败：备份文件为空"
        rm -f "$BACKUP_FILE"
        exit 1
    fi
    log "备份完成 ${BACKUP_FILE} (${SIZE} KB)"
else
    log "失败：mysqldump 返回非零"
    rm -f "$BACKUP_FILE"
    exit 1
fi

DELETED=$(find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -type f -mtime +"$KEEP_DAYS" -print -delete | wc -l)
[ "$DELETED" -gt 0 ] && log "清理 ${DELETED} 个超过 ${KEEP_DAYS} 天的备份"

TOTAL=$(find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -type f | wc -l)
log "当前保留 ${TOTAL} 个备份文件"
