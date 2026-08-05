-- One row per workout session. start_time uniquely identifies a session
-- (every set in one workout shares the same start_time/end_time).
--
-- Strength and cardio metrics are aggregated separately rather than
-- combined into one "volume" number, since a session can mix both (e.g.
-- weightlifting followed by cycling) -- SUM() ignores NULLs automatically,
-- so a pure-cardio session just yields NULL total_volume_lbs rather than
-- an incorrect 0 or an error.

select
    start_time as session_start_time,
    end_time   as session_end_time,
    title,
    count(*)                                  as total_sets,
    sum(weight_lbs * reps)                    as total_volume_lbs,
    sum(reps)                                 as total_reps,
    sum(duration_seconds)                     as total_cardio_duration_seconds,
    sum(distance_miles)                       as total_cardio_distance_miles
from {{ ref('bronze_sets') }}
group by 1, 2, 3
