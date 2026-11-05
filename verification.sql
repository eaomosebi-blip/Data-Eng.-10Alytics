
-- RUSHMORE PIZZERIA: DATA QUALITY & OPTIMIZATION PROOF



-- =============================================
-- PART 1: DATA QUALITY
-- =============================================

-- 1.1 ROW COUNTS (expected values in the last column)
SELECT 'stores' AS table_name, COUNT(*) AS actual_rows, 4 AS expected_rows FROM stores
UNION ALL SELECT 'customers', COUNT(*), 6000 FROM customers
UNION ALL SELECT 'ingredients', COUNT(*), 45 FROM ingredients
UNION ALL SELECT 'menu_items', COUNT(*), 25 FROM menu_items
UNION ALL SELECT 'orders', COUNT(*), 30000 FROM orders
UNION ALL SELECT 'order_items', COUNT(*), 90000 FROM order_items   -- 30,000 orders x 3 items
UNION ALL SELECT 'menu_item_ingredients', COUNT(*), NULL FROM menu_item_ingredients;  -- 3 to 6 per item (75-150)


-- 1.2 INTEGRITY CHECKS (every issues_found should be 0)
SELECT check_name, issues_found,
       CASE WHEN issues_found = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM (

    -- Orphaned foreign keys
    SELECT 'order_items with no matching order' AS check_name, COUNT(*) AS issues_found
    FROM order_items oi LEFT JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_id IS NULL

    UNION ALL
    SELECT 'order_items with no matching menu item', COUNT(*)
    FROM order_items oi LEFT JOIN menu_items m ON m.item_id = oi.item_id
    WHERE m.item_id IS NULL

    UNION ALL
    SELECT 'orders with no matching store', COUNT(*)
    FROM orders o LEFT JOIN stores s ON s.store_id = o.store_id
    WHERE s.store_id IS NULL

    UNION ALL
    SELECT 'orders with missing customer', COUNT(*)
    FROM orders WHERE customer_id IS NULL

    UNION ALL
    SELECT 'recipe rows with no matching ingredient', COUNT(*)
    FROM menu_item_ingredients mii
    LEFT JOIN ingredients i ON i.ingredient_id = mii.ingredient_id
    WHERE i.ingredient_id IS NULL

    -- Duplicates
    UNION ALL
    SELECT 'duplicate customer emails', COUNT(*) FROM (
        SELECT email FROM customers GROUP BY email HAVING COUNT(*) > 1) d

    UNION ALL
    SELECT 'duplicate customer phones', COUNT(*) FROM (
        SELECT phone_number FROM customers GROUP BY phone_number HAVING COUNT(*) > 1) d

    UNION ALL
    SELECT 'duplicate items within one order', COUNT(*) FROM (
        SELECT order_id, item_id FROM order_items
        GROUP BY order_id, item_id HAVING COUNT(*) > 1) d

    -- Value ranges
    UNION ALL
    SELECT 'non-positive quantities or prices', COUNT(*)
    FROM order_items WHERE quantity <= 0 OR unit_price <= 0

    UNION ALL
    SELECT 'orders with zero or negative total', COUNT(*)
    FROM orders WHERE total_amount <= 0

    UNION ALL
    SELECT 'orders dated in the future', COUNT(*)
    FROM orders WHERE order_timestamp > CURRENT_TIMESTAMP

    UNION ALL
    SELECT 'negative ingredient stock', COUNT(*)
    FROM ingredients WHERE stock_quantity < 0

    -- Business rules
    UNION ALL
    SELECT 'orders where total <> sum of line items', COUNT(*) FROM (
        SELECT o.order_id
        FROM orders o
        JOIN order_items oi ON oi.order_id = o.order_id
        GROUP BY o.order_id, o.total_amount
        HAVING o.total_amount <> SUM(oi.quantity * oi.unit_price)) d

    UNION ALL
    SELECT 'order line price <> current menu price', COUNT(*)
    FROM order_items oi JOIN menu_items m ON m.item_id = oi.item_id
    WHERE oi.unit_price <> m.unit_price

    UNION ALL
    SELECT 'orders with no line items', COUNT(*)
    FROM orders o LEFT JOIN order_items oi ON oi.order_id = o.order_id
    WHERE oi.order_id IS NULL

    UNION ALL
    SELECT 'menu items with no recipe', COUNT(*)
    FROM menu_items m LEFT JOIN menu_item_ingredients mii ON mii.item_id = m.item_id
    WHERE mii.item_id IS NULL

) checks
ORDER BY status DESC, check_name;


