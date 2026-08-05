{#
  Overrides dbt's default schema-naming behavior, which would otherwise
  prefix custom schemas with the profile's default schema (e.g. "raw_bronze"
  instead of "bronze"). Since Snowflake already has real, exactly-named
  bronze/gold schemas (Phase 2), a model's `+schema:` config should map
  directly to that schema name with no prefix.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
