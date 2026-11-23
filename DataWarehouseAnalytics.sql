-- Advanced Data Analytics Project
-- Database: DataWarehouseAnalytics

USE DataWarehouseAnalytics;
GO

-- Change over Time (Trends)
SELECT 
*
FROM dbo.fact_sales

SELECT
DATETRUNC(MONTH,order_date) AS order_date,
SUM(sales_amount) AS Total_sales,
COUNT(DISTINCT customer_key) AS total_customer,
SUM(quantity) as total_quantity
FROM DBO.fact_sales 
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(MONTH,order_date)
ORDER BY DATETRUNC(MONTH,order_date)

-- same thing by year
SELECT
YEAR(order_date) AS order_year,
SUM(sales_amount) AS Total_sales,
COUNT(DISTINCT customer_key) AS total_customer,
SUM(quantity) as total_quantity
FROM DBO.fact_sales 
WHERE order_date IS NOT NULL
GROUP BY YEAR(order_date)
ORDER BY YEAR(order_date)


-- Cumulative Analysis
-- calculate the total sales per month 
-- and running total sales and moving average sales over time

SELECT
    order_date,
    Total_sales,
    SUM(Total_sales) OVER (ORDER BY order_date) AS running_totalsales,
    AVG(total_sales) OVER (ORDER BY order_date) AS moving_avgsales,
    AVG(avg_price) OVER (ORDER BY order_date) AS moving_avgprice
FROM (
    SELECT
        DATETRUNC(YEAR, order_date) AS order_date,
        SUM(sales_amount) AS Total_sales,
        AVG(price) AS avg_price
    FROM DBO.fact_sales
    WHERE order_date IS NOT NULL
    GROUP BY DATETRUNC(YEAR, order_date)
) SQ
ORDER BY order_date;

-- Analyze the yearly performance of products by comparing each product's sales 
-- To both  it's Average sales performance and the previous year perfomance
WITH yearly_performance AS(
SELECT 
    YEAR(F.order_date) AS order_date,
    P.product_name,
    SUM(F.sales_amount) AS current_sales
FROM dbo.fact_sales F
LEFT JOIN dbo.dim_products P
ON F.product_key = P.product_key
WHERE order_date IS NOT NULL
GROUP BY YEAR(F.order_date), P.product_name
)

SELECT 
    order_date,
    product_name,
    current_sales,
    LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_date) AS PY_product_sales,
    current_sales - LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_date) AS Diff_py_product_sales,
    (CASE
        WHEN current_sales - LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_date) > 0 THEN 'INCREASING'
        WHEN current_sales - LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_date) < 0 THEN 'DECREASING'
        ELSE 'NO CHANGE'
    END) AS py_sales_changes,
    AVG(current_sales) OVER(PARTITION BY product_name) AS avg_product_sales,
    current_sales - AVG(current_sales) OVER(PARTITION BY product_name) AS diff_average,
    (CASE
        WHEN current_sales - AVG(current_sales) OVER(PARTITION BY product_name) > 0 THEN 'ABOVE AVG'
        WHEN current_sales - AVG(current_sales) OVER(PARTITION BY product_name) < 0 THEN 'BELOW AVG'
        ELSE 'AVG'
    END) AS avg_sales_changes
FROM yearly_performance
ORDER BY product_name, order_date;


-- Which categories contribute the most to overall sales
-- (used OVER() empty here, with ORDER BY it was giving running total)
WITH category_sale 
AS(SELECT  
    category,
    SUM(sales_amount) AS total_category_sales
FROM dbo.fact_sales F
LEFT JOIN dbo.dim_products P
ON F.product_key = P.product_key
GROUP BY category)

SELECT 
    category,
    total_category_sales,
    SUM(total_category_sales) OVER () AS total_sales,
    CONCAT(ROUND((CAST(total_category_sales AS FLOAT) / SUM(total_category_sales) OVER ()) * 100, 2), '%') AS pct_of_total
FROM category_sale
ORDER BY total_category_sales DESC;


-- Data Segmentation
-- segment products into cost ranges and count how many products in each segment
WITH product_segment AS(
SELECT
    product_key,
    product_name,
    cost,
    (CASE
        WHEN cost < 100 THEN 'Below 100'
        WHEN cost BETWEEN 100 AND 500 THEN '100-500'
        WHEN cost BETWEEN 501 AND 1000 THEN '501-1000'
        ELSE 'Above 1000'
    END) AS cost_range
FROM dbo.dim_products
)

SELECT 
    cost_range,
    COUNT(product_key) AS total_products
FROM product_segment
GROUP BY cost_range
ORDER BY total_products DESC;

-- group customers into 3 segments based on spending
-- VIP : atleast 12 months history and spending more than 5000
-- Regular : atleast 12 months history but spending 5000 or less
-- New : lifespan less than 12 months
-- and find total customers in each group
WITH customer_spending AS(
SELECT 
    C.customer_key,
    SUM(F.sales_amount) AS total_spending,
    MIN(order_date) AS first_order,
    MAX(order_date) AS last_order,
    DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS lifespan
FROM dbo.fact_sales F
LEFT JOIN dbo.dim_customers C
ON F.customer_key = C.customer_key
GROUP BY C.customer_key
)

SELECT 
    customer_segment,
    COUNT(customer_key) AS total_customers
FROM (
    SELECT 
        customer_key,
        (CASE
            WHEN lifespan >= 12 AND total_spending > 5000 THEN 'VIP'
            WHEN lifespan >= 12 AND total_spending <= 5000 THEN 'Regular'
            ELSE 'New'
        END) AS customer_segment
    FROM customer_spending
) SQ
GROUP BY customer_segment
ORDER BY total_customers DESC;
GO


