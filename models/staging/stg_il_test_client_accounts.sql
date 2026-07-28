{{  config(
    materialized = 'view',
    tags          = ['staging', 'accounts', 'il_test']
) }}

with source as (

    select * from {{ source('il_test_client_accounts_src', 'il_test_client_accounts') }}

),

cleaned as (

    select

        -- ---------------------------------------------------------------
        -- Identity
        -- ---------------------------------------------------------------
        account_id,

        -- Strip leading/trailing whitespace from free-text name field
        trim(account_name)                                          as account_name,

        -- Normalise inconsistent casing (Municipal / INSTITUTIONAL / etc.)
        -- to consistent title-case (Municipal, Corporate, Institutional)
        initcap(lower(account_type))                               as account_type,

        -- ---------------------------------------------------------------
        -- Relationship manager — treat blank-ish sentinels as NULL
        -- ---------------------------------------------------------------
        case
            when relationship_manager is null              then null
            when trim(relationship_manager) = ''           then null
            when upper(trim(relationship_manager)) = 'TBD' then null
            else trim(relationship_manager)
        end                                                        as relationship_manager,

        -- ---------------------------------------------------------------
        -- Geography — keep as-is; invalid codes (e.g. 'ZZ') are preserved
        -- so downstream models can flag or filter them explicitly
        -- ---------------------------------------------------------------
        nullif(trim(state), '')                                    as state,

        -- ---------------------------------------------------------------
        -- AUM — safe cast: 'N/A' and NULL both become NULL
        -- Redshift does not support TRY_CAST, so we use CASE + REGEXP
        -- ---------------------------------------------------------------
        case
            when aum_usd is null                           then null
            when upper(trim(aum_usd)) = 'N/A'             then null
            -- Allow digits, optional leading minus, optional decimal point
            when aum_usd not similar to '%-?[0-9]+(\.[0-9]+)?%'
                                                           then null
            else cast(aum_usd as decimal(18, 2))
        end                                                        as aum_usd,

        -- ---------------------------------------------------------------
        -- Onboarded date — raw format MM/DD/YYYY
        -- Redshift TO_DATE handles this pattern safely; NULL stays NULL
        -- ---------------------------------------------------------------
        case
            when onboarded_date is null            then null
            when trim(onboarded_date) = ''         then null
            else to_date(trim(onboarded_date), 'MM/DD/YYYY')
        end                                                        as onboarded_date,

        -- ---------------------------------------------------------------
        -- Status & sector — kept as-is (already clean in source)
        -- ---------------------------------------------------------------
        nullif(trim(status), '')                                   as status,

        nullif(trim(sector_focus), '')                             as sector_focus,

        -- ---------------------------------------------------------------
        -- Timestamp — ISO 8601 string → TIMESTAMP
        -- ---------------------------------------------------------------
        case
            when timestamp is null         then null
            when trim(timestamp) = ''      then null
            else cast(trim(timestamp) as timestamp)
        end                                                        as loaded_at

    from source

)

select * from cleaned
