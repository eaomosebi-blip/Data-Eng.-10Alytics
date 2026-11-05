
-- =============================================
-- RUSHMORE PIZZERIA DATABASE
-- PostgreSQL CREATE TABLE SCRIPT
-- =============================================


-- 1. CUSTOMERS TABLE
CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- 2. STORES TABLE
CREATE TABLE stores (
    store_id SERIAL PRIMARY KEY,
    address VARCHAR(255) NOT NULL,
    city VARCHAR(100) NOT NULL,
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    opened_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- 3. INGREDIENTS TABLE
CREATE TABLE ingredients (
    ingredient_id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    stock_quantity NUMERIC(10,2) NOT NULL DEFAULT 0,
    unit VARCHAR(20) NOT NULL
);


-- 4. MENU_ITEMS TABLE
CREATE TABLE menu_items (
    item_id SERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    category VARCHAR(50) NOT NULL,
    size VARCHAR(20),
    unit_price NUMERIC(10,2) NOT NULL
        CHECK (unit_price > 0)
);

-- 5. ORDERS TABLE
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,

    customer_id INTEGER
        REFERENCES customers(customer_id)
        ON DELETE SET NULL,

    store_id INTEGER NOT NULL
        REFERENCES stores(store_id)
        ON DELETE RESTRICT,

    order_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total_amount NUMERIC(10,2) NOT NULL
);


-- 6. ORDER_ITEMS TABLE
CREATE TABLE order_items (
    order_item_id SERIAL PRIMARY KEY,

    order_id INTEGER NOT NULL
        REFERENCES orders(order_id),

    item_id INTEGER NOT NULL
        REFERENCES menu_items(item_id),

    quantity INTEGER NOT NULL,
    unit_price NUMERIC(10,2) NOT NULL
);


-- 7. MENU_ITEM_INGREDIENTS TABLE
CREATE TABLE menu_item_ingredients (
    item_id INTEGER NOT NULL,
    ingredient_id INTEGER NOT NULL,
    quantity_required NUMERIC(10,2) NOT NULL,
    unit VARCHAR(20) NOT NULL,

    PRIMARY KEY (item_id, ingredient_id),

    FOREIGN KEY (item_id)
        REFERENCES menu_items(item_id),

    FOREIGN KEY (ingredient_id)
        REFERENCES ingredients(ingredient_id)
);
