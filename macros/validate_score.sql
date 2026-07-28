-- =============================================================================
-- macros/validate_score.sql
--
-- Purpose : Reusable score-range validator that fixes a critical gap in the
--           original SSIS package: scores were accepted without any range
--           check, allowing values like 943 (should be 94.3) or negatives
--           to silently corrupt the dataset.
--
-- Usage   :
--   {{ validate_score('score_column') }}
--     → Returns the score unchanged when it is within [0, 100], or NULL
--       when it is out of range.
--
--   {{ validate_score('score_column', min_score=0, max_score=100) }}
--     → Same as above with explicit bounds (useful for overriding per-subject
--       scales in future models).
--
-- The companion flag column `score_out_of_range_flag` (BOOLEAN) is emitted
-- by the staging model that calls this macro so that data-quality dashboards
-- can surface bad rows without discarding them from the audit trail.
--
-- Warehouse : Redshift (no TRY_CAST; uses CASE + IS NULL guards)
-- =============================================================================

{% macro validate_score(score_col, min_score=0, max_score=100) %}

    case
        -- NULL input → propagate NULL (handled separately by not_null tests)
        when {{ score_col }} is null                                    then null
        -- Out-of-range → return NULL so the row is quarantined downstream
        when {{ score_col }} < {{ min_score }}
          or {{ score_col }} > {{ max_score }}                          then null
        -- Valid range → pass through unchanged
        else {{ score_col }}
    end

{% endmacro %}
