-- What category was each product in on a given date?
-- This is the join a sales fact would use: event date between valid_from and valid_to.
-- Compile with `dbt compile` and run the SQL in target/, or paste it into the duckdb CLI.
select
    h.category,
    h.subcategory,
    count(*) as products
from {{ ref('dim_product_hierarchy_history') }} h
where date '2021-06-30' between h.valid_from and h.valid_to
group by 1, 2
order by 1, 2
