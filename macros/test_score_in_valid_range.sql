{#
  Macro  : test_score_in_valid_range
  Type   : Generic dbt test
  Author : BrightBot (SSIS → dbt migration)

  Purpose
  -------
  Validates that a numeric score column contains only values in the
  closed interval [0, 100].

  This macro directly closes the known gap in the original SSIS package
  "Load_StudentScores_Weekly" (DTS:DTSID {D4E5F607-0010-4E5F-9004-000000000010}):

    <!-- Known real gap: no data-type or range validation on score,
         no error redirect configured on this destination -->

  In the SSIS pipeline, the OLE DB Destination inserted rows into
  dbo.student_graduation_score_subject_weekly with no CHECK CONSTRAINT
  on the score column, meaning values like 943 (a mis-keyed 94.3) would
  silently load and corrupt downstream reports.

  This generic test, combined with the WHERE score BETWEEN 0 AND 100
  filter in stg_student_scores_weekly, provides defence-in-depth:
    - The WHERE clause excludes bad rows from the staging view.
    - This test asserts that no out-of-range values survive into the model.

  Usage in schema.yml
  -------------------
  columns:
    - name: math_score
      tests:
        - test_score_in_valid_range

  Or with custom bounds (optional overrides):
    - name: math_score
      tests:
        - test_score_in_valid_range:
            min_value: 0
            max_value: 100
#}

{% macro test_score_in_valid_range(model, column_name, min_value=0, max_value=100) %}

    /*
      Returns the count of rows where column_name is outside [min_value, max_value].
      A passing test returns 0 rows.
    */
    select
        count(*) as failing_rows
    from {{ model }}
    where {{ column_name }} < {{ min_value }}
       or {{ column_name }} > {{ max_value }}
       or {{ column_name }} is null

{% endmacro %}
