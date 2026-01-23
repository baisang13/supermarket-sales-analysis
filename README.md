# 超市销售数据分析与运维自动化

拿一份超市的交易流水练手，用 MySQL 从建表一路做到出结论。

数据是 2019 年 1-3 月、缅甸三个城市三家门店的 1000 笔订单，17 个字段，
有城市、产品线、客户类型、支付方式、金额、评分这些。

## 做了什么

Windows 上用 MySQL 跑了一遍，之后又在 Debian 上从零装了一遍，两边结果对得上。

步骤大概是：建表 → 导数据 → 六类校验 → 加三个派生列（星期/月份/时段）→
25 条查询 → 整理成报告 → 部署备份和导出脚本 → 挂 cron。

导入这块折腾了挺久，DBeaver 的图形向导会自动往表里加列（列名对不上就新建），
后面干脆改用 LOAD DATA 把字段一个个写死，反而快。具体踩的坑记在 `docs/troubleshooting.md`。

运维部分也顺手做了：专用账号、限制监听地址、防火墙、SSH 密钥登录、
备份脚本和定时导出。都写在下面的「Linux 上怎么装起来的」里。

## 跑出来几个结果

**1. 毛利率那个字段是废的**

`gross_margin_pct` 整张表都是 4.7619，一千行一个数。
本来想按品类比毛利率，结果六个品类全是 4.76%，等于没说。
后来换成 `gross_income`（毛利额）来排，才有区别。
这个算是提醒自己：拿到数据先看看每个字段的分布，别默认它有用。

**2. 周六和周一差得挺多**

周六卖了 56120，周一 37899，差 48%。订单数是 164 对 125，只差 31%。
说明周末不光人多，买的也贵（客单价 342 对 303）。

时段上晚上 16 点以后有 432 单，占 43%。周六晚上 81 单，是最忙的时候。

**3. 钱主要在 500 以上的单子**

订单金额分五档，300 以下的单子占了 57%，但只贡献 21% 的销售额。
500 以上的单子占 22.7%，贡献了 49%。

**4. 三个城市销售额差不多，但结构反的**

Naypyitaw 34.24%，Yangon 和 Mandalay 各 32.88%，基本平分。
但客单价 Naypyitaw 337，Yangon 只有 312。
Yangon 单量最多（340 单）却最便宜，Naypyitaw 单少但单笔大。

拆到城市内部看品类冠军，三个城市完全不一样：
Naypyitaw 是食品，Yangon 是家居，Mandalay 是运动和个护。

**5. 评分低的单子反而贵**

这个最意外。评分 6 分以下的 315 单，客单价 340.57，全表最高。
评分 8 分以上的 329 单，客单价 323。
高低分整体比一下，323 对 322，几乎没差别。

所以评分和客单价之间应该没有正相关。为什么低分单贵，我猜是大额订单容易出问题
（等得久、缺货、期望高），但这只是猜，数据里没有能证明因果的东西。
报告里我写的是“建议关注大额订单的履约”，没敢写成结论。

## SQL 里用到的

`CASE WHEN` 分档（金额、评分、时段）、`SUM(CASE WHEN)` 一次算会员和普通两个口径、
`RANK()` 排名、`RANK() OVER (PARTITION BY ...)` 算城市内排名、
`LAG()` 算月度环比和城市间差距、`SUM() OVER (ORDER BY ...)` 算每日累计。

## 运维脚本

两个脚本，都挂在 cron 上。

`backup_mysql.sh` 做全库逻辑备份：mysqldump 导出 → gzip → 文件名带时间戳 →
只留最近 7 天 → 写日志。

`export_report.sh` 把城市、产品线、支付方式三个维度的汇总导出成 CSV，方便直接看。

```bash
/usr/local/bin/backup_mysql.sh
/usr/local/bin/export_report.sh
```

实际输出：

```
[2026-01-23 04:16:46] 开始备份 sales_analysis
[2026-01-23 04:16:46] 备份完成 /var/backups/mysql/sales_analysis_20260123_041646.sql.gz (40 KB)
[2026-01-23 04:16:46] 清理 2 个超过 7 天的备份
[2026-01-23 04:16:46] 当前保留 1 个备份文件
```

cron 配置：

```
0 2 * * *  /usr/local/bin/backup_mysql.sh >> /var/log/mysql_backup.log 2>&1
30 2 * * * /usr/local/bin/export_report.sh
```

两个任务错开半小时，避免同时占 IO。备份日志一份跟着备份目录走（`backup.log`），
一份在 `/var/log/mysql_backup.log` 里专门记 cron 的调度情况，排查"凌晨为什么没跑"时看后者。

### 恢复演练

备份能不能用，得真删一次试试。

删掉一个城市（Yangon 有 340 单）：

```sql
DELETE FROM sales_analysis.sales WHERE city='Yangon';
SELECT COUNT(*) FROM sales_analysis.sales;   -- 660
```

从备份恢复：

```bash
gzip -dc /d/sales_backup/sales_analysis_20261123_004223.sql.gz | mysql -u root sales_analysis
```

