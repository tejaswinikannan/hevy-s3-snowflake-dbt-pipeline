-- One row per exercise: the heaviest single-set weight ever lifted, and
-- when it was first achieved. Restricted to strength sets (weight_lbs is
-- not null) -- cardio exercises have no meaningful "weight PR".

select
    exercise_title,
    weight_lbs as pr_weight_lbs,
    reps       as pr_reps,
    end_time   as achieved_at
from {{ ref('bronze_sets') }}
where weight_lbs is not null
qualify row_number() over (
    partition by exercise_title
    order by weight_lbs desc, end_time asc
) = 1
