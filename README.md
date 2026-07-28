# student_scores dbt Project

## Overview

This dbt project automates and monitors the **national monthly student scores
data product** for LoopCapital. It replaces the legacy SSIS package
`Load_StudentScores_Weekly` with a fully version-controlled, tested, and
documented dbt transformation pipeline running on **Amazon Redshift**.

## SSIS-to-dbt Migration Context

| SSIS Component | dbt Equivalent |
|---|---|
| Flat File Connection Manager (`Src_AssessmentFeed`) | Ingestion pipeline → `sample_students` Redshift table |
| OLE DB Connection Manager (`Tgt_LoopCapitalAM`) | Redshift warehouse (profile: `loopcapital`) |
| DFT Extract Student Scores (Data Flow Task) | `stg_student_scores_weekly` (staging view) |
| `dbo.student_graduation_score_subject_weekly` | `mart_student_scores_weekly` (mart table) |
| Manual downstream report queries | `mart_student_scores_weekly` columns + score bands |

### Source Data

- **Catalog asset**: `"workspace-database"."database_128245155604"."sample_students"`
- **Source name in dbt**: `raw_assessment`
- **Table**: `sample_students`
- **Freshness**: warn after 7 days, error after 14 days

## Score Validation Gap — Fixed ✅

The original SSIS package had a **known, documented gap**:

```xml
<!-- Known real gap: no data-type or range validation on score,
     no error redirect configured on this destination -->
```

The OLE DB Destination inserted rows into
`dbo.student_graduation_score_subject_weekly` with **no range check** on score
columns. This meant values like `943` (a mis-keyed `94.3`) would silently load
and corrupt downstream reports.

**This dbt project closes that gap with defence-in-depth:**

1. **`stg_student_scores_weekly.sql` — WHERE clause filter**
   ```sql
   where math    between 0 and 100
     and english  between 0 and 100
     and science  between 0 and 100
   ```
   Out-of-range rows are excluded from the staging view entirely.

2. **`stg_student_scores_weekly.yml` — `dbt_utils.accepted_range` tests**
   ```yaml
   - dbt_utils.accepted_range:
       min_value: 0
       max_value: 100
   ```
   Applied to `math_score`, `english_score`, `science_score`, and `avg_score`.
   These tests assert that no out-of-range values survive into the model.

3. **`macros/test_score_in_valid_range.sql` — custom generic test**
   A reusable generic dbt test macro that can be applied to any score column
   in any model across the project. Documents the SSIS gap it closes.

4. **`DECIMAL(6,2)` casting**
   All integer scores are cast to `DECIMAL(6,2)` in staging, preventing
   integer overflow and enabling consistent downstream arithmetic.

## Project Structure

```
student_scores/
├── dbt_project.yml              # Project config (name: student_scores)
├── packages.yml                 # dbt-utils dependency
├── profiles.yml                 # Redshift connection template (do not commit secrets)
├── README.md
├── macros/
│   └── test_score_in_valid_range.sql   # Custom generic test (closes SSIS gap)
└── models/
    ├── staging/
    │   ├── sources.yml                    # raw_assessment source definition
    │   ├── stg_student_scores_weekly.sql  # Staging view: clean + validate
    │   └── stg_student_scores_weekly.yml  # Tests + documentation
    └── marts/
        ├── mart_student_scores_weekly.sql # Mart table: score bands + flags
        └── mart_student_scores_weekly.yml # Tests + documentation
```

## Data Lineage

```
Redshift: sample_students (raw)
    └── stg_student_scores_weekly  (view)   ← range filter + DECIMAL cast
            └── mart_student_scores_weekly (table) ← score bands + passing flags
```

## Running the Project

```bash
# Install dependencies
dbt deps

# Run all models
dbt run

# Run tests
dbt test

# Run + test in one step
dbt build

# Check source freshness
dbt source freshness

# Run only the student scores models
dbt build --select +mart_student_scores_weekly
```

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Staging as `view` | Cheap to recompute; no storage cost for the clean/filter layer |
| Mart as `table` | Fast reads for dashboards; scores data is modest volume |
| Wide format preserved | Source is wide (math/english/science columns); avoids an unpivot that would require Redshift-specific UNION ALL pattern |
| `avg_score` in staging | Computed once in staging so mart and any future models share the same definition |
| `dbt_utils.accepted_range` | More expressive than a custom test for simple min/max bounds; documents intent clearly |
| `DECIMAL(6,2)` not `FLOAT` | Avoids floating-point rounding errors in score comparisons and aggregations |
| `loaded_at` rename | Avoids collision with Redshift reserved word `timestamp` |

## Dependencies

- `dbt-labs/dbt_utils` >= 1.0.0 (for `accepted_range` test)
- Redshift dialect (no Snowflake syntax used)

## Freshness Monitoring

The `raw_assessment` source is configured with freshness checks:
- **Warn** if `sample_students` has not been updated in **7 days**
- **Error** if not updated in **14 days**

Run `dbt source freshness` to check the current state.
