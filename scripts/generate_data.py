"""
Generates a realistically sized, intentionally messy synthetic e-commerce
dataset -- 5,000 customers, ~500 products across a hierarchical category
tree, 25,000 orders, ~65,000 order line items, ~2,500 returns -- and writes
CSVs to /data for loading into the raw schema.

Messiness is deliberate: inconsistent date formats, mixed-case emails,
"$19.99" vs "19.99" price strings, a handful of duplicate customer rows,
and some missing categories -- this is what justifies the dbt staging
layer's cleaning logic and the data-quality tests in schema.yml, rather
than starting from data that's already clean.
"""
import csv
import os
import random
from datetime import datetime, timedelta

from faker import Faker

fake = Faker()
Faker.seed(42)
random.seed(42)

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
os.makedirs(OUT_DIR, exist_ok=True)

N_CUSTOMERS = 5000
N_ORDERS = 25000
N_RETURN_RATE = 0.08  # ~8% of order items get returned

STATES = ["NY", "CA", "TX", "FL", "IL", "WA", "MA", "CO", "GA", "NC"]
PAYMENT_METHODS = ["credit_card", "debit_card", "paypal", "gift_card"]
ORDER_STATUSES = ["placed", "shipped", "delivered", "cancelled", "returned"]
RETURN_REASONS = ["defective", "wrong_item", "no_longer_needed", "damaged_in_shipping", "changed_mind"]

# ---- Category tree: 6 top-level categories, each with 2-4 subcategories ----
CATEGORY_TREE = {
    "Electronics": ["Laptops", "Headphones", "Smart Home", "Cameras"],
    "Home & Kitchen": ["Cookware", "Furniture", "Bedding"],
    "Apparel": ["Men's", "Women's", "Kids"],
    "Sports & Outdoors": ["Fitness", "Camping", "Cycling"],
    "Beauty": ["Skincare", "Haircare"],
    "Books": ["Fiction", "Non-Fiction", "Children's"],
}


def gen_categories():
    rows = []
    cid = 1
    id_map = {}
    for top, subs in CATEGORY_TREE.items():
        top_id = f"CAT-{cid:03d}"
        id_map[top] = top_id
        rows.append({"category_id": top_id, "category_name": top, "parent_category_id": ""})
        cid += 1
        for sub in subs:
            sub_id = f"CAT-{cid:03d}"
            rows.append({"category_id": sub_id, "category_name": sub, "parent_category_id": top_id})
            id_map[sub] = sub_id
            cid += 1
    return rows, id_map


def gen_customers(n):
    rows = []
    for i in range(1, n + 1):
        cust_id = f"CUST-{i:06d}"
        name = fake.name()
        email = f"{name.split()[0].lower()}.{name.split()[-1].lower()}{random.randint(1,999)}@{fake.free_email_domain()}"
        if random.random() < 0.03:
            email = email.upper()  # messiness: inconsistent casing
        signup = fake.date_between(start_date="-3y", end_date="-1m")
        date_fmt = random.choice(["%Y-%m-%d", "%m/%d/%Y"])  # messiness: mixed formats
        rows.append(
            {
                "customer_id": cust_id,
                "full_name": name,
                "email": email if random.random() > 0.02 else "",  # some missing emails
                "signup_date": signup.strftime(date_fmt),
                "city": fake.city(),
                "state": random.choice(STATES),
                "country": "US",
                "segment": random.choice(["consumer", "small_business", "enterprise"]),
            }
        )
    # inject a handful of duplicate rows (messiness -> dedup logic in dbt staging)
    for _ in range(25):
        rows.append(random.choice(rows[: n]))
    return rows


def gen_products(category_ids):
    rows = []
    for i in range(1, 501):
        price = round(random.uniform(5, 500), 2)
        price_str = f"${price}" if random.random() < 0.4 else str(price)  # messiness
        rows.append(
            {
                "product_id": f"PROD-{i:05d}",
                "product_name": fake.catch_phrase(),
                "category_id": random.choice(category_ids) if random.random() > 0.01 else "",
                "brand": fake.company(),
                "unit_price": price_str,
                "is_active": random.choice(["true", "false", "TRUE", "1"]),  # messiness
            }
        )
    return rows


def gen_orders_and_items(customers, products, n_orders):
    orders = []
    items = []
    returns = []
    order_item_id = 1
    return_id = 1
    start = datetime(2024, 1, 1)

    for i in range(1, n_orders + 1):
        order_id = f"ORD-{i:07d}"
        cust = random.choice(customers)
        order_date = start + timedelta(days=random.randint(0, 940))
        status = random.choices(ORDER_STATUSES, weights=[5, 10, 65, 10, 10])[0]
        n_items = random.randint(1, 5)
        order_total = 0.0

        chosen_products = random.sample(products, n_items)
        for prod in chosen_products:
            qty = random.randint(1, 4)
            unit_price = round(random.uniform(5, 500), 2)
            discount = random.choice([0, 0, 0, 5, 10, 15, 20])
            line_total = round(qty * unit_price * (1 - discount / 100), 2)
            order_total += line_total

            items.append(
                {
                    "order_item_id": f"OI-{order_item_id:08d}",
                    "order_id": order_id,
                    "product_id": prod["product_id"],
                    "quantity": qty,
                    "unit_price": unit_price,
                    "discount_pct": discount,
                }
            )

            if status == "returned" or random.random() < N_RETURN_RATE:
                return_date = order_date + timedelta(days=random.randint(2, 30))
                returns.append(
                    {
                        "return_id": f"RET-{return_id:07d}",
                        "order_item_id": f"OI-{order_item_id:08d}",
                        "return_date": return_date.strftime("%Y-%m-%d"),
                        "return_reason": random.choice(RETURN_REASONS),
                        "refund_amount": round(line_total * random.uniform(0.8, 1.0), 2),
                    }
                )
                return_id += 1

            order_item_id += 1

        orders.append(
            {
                "order_id": order_id,
                "customer_id": cust["customer_id"],
                "order_date": order_date.strftime("%Y-%m-%d") if random.random() > 0.5 else order_date.strftime("%m/%d/%Y"),
                "order_status": status,
                "payment_method": random.choice(PAYMENT_METHODS),
                "shipping_cost": round(random.uniform(0, 15), 2),
            }
        )

    return orders, items, returns


def write_csv(path, rows, fieldnames):
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    categories, id_map = gen_categories()
    category_ids = [c["category_id"] for c in categories]
    customers = gen_customers(N_CUSTOMERS)
    products = gen_products(category_ids)
    orders, items, returns = gen_orders_and_items(customers, products, N_ORDERS)

    write_csv(f"{OUT_DIR}/categories.csv", categories, ["category_id", "category_name", "parent_category_id"])
    write_csv(f"{OUT_DIR}/customers.csv", customers, list(customers[0].keys()))
    write_csv(f"{OUT_DIR}/products.csv", products, list(products[0].keys()))
    write_csv(f"{OUT_DIR}/orders.csv", orders, list(orders[0].keys()))
    write_csv(f"{OUT_DIR}/order_items.csv", items, list(items[0].keys()))
    write_csv(f"{OUT_DIR}/returns.csv", returns, list(returns[0].keys()))

    print(f"categories={len(categories)} customers={len(customers)} products={len(products)} "
          f"orders={len(orders)} order_items={len(items)} returns={len(returns)}")
