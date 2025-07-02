-- Orders Table
DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
    order_id           INTEGER PRIMARY KEY,
    user_id            INTEGER NOT NULL,
    eval_set           VARCHAR(20) NOT NULL,
    order_number       INTEGER NOT NULL,
    order_dow          INTEGER NOT NULL,
    order_hour_of_day  INTEGER NOT NULL,
    days_since_prior   REAL
);
COPY orders(order_id, user_id, eval_set, order_number, order_dow, order_hour_of_day, days_since_prior)
FROM '/tmp/data/orders.csv'
DELIMITER ','
CSV HEADER;
UPDATE orders SET days_since_prior = ROUND(days_since_prior);
ALTER TABLE orders
ALTER COLUMN days_since_prior TYPE INTEGER
USING days_since_prior::INTEGER;

-- Aisles Table
DROP TABLE IF EXISTS aisles;
CREATE TABLE aisles (
    aisle_id   INTEGER PRIMARY KEY,
    aisle      VARCHAR(255) NOT NULL
);
COPY aisles(aisle_id, aisle)
FROM '/tmp/data/aisles.csv'
DELIMITER ','
CSV HEADER;

-- Departments Table
DROP TABLE IF EXISTS departments;
CREATE TABLE departments (
    department_id   INTEGER PRIMARY KEY,
    department      VARCHAR(255) NOT NULL
);
COPY departments(department_id, department)
FROM '/tmp/data/departments.csv'
DELIMITER ','
CSV HEADER;

-- Products Table
DROP TABLE IF EXISTS products;
CREATE TABLE products (
    product_id     INTEGER PRIMARY KEY,
    product_name   VARCHAR(255) NOT NULL,
    aisle_id       INTEGER NOT NULL,
    department_id  INTEGER NOT NULL
    -- FOREIGN KEY (aisle_id) REFERENCES aisles(aisle_id),
    -- FOREIGN KEY (department_id) REFERENCES departments(department_id)
);
COPY products(product_id, product_name, aisle_id, department_id)
FROM '/tmp/data/products.csv'
DELIMITER ','
CSV HEADER;

-- Prior Orders Table
DROP TABLE IF EXISTS order_products__prior;
CREATE TABLE order_products__prior (
    order_id           INTEGER NOT NULL,
    product_id         INTEGER NOT NULL,
    add_to_cart_order  INTEGER NOT NULL,
    reordered          BOOLEAN NOT NULL
    -- PRIMARY KEY (order_id, product_id),
    -- FOREIGN KEY (order_id) REFERENCES orders(order_id),
    -- FOREIGN KEY (product_id) REFERENCES products(product_id)
);
COPY order_products__prior(order_id, product_id, add_to_cart_order, reordered)
FROM '/tmp/data/order_products__prior.csv'
DELIMITER ','
CSV HEADER;

-- Train Orders Table
DROP TABLE IF EXISTS order_products__train;
CREATE TABLE order_products__train (
    order_id           INTEGER NOT NULL,
    product_id         INTEGER NOT NULL,
    add_to_cart_order  INTEGER NOT NULL,
    reordered          BOOLEAN NOT NULL
    -- PRIMARY KEY (order_id, product_id),
    -- FOREIGN KEY (order_id) REFERENCES orders(order_id),
    -- FOREIGN KEY (product_id) REFERENCES products(product_id)
);
COPY order_products__train(order_id, product_id, add_to_cart_order, reordered)
FROM '/tmp/data/order_products__train.csv'
DELIMITER ','
CSV HEADER;