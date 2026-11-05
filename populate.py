import os
import random
import re
from decimal import Decimal

import psycopg2
from psycopg2.extras import execute_values
from faker import Faker
from dotenv import load_dotenv


# 1. INITIAL CONFIGURATION
load_dotenv()

fake = Faker("en_US")

random.seed(42)
Faker.seed(42)

DB_CONFIG = {
    "host": os.getenv("DB_HOST"),
    "port": os.getenv("DB_PORT", "5432"),
    "dbname": os.getenv("DB_NAME"),
    "user": os.getenv("DB_USER"),
    "password": os.getenv("DB_PASSWORD"),
    "sslmode": os.getenv("DB_SSLMODE", "require"),
}

required_variables = ["DB_HOST", "DB_NAME", "DB_USER", "DB_PASSWORD"]

missing = [v for v in required_variables if not os.getenv(v)]

if missing:
    raise ValueError(f"Missing database environment variables: {missing}")



# 2. DATA VOLUMES
NUM_STORES = 4
NUM_CUSTOMERS = 6000
NUM_ORDERS = 30000
ITEMS_PER_ORDER = 3

BATCH_SIZE = 1000



# 3. HELPER FUNCTIONS
def batch_insert(cursor, query, records):
    """Insert records efficiently in batches."""

    if records:
        execute_values(cursor, query, records, page_size=BATCH_SIZE)


def insert_and_return_ids(cursor, query, records):
    """Insert records and return their generated IDs (in insert order)."""

    if not records:
        return []

    result = execute_values(
        cursor, query, records, page_size=BATCH_SIZE, fetch=True
    )

    return [row[0] for row in result]


def generate_phone(used_phones):
    """Generate unique phone numbers within VARCHAR(20)."""

    while True:
        raw_phone = fake.phone_number()
        digits = re.sub(r"\D", "", raw_phone)

        # Standardize to a 10-digit number.
        if len(digits) < 10:
            digits = re.sub(r"\D", "", fake.numerify("###-###-####"))

        phone = "+1" + digits[-10:]

        if phone not in used_phones:
            used_phones.add(phone)
            return phone



# 4. GENERATE STORES
def generate_stores(cursor):

    print("Generating stores...")

    records = []

    for _ in range(NUM_STORES):
        records.append((
            fake.address().replace("\n", ", ")[:255],
            fake.city(),
            fake.unique.numerify("+1##########"),
        ))

    query = """
        INSERT INTO stores
        (address, city, phone_number)
        VALUES %s
        RETURNING store_id
    """

    store_ids = insert_and_return_ids(cursor, query, records)

    print(f"Inserted {len(store_ids)} stores.")

    return store_ids



# 5. GENERATE CUSTOMERS
def generate_customers(cursor):

    print("Generating customers...")

    records = []
    used_phones = set()

    for _ in range(NUM_CUSTOMERS):

        full_name = fake.name().split()

        first_name = full_name[0]
        last_name = " ".join(full_name[1:]) or fake.last_name()

        email = fake.unique.email()
        phone_number = generate_phone(used_phones)

        records.append((first_name, last_name, email, phone_number))

    query = """
        INSERT INTO customers
        (first_name, last_name, email, phone_number)
        VALUES %s
        RETURNING customer_id
    """

    customer_ids = insert_and_return_ids(cursor, query, records)

    print(f"Inserted {len(customer_ids)} customers.")

    return customer_ids



