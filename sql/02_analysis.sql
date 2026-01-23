-- ============================================================
-- 超市销售数据分析 · 25 条分析查询
-- 前提：已执行 01_create_and_load.sql，且完成派生列创建
-- 数据库：MySQL 8.0+
-- ============================================================

USE sales_analysis;

-- ============================================================
-- 派生列（如未创建，先执行这一段）
-- ============================================================
-- ALTER TABLE sales
--   ADD COLUMN day_name    VARCHAR(10) NULL COMMENT '星期',
--   ADD COLUMN month_name  VARCHAR(10) NULL COMMENT '月份',
--   ADD COLUMN time_of_day VARCHAR(10) NULL COMMENT '时段';
--
-- UPDATE sales SET day_name = CASE DAYOFWEEK(sale_date)
--     WHEN 1 THEN '周日' WHEN 2 THEN '周一' WHEN 3 THEN '周二'
--     WHEN 4 THEN '周三' WHEN 5 THEN '周四' WHEN 6 THEN '周五'
--     ELSE '周六' END;
-- UPDATE sales SET month_name = DATE_FORMAT(sale_date, '%m月');
-- UPDATE sales SET time_of_day = CASE
--     WHEN sale_time <  '12:01:00' THEN '上午'
--     WHEN sale_time <= '16:00:00' THEN '下午'
--     ELSE '晚上' END;


-- ============================================================
-- A 组 · 总览（3 条）
-- ============================================================

-- A1 整体经营指标
-- 预期：1000 | 322966.75 | 15379.37 | 322.97 | 5510
SELECT COUNT(*)                    AS order_cnt,
       ROUND(SUM(total), 2)        AS sales_sum,
       ROUND(SUM(gross_income), 2) AS gross_sum,
       ROUND(AVG(total), 2)        AS avg_order,
       SUM(quantity)               AS total_qty
FROM sales;

-- A2 毛利率校验（发现常量字段陷阱）
-- 预期：4.76 | 4.7619  ← 两者一致，说明字段是常量
SELECT ROUND(100 * SUM(gross_income) / SUM(total), 2) AS real_margin,
       ROUND(AVG(gross_margin_pct), 4)                AS field_margin
FROM sales;

-- A3 单均价与件均
-- 预期：5.51 | 55.67 | 58.46
SELECT ROUND(AVG(quantity), 2)         AS avg_qty,
       ROUND(AVG(unit_price), 2)       AS avg_price,
       ROUND(AVG(total / quantity), 2) AS avg_per_item
FROM sales;


-- ============================================================
-- B 组 · 时间维度（5 条）
-- ============================================================

-- B1 月度经营
-- 预期：2019-01 116291.87/352 单；2019-02 97219.37/303；2019-03 109455.51/345
SELECT DATE_FORMAT(sale_date,'%Y-%m') AS ym,
       COUNT(*)                        AS order_cnt,
       ROUND(SUM(total), 2)            AS sales_sum,
       ROUND(AVG(total), 2)            AS avg_order
FROM sales
GROUP BY ym
ORDER BY ym;

-- B2 星期维度
-- 预期：周六 56120.81(164 单) 最高 … 周一 37899.08(125 单) 最低
SELECT day_name                        AS weekday,
       COUNT(*)                        AS order_cnt,
       ROUND(SUM(total), 2)            AS sales_sum,
       ROUND(AVG(total), 2)            AS avg_order
FROM sales
GROUP BY day_name
ORDER BY sales_sum DESC;

-- B3 时段维度
-- 预期：晚上 432 单/138370.92(43.2%)；下午 377；上午 191
SELECT time_of_day                                    AS timeslot,
       COUNT(*)                                        AS order_cnt,
       ROUND(SUM(total), 2)                            AS sales_sum,
       ROUND(AVG(total), 2)                            AS avg_order,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM sales), 1) AS order_pct
FROM sales
GROUP BY time_of_day
ORDER BY sales_sum DESC;

-- B4 时段 × 星期 交叉（黄金时段）
-- 预期：周六-晚上 81 单最高
SELECT day_name                        AS weekday,
       time_of_day                     AS timeslot,
       COUNT(*)                        AS order_cnt,
       ROUND(SUM(total), 2)            AS sales_sum
FROM sales
GROUP BY day_name, time_of_day
ORDER BY order_cnt DESC
LIMIT 8;

-- B5 每日销售额 + 累计（SUM OVER）
SELECT sale_date                                        AS d,
       ROUND(daily, 2)                                  AS daily_sales,
       ROUND(SUM(daily) OVER (ORDER BY sale_date), 2)    AS running_total
