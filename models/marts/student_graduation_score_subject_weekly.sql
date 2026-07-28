-- =============================================================================
-- models/marts/student_graduation_score_subject_weekly.sql
--
-- Purpose : Production mart model that replicates and improves upon the
--           SSIS package's destination table
--           dbo.student_graduation_score_subject_weekly.
--
--           Improvements over the SSIS package:
--             1. Idempotent UPSERT (merge) — re-running the model never
--                creates duplicate rows.  The SSIS package performed a
--                plain INSERT with no deduplication logic.
--             2. Score validation — only rows with a valid score in [0, 100]
--                are written to the mart.  Out-of-range rows are excluded
--                (they remain visible in the staging view with
--                score_out_of_range_flag = TRUE for investigation).
--             3. Null guard — rows missing any key column (student_id,
--                school_id, state, subject, week_ending_date) are excluded.
--             4. Audit columns — load_at and load_source are carried forward
--                from the staging layer so every mart row has full provenance.
--             5. Incremental strategy — on each weekly run only new or
--                changed rows (identified by week_ending_date) are processed,
--                keeping run times short as the dataset grows.
--
-- Grain        : One row per (student_id, school_id, week_ending_date, subject)
-- Unique key   : [student_id, school_id, week_ending_date, subject]
-- Materialized : incremental (merge strategy)
-- Warehouse    : Redshift
--
-- Incremental strategy notes:
--   • unique_key is a list — dbt compiles this to a composite surrogate for
--     the MERGE ON clause on Redshift.
--   • on_schema_change = 'sync_all_columns' ensures new columns added to the
--     staging model are automatically propagated to the mart table without a
--     full-refresh.
--   • The high-watermark filter ({% if is_incremental() %}) restricts each
--     run to weeks not yet present in the mart, or to weeks that arrived
--     after the last load (handles late-arriving corrections).
-- =============================================================================

{{  config(
    materialized        = 'incremental',
    unique_key          = ['student_id', 'school_id', 'week_ending_date', 'subject'],
    incremental_strategy = 'merge',
    on_schema_change    = 'sync_all_columns',
    tags                = ['marts', 'student_scores', 'education', 'incremental']
) }}

with staged as (

    select
        student_id,
        school_id,
        state,
        subject,
        week_ending_date,
        score,
        score_out_of_range_flag,
        load_at,
        load_source
    from {{ ref('stg_student_scores_raw') }}

    -- -------------------------------------------------------------------------
    -- Quality gate 1: exclude rows with NULL key columns.
    -- These would have been silently inserted by the SSIS package.
    -- -------------------------------------------------------------------------
    where student_id       is not null
      and school_id        is not null
      and state            is not null
      and subject          is not null
      and week_ending_date is not null

    -- -------------------------------------------------------------------------
    -- Quality gate 2: exclude rows where the score failed range validation.
    -- score = NULL after validate_score means the raw value was out of [0,100].
    -- -------------------------------------------------------------------------
      and score is not null

),

{% if is_incremental() %}

-- ---------------------------------------------------------------------------
-- Incremental filter: on subsequent runs, only process rows for weeks that
-- are either:
--   (a) brand-new (week_ending_date not yet in the mart), or
--   (b) updated corrections for the most-recent week already loaded
--       (handles late-arriving score amendments from the source system).
--
-- Using >= (max_week - 7 days) rather than > max_week gives a one-week
-- overlap window to catch any corrections to the prior week's data.
-- Adjust the interval via the var 'student_scores_lookback_days' if needed.
-- ---------------------------------------------------------------------------

incremental_filtered as (

    select staged.*
    from staged
    where staged.week_ending_date >= (
        select
            dateadd(
                day,
                -{{ var('student_scores_lookback_days', 7) }},
                max(week_ending_date)
            )
        from {{ this }}
    )

),

final as (select * from incremental_filtered)

{% else %}

-- ---------------------------------------------------------------------------
-- Full-refresh / first-run: load all valid rows from staging.
-- ---------------------------------------------------------------------------

final as (select * from staged)

{% endif %}

select
    -- -----------------------------------------------------------------
    -- Natural key columns
    -- -----------------------------------------------------------------
    student_id,
    school_id,
    state,
    subject,
    week_ending_date,

    -- -----------------------------------------------------------------
    -- Measures
    -- -----------------------------------------------------------------
    score,

    -- -----------------------------------------------------------------
    -- Data-quality metadata
    -- Carried forward so analysts can see which rows were originally
    -- flagged even after the mart has filtered them out.
    -- (score_out_of_range_flag will always be FALSE here because rows
    --  with score IS NULL are excluded above, but the column is retained
    --  for schema consistency with the staging layer.)
    -- -----------------------------------------------------------------
    score_out_of_range_flag,

    -- -----------------------------------------------------------------
    -- Audit columns (absent from the original SSIS package)
    -- -----------------------------------------------------------------
    load_at,
    load_source

from final