-- 1.3 DISTRIBUTION SANITY CHECKS (look for plausible spreads)
-- Orders per store
SELECT s.store_id, s.city, COUNT(o.order_id) AS orders, SUM(o.total_amount) AS revenue
FROM stores s LEFT JOIN orders o ON o.store_id = s.store_id
GROUP BY s.store_id, s.city ORDER BY s.store_id;

-- Orders per month
SELECT DATE_TRUNC('month', order_timestamp) AS month, COUNT(*) AS orders
FROM orders GROUP BY 1 ORDER BY 1;

-- Order value summary
SELECT MIN(total_amount) AS min_total, ROUND(AVG(total_amount), 2) AS avg_total,
       MAX(total_amount) AS max_total
FROM orders;


-- =============================================
-- PART 2: OPTIMIZATION PROOF (indexes)
-- PostgreSQL does NOT automatically index foreign key columns,
-- so the joins below start as sequential scans.
-- =============================================

-- 2.1 BASELINE: remove any custom indexes so the "before" run is clean
DROP INDEX IF EXISTS idx_orders_customer_id;
DROP INDEX IF EXISTS idx_orders_store_id;
DROP INDEX IF EXISTS idx_orders_timestamp;
DROP INDEX IF EXISTS idx_order_items_order_id;
DROP INDEX IF EXISTS idx_order_items_item_id;
DROP INDEX IF EXISTS idx_mii_ingredient_id;
ANALYZE;

-- 2.2 BEFORE: run each query and record "Execution Time" and the scan type
-- Query A: order history for one customer
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.order_id, o.order_timestamp, o.total_amount
FROM orders o
WHERE o.customer_id = 100
ORDER BY o.order_timestamp DESC;

-- Query B: line items for a single order (join)
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.order_id, m.name, oi.quantity, oi.unit_price
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN menu_items m ON m.item_id = oi.item_id
WHERE o.order_id = 12345;

-- Query C: monthly revenue for one store
EXPLAIN (ANALYZE, BUFFERS)
SELECT DATE_TRUNC('month', order_timestamp) AS month, SUM(total_amount) AS revenue
FROM orders
WHERE store_id = 2
  AND order_timestamp >= DATE_TRUNC('year', CURRENT_DATE)
GROUP BY 1 ORDER BY 1;

-- Query D: best-selling items
EXPLAIN (ANALYZE, BUFFERS)
SELECT m.name, SUM(oi.quantity) AS units_sold, SUM(oi.quantity * oi.unit_price) AS revenue
FROM order_items oi
JOIN menu_items m ON m.item_id = oi.item_id
GROUP BY m.name
ORDER BY units_sold DESC
LIMIT 10;


-- 2.3 CREATE INDEXES
CREATE INDEX idx_orders_customer_id    ON orders (customer_id, order_timestamp DESC);
CREATE INDEX idx_orders_store_time     ON orders (store_id, order_timestamp);
CREATE INDEX idx_orders_timestamp      ON orders (order_timestamp);
CREATE INDEX idx_order_items_order_id  ON order_items (order_id);
CREATE INDEX idx_order_items_item_id   ON order_items (item_id);
CREATE INDEX idx_mii_ingredient_id     ON menu_item_ingredients (ingredient_id);
ANALYZE;


-- 2.4 AFTER: rerun the exact same four queries and compare
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.order_id, o.order_timestamp, o.total_amount
FROM orders o
WHERE o.customer_id = 100
ORDER BY o.order_timestamp DESC;

EXPLAIN (ANALYZE, BUFFERS)
SELECT o.order_id, m.name, oi.quantity, oi.unit_price
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN menu_items m ON m.item_id = oi.item_id
WHERE o.order_id = 12345;

EXPLAIN (ANALYZE, BUFFERS)
SELECT DATE_TRUNC('month', order_timestamp) AS month, SUM(total_amount) AS revenue
FROM orders
WHERE store_id = 2
  AND order_timestamp >= DATE_TRUNC('year', CURRENT_DATE)
GROUP BY 1 ORDER BY 1;

EXPLAIN (ANALYZE, BUFFERS)
SELECT m.name, SUM(oi.quantity) AS units_sold, SUM(oi.quantity * oi.unit_price) AS revenue
FROM order_items oi
JOIN menu_items m ON m.item_id = oi.item_id
GROUP BY m.name
ORDER BY units_sold DESC
LIMIT 10;


-- 2.5 LIST THE INDEXES AS EVIDENCE
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;
