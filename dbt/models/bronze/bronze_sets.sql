{{
  config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='set_pk'
  )
}}

-- One row per set, cleaned and typed. Incremental: each run only processes
-- rows past the control table's watermark, merged in by set_pk -- so a
-- file reprocessed at the boundary can't create duplicates.
--
-- set_pk is a surrogate key over (start_time, exercise_title, set_index)
-- since Hevy's export has no true row-level ID (see build plan). Known
-- limitation: if the same exercise appears twice non-contiguously in one
-- workout, set_index could collide -- not observed in sample data, not
-- solved here.
--
-- Timestamps use Snowflake's TRY_TO_TIMESTAMP (returns NULL instead of
-- erroring on a bad value) against the live export's actual format, e.g.
-- "Jul 31, 2026, 6:52 PM" -- confirmed by testing the real extraction
-- script, which differs from the original static sample file's format.

with source as (
    select * from {{ source('raw', 'hevy_export') }}
),

casted as (
    select
        md5(start_time || '|' || exercise_title || '|' || set_index) as set_pk,
        title,
        try_to_timestamp(start_time, 'mon dd, yyyy, hh12:mi am') as start_time,
        try_to_timestamp(end_time, 'mon dd, yyyy, hh12:mi am')   as end_time,
        nullif(description, '')     as description,
        exercise_title,
        nullif(superset_id, '')     as superset_id,
        nullif(exercise_notes, '')  as exercise_notes,
        try_to_number(set_index)    as set_index,
        set_type,
        try_to_number(weight_lbs)      as weight_lbs,
        try_to_number(reps)            as reps,
        try_to_double(distance_miles)  as distance_miles,
        try_to_number(duration_seconds) as duration_seconds,
        try_to_number(rpe)             as rpe
    from source
)

select * from casted

{% if is_incremental() %}
where end_time > (
    select last_watermark_ts
    from {{ source('bronze', 'pipeline_control') }}
    where pipeline_name = 'hevy'
)
{% endif %}
