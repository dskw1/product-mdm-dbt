-- Every record from every source must land in the crosswalk exactly once.
-- A record that falls out of the xref is invisible to every downstream report.
select r.source_system, r.source_key
from {{ ref('int_product_records') }} r
left join {{ ref('xref_product_source') }} x using (source_system, source_key)
where x.master_product_id is null
