{{  config(
    materialized = 'table',
    tags          = ['marts', 'student_scores', 'assessment', 'national-monthly']
) }}

/*
  Model : mart_student_scores_weekly
  Layer : Marts
  Source: {{ ref('stg_student_scores_weekly') }}

  Purpose
  -------
  Final analytical table for the national monthly student scores data product.
  Builds on the cleaned staging view and adds:

    - score_band_*  : Letter-grade band (A/B/C/D/F) for each subject score
                      and the overall average, using standard US grading thresholds.
    - is_passing_*  : Boolean flag (score >= 60) per subject and overall.
    - overall_band  : Grade band derived from avg_score.
    - is_overall_passing: TRUE when avg_score >= 60.

  This model is the primary consumer-facing table for dashboards and reports
  tracking student performance trends at the national level.

  SSIS migration context
  ----------------------
  Replaces the downstream reporting queries that read from
  dbo.student_graduation_score_subject_weekly in LoopCapitalAM SQL Server.
  Score band logic was previously applied ad-hoc in report queries; it is
  now codified and tested here.
*/

with staged as (

    select * from {{ ref('stg_student_scores_weekly') }}

),

enriched as (

    select

        -- -----------------------------------------------------------------
        -- Pass-through from staging
        -- -----------------------------------------------------------------
        student_id,
        student_name,
        classroom_id,
        week_start_date,
        math_score,
        english_score,
        science_score,
        avg_score,
        loaded_at,
        dbt_loaded_at,

        -- -----------------------------------------------------------------
        -- Score bands — standard US letter-grade thresholds
        -- A: 90–100 | B: 80–89 | C: 70–79 | D: 60–69 | F: 0–59
        -- -----------------------------------------------------------------
        case
            when math_score >= 90 then 'A'
            when math_score >= 80 then 'B'
            when math_score >= 70 then 'C'
            when math_score >= 60 then 'D'
            else 'F'
        end                                                         as math_score_band,

        case
            when english_score >= 90 then 'A'
            when english_score >= 80 then 'B'
            when english_score >= 70 then 'C'
            when english_score >= 60 then 'D'
            else 'F'
        end                                                         as english_score_band,

        case
            when science_score >= 90 then 'A'
            when science_score >= 80 then 'B'
            when science_score >= 70 then 'C'
            when science_score >= 60 then 'D'
            else 'F'
        end                                                         as science_score_band,

        case
            when avg_score >= 90 then 'A'
            when avg_score >= 80 then 'B'
            when avg_score >= 70 then 'C'
            when avg_score >= 60 then 'D'
            else 'F'
        end                                                         as overall_score_band,

        -- -----------------------------------------------------------------
        -- Passing flags (score >= 60 is the passing threshold)
        -- -----------------------------------------------------------------
        (math_score    >= 60)                                       as is_math_passing,
        (english_score >= 60)                                       as is_english_passing,
        (science_score >= 60)                                       as is_science_passing,
        (avg_score     >= 60)                                       as is_overall_passing

    from staged

)

select * from enriched
