-- Recursive CTE: rolls sales up through the category hierarchy so a parent
-- category's total includes all of its subcategories' sales, not just its
-- own directly-tagged products. dbt equivalent of
-- sql/advanced/recursive_cte_category_rollup.sql.
with recursive category_tree as (
    select category_key, category_id, category_name, parent_category_id, category_key as root_category_key
    from {{ ref('dim_category') }}
    where parent_category_id is null

    union all

    select c.category_key, c.category_id, c.category_name, c.parent_category_id, ct.root_category_key
    from {{ ref('dim_category') }} c
    inner join category_tree ct on c.parent_category_id = ct.category_id
),

sales as (
    select
        dp.category_key,
        foi.line_total
    from {{ ref('fct_order_items') }} foi
    inner join {{ ref('dim_product') }} dp on foi.product_key = dp.product_key
)

select
    ct.root_category_key as category_key,
    root.category_name,
    count(distinct ct.category_key) as subcategory_count,
    coalesce(sum(s.line_total), 0) as total_sales,
    count(s.line_total) as line_item_count
from category_tree ct
inner join {{ ref('dim_category') }} root on ct.root_category_key = root.category_key
left join sales s on s.category_key = ct.category_key
group by ct.root_category_key, root.category_name
order by total_sales desc
