/*
SCD Type 2 product hierarchy, built from the ERP category change log.

Reports that need "what category was this in when we sold it" join on
sale_date between valid_from and valid_to. Steps:
  1. Map each ERP log entry to its master product and canonical category.
     Where a product has duplicate ERP materials, the oldest one is the survivor.
  2. Collapse consecutive rows that land on the same canonical category
     (re-saves, or two old codes that map to the same place).
  3. Close each version the day before the next one starts.
*/
with survivor_material as (
    select
        x.master_product_id,
        arg_min(x.source_key, r.created_on) as material_number
    from {{ ref('xref_product_source') }} x
    join {{ ref('int_product_records') }} r using (source_system, source_key)
    where x.source_system = 'erp'
    group by x.master_product_id
),

log as (
    select
        s.master_product_id,
        cast(l.effective_date as date) as effective_date,
        l.category_code,
        m.category,
        m.subcategory,
        row_number() over (partition by s.master_product_id order by cast(l.effective_date as date), l.category_code) as seq
    from {{ ref('raw_erp_category_log') }} l
    join survivor_material s on s.material_number = l.material_number
    left join {{ ref('ref_category_map') }} m
        on m.source_system = 'erp' and m.source_category = l.category_code
),

flagged as (
    select
        *,
        case when coalesce(category, '?') || '|' || coalesce(subcategory, '?')
                = lag(coalesce(category, '?') || '|' || coalesce(subcategory, '?'))
                  over (partition by master_product_id order by seq)
             then 0 else 1 end as is_change
    from log
),

islands as (
    select
        *,
        sum(is_change) over (partition by master_product_id order by seq
                             rows between unbounded preceding and current row) as version
    from flagged
),

versions as (
    select
        master_product_id,
        version,
        min(effective_date)          as valid_from,
        arg_min(category_code, seq)  as category_code,
        any_value(category)          as category,
        any_value(subcategory)       as subcategory
    from islands
    group by master_product_id, version
),

-- two different categories on the same day: keep the later entry
same_day as (
    select *
    from versions
    qualify row_number() over (partition by master_product_id, valid_from order by version desc) = 1
)

select
    master_product_id || '-' || lpad(cast(row_number() over (partition by master_product_id order by valid_from) as varchar), 3, '0')
                                                         as hierarchy_version_id,
    master_product_id,
    category_code                                        as source_category_code,
    category,
    subcategory,
    valid_from,
    coalesce(lead(valid_from) over (partition by master_product_id order by valid_from) - interval 1 day,
             date '9999-12-31')::date                    as valid_to,
    lead(valid_from) over (partition by master_product_id order by valid_from) is null as is_current
from same_day