FROM (SELECT sale_date, SUM(total) AS daily FROM sales GROUP BY sale_date) t
ORDER BY sale_date DESC
LIMIT 10;


-- ============================================================
-- C 组 · 地理与门店（3 条）
-- ============================================================

-- C1 城市维度
-- 预期：Naypyitaw 110568.71(34.24%) / Yangon 106200.37(32.88%) / Mandalay 106197.67(32.88%)
SELECT city                            AS city,
       COUNT(*)                        AS order_cnt,
       ROUND(SUM(total), 2)            AS sales_sum,
       ROUND(AVG(total), 2)            AS avg_order,
       ROUND(100 * SUM(total) / (SELECT SUM(total) FROM sales), 2) AS sales_pct
FROM sales
GROUP BY city
ORDER BY sales_sum DESC;

-- C2 门店对比
SELECT branch                          AS branch,
       city                            AS city,
       COUNT(*)                        AS order_cnt,
       ROUND(SUM(total), 2)            AS sales_sum,
       ROUND(AVG(total), 2)            AS avg_order,
       ROUND(AVG(rating), 2)           AS avg_rating
FROM sales
GROUP BY branch, city
ORDER BY sales_sum DESC;

-- C3 城市 × 产品线 TOP8
-- 预期：Naypyitaw-Food and beverages 23766.85 第一
SELECT city                            AS city,
       product_line                    AS product_line,
       COUNT(*)                        AS order_cnt,
       ROUND(SUM(total), 2)            AS sales_sum
FROM sales
GROUP BY city, product_line
ORDER BY sales_sum DESC
LIMIT 8;


-- ============================================================
-- D 组 · 商品品类（4 条）
-- ============================================================

-- D1 产品线排行（RANK）
-- 预期：1 Food and beverages 56144.84 … 6 Health and beauty 49193.74
SELECT product_line                    AS product_line,
       ROUND(SUM(total), 2)            AS sales_sum,
       SUM(quantity)                   AS qty_sum,
       ROUND(AVG(total), 2)            AS avg_order,
       RANK() OVER (ORDER BY SUM(total) DESC) AS rk
FROM sales
GROUP BY product_line
ORDER BY rk;

-- D2 销量 vs 件均（低价高频 vs 高价低频）
SELECT product_line                        AS product_line,
       SUM(quantity)                       AS qty_sum,
       ROUND(SUM(total) / SUM(quantity), 2) AS per_item_sales,
       ROUND(100 * SUM(total) / (SELECT SUM(total) FROM sales), 2) AS sales_pct
FROM sales
GROUP BY product_line
ORDER BY per_item_sales DESC;

-- D3 单笔金额 TOP5
-- 预期：最高 1042.65，评分仅 6.6
SELECT invoice_id, city, product_line, quantity, total, rating
FROM sales
ORDER BY total DESC
LIMIT 5;

-- D4 会员 vs 普通 按品类（条件聚合）
-- 预期：Food and beverages 会员占 55.9% 最高；Electronic accessories 45.1% 最低
SELECT product_line                    AS product_line,
       ROUND(SUM(CASE WHEN customer_type = 'Member' THEN total ELSE 0 END), 2) AS member_sales,
       ROUND(SUM(CASE WHEN customer_type = 'Normal' THEN total ELSE 0 END), 2) AS normal_sales,
       ROUND(100 * SUM(CASE WHEN customer_type = 'Member' THEN total ELSE 0 END)
             / SUM(total), 1)          AS member_pct
FROM sales
GROUP BY product_line
ORDER BY member_pct DESC;


-- ============================================================
-- E 组 · 客户（4 条）
-- ============================================================

-- E1 会员 vs 普通
-- 预期：会员 501 单/164223.44/327.79 | 普通 499 单/158743.30/318.12
SELECT customer_type                   AS ctype,
       COUNT(*)                        AS order_cnt,
       ROUND(SUM(total), 2)            AS sales_sum,
       ROUND(AVG(total), 2)            AS avg_order,
       ROUND(AVG(rating), 2)           AS avg_rating
FROM sales
GROUP BY customer_type;

-- E2 性别维度
-- 预期：女 167882.92 / 男 155083.82
SELECT gender                          AS gender,
       COUNT(*)                        AS order_cnt,
       ROUND(SUM(total), 2)            AS sales_sum,
       ROUND(AVG(total), 2)            AS avg_order
FROM sales
GROUP BY gender;

