{{  config(
    materialized = 'view',
    tags          = ['staging', 'student_scores', 'assessment']
) }}

/*
  Model : stg_student_scores_weekly
  Layer : Staging
  Source: {{ source('raw_assessment', 'sample_students') }}

  Purpose
  -------
  Cleans and standardises the raw student assessment feed that was previously
  loaded by the SSIS package "Load_StudentScores_Weekly". The SSIS package had
  a known gap: no data-type or range validation was configured on the OLE DB
  Destination (see XML comment: "no data-type or range validation on score,
  no error redirect configured on this destination"). This model closes that
  gap by:

    1. Filtering rows WHERE each subject score is BETWEEN 0 AND 100, excluding
       out-of-range values such as 943 (likely a mis-keyed 94.3).
    2. Casting each integer score to DECIMAL(6,2) for consistent downstream
       arithmetic (e.g. averaging across subjects).
    3. Parsing week_start_date from VARCHAR to DATE.
    4. Casting the source timestamp string to TIMESTAMP and renaming to
       loaded_at (avoids collision with the Redshift reserved word).

  Schema note
  -----------
  The source table uses WIDE format (one column per subject: math, english,
  science). This staging model preserves that wide format and adds a
  computed avg_score column. The mart model further enriches with score bands.

  SSIS migration notes
  --------------------
  - SSIS source  : Flat File Source reading student_scores_weekly.csv
  - SSIS dest    : OLE DB Destination → dbo.student_graduation_score_subject_weekly
  - dbt equivalent: this view replaces the transformation logic; the ingestion
    pipeline that populates sample_students replaces the SSIS flat-file read.
*/

with source as (

    select * from {{ source('raw_assessment', 'sample_students') }}

),

cleaned as (

    select

        -- -----------------------------------------------------------------
        -- Identity
        -- -----------------------------------------------------------------
        student_id,

        -- Strip whitespace from free-text name field
        trim(student_name)                                          as student_name,

        -- classroom acts as the school/section grouping key
        classroom                                                   as classroom_id,

        -- -----------------------------------------------------------------
        -- Week anchor date
        -- Raw source stores as VARCHAR; cast to DATE.
        -- Maps to SSIS output column week_ending_date (DBDATE).
        -- -----------------------------------------------------------------
        case
            when week_start_date is null         then null
            when trim(week_start_date) = ''      then null
            else cast(trim(week_start_date) as date)
        end                                                         as week_start_date,

        -- -----------------------------------------------------------------
        -- Subject scores — SSIS GAP FIX
        -- The original SSIS OLE DB Destination had no range validation and
        -- no error redirect. Values like 943 (should be 94.3) would silently
        -- load. Here we:
        --   a) Filter out-of-range rows in the WHERE clause below.
        --   b) Cast to DECIMAL(6,2) for consistent downstream arithmetic.
        -- -----------------------------------------------------------------
        cast(math    as decimal(6, 2))                              as math_score,
        cast(english as decimal(6, 2))                              as english_score,
        cast(science as decimal(6, 2))                              as science_score,

        -- Convenience: average across the three subjects
        cast(
            (math + english + science) / 3.0
        as decimal(6, 2))                                           as avg_score,

        -- -----------------------------------------------------------------
        -- Loaded timestamp
        -- Renamed from 'timestamp' to avoid Redshift reserved-word collision.
        -- -----------------------------------------------------------------
        case
            when timestamp is null         then null
            when trim(timestamp) = ''      then null
            else cast(trim(timestamp) as timestamp)
        end                                                         as loaded_at,

        -- Audit column: when this dbt model last processed the row
        current_timestamp                                           as dbt_loaded_at

    from source

    -- -----------------------------------------------------------------------
    -- SSIS GAP FIX: Range validation on all subject scores.
    -- The SSIS package had no score range check; this WHERE clause rejects
    -- any row where ANY subject score falls outside the valid 0–100 range.
    -- Such rows are excluded from the staging view and will surface as
    -- missing records in downstream reconciliation.
    -- -----------------------------------------------------------------------
    where math    between 0 and 100
      and english  between 0 and 100
      and science  between 0 and 100

)

select * from cleaned
