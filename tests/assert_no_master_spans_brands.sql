-- A master product built from records with different brands is a false merge.
-- (Brand is part of the match key and the fuzzy block, so this should never fire.
-- It's here so a future change to the matching logic can't quietly break that.)
select x.master_product_id, count(distinct r.brand_name) as brands
from {{ ref('xref_product_source') }} x
join {{ ref('int_product_records') }} r using (source_system, source_key)
group by x.master_product_id
having count(distinct r.brand_name) > 1