# 6. GENERATE INGREDIENTS
def generate_ingredients(cursor):

    print("Generating ingredients...")

    # (name, unit)
    ingredients = [
        ("Mozzarella Cheese", "kg"), ("Cheddar Cheese", "kg"),
        ("Parmesan Cheese", "kg"), ("Pepperoni", "kg"),
        ("Italian Sausage", "kg"), ("Chicken Breast", "kg"),
        ("Ground Beef", "kg"), ("Bacon", "kg"), ("Ham", "kg"),
        ("Mushrooms", "kg"), ("Black Olives", "kg"),
        ("Green Olives", "kg"), ("Green Peppers", "kg"),
        ("Red Onions", "kg"), ("Tomatoes", "kg"),
        ("Pineapple", "kg"), ("Spinach", "kg"), ("Jalapenos", "kg"),
        ("Garlic", "kg"), ("Basil", "kg"), ("Oregano", "kg"),
        ("Pizza Dough", "kg"), ("Tomato Sauce", "liters"),
        ("BBQ Sauce", "liters"), ("Alfredo Sauce", "liters"),
        ("Flour", "kg"), ("Yeast", "kg"), ("Salt", "kg"),
        ("Sugar", "kg"), ("Olive Oil", "liters"),
        ("Cornmeal", "kg"), ("Red Pepper Flakes", "kg"),
        ("Feta Cheese", "kg"), ("Ricotta Cheese", "kg"),
        ("Blue Cheese", "kg"), ("Cucumber", "kg"),
        ("Lettuce", "kg"), ("Ranch Dressing", "liters"),
        ("Buffalo Sauce", "liters"), ("Cilantro", "kg"),
        ("Lemon Juice", "liters"), ("Milk", "liters"),
        ("Butter", "kg"), ("Eggs", "units"), ("Water", "liters"),
    ]

    records = []

    for name, unit in ingredients:
        stock_quantity = Decimal(str(round(random.uniform(100, 1000), 2)))
        records.append((name, stock_quantity, unit))

    query = """
        INSERT INTO ingredients
        (name, stock_quantity, unit)
        VALUES %s
        RETURNING ingredient_id
    """

    ingredient_ids = insert_and_return_ids(cursor, query, records)

    # Map ingredient_id -> unit so recipes can reuse the stock unit.
    ingredient_units = {
        ingredient_id: unit
        for ingredient_id, (_, unit) in zip(ingredient_ids, ingredients)
    }

    print(f"Inserted {len(ingredient_ids)} ingredients.")

    return ingredient_ids, ingredient_units



# 7. GENERATE MENU ITEMS
def generate_menu_items(cursor):

    print("Generating menu items...")

    # Price ranges per category (min, max)
    price_ranges = {
        "Pizza": (12.00, 24.00),
        "Side": (4.00, 12.00),
        "Dessert": (4.00, 9.00),
        "Drink": (1.50, 4.50),
    }

    menu = [
        ("Classic Pepperoni Pizza", "Pizza", "Large"),
        ("Classic Cheese Pizza", "Pizza", "Medium"),
        ("Margherita Pizza", "Pizza", "Large"),
        ("BBQ Chicken Pizza", "Pizza", "Large"),
        ("Hawaiian Pizza", "Pizza", "Medium"),
        ("Supreme Pizza", "Pizza", "Large"),
        ("Veggie Delight Pizza", "Pizza", "Large"),
        ("Meat Lovers Pizza", "Pizza", "Large"),
        ("Buffalo Chicken Pizza", "Pizza", "Medium"),
        ("Four Cheese Pizza", "Pizza", "Large"),
        ("Garlic Bread", "Side", "Regular"),
        ("Chicken Wings", "Side", "Regular"),
        ("Mozzarella Sticks", "Side", "Regular"),
        ("French Fries", "Side", "Regular"),
        ("Onion Rings", "Side", "Regular"),
        ("Caesar Salad", "Side", "Regular"),
        ("Chocolate Brownie", "Dessert", "Regular"),
        ("Cheesecake", "Dessert", "Regular"),
        ("Vanilla Ice Cream", "Dessert", "Regular"),
        ("Chocolate Cake", "Dessert", "Regular"),
        ("Coca-Cola", "Drink", "500ml"),
        ("Sprite", "Drink", "500ml"),
        ("Orange Juice", "Drink", "500ml"),
        ("Bottled Water", "Drink", "500ml"),
        ("Lemonade", "Drink", "500ml"),
    ]

    # menu_items now has a NOT NULL unit_price column, so include it.
    records = []
    for name, category, size in menu:
        low, high = price_ranges[category]
        unit_price = Decimal(str(round(random.uniform(low, high), 2)))
        records.append((name, category, size, unit_price))

    query = """
        INSERT INTO menu_items
        (name, category, size, unit_price)
        VALUES %s
        RETURNING item_id
    """

    item_ids = insert_and_return_ids(cursor, query, records)

    # item_id -> unit_price, used when building order lines.
    prices = {
        item_id: record[3] for item_id, record in zip(item_ids, records)
    }

    print(f"Inserted {len(item_ids)} menu items.")

    return item_ids, prices


