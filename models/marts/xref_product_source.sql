-- Crosswalk: which master product each source record rolls up to, and how it got there.
-- This is the table every downstream system joins through.
select
    cast(m.source_system as varchar)                                     as source_system,
    cast(m.source_key as varchar)                                        as source_key,
    cast('MP' || upper(substr(md5(m.match_key), 1, 10)) as varchar)      as master_product_id,
    cast(m.match_method as varchar)                                      as match_method,
    cast(m.match_score as double)                                        as match_score,
    cast(r.is_active as boolean)                                         as is_source_active
from {{ ref('int_product_matches') }} m
join {{ ref('int_product_records') }} r using (source_system, source_key)
