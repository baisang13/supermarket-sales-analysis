# 踩坑记录

做这个项目过程中遇到的问题，按遇到的时间顺序记的。有的一两句，有的折腾了半天。

## 导入前：数据落不了库

### CSV 表头被当成数据导进去了

第一次用 DBeaver 的导入向导，导完报 `Data too long for column 'branch'`。
branch 是 CHAR(1)，怎么会超长。

翻了一下设置，发现「标题位置」那一栏是 `none`，意思是告诉它"这文件没有表头"。
所以第一行 `Invoice ID, Branch, City...` 被当成一条数据插进去，
`Branch` 这六个字符塞不进 CHAR(1)。

改成 `top` 就好了。这个选项藏在「输入文件」页的导入程序设置表里，第一次找了好一会儿。

### 表莫名变成 26 列

改了标题位置之后还是报错，这回是 `Field 'invoice_id' doesn't have a default value`。

点开表看结构，发现表有 26 个字段。多出来的 9 个叫 `Invoice ID`、`Customer type`、
`Tax 5%`、`gross margin percentage` 这些——全是 CSV 的原始列名。

原来 DBeaver 在映射的时候，如果 CSV 列名在目标表里找不到同名字段，
不会报错，而是直接 `ADD COLUMN` 建一个新字段，然后往新字段里插数据。
原来的 17 个字段一个都没填上，主键自然是空的。

这个行为挺坑的，因为界面上看不出任何异常，映射列表显示的都是"已映射"。

最后的处理：把表删了重建，然后不用图形向导，改用 LOAD DATA 一句句写字段名。

### DECIMAL 精度给少了

建表的时候 `gross_margin_pct` 给了 `DECIMAL(12,8)`，觉得八位小数够用了。

导入时报批量插入失败，DBeaver 只给一句笼统的错误，点「详细信息」才看到是
`Data truncation: Data too long for column 'gross_margin_pct'`。

回去查源数据，这一列的值是 `4.761904762`，九位小数。八位存不下。
MySQL 默认是严格模式，超精度直接拒绝，整批回滚。

改成 `DECIMAL(16,10)` 之后正常。

教训是建表前应该先看一眼每列的小数位数和最大长度，不能凭感觉给。

## 命令行的几个问题

### PowerShell 不认 <

`mysql -u root -p db < file.sql` 直接报错：
`"<"运算符是为将来使用而保留的`。

PowerShell 不支持 Unix 那种输入重定向。查了下，`>` 支持，`<` 不支持。

用 `cmd /c "..."` 包一层绕过去。也可以用 mysql 自己的 `source` 命令。

### 脚本里的中文全变乱码

`cmd /c` 能跑了，又报语法错误，提示里是一堆 `?敷粶?`。

原因是我用 UTF-8 存的 SQL 文件，但 Windows 下 mysql 客户端按 GBK 读。
中文别名 `AS 行数` 变成乱码，SQL 就解析不了。

解决办法最省事的是脚本里别写中文。注释和别名全改英文，一次解决。
也可以用 `--default-character-set=utf8mb4` 参数，但每次都要记得加。

### AS rows 报错

```sql
SELECT COUNT(*) AS rows FROM sales;
```

报 `ERROR 1064 ... near 'rows'`。

`ROWS` 是 MySQL 8 的保留字，窗口函数的 `ROWS BETWEEN` 用的。
改成 `row_count` 就好了。

类似的还有 `rank`、`groups`、`lead`、`lag`，做别名的时候容易撞。

## 建表和查询

### 全表 UPDATE 弹窗警告

执行 `UPDATE sales SET day_name = ...` 的时候，DBeaver 弹了个框，
说"没有 WHERE 条件，可能会丢失数据"，问要不要继续。

这个是要给一千行都算星期，本来就得全表更新，直接点确定。
后面两次 UPDATE 也弹，选了「全部为是」。

这个提示我留着了，没勾"不再询问"。
以后要是手滑写了 `DELETE FROM sales`，它还能拦一下。

### Ctrl+Enter 只跑了一条

