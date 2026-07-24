{{ config(
    materialized = 'view',
    tags         = ['staging', 'client_accounts']
) }}

with source as (

    select * from {{ source('database_128245155604', 'il_test_client_accounts') }}

),

renamed as (

    select

        account_id::varchar                                     as account_id,
        trim(client_name)                                       as client_name,
        trim(client_type)                                       as client_type,
        trim(segment)                                           as segment,
        trim(email)                                             as email,
        trim(phone)                                             as phone,
        trim(account_status)                                    as account_status,
        trim(account_type)                                      as account_type,
        trim(industry)                                          as industry,
        trim(region)                                            as region,
        trim(country)                                           as country,
        aum_usd::decimal(18, 2)                                 as aum_usd,
        revenue_usd::decimal(18, 2)                             as revenue_usd,
        ltv::decimal(18, 2)                                     as ltv,
        acquisition_cost::decimal(18, 2)                        as acquisition_cost,

        case
            when acquisition_date   = '' or acquisition_date   is null then null
            else acquisition_date::date
        end                                                     as acquisition_date,

        case
            when first_purchase_date = '' or first_purchase_date is null then null
            else first_purchase_date::date
        end                                                     as first_purchase_date,

        case
            when last_activity_date  = '' or last_activity_date  is null then null
            else last_activity_date::date
        end                                                     as last_activity_date,

        risk_score::decimal(10, 4)                              as risk_score,
        trim(source_system)                                     as source_system,

        case
            when timestamp = '' or timestamp is null then null
            else timestamp::timestamp
        end                                                     as loaded_at

    from source

)

select * from renamed
