-- Triggers demonstrating: (1) auto-maintained audit trail, (2) enforced
-- data-quality rule beyond a static CHECK constraint, (3) auto-updated
-- timestamp.

-- 1) Audit trail: log every order status change automatically.
CREATE OR REPLACE FUNCTION warehouse.trg_log_order_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.order_status IS DISTINCT FROM NEW.order_status THEN
        INSERT INTO warehouse.order_status_audit (order_key, old_status, new_status)
        VALUES (NEW.order_key, OLD.order_status, NEW.order_status);
    END IF;
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_order_status_audit ON warehouse.fact_orders;
CREATE TRIGGER trg_order_status_audit
    BEFORE UPDATE ON warehouse.fact_orders
    FOR EACH ROW
    EXECUTE FUNCTION warehouse.trg_log_order_status_change();

-- 2) Data-quality guardrail a CHECK constraint can't express: a "returned"
--    order must have at least one corresponding row in fact_returns once
--    the order transitions to that status. Enforced as a deferred check
--    via trigger since it spans two tables.
CREATE OR REPLACE FUNCTION warehouse.trg_enforce_return_has_record()
RETURNS TRIGGER AS $$
DECLARE
    return_count INT;
BEGIN
    IF NEW.order_status = 'returned' THEN
        SELECT count(*) INTO return_count
        FROM warehouse.fact_returns r
        JOIN warehouse.fact_order_items oi ON r.order_item_key = oi.order_item_key
        WHERE oi.order_key = NEW.order_key;

        IF return_count = 0 THEN
            RAISE EXCEPTION 'Order % marked returned with no fact_returns record -- insert the return row first', NEW.order_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_return_requires_record ON warehouse.fact_orders;
CREATE TRIGGER trg_return_requires_record
    BEFORE UPDATE ON warehouse.fact_orders
    FOR EACH ROW
    EXECUTE FUNCTION warehouse.trg_enforce_return_has_record();

-- 3) Keep dim_customer.updated_at current on any change.
CREATE OR REPLACE FUNCTION warehouse.trg_touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_customer_touch ON warehouse.dim_customer;
CREATE TRIGGER trg_customer_touch
    BEFORE UPDATE ON warehouse.dim_customer
    FOR EACH ROW
    EXECUTE FUNCTION warehouse.trg_touch_updated_at();
