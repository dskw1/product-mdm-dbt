-- Every source record in one shape, with the canonical category attached
-- and the text used for fuzzy matching.
with unioned as (
    select * from {{ ref('stg_erp__products') }}
    union all
    select * from {{ ref('stg_catalog__products') }}
    union all
    select * from {{ ref('stg_acq__products') }}
),

cat_map as (
    select * from {{ ref('ref_category_map') }}
)

select
    u.*,
    m.category,
    m.subcategory,
    {{ match_text('u.source_description', 'u.brand_name') }} as match_text
from unioned u
left join cat_map m
    on  m.source_system   = u.source_system
    and m.source_category = u.source_category
