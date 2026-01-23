USE sales_analysis;

DROP TABLE IF EXISTS sales;

CREATE TABLE sales (
  invoice_id       VARCHAR(20)    NOT NULL ,
  branch           CHAR(1)        NOT NULL ,
  city             VARCHAR(20)    NOT NULL ,
  customer_type    VARCHAR(10)    NOT NULL ,
  gender           VARCHAR(6)     NOT NULL ,
  product_line     VARCHAR(40)    NOT NULL ,
  unit_price       DECIMAL(10,2)  NOT NULL ,
  quantity         INT            NOT NULL ,
  tax_5pct         DECIMAL(10,4)  NOT NULL ,
  total            DECIMAL(12,4)  NOT NULL ,
  sale_date        DATE           NOT NULL ,
  sale_time        TIME           NOT NULL ,
  payment          VARCHAR(15)    NOT NULL ,
  cogs             DECIMAL(12,4)  NOT NULL ,
  gross_margin_pct DECIMAL(16,10) NOT NULL ,
  gross_income     DECIMAL(12,4)  NOT NULL ,
  rating           DECIMAL(3,1)   NOT NULL ,
  PRIMARY KEY (invoice_id),
  KEY idx_date (sale_date),
  KEY idx_city (city),
  KEY idx_line (product_line)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 ;

LOAD DATA LOCAL INFILE 'D:/data/supermarket_sales.csv'
INTO TABLE sales
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(@invoice,@branch,@city,@ctype,@gender,@pline,@uprice,@qty,@tax,@total,
 @date,@time,@payment,@cogs,@gmp,@gincome,@rating)
SET invoice_id       = @invoice,
    branch           = @branch,
    city             = @city,
    customer_type    = @ctype,
    gender           = @gender,
    product_line     = @pline,
    unit_price       = @uprice,
    quantity         = @qty,
    tax_5pct         = @tax,
    total            = @total,
    sale_date        = STR_TO_DATE(@date, '%Y-%m-%d'),
    sale_time        = @time,
    payment          = @payment,
    cogs             = @cogs,
    gross_margin_pct = @gmp,
    gross_income     = @gincome,
    rating           = @rating;

SELECT COUNT(*)                        AS row_count,
       ROUND(SUM(total), 2)            AS total_sales,
       ROUND(SUM(gross_income), 2)     AS gross_income_sum,
       ROUND(AVG(gross_margin_pct), 9) AS avg_margin
FROM sales;
