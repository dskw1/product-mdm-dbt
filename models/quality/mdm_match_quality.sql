/*
Score the matching against the ground truth file, using pairwise precision and recall.

  A "pair" is two source records that belong together.
  precision = of the pairs we merged, how many really are the same product
  recall    = of the pairs that really are the same product, how many we merged

The ground truth only exists because the data is synthetic. In production you'd
get the same numbers from a steward-labeled sample.
*/
with x as (
    select x.source_system, x.source_key, x.master_product_id, x.match_method, t.true_product_id
    from {{ ref('xref_product_source') }} x
    join {{ ref('mdm_ground_truth') }} t using (source_system, source_key)
),

predicted as (
    select sum(n * (n - 1) / 2) as pairs
    from (select count(*) as n from x group by master_product_id)
),

actual as (
    select sum(n * (n - 1) / 2) as pairs
    from (select count(*) as n from x group by true_product_id)
),

correct as (
    select sum(n * (n - 1) / 2) as pairs
    from (select count(*) as n from x group by master_product_id, true_product_id)
)

select
    (select count(*) from x)                                    as source_records,
    (select count(distinct true_product_id) from x)             as true_products,
    (select count(distinct master_product_id) from x)           as master_products,
    (select count(*) from x where match_method = 'exact_mpn')         as exact_matched_records,
    (select count(*) from x where match_method = 'fuzzy_description') as fuzzy_matched_records,
    (select count(*) from x where match_method = 'unmatched')         as unmatched_records,
    cast(c.pairs as bigint)                                     as correct_pairs,
    cast(p.pairs as bigint)                                     as predicted_pairs,
    cast(a.pairs as bigint)                                     as actual_pairs,
    round(c.pairs / nullif(p.pairs, 0), 4)                      as pair_precision,
    round(c.pairs / nullif(a.pairs, 0), 4)                      as pair_recall
from correct c, predicted p, actual a
