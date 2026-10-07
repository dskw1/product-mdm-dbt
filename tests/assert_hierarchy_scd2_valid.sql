-- SCD2 rules for the product hierarchy:
--   * no overlapping versions for a product
--   * no gaps between versions
--   * exactly one current version per product
--   * valid_from never after valid_to
with h as (
    select
        *,
        lag(valid_to) over (partition by master_product_id order by valid_from) as prev_valid_to
    from {{ ref('dim_product_hierarchy_history') }}
),

bad_rows as (
    select master_product_id, 'overlap or gap' as problem
    from h
    where prev_valid_to is not null and valid_from <> prev_valid_to + interval 1 day

    union all
    select master_product_id, 'valid_from after valid_to'
    from h
    where valid_from > valid_to

    union all
    select master_product_id, 'current version count <> 1'
    from h
    group by master_product_id
    having count(*) filter (where is_current) <> 1
)

select * from bad_rows
