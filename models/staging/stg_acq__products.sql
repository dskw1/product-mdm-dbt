-- Item file from the acquired distributor, one row per item id.
with src as (
    select * from {{ ref('raw_acq_products') }}
),

brands as (
    select distinct upper(trim(brand_alias)) as alias_key, brand_name
    from {{ ref('ref_brand_aliases') }}
)

select
    'acquired'                                   as source_system,
    s.item_id                                    as source_key,
    s.item_desc                                  as source_description,
    s.vendor_name                                as source_brand,
    coalesce(b.brand_name, s.vendor_name)        as brand_name,
    b.brand_name is not null                     as is_brand_resolved,
    nullif(trim(s.vendor_part_no), '')           as mpn_raw,
    {{ normalize_mpn('s.vendor_part_no') }}      as mpn_norm,
    s.item_category                              as source_category,
    s.last_cost                                  as unit_cost,
    cast(null as decimal(12, 2))                 as list_price,
    true                                         as is_active,
    cast(s.acquired_on as date)                  as created_on,
    cast(s.acquired_on as date)                  as updated_on
from src s
left join brands b on upper(trim(s.vendor_name)) = b.alias_key
