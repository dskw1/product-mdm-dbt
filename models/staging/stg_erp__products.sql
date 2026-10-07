-- ERP material master, one row per material number.
with src as (
    select * from {{ ref('raw_erp_products') }}
),

brands as (
    select distinct upper(trim(brand_alias)) as alias_key, brand_name
    from {{ ref('ref_brand_aliases') }}
)

select
    'erp'                                        as source_system,
    s.material_number                            as source_key,
    s.material_desc                              as source_description,
    s.manufacturer                               as source_brand,
    coalesce(b.brand_name, s.manufacturer)       as brand_name,
    b.brand_name is not null                     as is_brand_resolved,
    nullif(trim(s.mfr_part_number), '')          as mpn_raw,
    {{ normalize_mpn('s.mfr_part_number') }}     as mpn_norm,
    s.category_code                              as source_category,
    s.standard_cost                              as unit_cost,
    cast(null as decimal(12, 2))                 as list_price,
    coalesce(s.deletion_flag, '') <> 'X'         as is_active,
    cast(s.created_on as date)                   as created_on,
    cast(s.changed_on as date)                   as updated_on
from src s
left join brands b on upper(trim(s.manufacturer)) = b.alias_key
