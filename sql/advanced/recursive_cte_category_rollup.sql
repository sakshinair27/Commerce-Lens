-- Recursive CTE: category tree traversal. dim_category is self-referencing
-- (parent_category_id), so computing "total sales for Electronics including
-- every subcategory under it" requires walking the tree -- a plain JOIN
-- can't do this for an arbitrary-depth hierarchy.

WITH RECURSIVE category_tree AS (
    -- anchor: every category is its own root-of-traversal to start
    SELECT
        category_id,
        category_name,
        parent_category_id,
        category_id AS top_level_category_id,
        category_name AS top_level_category_name,
        0 AS depth
    FROM warehouse.dim_category
    WHERE parent_category_id IS NULL

    UNION ALL

    SELECT
        c.category_id,
        c.category_name,
        c.parent_category_id,
        ct.top_level_category_id,
        ct.top_level_category_name,
        ct.depth + 1
    FROM warehouse.dim_category c
    JOIN category_tree ct ON c.parent_category_id = ct.category_id
)
SELECT
    ct.top_level_category_id,
    ct.top_level_category_name,
    COUNT(DISTINCT ct.category_id) AS subcategory_count,
    COALESCE(SUM(foi.line_total), 0) AS total_sales,
    COALESCE(SUM(foi.quantity), 0) AS total_units_sold
FROM category_tree ct
LEFT JOIN warehouse.dim_product dp ON dp.category_id = ct.category_id
LEFT JOIN warehouse.fact_order_items foi ON foi.product_key = dp.product_key
GROUP BY ct.top_level_category_id, ct.top_level_category_name
ORDER BY total_sales DESC;
