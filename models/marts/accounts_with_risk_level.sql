{{{
  config(
    materialized = 'table',
    tags         = ['risk', 'accounts', 'RISK-POL-014']
  )
}}}

/*
  Model : accounts_with_risk_level
  Policy: RISK-POL-014

  Risk classification logic:
    high-risk  — outstanding_balance > 50,000 AND days_delinquent > 60
    watch-list — ONLY ONE of the two conditions is met
    standard   — neither condition is met
*/

SELECT
    account_id,
    customer_name,
    outstanding_balance,
    days_delinquent,
    timestamp,
    CASE
        WHEN outstanding_balance > 50000 AND days_delinquent > 60 THEN 'high-risk'
        WHEN outstanding_balance > 50000 OR  days_delinquent > 60 THEN 'watch-list'
        ELSE 'standard'
    END AS risk_level
FROM {{ source('database_128245155604', 'accounts_unstructured_test') }}