建表脚本里有 `CREATE DATABASE`、`USE`、`CREATE TABLE` 三条，
光标停在 `CREATE TABLE` 上按了 Ctrl+Enter，报 `No database selected`。

DBeaver 的 Ctrl+Enter 只执行光标所在的那一条。
要跑整个脚本得 Ctrl+A 全选再执行，或者按 Alt+X。

后面所有多语句的脚本都是用 Alt+X 跑的。

## 环境相关

### MySQL 迁到 D 盘之后起不来

C 盘空间不够，把 MySQL 整个搬到 `D:\sql`。改完配置重启服务，起不来，
而且 `data` 目录下的 err 日志一条新的都没有。

查了半天，最后是看了 my.ini 的头三个字节：`EF BB BF`。
我把配置写成了带 BOM 的 UTF-8。

MySQL 读到第一行是 `\ufeff[mysqld]`，组名认不出来，整份配置全部失效。
配置失效导致 datadir 也找不到，所以日志写不出来——这也是为什么一点线索都没有。

PowerShell 5.1 的 `Set-Content -Encoding UTF8` 默认带 BOM，得用
`[System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))`。

### sc config 改服务路径没生效

改完 MySQL 服务的启动参数，`sc qc MySQL80` 看还是旧的。

因为 PowerShell 会重新解析 sc.exe 的参数，路径里的引号被吃掉了一部分。
改成直接写注册表 `HKLM:\SYSTEM\CurrentControlSet\Services\MySQL80` 的 ImagePath 才行。

---

### Access denied 先看 using password 是 NO 还是 YES

做恢复演练的时候第一次删数据，报：

```
ERROR 1045 (28000): Access denied for user 'root'@'localhost' (using password: NO)
```

`using password: NO` 的意思是**压根没传密码**，不是密码错了。
`mysql -u root -e "..."` 这种写法，不带 `-p` 也不设 `MYSQL_PWD`，就是空密码连接。

所以那条 DELETE 根本没执行，COUNT 还是 1000。
差一点就当成"演练成功"了——删 1000 恢复 1000，数字对上纯属巧合。

换成 `$env:MYSQL_PWD="1234"; mysql -u root -e "..."` 之后，COUNT 才真的变成 660。

同一个报错还有一种 `using password: YES` 的，那是密码传进去了但值不对。
排查时先看这个后缀，能少绕不少弯：

- `NO` → 凭据没传进去（环境变量、-p、配置文件都没生效）
- `YES` → 凭据传了但不对（密码错、用户错、host 不匹配）

### Windows 下 ~/.my.cnf 不生效

按 Linux 的习惯在 `C:\Users\97707\.my.cnf` 里写了 `[client]` 段，客户端不读。
连上去报的用户名是 `ODBC`——这是 MySQL 客户端在 Windows 上的默认用户名，
说明它根本没加载配置文件。

`mysql --help` 会打印实际搜索的路径：

```
C:\Windows\my.ini  C:\Windows\my.cnf  C:\my.ini  C:\my.cnf  D:\sql\server\my.ini  D:\sql\server\my.cnf
```

Windows 版只认这几个位置，用户目录下的 `.my.cnf` 是 Unix 的规则。
放到 `D:\sql\server\my.cnf`（mysqld.exe 的上级目录）之后就正常了，
mysql 和 mysqldump 都不用再传密码。

结论：配完没生效，别急着怀疑配置写错了，先用 `--help` 看它到底读哪个文件。
我一开始还以为是格式或者权限问题，用 `--defaults-extra-file` 强制指定才发现内容完全没问题，
纯粹是放错地方了。

---

整理一下，一共十二个坑：

DBeaver 那边三个（表头、自动建列、全表更新弹窗），
建表精度一个，命令行三个（重定向、编码、保留字），
权限两个（using password 的 NO/YES、Windows 配置文件路径），
环境两个（BOM、sc config），还有一个 Ctrl+Enter 的小问题。

做完之后回头看，图形化工具的问题往往更麻烦，因为它不报错，
只是默默做了一件你没让它做的事。导数据这种活还是写脚本靠得住。
