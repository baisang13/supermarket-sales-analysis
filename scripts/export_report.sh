#!/usr/bin/env bash
#
# 把城市 / 产品线 / 支付方式三个维度的汇总导出成 CSV
#
# 用法：
#   ./scripts/export_report.sh
#
# cron：
#   30 2 * * * /usr/local/bin/export_report.sh

set -euo pipefail

DB_NAME="${DB_NAME:-sales_analysis}"
OUT_DIR="${OUT_DIR:-/var/reports}"
LOG_FILE="${OUT_DIR}/export.log"

mkdir -p "$OUT_DIR"
STAMP=$(date +%Y%m%d_%H%M%S)
OUT_FILE="${OUT_DIR}/sales_summary_${STAMP}.csv"

echo "[$(date '+%F %T')] 开始导出" >> "$LOG_FILE"

mysql -u root --default-character-set=utf8mb4 "$DB_NAME" -e "
SELECT '城市' AS dim, city AS k, COUNT(*) AS orders, ROUND(SUM(total),2) AS sales
FROM sales GROUP BY city
UNION ALL
SELECT '产品线', product_line, COUNT(*), ROUND(SUM(total),2)
FROM sales GROUP BY product_line
UNION ALL
SELECT '支付方式', payment, COUNT(*), ROUND(SUM(total),2)
FROM sales GROUP BY payment;
" > "$OUT_FILE" 2>>"$LOG_FILE"

ROWS=$(wc -l < "$OUT_FILE")
echo "[$(date '+%F %T')] 导出完成 ${OUT_FILE} (${ROWS} 行)" >> "$LOG_FILE"
