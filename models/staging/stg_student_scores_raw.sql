-- =============================================================================
-- models/staging/stg_student_scores_raw.sql
--
-- Purpose : Raw extraction and light-cleaning layer for the weekly student
--           assessment CSV data.  This model is the dbt equivalent of the
--           SSIS flat-file source + OLE DB destination step, but with the
--           critical fixes the SSIS package was missing:
--
--             1. Type casting  — all columns arrive as VARCHAR from the CSV
--                                landing table; this model casts each to its
--                                correct analytical type.
--             2. Null handling — key columns (student_id, school_id, state,
--                                subject, week_ending_date) are coerced to
--                                NULL when blank/empty so that not_null tests
--                                catch bad rows explicitly.
--             3. Score validation — the validate_score macro returns NULL for
--                                any score outside [0, 100] (e.g. 943, -5).
--                                A companion boolean flag records which rows
--                                were quarantined so data-quality dashboards
--                                can surface them without losing the raw value.
--             4. Audit metadata — load_at (TIMESTAMP) and load_source
--                                (VARCHAR) are added so every row carries
--                                provenance information that was absent from
--                                the SSIS load.
--
-- Grain       : One row per raw source row (no deduplication at this layer;
--               deduplication happens in the mart via the incremental merge).
-- Materialized: view  (cheap to recompute; staging convention in this project)
-- Warehouse   : Redshift
-- =============================================================================

{{  config(
    materialized = 'view',
    tags          = ['staging', 'student_scores', 'education']
) }}

with source as (

    select * from {{ source('student_scores_src', 'student_scores_weekly') }}

),

cleaned as (

    select

        -- -----------------------------------------------------------------
        -- Identity columns — trim whitespace; treat blank strings as NULL
        -- -----------------------------------------------------------------
        nullif(trim(student_id),       '')                          as student_id,
        nullif(trim(school_id),        '')                          as school_id,

        -- State: upper-case and trim; NULL when blank
        nullif(upper(trim(state)),     '')                          as state,

        -- Subject: trim only; preserve original casing for downstream joins
        nullif(trim(subject),          '')                          as subject,

        -- -----------------------------------------------------------------
        -- Temporal — cast date string to DATE
        -- Redshift TO_DATE is NULL-safe; blank strings become NULL via nullif
        -- -----------------------------------------------------------------
        case
            when week_ending_date is null              then null
            when trim(week_ending_date) = ''           then null
            else to_date(trim(week_ending_date), 'YYYY-MM-DD')
        end                                                         as week_ending_date,

        -- -----------------------------------------------------------------
        -- Score — safe cast from VARCHAR to FLOAT8
        -- Step 1: guard against non-numeric strings (Redshift has no
        --         TRY_CAST, so we use SIMILAR TO to pre-validate)
        -- Step 2: pass the numeric value through the validate_score macro
        --         which NULLs out anything outside [0, 100]
        -- -----------------------------------------------------------------
        case
            when score is null                         then null
            when trim(score) = ''                      then null
            -- Allow optional leading minus, digits, optional decimal part
            when trim(score) not similar to '-?[0-9]+(\.[0-9]+)?'
                                                       then null
            else cast(trim(score) as float8)
        end                                                         as score_raw,

        {{ validate_score(
            "case
                when score is null                         then null
                when trim(score) = ''                      then null
                when trim(score) not similar to '-?[0-9]+(\.[0-9]+)?'
                                                           then null
                else cast(trim(score) as float8)
             end"
        ) }}                                                        as score,

        -- -----------------------------------------------------------------
        -- Score quality flag — TRUE when the raw numeric value existed but
        -- fell outside [0, 100]; FALSE / NULL otherwise.
        -- Downstream consumers can filter on this column to quarantine rows.
        -- -----------------------------------------------------------------
        case
            when score is null                         then false
            when trim(score) = ''                      then false
            when trim(score) not similar to '-?[0-9]+(\.[0-9]+)?'
                                                       then false
            when cast(trim(score) as float8) < 0
              or cast(trim(score) as float8) > 100     then true
            else false
        end                                                         as score_out_of_range_flag,

        -- -----------------------------------------------------------------
        -- Audit metadata — absent from the original SSIS package
        -- load_at  : wall-clock time this dbt run materialised the row
        -- load_source : identifies the pipeline that produced the record
        -- -----------------------------------------------------------------
        getdate()                                                   as load_at,
        'student_scores_weekly_csv'::varchar(50)                    as load_source

    from source

)

select * from cleaned
