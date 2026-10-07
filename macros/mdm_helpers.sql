{# Part numbers show up as "AL-48213-B", "AL48213B", "al 48213 b", "AL/48213/B".
   Strip everything that isn't a letter or digit so they all compare equal. #}
{% macro normalize_mpn(col) -%}
    nullif(regexp_replace(upper(coalesce({{ col }}, '')), '[^A-Z0-9]', '', 'g'), '')
{%- endmacro %}

{# Text used for fuzzy matching. Lowercase, drop the brand (every record in a
   matching block shares it, so it only inflates similarity), unify "3 ton" / "3t",
   then squash out spaces and punctuation. #}
{% macro match_text(text_col, brand_col) -%}
    regexp_replace(
        regexp_replace(
            replace(lower({{ text_col }}), lower({{ brand_col }}), ''),
            '\s*(ton)\b', 't', 'g'),
        '[^a-z0-9./]', '', 'g')
{%- endmacro %}

{# Put the schema name exactly where the project says, without the target prefix. #}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}{{ target.schema }}{%- else -%}{{ custom_schema_name | trim }}{%- endif -%}
{%- endmacro %}
