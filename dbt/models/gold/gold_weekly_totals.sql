-- One row per week: workout count and rolled-up strength/cardio totals.
-- Built from gold_session_volume rather than re-aggregating bronze_sets
-- directly, since the weekly rollup is really "sum of sessions", not a
-- separate independent aggregation.

select
    date_trunc('week', session_start_time) as week_start,
    count(*)                               as num_workouts,
    sum(total_volume_lbs)                  as total_volume_lbs,
    sum(total_sets)                        as total_sets,
    sum(total_cardio_duration_seconds)     as total_cardio_duration_seconds,
    sum(total_cardio_distance_miles)       as total_cardio_distance_miles
from {{ ref('gold_session_volume') }}
group by 1
order by 1
