/*
Golden record: one row per real product.

Survivorship rules (which source wins for each attribute):
  product_name      catalog > acquired > erp   (catalog titles are written for humans)
  mpn               catalog > erp > acquired   (catalog keeps the manufacturer's formatting)
  category          erp > catalog > acquired   (ERP drives purchasing and finance reporting)
  unit_cost         erp (most recently changed, active) > acquired
  list_price        catalog
  is_active         true if any source still has it active
*/
with x as (
    select * from {{ ref('xref_product_source') }}
),

r as (
    select
        x.master_product_id,
        x.match_method,
        rec.*,
        case rec.source_system when 'catalog' then 1 when 'acquired' then 2 else 3 end as name_rank,
        case rec.source_system when 'catalog' then 1 when 'erp' then 2 else 3 end      as mpn_rank,
        case rec.source_system when 'erp' then 1 when 'catalog' then 2 else 3 end      as category_rank,
        case rec.source_system when 'erp' then 1 else 2 end                            as cost_rank
    from x
    join {{ ref('int_product_records') }} rec using (source_system, source_key)
),

golden as (
    select
        master_product_id,
        arg_min(source_description, name_rank)                                 as product_name,
        arg_min(brand_name, category_rank)                                     as brand_name,
        arg_min(mpn_raw, mpn_rank) filter (where mpn_raw is not null)          as mpn,
        arg_min(mpn_norm, mpn_rank) filter (where mpn_norm is not null)        as mpn_key,
        arg_min(category, category_rank) filter (where category is not null)   as category,
        arg_min(subcategory, category_rank) filter (where subcategory is not null) as subcategory,
        arg_min(unit_cost, cost_rank * 100000 - datediff('day', date '2000-01-01', coalesce(updated_on, date '2000-01-01')))
            filter (where unit_cost is not null and is_active)                 as unit_cost,
        max(list_price)                                                         as list_price,
        bool_or(is_active)                                                      as is_active,
        min(created_on)                                                         as first_seen_on,
        count(*)                                                                as source_record_count,
        count(*) filter (where source_system = 'erp')                           as erp_record_count,
        bool_or(source_system = 'erp')                                          as in_erp,
        bool_or(source_system = 'catalog')                                      as in_catalog,
        bool_or(source_system = 'acquired')                                     as in_acquired,
        bool_or(match_method = 'fuzzy_description')                             as has_fuzzy_match,
        bool_or(match_method = 'unmatched')                                     as is_unmatched_single,
        bool_and(is_brand_resolved)                                             as is_brand_resolved
    from r
    group by master_product_id
)

select
    cast(master_product_id as varchar)        as master_product_id,
    cast(product_name as varchar)             as product_name,
    cast(brand_name as varchar)               as brand_name,
    cast(mpn as varchar)                      as mpn,
    cast(mpn_key as varchar)                  as mpn_key,
    cast(category as varchar)                 as category,
    cast(subcategory as varchar)              as subcategory,
    cast(unit_cost as decimal(12, 2))         as unit_cost,
    cast(list_price as decimal(12, 2))        as list_price,
    cast(case when unit_cost > 0 and list_price is not null
              then round((list_price - unit_cost) / list_price, 4) end as decimal(6, 4)) as list_margin_pct,
    cast(is_active as boolean)                as is_active,
    cast(first_seen_on as date)               as first_seen_on,
    cast(source_record_count as integer)      as source_record_count,
    cast(in_erp as boolean)                   as in_erp,
    cast(in_catalog as boolean)               as in_catalog,
    cast(in_acquired as boolean)              as in_acquired,
    cast(
        erp_record_count > 1
        or has_fuzzy_match
        or is_unmatched_single
        or not is_brand_resolved
        or category is null
        or (in_erp and unit_cost is null and is_active)
    as boolean)                               as needs_steward_review
from golden