验证回来了：

```sql
SELECT COUNT(*) FROM sales_analysis.sales;   -- 1000
SELECT city, COUNT(*) FROM sales_analysis.sales GROUP BY city;
-- Mandalay 332 / Naypyitaw 328 / Yangon 340
```

第一次做的时候踩了个坑：删数据那条报了 `Access denied (using password: NO)`，
密码根本没传进去，DELETE 没执行，COUNT 还是 1000。
表面上「删 1000 → 恢复 1000」看着像成功了，实际上什么也没删。
后面用 `$env:MYSQL_PWD` 显式传密码才真正跑通。

## 环境和复现

Windows 和 Linux 两个环境都跑过，结果一致。

**Windows 侧**

MySQL 8.0.46 + DBeaver。执行 `sql/` 下两个文件就能把库建起来。

**Linux 侧**

Debian 13，MariaDB 11.8.9，服务器版没装桌面（后来发现装上了，卸过一次）。

```bash
apt install -y mariadb-server
systemctl enable --now mariadb
mysql -e "CREATE DATABASE sales_analysis CHARACTER SET utf8mb4;"
mysql sales_analysis < sql/01_create_and_load.sql
```

部署的时候顺手做了几件事：

- 建了个专用账号 `sales`@`localhost`，只给 `sales_analysis` 这一个库的增删改查，不给 DROP
- 配置文件里 `bind-address=127.0.0.1`，只接受本机连接，`ss -lntp | grep 3306` 能验证
- ufw 只放行 22（SSH），3306 不对公网开

两个环境跑同一份数据，出来的数完全一样：1000 行 / 322966.75 / 15379.37。

数据文件在 `data/` 下，1001 行（含表头）。GitHub 的 diff 视图对上千行的文件经常折叠或者加载不出来，
点文件名进入文件页就能正常看，文件本身是完整的。

## Linux 上怎么装起来的

从裸机到跑起来，大概这么几步。

**1. 装系统**

Debian 13 netinst，安装时只勾 `SSH server` 和 `standard system utilities`，不装桌面。

**2. 装数据库**

```bash
apt update
apt install -y mariadb-server mariadb-client
systemctl enable --now mariadb
```

**3. 建库导数据**

```bash
mysql -e "CREATE DATABASE sales_analysis CHARACTER SET utf8mb4;"
mysql --local-infile=1 sales_analysis < sql/01_create_and_load.sql
```

`--local-infile=1` 不能省，客户端没开这个参数会报 1148。

**4. 建专用账号**

```bash
mysql -e "CREATE USER 'sales'@'localhost' IDENTIFIED BY '...';"
mysql -e "GRANT SELECT,INSERT,UPDATE,DELETE ON sales_analysis.* TO 'sales'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"
```

只给这一个库的增删改查，不给 DROP、不给 GRANT。

**5. 限制监听地址、开防火墙**

```bash
grep bind-address /etc/mysql/mariadb.conf.d/50-server.cnf
ss -lntp | grep 3306
ufw allow 22/tcp
ufw --force enable
ufw status verbose
```

**6. 部署脚本和定时任务**

```bash
install -m 755 scripts/backup_mysql.sh /usr/local/bin/
install -m 755 scripts/export_report.sh /usr/local/bin/

(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/backup_mysql.sh >> /var/log/mysql_backup.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "30 2 * * * /usr/local/bin/export_report.sh") | crontab -
```

**7. SSH 加固**

```bash
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sshd -t && systemctl restart ssh
```

关掉 root 直连和密码认证，只允许普通用户用密钥登录。改完先在控制台验证密钥能进，再关掉终端。

## 一次抓包排查

想确认 mysql 客户端连过来到底走没走网络，用 tcpdump 抓了一次：

```bash
timeout 15 tcpdump -i lo port 3306 -c 10 -w /root/3306.pcap &
mysql -h 127.0.0.1 -u sales -p'...' sales_analysis -e "SELECT COUNT(*) FROM sales;"
wait
tcpdump -r /root/3306.pcap -nn | head
```

第一次抓了 0 个包。两个原因：mysql 没带 `-h 127.0.0.1`，默认走 unix socket，
压根没走 TCP；另外 `-i any` 在虚拟机上抓不到 loopback。

改成 `-i lo` 加 `-h 127.0.0.1` 之后就正常了：

```
127.0.0.1.59434 > 127.0.0.1.3306: Flags [S]          客户端发起
127.0.0.1.3306 > 127.0.0.1.59434: Flags [S.]         服务端响应
127.0.0.1.59434 > 127.0.0.1.3306: Flags [.]          握手完成
127.0.0.1.3306 > 127.0.0.1.59434: Flags [P.] length 108    MySQL 握手包
```

判断连接问题的顺序大概是：先 `ss -lntp` 看服务有没有在听，再 tcpdump 看包到没到。
有 SYN 没 SYN-ACK 一般是防火墙挡了；连 SYN 都抓不到，说明客户端根本没连这个端口。
