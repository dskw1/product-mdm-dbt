-- Work queue for data stewards: one row per issue, with enough context to act on it.
with m as (
    select * from {{ ref('dim_product_master') }}
),

x as (
    select * from {{ ref('xref_product_source') }}
),

issues as (
    select master_product_id, 'duplicate_erp_material' as issue_type, 1 as priority,
           'Same part exists under ' || count(*) || ' ERP material numbers: ' || string_agg(source_key, ', ' order by source_key) as detail
    from x where source_system = 'erp'
    group by master_product_id having count(*) > 1

    union all
    select master_product_id, 'fuzzy_match_to_confirm', 2,
           'Matched on description, score ' || round(match_score, 3) || ' (' || source_system || ' ' || source_key || ')'
    from x where match_method = 'fuzzy_description'

    union all
    select master_product_id, 'unmatched_no_mpn', 2,
           source_system || ' ' || source_key || ' has no part number and no confident match'
    from x where match_method = 'unmatched'

    union all
    select master_product_id, 'missing_cost', 3, 'Active in ERP with no usable standard cost'
    from m where in_erp and unit_cost is null and is_active

    union all
    select master_product_id, 'unmapped_category', 3, 'No canonical category from any source'
    from m where category is null

    union all
    select master_product_id, 'unresolved_brand', 3, 'Brand spelling not in the alias table: ' || brand_name
    from m where not coalesce(
        (select bool_and(is_brand_resolved) from {{ ref('int_product_records') }} r
         join x using (source_system, source_key) where x.master_product_id = m.master_product_id), true)

    union all
    select master_product_id, 'not_on_website', 4, 'Active in ERP but missing from the catalog'
    from m where in_erp and not in_catalog and is_active
)

select
    i.priority,
    i.issue_type,
    i.master_product_id,
    m.product_name,
    m.brand_name,
    i.detail
from issues i
join m using (master_product_id)
order by i.priority, i.issue_type, i.master_product_id