-- E3 性别 × 客户类型 四象限
-- 预期：女性会员 88146.94 最高；男性会员 76076.50 最低
SELECT gender, customer_type,
       COUNT(*)                        AS order_cnt,
       ROUND(SUM(total), 2)            AS sales_sum,
       ROUND(AVG(rating), 2)           AS avg_rating
FROM sales
GROUP BY gender, customer_type
ORDER BY sales_sum DESC;

-- E4 单笔金额分档（帕累托结构）
-- 预期：500-800 档占销售额 33.3%
SELECT CASE
         WHEN total < 100 THEN '1: <100'
         WHEN total < 300 THEN '2: 100-300'
         WHEN total < 500 THEN '3: 300-500'
         WHEN total < 800 THEN '4: 500-800'
         ELSE '5: 800+'
       END                             AS amount_bucket,
       COUNT(*)                        AS order_cnt,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM sales), 1) AS order_pct,
       ROUND(SUM(total), 2)            AS sales_sum
FROM sales
GROUP BY amount_bucket
ORDER BY amount_bucket;


-- ============================================================
-- F 组 · 支付与评分（4 条）
-- ============================================================

-- F1 支付方式
-- 预期：Cash 344(34.4%) / Ewallet 345(34.5%) / Credit card 311(31.1%)
SELECT payment                          AS pay_method,
       COUNT(*)                         AS order_cnt,
       ROUND(SUM(total), 2)             AS sales_sum,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM sales), 1) AS order_pct,
       ROUND(AVG(total), 2)             AS avg_order
FROM sales
GROUP BY payment
ORDER BY sales_sum DESC;

-- F2 各城市支付偏好
-- 预期：Yangon 偏 Ewallet(126)，Naypyitaw 偏 Cash(124)
SELECT city, payment, COUNT(*) AS order_cnt
FROM sales
GROUP BY city, payment
ORDER BY city, order_cnt DESC;

-- F3 评分分布 vs 客单价（核心发现）
-- 预期：<6 分 315 单，客单价 340.57 全表最高
SELECT CASE
         WHEN rating < 6 THEN '1: <6'
         WHEN rating < 7 THEN '2: 6-7'
         WHEN rating < 8 THEN '3: 7-8'
         WHEN rating < 9 THEN '4: 8-9'
         ELSE '5: 9-10'
       END                              AS rating_bucket,
       COUNT(*)                         AS order_cnt,
       ROUND(AVG(total), 2)             AS avg_order,
       ROUND(SUM(total), 2)             AS sales_sum
FROM sales
GROUP BY rating_bucket
ORDER BY rating_bucket;

-- F4 高分 vs 低分对比（验证无相关性）
-- 预期：high(>=8) 323.28 vs low(<8) 322.81，几乎相同
SELECT CASE WHEN rating >= 8 THEN 'high(>=8)' ELSE 'low(<8)' END AS grp,
       COUNT(*)                         AS order_cnt,
       ROUND(AVG(total), 2)             AS avg_order,
       ROUND(AVG(quantity), 2)          AS avg_qty
FROM sales
GROUP BY grp;


-- ============================================================
-- G 组 · 窗口函数进阶（3 条）
-- ============================================================

-- G1 城市占比 + 与上一名差距（LAG）
-- 预期：第 1-2 名差 4368.34，第 2-3 名只差 2.70
SELECT city                            AS city,
       ROUND(SUM(total), 2)            AS sales_sum,
       ROUND(100 * SUM(total) / (SELECT SUM(total) FROM sales), 2) AS sales_pct,
       ROUND(SUM(total) - LAG(SUM(total)) OVER (ORDER BY SUM(total) DESC), 2) AS gap_to_prev
FROM sales
GROUP BY city
ORDER BY sales_sum DESC;

-- G2 每个城市内部的产品线排名（RANK + PARTITION BY）
-- 预期：三城冠军品类各不相同
SELECT city                            AS city,
       product_line                    AS product_line,
       ROUND(SUM(total), 2)            AS sales_sum,
       RANK() OVER (PARTITION BY city ORDER BY SUM(total) DESC) AS rank_in_city
FROM sales
GROUP BY city, product_line
ORDER BY city, rank_in_city;

-- G3 月度环比（LAG 求 MoM%）
-- 预期：2 月 -16.40，3 月 +12.59
SELECT ym, sales_sum,
       ROUND(100 * (sales_sum - LAG(sales_sum) OVER (ORDER BY ym))
             / LAG(sales_sum) OVER (ORDER BY ym), 2) AS mom_pct
FROM (
  SELECT DATE_FORMAT(sale_date, '%Y-%m') AS ym, SUM(total) AS sales_sum
  FROM sales
  GROUP BY ym
) t
ORDER BY ym;
