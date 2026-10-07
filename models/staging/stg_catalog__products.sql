-- E-commerce catalog, one row per web SKU.
with src as (
    select * from {{ ref('raw_catalog_products') }}
),

brands as (
    select distinct upper(trim(brand_alias)) as alias_key, brand_name
    from {{ ref('ref_brand_aliases') }}
)

select
    'catalog'                                    as source_system,
    s.catalog_sku                                as source_key,
    s.title                                      as source_description,
    s.brand                                      as source_brand,
    coalesce(b.brand_name, s.brand)              as brand_name,
    b.brand_name is not null                     as is_brand_resolved,
    nullif(trim(s.mpn), '')                      as mpn_raw,
    {{ normalize_mpn('s.mpn') }}                 as mpn_norm,
    s.category_path                              as source_category,
    cast(null as decimal(12, 2))                 as unit_cost,
    s.list_price                                 as list_price,
    cast(s.is_published as boolean)              as is_active,
    cast(null as date)                           as created_on,
    cast(null as date)                           as updated_on
from src s
left join brands b on upper(trim(s.brand)) = b.alias_key
