/*
Assign every source record a match key. Records sharing a key become one master product.

Pass 1, exact: brand + normalized MPN. This handles most records, including the
ERP's own duplicate material numbers.

Pass 2, fuzzy: records with no MPN are compared to the exact-match clusters in the
same brand and subcategory (the "block"). Candidates must also pass a spec guard:
every number in the description (tonnage, SEER, HP, filter size) has to match.
Text similarity alone happily pairs "2 ton 14 SEER" with "2 ton 18 SEER".
A record joins a cluster only if its best score clears fuzzy_min_score AND beats
the runner-up by fuzzy_min_margin. Close calls
stay unmatched on purpose. A false merge is much more expensive to undo than a
false split, so ambiguous records go to a data steward instead.

Anything left becomes its own single-record master and gets flagged for review.
*/
with records as (
    select * from {{ ref('int_product_records') }}
),

exact as (
    select
        source_system,
        source_key,
        brand_name || '|' || mpn_norm as match_key,
        'exact_mpn'                   as match_method,
        cast(1.0 as double)           as match_score
    from records
    where mpn_norm is not null
),

-- One reference text per exact cluster. Catalog titles are the cleanest, so prefer them.
cluster_text as (
    select
        e.match_key,
        r.brand_name,
        r.subcategory,
        arg_min(r.match_text, case r.source_system when 'catalog' then 1 when 'acquired' then 2 else 3 end) as match_text
    from exact e
    join records r using (source_system, source_key)
    group by e.match_key, r.brand_name, r.subcategory
),

no_mpn as (
    select * from records where mpn_norm is null
),

scored as (
    select
        n.source_system,
        n.source_key,
        c.match_key,
        jaro_winkler_similarity(n.match_text, c.match_text) as score
    from no_mpn n
    join cluster_text c
        on  c.brand_name  = n.brand_name
        and c.subcategory = n.subcategory
    -- spec guard
    where list_sort(regexp_extract_all(n.match_text, '[0-9]+(?:\.[0-9]+)?'))
        = list_sort(regexp_extract_all(c.match_text, '[0-9]+(?:\.[0-9]+)?'))
),

ranked as (
    select
        *,
        row_number() over (partition by source_system, source_key order by score desc, match_key) as rnk,
        lead(score)  over (partition by source_system, source_key order by score desc, match_key) as runner_up
    from scored
),

fuzzy as (
    select
        source_system,
        source_key,
        match_key,
        'fuzzy_description' as match_method,
        score               as match_score
    from ranked
    where rnk = 1
      and score >= {{ var('fuzzy_min_score') }}
      and score - coalesce(runner_up, 0) >= {{ var('fuzzy_min_margin') }}
),

unmatched as (
    select
        n.source_system,
        n.source_key,
        'single|' || n.source_system || '|' || n.source_key as match_key,
        'unmatched'                                         as match_method,
        cast(null as double)                                as match_score
    from no_mpn n
    anti join fuzzy f using (source_system, source_key)
)

select * from exact
union all
select * from fuzzy
union all
select * from unmatched