/*
Customer Report
- basic details : name, age, transaction details
- segments : VIP / Regular / New and age groups
- metrics : total orders, total sales, total quantity, total products, lifespan
- KPIs : recency, avg order value, avg monthly spend
*/
IF OBJECT_ID('dbo.report_customers', 'V') IS NOT NULL
    DROP VIEW dbo.report_customers;
GO

CREATE VIEW dbo.report_customers AS
WITH base_query AS(
-- base query : core columns from fact and customers
SELECT 
    F.order_number,
    F.product_key,
    F.order_date,
    F.sales_amount,
    F.quantity,
    C.customer_key,
    C.customer_number,
    CONCAT(C.first_name, ' ', C.last_name) AS customer_name,
    DATEDIFF(YEAR, C.birthdate, GETDATE()) AS age
FROM dbo.fact_sales F
LEFT JOIN dbo.dim_customers C
ON F.customer_key = C.customer_key
WHERE order_date IS NOT NULL
),
customer_aggregation AS(
-- aggregate at customer level
SELECT 
    customer_key,
    customer_number,
    customer_name,
    age,
    COUNT(DISTINCT order_number) AS total_orders,
    SUM(sales_amount) AS total_sales,
    SUM(quantity) AS total_quantity,
    COUNT(DISTINCT product_key) AS total_products,
    MAX(order_date) AS last_order_date,
    DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS lifespan
FROM base_query
GROUP BY customer_key, customer_number, customer_name, age
)

SELECT 
    customer_key,
    customer_number,
    customer_name,
    age,
    (CASE
        WHEN age < 20 THEN 'Under 20'
        WHEN age BETWEEN 20 AND 29 THEN '20-29'
        WHEN age BETWEEN 30 AND 39 THEN '30-39'
        WHEN age BETWEEN 40 AND 49 THEN '40-49'
        ELSE '50 and above'
    END) AS age_group,
    (CASE
        WHEN lifespan >= 12 AND total_sales > 5000 THEN 'VIP'
        WHEN lifespan >= 12 AND total_sales <= 5000 THEN 'Regular'
        ELSE 'New'
    END) AS customer_segment,
    last_order_date,
    DATEDIFF(MONTH, last_order_date, GETDATE()) AS recency,
    total_orders,
    total_sales,
    total_quantity,
    total_products,
    lifespan,
    -- avg order value
    (CASE WHEN total_orders = 0 THEN 0
          ELSE total_sales / total_orders
    END) AS avg_order_value,
    -- avg monthly spend
    (CASE WHEN lifespan = 0 THEN total_sales
          ELSE total_sales / lifespan
    END) AS avg_monthly_spend
FROM customer_aggregation;
GO

SELECT * FROM dbo.report_customers;

SELECT 
    customer_segment,
    COUNT(customer_number) AS total_customers,
    SUM(total_sales) AS total_sales
FROM dbo.report_customers
GROUP BY customer_segment;
GO


/*
Product Report
- basic details : product name, category, subcategory, cost
- segments : High-Performer / Mid-Range / Low-Performer by revenue
- metrics : total orders, total sales, total quantity, total customers, lifespan
- KPIs : recency, avg order revenue, avg monthly revenue
*/
IF OBJECT_ID('dbo.report_products', 'V') IS NOT NULL
    DROP VIEW dbo.report_products;
GO

CREATE VIEW dbo.report_products AS
WITH base_query AS(
-- base query : core columns from fact and products
SELECT 
    F.order_number,
    F.order_date,
    F.customer_key,
    F.sales_amount,
    F.quantity,
    P.product_key,
    P.product_name,
    P.category,
    P.subcategory,
    P.cost
FROM dbo.fact_sales F
LEFT JOIN dbo.dim_products P
ON F.product_key = P.product_key
WHERE order_date IS NOT NULL
),
product_aggregation AS(
-- aggregate at product level
SELECT 
    product_key,
    product_name,
    category,
    subcategory,
    cost,
    DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS lifespan,
    MAX(order_date) AS last_sale_date,
    COUNT(DISTINCT order_number) AS total_orders,
    COUNT(DISTINCT customer_key) AS total_customers,
    SUM(sales_amount) AS total_sales,
    SUM(quantity) AS total_quantity,
    ROUND(AVG(CAST(sales_amount AS FLOAT) / NULLIF(quantity, 0)), 1) AS avg_selling_price
FROM base_query
GROUP BY product_key, product_name, category, subcategory, cost
)

SELECT 
    product_key,
    product_name,
    category,
    subcategory,
    cost,
    last_sale_date,
    DATEDIFF(MONTH, last_sale_date, GETDATE()) AS recency_in_months,
    (CASE
        WHEN total_sales > 50000 THEN 'High-Performer'
        WHEN total_sales >= 10000 THEN 'Mid-Range'
        ELSE 'Low-Performer'
    END) AS product_segment,
    lifespan,
    total_orders,
    total_sales,
    total_quantity,
    total_customers,
    avg_selling_price,
    -- avg order revenue
    (CASE WHEN total_orders = 0 THEN 0
          ELSE total_sales / total_orders
    END) AS avg_order_revenue,
    -- avg monthly revenue
    (CASE WHEN lifespan = 0 THEN total_sales
          ELSE total_sales / lifespan
    END) AS avg_monthly_revenue
FROM product_aggregation;
GO

SELECT * FROM dbo.report_products;