# 8. GENERATE MENU ITEM INGREDIENTS
def generate_menu_item_ingredients(
    cursor, item_ids, ingredient_ids, ingredient_units
):

    print("Generating menu-item ingredient relationships...")

    records = []

    for item_id in item_ids:

        # random.sample guarantees unique ingredients per item,
        # which satisfies the (item_id, ingredient_id) primary key.
        selected_ingredients = random.sample(
            ingredient_ids, random.randint(3, 6)
        )

        for ingredient_id in selected_ingredients:

            quantity_required = Decimal(
                str(round(random.uniform(0.05, 1.5), 2))
            )

            # Use the same unit the ingredient is stocked in.
            unit = ingredient_units[ingredient_id]

            records.append((item_id, ingredient_id, quantity_required, unit))

    query = """
        INSERT INTO menu_item_ingredients
        (item_id, ingredient_id, quantity_required, unit)
        VALUES %s
    """

    batch_insert(cursor, query, records)

    print(f"Inserted {len(records)} menu-item ingredient records.")



# 9. GENERATE ORDERS AND ORDER ITEMS
def generate_orders(cursor, customer_ids, store_ids, item_ids, prices):

    print(f"Generating {NUM_ORDERS} orders...")

    order_records = []
    order_lines = []

    for _ in range(NUM_ORDERS):

        customer_id = random.choice(customer_ids)
        store_id = random.choice(store_ids)

        order_timestamp = fake.date_time_this_year()

        selected_items = random.sample(item_ids, ITEMS_PER_ORDER)

        order_total = Decimal("0.00")
        current_lines = []

        for item_id in selected_items:

            quantity = random.randint(1, 3)
            unit_price = prices[item_id]

            order_total += unit_price * quantity

            current_lines.append((item_id, quantity, unit_price))

        order_records.append((
            customer_id, store_id, order_timestamp, order_total
        ))

        order_lines.append(current_lines)

    order_query = """
        INSERT INTO orders
        (customer_id, store_id, order_timestamp, total_amount)
        VALUES %s
        RETURNING order_id
    """

    order_ids = insert_and_return_ids(cursor, order_query, order_records)

    print(f"Inserted {len(order_ids)} orders.")

    order_item_records = []

    for order_id, lines in zip(order_ids, order_lines):
        for item_id, quantity, unit_price in lines:
            order_item_records.append((
                order_id, item_id, quantity, unit_price
            ))

    order_item_query = """
        INSERT INTO order_items
        (order_id, item_id, quantity, unit_price)
        VALUES %s
    """

    batch_insert(cursor, order_item_query, order_item_records)

    print(f"Inserted {len(order_item_records)} order items.")



# 10. MAIN EXECUTION
def main():

    connection = None

    try:

        print("Connecting to PostgreSQL...")

        connection = psycopg2.connect(**DB_CONFIG)
        cursor = connection.cursor()

        print("Connection successful!")

        # Parent tables first.
        store_ids = generate_stores(cursor)
        customer_ids = generate_customers(cursor)
        ingredient_ids, ingredient_units = generate_ingredients(cursor)
        item_ids, prices = generate_menu_items(cursor)

        # Many-to-many relationship.
        generate_menu_item_ingredients(
            cursor, item_ids, ingredient_ids, ingredient_units
        )

        # Transaction tables.
        generate_orders(
            cursor, customer_ids, store_ids, item_ids, prices
        )

        # Commit all inserts together.
        connection.commit()

        print("\n===================================")
        print("DATABASE POPULATION COMPLETED!")
        print("===================================")

    except Exception as error:

        if connection:
            connection.rollback()

        print("\nDATABASE POPULATION FAILED!")
        print("Error:", error)

        raise

    finally:

        if connection:
            connection.close()
            print("Database connection closed.")


if __name__ == "__main__":
    main()