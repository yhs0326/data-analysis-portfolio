/* ============================================================
   01. RAW 스키마 확인
   ============================================================ */

CREATE SCHEMA IF NOT EXISTS raw;

/* ============================================================
   02. Campaign·Coupon RAW 테이블 생성
   ============================================================ */

CREATE TABLE IF NOT EXISTS raw.campaign_desc (
    campaign       TEXT,
    description    TEXT,
    start_day      TEXT,
    end_day        TEXT,
    source_row_id  BIGINT GENERATED ALWAYS AS IDENTITY,
    source_file    TEXT DEFAULT 'campaign_desc.csv',
    load_batch_id  TEXT DEFAULT current_setting('raw.load_batch_id', true),
    loaded_at      TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

TRUNCATE TABLE raw.campaign_desc RESTART IDENTITY;
SELECT campaign, description, start_day, end_day FROM raw.campaign_desc LIMIT 10;

DROP TABLE raw.campaign_table;

CREATE TABLE raw.campaign_table (
    description    TEXT,
    household_key  TEXT,
    campaign       TEXT,
    source_row_id  BIGINT GENERATED ALWAYS AS IDENTITY,
    source_file    TEXT DEFAULT 'campaign_table.csv',
    load_batch_id  TEXT DEFAULT current_setting('raw.load_batch_id', true),
    loaded_at      TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS raw.coupon (
    coupon_upc     TEXT,
    product_id     TEXT,
    campaign       TEXT,
    source_row_id  BIGINT GENERATED ALWAYS AS IDENTITY,
    source_file    TEXT DEFAULT 'coupon.csv',
    load_batch_id  TEXT DEFAULT current_setting('raw.load_batch_id', true),
    loaded_at      TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS raw.coupon_redempt (
    household_key  TEXT,
    day            TEXT,
    coupon_upc     TEXT,
    campaign       TEXT,
    source_row_id  BIGINT GENERATED ALWAYS AS IDENTITY,
    source_file    TEXT DEFAULT 'coupon_redempt.csv',
    load_batch_id  TEXT DEFAULT current_setting('raw.load_batch_id', true),
    loaded_at      TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

/* ============================================================
   03. CSV 적재
   psql \copy 별도 실행
   ============================================================ */

/* CSV 적재는 psql \copy로 별도 실행 */

/* ============================================================
   04. RAW 적재 결과 검증
   ============================================================ */

-- 테이블별 적재 행 수와 적재 메타데이터 현황을 한 번의 스캔으로 확인한다.
SELECT
    'raw.campaign_desc'::TEXT AS table_name,
    30::BIGINT AS expected_csv_row_count,
    COUNT(*)::BIGINT AS loaded_row_count,
    CASE WHEN COUNT(*) = 30 THEN 'PASS' ELSE 'FAIL' END AS status,
    MIN(source_file) AS source_file,
    COUNT(DISTINCT source_file)::BIGINT AS source_file_count,
    MIN(load_batch_id) AS load_batch_id,
    COUNT(DISTINCT load_batch_id)::BIGINT AS load_batch_id_count,
    MIN(loaded_at) AS first_loaded_at,
    MAX(loaded_at) AS last_loaded_at
FROM raw.campaign_desc

UNION ALL

SELECT
    'raw.campaign_table',
    7208::BIGINT,
    COUNT(*)::BIGINT,
    CASE WHEN COUNT(*) = 7208 THEN 'PASS' ELSE 'FAIL' END,
    MIN(source_file),
    COUNT(DISTINCT source_file)::BIGINT,
    MIN(load_batch_id),
    COUNT(DISTINCT load_batch_id)::BIGINT,
    MIN(loaded_at),
    MAX(loaded_at)
FROM raw.campaign_table

UNION ALL

SELECT
    'raw.coupon',
    124548::BIGINT,
    COUNT(*)::BIGINT,
    CASE WHEN COUNT(*) = 124548 THEN 'PASS' ELSE 'FAIL' END,
    MIN(source_file),
    COUNT(DISTINCT source_file)::BIGINT,
    MIN(load_batch_id),
    COUNT(DISTINCT load_batch_id)::BIGINT,
    MIN(loaded_at),
    MAX(loaded_at)
FROM raw.coupon

UNION ALL

SELECT
    'raw.coupon_redempt',
    2318::BIGINT,
    COUNT(*)::BIGINT,
    CASE WHEN COUNT(*) = 2318 THEN 'PASS' ELSE 'FAIL' END,
    MIN(source_file),
    COUNT(DISTINCT source_file)::BIGINT,
    MIN(load_batch_id),
    COUNT(DISTINCT load_batch_id)::BIGINT,
    MIN(loaded_at),
    MAX(loaded_at)
FROM raw.coupon_redempt;

-- campaign_desc 핵심 컬럼과 적재 메타데이터를 한 번의 스캔으로 확인한다.
SELECT
    COUNT(*) FILTER (WHERE campaign IS NULL)::BIGINT AS campaign_null_count,
    COUNT(*) FILTER (WHERE campaign = '')::BIGINT AS campaign_empty_count,
    COUNT(*) FILTER (WHERE description IS NULL)::BIGINT AS description_null_count,
    COUNT(*) FILTER (WHERE description = '')::BIGINT AS description_empty_count,
    COUNT(*) FILTER (WHERE start_day IS NULL)::BIGINT AS start_day_null_count,
    COUNT(*) FILTER (WHERE start_day = '')::BIGINT AS start_day_empty_count,
    COUNT(*) FILTER (WHERE end_day IS NULL)::BIGINT AS end_day_null_count,
    COUNT(*) FILTER (WHERE end_day = '')::BIGINT AS end_day_empty_count,
    COUNT(*) FILTER (WHERE source_file IS NULL)::BIGINT AS source_file_null_count,
    COUNT(*) FILTER (WHERE load_batch_id IS NULL)::BIGINT AS load_batch_id_null_count,
    COUNT(*) FILTER (WHERE loaded_at IS NULL)::BIGINT AS loaded_at_null_count,
    (COUNT(source_row_id) - COUNT(DISTINCT source_row_id))::BIGINT AS source_row_id_duplicate_count
FROM raw.campaign_desc;

-- campaign_table 핵심 컬럼과 적재 메타데이터를 한 번의 스캔으로 확인한다.
SELECT
    COUNT(*) FILTER (WHERE description IS NULL)::BIGINT AS description_null_count,
    COUNT(*) FILTER (WHERE description = '')::BIGINT AS description_empty_count,
    COUNT(*) FILTER (WHERE household_key IS NULL)::BIGINT AS household_key_null_count,
    COUNT(*) FILTER (WHERE household_key = '')::BIGINT AS household_key_empty_count,
    COUNT(*) FILTER (WHERE campaign IS NULL)::BIGINT AS campaign_null_count,
    COUNT(*) FILTER (WHERE campaign = '')::BIGINT AS campaign_empty_count,
    COUNT(*) FILTER (WHERE source_file IS NULL)::BIGINT AS source_file_null_count,
    COUNT(*) FILTER (WHERE load_batch_id IS NULL)::BIGINT AS load_batch_id_null_count,
    COUNT(*) FILTER (WHERE loaded_at IS NULL)::BIGINT AS loaded_at_null_count,
    (COUNT(source_row_id) - COUNT(DISTINCT source_row_id))::BIGINT AS source_row_id_duplicate_count
FROM raw.campaign_table;

-- coupon 핵심 컬럼과 적재 메타데이터를 한 번의 스캔으로 확인한다.
SELECT
    COUNT(*) FILTER (WHERE coupon_upc IS NULL)::BIGINT AS coupon_upc_null_count,
    COUNT(*) FILTER (WHERE coupon_upc = '')::BIGINT AS coupon_upc_empty_count,
    COUNT(*) FILTER (WHERE product_id IS NULL)::BIGINT AS product_id_null_count,
    COUNT(*) FILTER (WHERE product_id = '')::BIGINT AS product_id_empty_count,
    COUNT(*) FILTER (WHERE campaign IS NULL)::BIGINT AS campaign_null_count,
    COUNT(*) FILTER (WHERE campaign = '')::BIGINT AS campaign_empty_count,
    COUNT(*) FILTER (WHERE source_file IS NULL)::BIGINT AS source_file_null_count,
    COUNT(*) FILTER (WHERE load_batch_id IS NULL)::BIGINT AS load_batch_id_null_count,
    COUNT(*) FILTER (WHERE loaded_at IS NULL)::BIGINT AS loaded_at_null_count,
    (COUNT(source_row_id) - COUNT(DISTINCT source_row_id))::BIGINT AS source_row_id_duplicate_count
FROM raw.coupon;

-- coupon_redempt 핵심 컬럼과 적재 메타데이터를 한 번의 스캔으로 확인한다.
SELECT
    COUNT(*) FILTER (WHERE household_key IS NULL)::BIGINT AS household_key_null_count,
    COUNT(*) FILTER (WHERE household_key = '')::BIGINT AS household_key_empty_count,
    COUNT(*) FILTER (WHERE day IS NULL)::BIGINT AS day_null_count,
    COUNT(*) FILTER (WHERE day = '')::BIGINT AS day_empty_count,
    COUNT(*) FILTER (WHERE coupon_upc IS NULL)::BIGINT AS coupon_upc_null_count,
    COUNT(*) FILTER (WHERE coupon_upc = '')::BIGINT AS coupon_upc_empty_count,
    COUNT(*) FILTER (WHERE campaign IS NULL)::BIGINT AS campaign_null_count,
    COUNT(*) FILTER (WHERE campaign = '')::BIGINT AS campaign_empty_count,
    COUNT(*) FILTER (WHERE source_file IS NULL)::BIGINT AS source_file_null_count,
    COUNT(*) FILTER (WHERE load_batch_id IS NULL)::BIGINT AS load_batch_id_null_count,
    COUNT(*) FILTER (WHERE loaded_at IS NULL)::BIGINT AS loaded_at_null_count,
    (COUNT(source_row_id) - COUNT(DISTINCT source_row_id))::BIGINT AS source_row_id_duplicate_count
FROM raw.coupon_redempt;

-- 원천 컬럼 기준 완전 중복 추가 행이 Python 프로파일링 결과와 같은지 확인한다.
WITH duplicate_validation AS (
    SELECT
        'raw.campaign_desc'::TEXT AS table_name,
        0::BIGINT AS expected_duplicate_extra_rows,
        COALESCE(SUM(row_count - 1), 0)::BIGINT AS duplicate_extra_rows
    FROM (
        SELECT COUNT(*)::BIGINT AS row_count
        FROM raw.campaign_desc
        GROUP BY campaign, description, start_day, end_day
        HAVING COUNT(*) > 1
    ) AS duplicates

    UNION ALL

    SELECT
        'raw.campaign_table',
        0::BIGINT,
        COALESCE(SUM(row_count - 1), 0)::BIGINT
    FROM (
        SELECT COUNT(*)::BIGINT AS row_count
        FROM raw.campaign_table
        GROUP BY description, household_key, campaign
        HAVING COUNT(*) > 1
    ) AS duplicates

    UNION ALL

    SELECT
        'raw.coupon',
        5164::BIGINT,
        COALESCE(SUM(row_count - 1), 0)::BIGINT
    FROM (
        SELECT COUNT(*)::BIGINT AS row_count
        FROM raw.coupon
        GROUP BY coupon_upc, product_id, campaign
        HAVING COUNT(*) > 1
    ) AS duplicates

    UNION ALL

    SELECT
        'raw.coupon_redempt',
        0::BIGINT,
        COALESCE(SUM(row_count - 1), 0)::BIGINT
    FROM (
        SELECT COUNT(*)::BIGINT AS row_count
        FROM raw.coupon_redempt
        GROUP BY household_key, day, coupon_upc, campaign
        HAVING COUNT(*) > 1
    ) AS duplicates
)
SELECT
    table_name,
    expected_duplicate_extra_rows,
    duplicate_extra_rows,
    CASE
        WHEN duplicate_extra_rows = expected_duplicate_extra_rows THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM duplicate_validation;

/* ============================================================
   05. Campaign·Coupon BASE 타입 변환 검증
   ============================================================ */

-- RAW TEXT 값의 숫자형 변환 가능 여부를 확인한다.
WITH conversion_checks AS (
    SELECT
        'raw.campaign_desc'::TEXT AS table_name,
        value.column_name,
        COUNT(*) FILTER (
            WHERE CASE
                WHEN BTRIM(value.raw_value) ~ '^[+-]?[0-9]+$'
                    THEN BTRIM(value.raw_value)::NUMERIC NOT BETWEEN value.min_value AND value.max_value
                ELSE TRUE
            END
        )::BIGINT AS conversion_failure_count
    FROM raw.campaign_desc
    CROSS JOIN LATERAL (VALUES
        ('campaign', campaign, -2147483648::NUMERIC, 2147483647::NUMERIC),
        ('start_day', start_day, -2147483648::NUMERIC, 2147483647::NUMERIC),
        ('end_day', end_day, -2147483648::NUMERIC, 2147483647::NUMERIC)
    ) AS value(column_name, raw_value, min_value, max_value)
    GROUP BY value.column_name

    UNION ALL

    SELECT
        'raw.campaign_table',
        value.column_name,
        COUNT(*) FILTER (
            WHERE CASE
                WHEN BTRIM(value.raw_value) ~ '^[+-]?[0-9]+$'
                    THEN BTRIM(value.raw_value)::NUMERIC NOT BETWEEN value.min_value AND value.max_value
                ELSE TRUE
            END
        )::BIGINT
    FROM raw.campaign_table
    CROSS JOIN LATERAL (VALUES
        ('household_key', household_key, -9223372036854775808::NUMERIC, 9223372036854775807::NUMERIC),
        ('campaign', campaign, -2147483648::NUMERIC, 2147483647::NUMERIC)
    ) AS value(column_name, raw_value, min_value, max_value)
    GROUP BY value.column_name

    UNION ALL

    SELECT
        'raw.coupon',
        value.column_name,
        COUNT(*) FILTER (
            WHERE CASE
                WHEN BTRIM(value.raw_value) ~ '^[+-]?[0-9]+$'
                    THEN BTRIM(value.raw_value)::NUMERIC NOT BETWEEN value.min_value AND value.max_value
                ELSE TRUE
            END
        )::BIGINT
    FROM raw.coupon
    CROSS JOIN LATERAL (VALUES
        ('coupon_upc', coupon_upc, -9223372036854775808::NUMERIC, 9223372036854775807::NUMERIC),
        ('product_id', product_id, -9223372036854775808::NUMERIC, 9223372036854775807::NUMERIC),
        ('campaign', campaign, -2147483648::NUMERIC, 2147483647::NUMERIC)
    ) AS value(column_name, raw_value, min_value, max_value)
    GROUP BY value.column_name

    UNION ALL

    SELECT
        'raw.coupon_redempt',
        value.column_name,
        COUNT(*) FILTER (
            WHERE CASE
                WHEN BTRIM(value.raw_value) ~ '^[+-]?[0-9]+$'
                    THEN BTRIM(value.raw_value)::NUMERIC NOT BETWEEN value.min_value AND value.max_value
                ELSE TRUE
            END
        )::BIGINT
    FROM raw.coupon_redempt
    CROSS JOIN LATERAL (VALUES
        ('household_key', household_key, -9223372036854775808::NUMERIC, 9223372036854775807::NUMERIC),
        ('day', day, -2147483648::NUMERIC, 2147483647::NUMERIC),
        ('coupon_upc', coupon_upc, -9223372036854775808::NUMERIC, 9223372036854775807::NUMERIC),
        ('campaign', campaign, -2147483648::NUMERIC, 2147483647::NUMERIC)
    ) AS value(column_name, raw_value, min_value, max_value)
    GROUP BY value.column_name
)
SELECT
    table_name,
    column_name,
    conversion_failure_count,
    CASE WHEN conversion_failure_count = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM conversion_checks;


SELECT campaign, description, start_day, end_day FROM raw.campaign_desc LIMIT 10;
/* ============================================================
   06. Campaign·Coupon BASE 테이블 생성
   ============================================================ */

BEGIN;

CREATE SCHEMA IF NOT EXISTS base;

DROP TABLE IF EXISTS base.coupon_redempt;
DROP TABLE IF EXISTS base.coupon;
DROP TABLE IF EXISTS base.campaign_table;
DROP TABLE IF EXISTS base.campaign_desc;

CREATE TABLE base.campaign_desc (
    campaign       INTEGER PRIMARY KEY,
    description    TEXT,
    start_day      INTEGER,
    end_day        INTEGER,
    source_row_id  BIGINT UNIQUE,
    source_file    TEXT,
    load_batch_id  TEXT,
    loaded_at      TIMESTAMPTZ,
    base_loaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE base.campaign_table (
    description    TEXT,
    household_key  BIGINT,
    campaign       INTEGER,
    source_row_id  BIGINT UNIQUE,
    source_file    TEXT,
    load_batch_id  TEXT,
    loaded_at      TIMESTAMPTZ,
    base_loaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE base.coupon (
    coupon_upc     BIGINT,
    product_id     BIGINT,
    campaign       INTEGER,
    source_row_id  BIGINT UNIQUE,
    source_file    TEXT,
    load_batch_id  TEXT,
    loaded_at      TIMESTAMPTZ,
    base_loaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (campaign, coupon_upc, product_id)
);

CREATE TABLE base.coupon_redempt (
    household_key  BIGINT,
    day            INTEGER,
    coupon_upc     BIGINT,
    campaign       INTEGER,
    source_row_id  BIGINT UNIQUE,
    source_file    TEXT,
    load_batch_id  TEXT,
    loaded_at      TIMESTAMPTZ,
    base_loaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO base.campaign_desc (
    campaign, description, start_day, end_day,
    source_row_id, source_file, load_batch_id, loaded_at
)
SELECT
    BTRIM(campaign)::INTEGER,
    description,
    BTRIM(start_day)::INTEGER,
    BTRIM(end_day)::INTEGER,
    source_row_id,
    source_file,
    load_batch_id,
    loaded_at
FROM raw.campaign_desc;

INSERT INTO base.campaign_table (
    description, household_key, campaign,
    source_row_id, source_file, load_batch_id, loaded_at
)
SELECT
    description,
    BTRIM(household_key)::BIGINT,
    BTRIM(campaign)::INTEGER,
    source_row_id,
    source_file,
    load_batch_id,
    loaded_at
FROM raw.campaign_table;

-- coupon 원본의 완전 중복행만 제거하고 Coupon-Product 다중 관계는 유지한다.
INSERT INTO base.coupon (
    coupon_upc, product_id, campaign,
    source_row_id, source_file, load_batch_id, loaded_at
)
SELECT DISTINCT ON (BTRIM(campaign)::INTEGER, BTRIM(coupon_upc)::BIGINT, BTRIM(product_id)::BIGINT)
    BTRIM(coupon_upc)::BIGINT,
    BTRIM(product_id)::BIGINT,
    BTRIM(campaign)::INTEGER,
    source_row_id,
    source_file,
    load_batch_id,
    loaded_at
FROM raw.coupon
ORDER BY
    BTRIM(campaign)::INTEGER,
    BTRIM(coupon_upc)::BIGINT,
    BTRIM(product_id)::BIGINT,
    source_row_id;

INSERT INTO base.coupon_redempt (
    household_key, day, coupon_upc, campaign,
    source_row_id, source_file, load_batch_id, loaded_at
)
SELECT
    BTRIM(household_key)::BIGINT,
    BTRIM(day)::INTEGER,
    BTRIM(coupon_upc)::BIGINT,
    BTRIM(campaign)::INTEGER,
    source_row_id,
    source_file,
    load_batch_id,
    loaded_at
FROM raw.coupon_redempt;

CREATE INDEX idx_base_campaign_table_campaign
    ON base.campaign_table (campaign);
CREATE INDEX idx_base_campaign_table_household
    ON base.campaign_table (household_key);
CREATE INDEX idx_base_coupon_product
    ON base.coupon (product_id);
CREATE INDEX idx_base_coupon_redempt_campaign_coupon
    ON base.coupon_redempt (campaign, coupon_upc);
CREATE INDEX idx_base_coupon_redempt_household
    ON base.coupon_redempt (household_key);

COMMIT;

ANALYZE base.campaign_desc;
ANALYZE base.campaign_table;
ANALYZE base.coupon;
ANALYZE base.coupon_redempt;

/* ============================================================
   07. BASE 기본 품질 검증
   ============================================================ */

SELECT
    table_name,
    expected_row_count,
    actual_row_count,
    CASE WHEN actual_row_count = expected_row_count THEN 'PASS' ELSE 'FAIL' END AS status
FROM (
    SELECT 'base.campaign_desc'::TEXT AS table_name, 30::BIGINT AS expected_row_count,
           COUNT(*)::BIGINT AS actual_row_count
    FROM base.campaign_desc
    UNION ALL
    SELECT 'base.campaign_table', 7208::BIGINT, COUNT(*)::BIGINT
    FROM base.campaign_table
    UNION ALL
    SELECT 'base.coupon', 119384::BIGINT, COUNT(*)::BIGINT
    FROM base.coupon
    UNION ALL
    SELECT 'base.coupon_redempt', 2318::BIGINT, COUNT(*)::BIGINT
    FROM base.coupon_redempt
) AS row_counts;

-- RAW와 BASE 행 수를 비교해 coupon 완전 중복행 5,164건만 제거되었는지 확인한다.
WITH coupon_row_counts AS (
    SELECT
        (SELECT COUNT(*)::BIGINT FROM raw.coupon) AS raw_coupon_row_count,
        (SELECT COUNT(*)::BIGINT FROM base.coupon) AS base_coupon_row_count
)
SELECT
    raw_coupon_row_count,
    base_coupon_row_count,
    raw_coupon_row_count - base_coupon_row_count AS removed_duplicate_rows,
    5164::BIGINT AS expected_removed_duplicate_rows,
    CASE
        WHEN raw_coupon_row_count - base_coupon_row_count = 5164 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM coupon_row_counts;

/* ============================================================
   08. BASE ID·기간 무결성 검증
   ============================================================ */

-- Campaign ID가 campaign_desc에 모두 매핑되는지 확인한다.
SELECT
    source_table,
    unmatched_campaign_count,
    CASE WHEN unmatched_campaign_count = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM (
    SELECT 'base.campaign_table'::TEXT AS source_table,
           COUNT(DISTINCT source.campaign)::BIGINT AS unmatched_campaign_count
    FROM base.campaign_table AS source
    WHERE NOT EXISTS (
        SELECT 1 FROM base.campaign_desc AS target
        WHERE target.campaign = source.campaign
    )
    UNION ALL
    SELECT 'base.coupon', COUNT(DISTINCT source.campaign)::BIGINT
    FROM base.coupon AS source
    WHERE NOT EXISTS (
        SELECT 1 FROM base.campaign_desc AS target
        WHERE target.campaign = source.campaign
    )
    UNION ALL
    SELECT 'base.coupon_redempt', COUNT(DISTINCT source.campaign)::BIGINT
    FROM base.coupon_redempt AS source
    WHERE NOT EXISTS (
        SELECT 1 FROM base.campaign_desc AS target
        WHERE target.campaign = source.campaign
    )
) AS campaign_integrity;

-- 쿠폰 상환의 Campaign-Coupon 조합이 coupon 데이터에 매핑되는지 확인한다.
SELECT
    COUNT(*)::BIGINT AS unmatched_redemption_campaign_coupon_rows,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM base.coupon_redempt AS redemption
WHERE NOT EXISTS (
    SELECT 1
    FROM base.coupon AS coupon
    WHERE coupon.campaign = redemption.campaign
      AND coupon.coupon_upc = redemption.coupon_upc
);

-- coupon의 Product ID가 기존 base.product에 모두 매핑되는지 확인한다.
SELECT
    COUNT(DISTINCT coupon.product_id)::BIGINT AS unmatched_product_id_count,
    CASE WHEN COUNT(DISTINCT coupon.product_id) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM base.coupon AS coupon
WHERE NOT EXISTS (
    SELECT 1
    FROM base.product AS product
    WHERE product.product_id = coupon.product_id
);

-- 캠페인·상환 고객이 기존 거래데이터의 Household Key에 매핑되는지 확인한다.
WITH transaction_households AS MATERIALIZED (
    SELECT DISTINCT household_key
    FROM base.transaction_data
), source_households AS (
    SELECT 'base.campaign_table'::TEXT AS source_table, household_key
    FROM base.campaign_table
    UNION ALL
    SELECT 'base.coupon_redempt', household_key
    FROM base.coupon_redempt
)
SELECT
    source.source_table,
    COUNT(DISTINCT source.household_key) FILTER (
        WHERE target.household_key IS NULL
    )::BIGINT AS unmatched_household_count,
    CASE
        WHEN COUNT(DISTINCT source.household_key) FILTER (
            WHERE target.household_key IS NULL
        ) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM source_households AS source
LEFT JOIN transaction_households AS target
    ON target.household_key = source.household_key
GROUP BY source.source_table;

-- 쿠폰 상환일이 해당 캠페인의 시작일~종료일 범위에 있는지 확인한다.
SELECT
    COUNT(*)::BIGINT AS total_redemptions,
    COUNT(*) FILTER (
        WHERE campaign.campaign IS NOT NULL
          AND redemption.day BETWEEN campaign.start_day AND campaign.end_day
    )::BIGINT AS inside_campaign_period,
    COUNT(*) FILTER (
        WHERE campaign.campaign IS NOT NULL
          AND redemption.day < campaign.start_day
    )::BIGINT AS before_campaign_start,
    COUNT(*) FILTER (
        WHERE campaign.campaign IS NOT NULL
          AND redemption.day > campaign.end_day
    )::BIGINT AS after_campaign_end,
    COUNT(*) FILTER (
        WHERE campaign.campaign IS NULL
           OR redemption.day IS NULL
           OR campaign.start_day IS NULL
           OR campaign.end_day IS NULL
    )::BIGINT AS period_unavailable
FROM base.coupon_redempt AS redemption
LEFT JOIN base.campaign_desc AS campaign
    ON campaign.campaign = redemption.campaign;

-- 동일 Campaign의 description이 두 원천 데이터에서 일치하는지 확인한다.
SELECT
    COUNT(*) FILTER (
        WHERE campaign.campaign IS NULL
           OR campaign_table.description IS DISTINCT FROM campaign.description
    )::BIGINT AS mismatched_description_rows,
    COUNT(DISTINCT campaign_table.campaign) FILTER (
        WHERE campaign.campaign IS NULL
           OR campaign_table.description IS DISTINCT FROM campaign.description
    )::BIGINT AS mismatched_campaign_count,
    CASE
        WHEN COUNT(*) FILTER (
            WHERE campaign.campaign IS NULL
               OR campaign_table.description IS DISTINCT FROM campaign.description
        ) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM base.campaign_table AS campaign_table
LEFT JOIN base.campaign_desc AS campaign
    ON campaign.campaign = campaign_table.campaign;

/* ============================================================
   09. MART 스키마 및 재실행 준비
   ============================================================ */

BEGIN;

CREATE SCHEMA IF NOT EXISTS mart;

DROP TABLE IF EXISTS mart.household_campaign_response;
DROP TABLE IF EXISTS mart.fact_coupon_redemption;
DROP TABLE IF EXISTS mart.bridge_coupon_product;
DROP TABLE IF EXISTS mart.fact_campaign_household;
DROP TABLE IF EXISTS mart.dim_campaign;

/* ============================================================
   10. Campaign Dimension 생성
   ============================================================ */

CREATE TABLE mart.dim_campaign AS
WITH data_bounds AS (
    SELECT MIN(day)::INTEGER AS data_min_day,
           MAX(day)::INTEGER AS data_max_day
    FROM base.transaction_data
)
SELECT
    campaign.campaign,
    campaign.description,
    campaign.start_day,
    campaign.end_day,
    campaign.end_day - campaign.start_day + 1 AS campaign_duration,
    campaign.start_day - 182 AS pre_26w_start_day,
    campaign.start_day - 56 AS pre_8w_start_day,
    campaign.start_day - 56 AS previous_4w_start_day,
    campaign.start_day - 28 AS recent_4w_start_day,
    campaign.end_day + 28 AS post_4w_end_day,
    campaign.start_day - 182 >= bounds.data_min_day AS has_pre_26w_coverage,
    campaign.start_day - 56 >= bounds.data_min_day AS has_pre_8w_coverage,
    campaign.start_day >= bounds.data_min_day
        AND campaign.end_day <= bounds.data_max_day AS has_campaign_period_coverage,
    campaign.end_day + 28 <= bounds.data_max_day AS has_post_4w_coverage,
    campaign.start_day - 182 >= bounds.data_min_day
        AND campaign.end_day + 28 <= bounds.data_max_day AS has_full_behavior_coverage
FROM base.campaign_desc AS campaign
CROSS JOIN data_bounds AS bounds;

ALTER TABLE mart.dim_campaign
    ADD CONSTRAINT pk_dim_campaign PRIMARY KEY (campaign);

/* ============================================================
   11. Campaign Household Fact 생성
   ============================================================ */

-- 캠페인 대상 여부만 보존하며 고객별 Coupon 노출은 추정하지 않는다.
CREATE TABLE mart.fact_campaign_household AS
SELECT
    recipient.household_key,
    recipient.campaign,
    campaign.description,
    campaign.start_day,
    campaign.end_day,
    campaign.campaign_duration
FROM base.campaign_table AS recipient
JOIN mart.dim_campaign AS campaign
    ON campaign.campaign = recipient.campaign;

ALTER TABLE mart.fact_campaign_household
    ADD CONSTRAINT pk_fact_campaign_household
    PRIMARY KEY (household_key, campaign);

CREATE INDEX idx_fact_campaign_household_campaign
    ON mart.fact_campaign_household (campaign);

/* ============================================================
   12. Coupon-Product Bridge 생성
   ============================================================ */

-- Coupon-Product 다중 관계를 campaign × coupon × product Grain으로 유지한다.
CREATE TABLE mart.bridge_coupon_product AS
SELECT
    coupon.campaign,
    coupon.coupon_upc,
    coupon.product_id,
    product.department,
    product.brand,
    product.commodity_desc,
    product.sub_commodity_desc
FROM base.coupon AS coupon
JOIN base.product AS product
    ON product.product_id = coupon.product_id;

ALTER TABLE mart.bridge_coupon_product
    ADD CONSTRAINT pk_bridge_coupon_product
    PRIMARY KEY (campaign, coupon_upc, product_id);

CREATE INDEX idx_bridge_coupon_product_product
    ON mart.bridge_coupon_product (product_id);

/* ============================================================
   13. Coupon Redemption Fact 생성
   ============================================================ */

-- Coupon-Product Bridge를 결합하지 않고 원본 쿠폰 상환 Grain을 유지한다.
CREATE TABLE mart.fact_coupon_redemption AS
SELECT
    redemption.household_key,
    redemption.campaign,
    redemption.coupon_upc,
    redemption.day AS redemption_day,
    redemption.day - campaign.start_day AS days_from_campaign_start
FROM base.coupon_redempt AS redemption
JOIN mart.dim_campaign AS campaign
    ON campaign.campaign = redemption.campaign;

ALTER TABLE mart.fact_coupon_redemption
    ADD CONSTRAINT pk_fact_coupon_redemption
    PRIMARY KEY (household_key, campaign, coupon_upc, redemption_day);

CREATE INDEX idx_fact_coupon_redemption_campaign_household
    ON mart.fact_coupon_redemption (campaign, household_key);
CREATE INDEX idx_fact_coupon_redemption_campaign_coupon
    ON mart.fact_coupon_redemption (campaign, coupon_upc);

/* ============================================================
   14. Household × Campaign Response Mart 생성
   ============================================================ */

-- 유효 구매 Basket을 전체 필요기간에 한 번 연결한 뒤 기간별 지표를 함께 계산한다.
CREATE TABLE mart.household_campaign_response AS
WITH recipients AS MATERIALIZED (
    SELECT
        recipient.household_key,
        recipient.campaign,
        recipient.description,
        recipient.start_day,
        recipient.end_day,
        recipient.campaign_duration,
        campaign.pre_26w_start_day,
        campaign.pre_8w_start_day,
        campaign.previous_4w_start_day,
        campaign.recent_4w_start_day,
        campaign.post_4w_end_day,
        campaign.has_pre_26w_coverage,
        campaign.has_pre_8w_coverage,
        campaign.has_campaign_period_coverage,
        campaign.has_post_4w_coverage,
        campaign.has_full_behavior_coverage
    FROM mart.fact_campaign_household AS recipient
    JOIN mart.dim_campaign AS campaign
        ON campaign.campaign = recipient.campaign
),
basket_behavior AS (
    SELECT
        recipient.household_key,
        recipient.campaign,
        COALESCE(SUM(basket.basket_sales) FILTER (
            WHERE basket.day BETWEEN recipient.pre_26w_start_day AND recipient.start_day - 1
        ), 0::NUMERIC) AS pre_26w_sales,
        COUNT(basket.basket_id) FILTER (
            WHERE basket.day BETWEEN recipient.pre_26w_start_day AND recipient.start_day - 1
        )::BIGINT AS pre_26w_basket_count,
        COUNT(DISTINCT basket.day) FILTER (
            WHERE basket.day BETWEEN recipient.pre_26w_start_day AND recipient.start_day - 1
        )::BIGINT AS pre_26w_purchase_day_count,
        COUNT(DISTINCT basket.week_no) FILTER (
            WHERE basket.day BETWEEN recipient.pre_26w_start_day AND recipient.start_day - 1
        )::BIGINT AS pre_26w_purchase_week_count,
        COALESCE(SUM(basket.discount_amount) FILTER (
            WHERE basket.day BETWEEN recipient.pre_26w_start_day AND recipient.start_day - 1
        ), 0::NUMERIC) AS pre_26w_discount_amount,
        COUNT(basket.basket_id) FILTER (
            WHERE basket.day BETWEEN recipient.pre_26w_start_day AND recipient.start_day - 1
              AND basket.discount_amount > 0
        )::BIGINT AS pre_26w_discounted_basket_count,
        COALESCE(SUM(basket.basket_sales) FILTER (
            WHERE basket.day BETWEEN recipient.pre_8w_start_day AND recipient.start_day - 1
        ), 0::NUMERIC) AS pre_8w_sales,
        COUNT(basket.basket_id) FILTER (
            WHERE basket.day BETWEEN recipient.pre_8w_start_day AND recipient.start_day - 1
        )::BIGINT AS pre_8w_basket_count,
        COUNT(DISTINCT basket.day) FILTER (
            WHERE basket.day BETWEEN recipient.pre_8w_start_day AND recipient.start_day - 1
        )::BIGINT AS pre_8w_purchase_day_count,
        COUNT(DISTINCT basket.week_no) FILTER (
            WHERE basket.day BETWEEN recipient.pre_8w_start_day AND recipient.start_day - 1
        )::BIGINT AS pre_8w_purchase_week_count,
        COALESCE(SUM(basket.basket_sales) FILTER (
            WHERE basket.day BETWEEN recipient.previous_4w_start_day AND recipient.start_day - 29
        ), 0::NUMERIC) AS previous_4w_sales,
        COUNT(basket.basket_id) FILTER (
            WHERE basket.day BETWEEN recipient.previous_4w_start_day AND recipient.start_day - 29
        )::BIGINT AS previous_4w_basket_count,
        COALESCE(SUM(basket.basket_sales) FILTER (
            WHERE basket.day BETWEEN recipient.recent_4w_start_day AND recipient.start_day - 1
        ), 0::NUMERIC) AS recent_4w_sales,
        COUNT(basket.basket_id) FILTER (
            WHERE basket.day BETWEEN recipient.recent_4w_start_day AND recipient.start_day - 1
        )::BIGINT AS recent_4w_basket_count,
        COALESCE(SUM(basket.basket_sales) FILTER (
            WHERE basket.day BETWEEN recipient.start_day AND recipient.end_day
        ), 0::NUMERIC) AS campaign_sales,
        COUNT(basket.basket_id) FILTER (
            WHERE basket.day BETWEEN recipient.start_day AND recipient.end_day
        )::BIGINT AS campaign_basket_count,
        COUNT(DISTINCT basket.day) FILTER (
            WHERE basket.day BETWEEN recipient.start_day AND recipient.end_day
        )::BIGINT AS campaign_purchase_day_count,
        COALESCE(SUM(basket.basket_sales) FILTER (
            WHERE basket.day BETWEEN recipient.end_day + 1 AND recipient.post_4w_end_day
        ), 0::NUMERIC) AS post_4w_sales,
        COUNT(basket.basket_id) FILTER (
            WHERE basket.day BETWEEN recipient.end_day + 1 AND recipient.post_4w_end_day
        )::BIGINT AS post_4w_basket_count,
        COUNT(DISTINCT basket.day) FILTER (
            WHERE basket.day BETWEEN recipient.end_day + 1 AND recipient.post_4w_end_day
        )::BIGINT AS post_4w_purchase_day_count
    FROM recipients AS recipient
    LEFT JOIN mart.fact_basket AS basket
        ON basket.household_key = recipient.household_key
       AND basket.is_valid_purchase_basket
       AND basket.day BETWEEN recipient.pre_26w_start_day AND recipient.post_4w_end_day
    GROUP BY recipient.household_key, recipient.campaign
),
-- 할인값의 음수 부호를 양의 할인액으로 바꾸며 PRE26 범위만 한 번 집계한다.
discount_behavior AS (
    SELECT
        recipient.household_key,
        recipient.campaign,
        COALESCE(SUM(GREATEST(-COALESCE(transaction_data.retail_disc, 0), 0)), 0::NUMERIC)
            AS pre_26w_retail_discount_amount,
        COALESCE(SUM(
            GREATEST(-COALESCE(transaction_data.coupon_disc, 0), 0)
            + GREATEST(-COALESCE(transaction_data.coupon_match_disc, 0), 0)
        ), 0::NUMERIC) AS pre_26w_coupon_discount_amount
    FROM recipients AS recipient
    LEFT JOIN base.transaction_data AS transaction_data
        ON transaction_data.household_key = recipient.household_key
       AND transaction_data.day BETWEEN recipient.pre_26w_start_day AND recipient.start_day - 1
    GROUP BY recipient.household_key, recipient.campaign
),
redemption_behavior AS (
    SELECT
        redemption.household_key,
        redemption.campaign,
        COUNT(*)::BIGINT AS redemption_count,
        COUNT(DISTINCT redemption.coupon_upc)::BIGINT AS distinct_redeemed_coupon_count,
        MIN(redemption.redemption_day)::INTEGER AS first_redemption_day,
        MAX(redemption.redemption_day)::INTEGER AS last_redemption_day,
        MIN(redemption.days_from_campaign_start)::INTEGER AS first_redemption_days_from_start
    FROM mart.fact_coupon_redemption AS redemption
    GROUP BY redemption.household_key, redemption.campaign
)
SELECT
    recipient.household_key,
    recipient.campaign,
    recipient.description,
    recipient.start_day,
    recipient.end_day,
    recipient.campaign_duration,
    recipient.has_pre_26w_coverage,
    recipient.has_pre_8w_coverage,
    recipient.has_campaign_period_coverage,
    recipient.has_post_4w_coverage,
    recipient.has_full_behavior_coverage,
    behavior.pre_26w_sales,
    behavior.pre_26w_basket_count,
    behavior.pre_26w_purchase_day_count,
    behavior.pre_26w_purchase_week_count,
    COALESCE(
        behavior.pre_26w_sales / NULLIF(behavior.pre_26w_basket_count, 0),
        0::NUMERIC
    ) AS pre_26w_average_basket_value,
    behavior.pre_26w_discount_amount,
    behavior.pre_26w_discounted_basket_count,
    COALESCE(
        behavior.pre_26w_discounted_basket_count::NUMERIC
            / NULLIF(behavior.pre_26w_basket_count, 0),
        0::NUMERIC
    ) AS pre_26w_discounted_basket_rate,
    discount.pre_26w_retail_discount_amount,
    discount.pre_26w_coupon_discount_amount,
    behavior.pre_8w_sales,
    behavior.pre_8w_basket_count,
    behavior.pre_8w_purchase_day_count,
    behavior.pre_8w_purchase_week_count,
    COALESCE(
        behavior.pre_8w_sales / NULLIF(behavior.pre_8w_basket_count, 0),
        0::NUMERIC
    ) AS pre_8w_average_basket_value,
    behavior.previous_4w_sales,
    behavior.previous_4w_basket_count,
    behavior.recent_4w_sales,
    behavior.recent_4w_basket_count,
    behavior.campaign_sales,
    behavior.campaign_basket_count,
    behavior.campaign_purchase_day_count,
    COALESCE(
        behavior.campaign_sales / NULLIF(behavior.campaign_basket_count, 0),
        0::NUMERIC
    ) AS campaign_average_basket_value,
    behavior.post_4w_sales,
    behavior.post_4w_basket_count,
    behavior.post_4w_purchase_day_count,
    COALESCE(
        behavior.post_4w_sales / NULLIF(behavior.post_4w_basket_count, 0),
        0::NUMERIC
    ) AS post_4w_average_basket_value,
    COALESCE(redemption.redemption_count, 0)::BIGINT > 0 AS redeemed_flag,
    COALESCE(redemption.redemption_count, 0)::BIGINT AS redemption_count,
    COALESCE(redemption.distinct_redeemed_coupon_count, 0)::BIGINT
        AS distinct_redeemed_coupon_count,
    redemption.first_redemption_day,
    redemption.last_redemption_day,
    redemption.first_redemption_days_from_start
FROM recipients AS recipient
JOIN basket_behavior AS behavior
    ON behavior.household_key = recipient.household_key
   AND behavior.campaign = recipient.campaign
JOIN discount_behavior AS discount
    ON discount.household_key = recipient.household_key
   AND discount.campaign = recipient.campaign
LEFT JOIN redemption_behavior AS redemption
    ON redemption.household_key = recipient.household_key
   AND redemption.campaign = recipient.campaign;

ALTER TABLE mart.household_campaign_response
    ADD CONSTRAINT pk_household_campaign_response
    PRIMARY KEY (household_key, campaign);

CREATE INDEX idx_household_campaign_response_campaign
    ON mart.household_campaign_response (campaign);

COMMIT;

ANALYZE mart.dim_campaign;
ANALYZE mart.fact_campaign_household;
ANALYZE mart.bridge_coupon_product;
ANALYZE mart.fact_coupon_redemption;
ANALYZE mart.household_campaign_response;

/* ============================================================
   15. MART 품질 검증
   ============================================================ */

SELECT
    table_name,
    expected_row_count,
    actual_row_count,
    CASE WHEN actual_row_count = expected_row_count THEN 'PASS' ELSE 'FAIL' END AS status
FROM (
    SELECT 'mart.dim_campaign'::TEXT AS table_name, 30::BIGINT AS expected_row_count,
           COUNT(*)::BIGINT AS actual_row_count
    FROM mart.dim_campaign
    UNION ALL
    SELECT 'mart.fact_campaign_household', 7208::BIGINT, COUNT(*)::BIGINT
    FROM mart.fact_campaign_household
    UNION ALL
    SELECT 'mart.bridge_coupon_product', 119384::BIGINT, COUNT(*)::BIGINT
    FROM mart.bridge_coupon_product
    UNION ALL
    SELECT 'mart.fact_coupon_redemption', 2318::BIGINT, COUNT(*)::BIGINT
    FROM mart.fact_coupon_redemption
    UNION ALL
    SELECT 'mart.household_campaign_response', 7208::BIGINT, COUNT(*)::BIGINT
    FROM mart.household_campaign_response
) AS row_counts;

-- Product 결합 전후 행 수가 같아 Coupon-Product Grain이 보존되는지 확인한다.
WITH product_join_counts AS (
    SELECT
        (SELECT COUNT(*)::BIGINT FROM base.coupon) AS coupon_row_count,
        (SELECT COUNT(*)::BIGINT FROM mart.bridge_coupon_product) AS bridge_row_count
)
SELECT
    coupon_row_count,
    bridge_row_count,
    CASE WHEN coupon_row_count = bridge_row_count THEN 'PASS' ELSE 'FAIL' END AS status
FROM product_join_counts;

-- 직접 Bridge 결합 시 상환행이 상품 수만큼 증가하는 구조를 정보성으로 진단한다.
WITH join_counts AS (
    SELECT
        (SELECT COUNT(*)::BIGINT FROM mart.fact_coupon_redemption) AS redemption_row_count,
        COUNT(*)::BIGINT AS direct_bridge_join_row_count
    FROM mart.fact_coupon_redemption AS redemption
    JOIN mart.bridge_coupon_product AS bridge
        ON bridge.campaign = redemption.campaign
       AND bridge.coupon_upc = redemption.coupon_upc
)
SELECT
    redemption_row_count,
    direct_bridge_join_row_count,
    direct_bridge_join_row_count - redemption_row_count AS amplified_row_count,
    direct_bridge_join_row_count::NUMERIC / NULLIF(redemption_row_count, 0) AS join_multiplier,
    CASE
        WHEN direct_bridge_join_row_count > redemption_row_count THEN 'EXPECTED_1_TO_N'
        ELSE 'INFO_NO_AMPLIFICATION'
    END AS status
FROM join_counts;

-- 모든 쿠폰 상환이 실제 Campaign Recipient에 매핑되는지 확인한다.
SELECT
    COUNT(*)::BIGINT AS total_redemption_rows,
    COUNT(*) FILTER (WHERE recipient.household_key IS NOT NULL)::BIGINT
        AS mapped_recipient_redemption_rows,
    COUNT(*) FILTER (WHERE recipient.household_key IS NULL)::BIGINT
        AS unmatched_recipient_redemption_rows,
    CASE
        WHEN COUNT(*) FILTER (WHERE recipient.household_key IS NULL) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM mart.fact_coupon_redemption AS redemption
LEFT JOIN mart.fact_campaign_household AS recipient
    ON recipient.household_key = redemption.household_key
   AND recipient.campaign = redemption.campaign;

-- Response의 상환 합계와 Flag가 Coupon Redemption Fact와 일치하는지 확인한다.
WITH response_check AS (
    SELECT
        (SELECT COUNT(*)::BIGINT
         FROM mart.fact_coupon_redemption AS redemption
         WHERE EXISTS (
             SELECT 1
             FROM mart.fact_campaign_household AS recipient
             WHERE recipient.household_key = redemption.household_key
               AND recipient.campaign = redemption.campaign
         )) AS mapped_redemption_count,
        COALESCE(SUM(response.redemption_count), 0)::BIGINT AS response_redemption_count,
        COUNT(*) FILTER (
            WHERE response.redeemed_flag IS DISTINCT FROM (response.redemption_count > 0)
        )::BIGINT AS inconsistent_response_flag_rows
    FROM mart.household_campaign_response AS response
)
SELECT
    mapped_redemption_count,
    response_redemption_count,
    inconsistent_response_flag_rows,
    CASE
        WHEN mapped_redemption_count = response_redemption_count
         AND inconsistent_response_flag_rows = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM response_check;

-- 쿠폰 상환일이 해당 캠페인 기간 안에 있는지 재확인한다.
SELECT
    COUNT(*)::BIGINT AS total_redemptions,
    COUNT(*) FILTER (
        WHERE redemption.redemption_day BETWEEN campaign.start_day AND campaign.end_day
    )::BIGINT AS inside_campaign_period,
    COUNT(*) FILTER (
        WHERE redemption.redemption_day < campaign.start_day
    )::BIGINT AS before_campaign_start,
    COUNT(*) FILTER (
        WHERE redemption.redemption_day > campaign.end_day
    )::BIGINT AS after_campaign_end,
    COUNT(*) FILTER (
        WHERE redemption.redemption_day IS NULL
           OR campaign.start_day IS NULL
           OR campaign.end_day IS NULL
    )::BIGINT AS period_unavailable,
    CASE
        WHEN COUNT(*) FILTER (
            WHERE redemption.redemption_day BETWEEN campaign.start_day AND campaign.end_day
        ) = COUNT(*) THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM mart.fact_coupon_redemption AS redemption
JOIN mart.dim_campaign AS campaign
    ON campaign.campaign = redemption.campaign;

-- Coverage Flag는 캠페인 제외 조건이 아니라 분석 가능기간 정보로 보고한다.
SELECT
    COUNT(*) FILTER (WHERE has_pre_26w_coverage)::BIGINT AS pre_26w_covered_campaigns,
    COUNT(*) FILTER (WHERE has_pre_8w_coverage)::BIGINT AS pre_8w_covered_campaigns,
    COUNT(*) FILTER (WHERE has_campaign_period_coverage)::BIGINT AS period_covered_campaigns,
    COUNT(*) FILTER (WHERE has_post_4w_coverage)::BIGINT AS post_4w_covered_campaigns,
    COUNT(*) FILTER (WHERE has_full_behavior_coverage)::BIGINT AS fully_covered_campaigns,
    'INFO'::TEXT AS status
FROM mart.dim_campaign;

SELECT
    campaign,
    description,
    start_day,
    end_day,
    has_pre_26w_coverage,
    has_pre_8w_coverage,
    has_campaign_period_coverage,
    has_post_4w_coverage,
    has_full_behavior_coverage
FROM mart.dim_campaign
WHERE NOT has_campaign_period_coverage
   OR NOT has_post_4w_coverage
ORDER BY start_day;

/* ============================================================
   16. Campaign Response 분석 대상 확정
   ============================================================ */

-- 캠페인 기간 전체가 관찰된 Campaign만 Response 분석에 포함한다.
SELECT
    COUNT(*)::BIGINT AS total_campaign_count,
    COUNT(*) FILTER (WHERE has_campaign_period_coverage)::BIGINT AS covered_campaign_count,
    COUNT(*) FILTER (WHERE NOT has_campaign_period_coverage)::BIGINT AS excluded_campaign_count,
    'INFO'::TEXT AS status
FROM mart.dim_campaign;

SELECT
    campaign,
    description,
    start_day,
    end_day,
    has_campaign_period_coverage
FROM mart.dim_campaign
WHERE NOT has_campaign_period_coverage;

/* ============================================================
   17. Campaign별 Response KPI 생성
   ============================================================ */

BEGIN;

DROP TABLE IF EXISTS mart.campaign_response_summary;

-- 반응률은 대상 고객 수와 실제 쿠폰 상환 고객 수를 함께 보존한다.
CREATE TABLE mart.campaign_response_summary AS
WITH campaign_totals AS (
    SELECT
        response.campaign,
        response.description,
        response.start_day,
        response.end_day,
        response.campaign_duration,
        COUNT(*)::BIGINT AS recipient_count,
        COUNT(*) FILTER (WHERE response.redeemed_flag)::BIGINT AS redeemer_count,
        COALESCE(SUM(response.redemption_count), 0)::BIGINT AS total_redemption_count,
        AVG(response.first_redemption_days_from_start) FILTER (
            WHERE response.redeemed_flag
        ) AS average_first_redemption_days,
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY response.first_redemption_days_from_start
        ) FILTER (WHERE response.redeemed_flag) AS median_first_redemption_days
    FROM mart.household_campaign_response AS response
    WHERE response.has_campaign_period_coverage
    GROUP BY
        response.campaign,
        response.description,
        response.start_day,
        response.end_day,
        response.campaign_duration
)
SELECT
    campaign,
    description,
    start_day,
    end_day,
    campaign_duration,
    recipient_count,
    redeemer_count,
    redeemer_count::NUMERIC / NULLIF(recipient_count, 0) AS redemption_rate,
    total_redemption_count,
    total_redemption_count::NUMERIC / NULLIF(redeemer_count, 0) AS redemption_intensity,
    average_first_redemption_days,
    median_first_redemption_days
FROM campaign_totals;

ALTER TABLE mart.campaign_response_summary
    ADD CONSTRAINT pk_campaign_response_summary PRIMARY KEY (campaign);

COMMIT;

ANALYZE mart.campaign_response_summary;

SELECT
    campaign,
    description,
    recipient_count,
    redeemer_count,
    redemption_rate,
    redemption_intensity,
    average_first_redemption_days,
    median_first_redemption_days,
    campaign_duration
FROM mart.campaign_response_summary
ORDER BY redemption_rate DESC NULLS LAST, recipient_count DESC, campaign;

/* ============================================================
   18. Campaign Type별 Response 비교
   ============================================================ */

-- 고객 전체 기준 pooled rate와 Campaign별 rate 분포를 구분한다.
SELECT
    description,
    COUNT(*)::BIGINT AS campaign_count,
    SUM(recipient_count)::BIGINT AS total_recipient_count,
    SUM(redeemer_count)::BIGINT AS total_redeemer_count,
    SUM(redeemer_count)::NUMERIC / NULLIF(SUM(recipient_count), 0)
        AS pooled_redemption_rate,
    AVG(redemption_rate) AS average_campaign_redemption_rate,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY redemption_rate)
        AS median_campaign_redemption_rate,
    MIN(recipient_count)::BIGINT AS minimum_recipient_count,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY recipient_count)
        AS median_recipient_count,
    MAX(recipient_count)::BIGINT AS maximum_recipient_count,
    SUM(total_redemption_count)::BIGINT AS total_redemption_count,
    SUM(total_redemption_count)::NUMERIC / NULLIF(SUM(redeemer_count), 0)
        AS pooled_redemption_intensity,
    SUM(COUNT(*)) OVER ()::BIGINT AS analyzed_campaign_count,
    CASE WHEN SUM(COUNT(*)) OVER () = 29 THEN 'PASS' ELSE 'FAIL' END
        AS campaign_count_status
FROM mart.campaign_response_summary
GROUP BY description;

/* ============================================================
   19. 이전 Campaign 수신 경험별 Response 비교
   ============================================================ */

-- 현재 Campaign 시작 전에 종료된 Campaign 수신 경험만 사용한다.
WITH current_recipients AS MATERIALIZED (
    SELECT
        response.household_key,
        response.campaign,
        response.start_day,
        response.redeemed_flag,
        response.redemption_count
    FROM mart.household_campaign_response AS response
    WHERE response.has_campaign_period_coverage
),
prior_exposure AS (
    SELECT
        current.household_key,
        current.campaign,
        current.redeemed_flag,
        current.redemption_count,
        COUNT(prior_campaign.campaign)::BIGINT AS prior_completed_campaign_count
    FROM current_recipients AS current
    LEFT JOIN mart.fact_campaign_household AS prior_recipient
        ON prior_recipient.household_key = current.household_key
       AND prior_recipient.campaign <> current.campaign
    LEFT JOIN mart.dim_campaign AS prior_campaign
        ON prior_campaign.campaign = prior_recipient.campaign
       AND prior_campaign.end_day < current.start_day
    GROUP BY
        current.household_key,
        current.campaign,
        current.redeemed_flag,
        current.redemption_count
),
group_totals AS (
    SELECT
        CASE
            WHEN prior_completed_campaign_count = 0 THEN 'NO_PRIOR_COMPLETED_CAMPAIGN'
            ELSE 'PRIOR_COMPLETED_CAMPAIGN'
        END AS prior_exposure_group,
        COUNT(*)::BIGINT AS recipient_count,
        COUNT(*) FILTER (WHERE redeemed_flag)::BIGINT AS redeemer_count,
        COALESCE(SUM(redemption_count), 0)::BIGINT AS total_redemption_count
    FROM prior_exposure
    GROUP BY 1
)
SELECT
    prior_exposure_group,
    recipient_count,
    redeemer_count,
    redeemer_count::NUMERIC / NULLIF(recipient_count, 0) AS redemption_rate,
    total_redemption_count,
    total_redemption_count::NUMERIC / NULLIF(redeemer_count, 0)
        AS redemption_intensity
FROM group_totals;

/* ============================================================
   20. Campaign Response 품질 검증
   ============================================================ */

SELECT
    29::BIGINT AS expected_campaign_count,
    COUNT(*)::BIGINT AS actual_campaign_count,
    CASE WHEN COUNT(*) = 29 THEN 'PASS' ELSE 'FAIL' END AS status
FROM mart.campaign_response_summary;

-- Coverage가 부족한 Campaign이 Summary에 포함되지 않았는지 확인한다.
SELECT
    COUNT(*) FILTER (WHERE NOT campaign.has_campaign_period_coverage)::BIGINT
        AS uncovered_campaign_count,
    CASE
        WHEN COUNT(*) FILTER (WHERE NOT campaign.has_campaign_period_coverage) = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM mart.campaign_response_summary AS summary
JOIN mart.dim_campaign AS campaign
    ON campaign.campaign = summary.campaign;

-- Recipient·Redeemer·Redemption 합계를 분석 대상 원천과 대사한다.
WITH summary_totals AS (
    SELECT
        SUM(recipient_count)::BIGINT AS summary_recipient_count,
        SUM(redeemer_count)::BIGINT AS summary_redeemer_count,
        SUM(total_redemption_count)::BIGINT AS summary_redemption_count
    FROM mart.campaign_response_summary
),
response_totals AS (
    SELECT
        COUNT(*)::BIGINT AS response_recipient_count,
        COUNT(*) FILTER (WHERE redeemed_flag)::BIGINT AS response_redeemer_count
    FROM mart.household_campaign_response
    WHERE has_campaign_period_coverage
),
redemption_totals AS (
    SELECT COUNT(*)::BIGINT AS covered_redemption_count
    FROM mart.fact_coupon_redemption AS redemption
    JOIN mart.dim_campaign AS campaign
        ON campaign.campaign = redemption.campaign
    WHERE campaign.has_campaign_period_coverage
)
SELECT
    summary_recipient_count,
    response_recipient_count,
    summary_redeemer_count,
    response_redeemer_count,
    summary_redemption_count,
    covered_redemption_count,
    CASE
        WHEN summary_recipient_count = response_recipient_count
         AND summary_redeemer_count = response_redeemer_count
         AND summary_redemption_count = covered_redemption_count THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM summary_totals
CROSS JOIN response_totals
CROSS JOIN redemption_totals;

-- Rate·Intensity·Timing 계산의 논리 범위를 한 번의 스캔으로 확인한다.
SELECT
    COUNT(*) FILTER (
        WHERE redemption_rate IS NULL
           OR redemption_rate < 0
           OR redemption_rate > 1
           OR redeemer_count > recipient_count
    )::BIGINT AS rate_issue_count,
    COUNT(*) FILTER (
        WHERE (redeemer_count > 0 AND (redemption_intensity IS NULL OR redemption_intensity <= 0))
           OR (redeemer_count = 0 AND redemption_intensity IS NOT NULL)
    )::BIGINT AS intensity_issue_count,
    COUNT(*) FILTER (
        WHERE (redeemer_count > 0 AND (
                  average_first_redemption_days IS NULL
               OR median_first_redemption_days IS NULL
               OR average_first_redemption_days < 0
               OR median_first_redemption_days < 0
               OR average_first_redemption_days > campaign_duration - 1
               OR median_first_redemption_days > campaign_duration - 1
              ))
           OR (redeemer_count = 0 AND (
                  average_first_redemption_days IS NOT NULL
               OR median_first_redemption_days IS NOT NULL
              ))
    )::BIGINT AS timing_issue_count,
    CASE
        WHEN COUNT(*) FILTER (
            WHERE redemption_rate IS NULL
               OR redemption_rate < 0
               OR redemption_rate > 1
               OR redeemer_count > recipient_count
               OR (redeemer_count > 0 AND (redemption_intensity IS NULL OR redemption_intensity <= 0))
               OR (redeemer_count = 0 AND redemption_intensity IS NOT NULL)
               OR (redeemer_count > 0 AND (
                      average_first_redemption_days IS NULL
                   OR median_first_redemption_days IS NULL
                   OR average_first_redemption_days < 0
                   OR median_first_redemption_days < 0
                   OR average_first_redemption_days > campaign_duration - 1
                   OR median_first_redemption_days > campaign_duration - 1
                  ))
               OR (redeemer_count = 0 AND (
                      average_first_redemption_days IS NOT NULL
                   OR median_first_redemption_days IS NOT NULL
                  ))
        ) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM mart.campaign_response_summary;

/* ============================================================
   21. Redeemer·Non-Redeemer 분석 대상 확정
   ============================================================ */

-- Campaign 기간 전체가 관찰된 가구×Campaign 관측치만 비교한다.
SELECT
    CASE WHEN redeemed_flag THEN 'REDEEMER' ELSE 'NON_REDEEMER' END AS response_group,
    COUNT(*)::BIGINT AS observation_count,
    COUNT(DISTINCT household_key)::BIGINT AS distinct_household_count,
    COUNT(DISTINCT campaign)::BIGINT AS campaign_count
FROM mart.household_campaign_response
WHERE has_campaign_period_coverage
GROUP BY 1;

/* ============================================================
   22. Campaign 이전 고객 특성 Feature 생성
   ============================================================ */

BEGIN;

DROP TABLE IF EXISTS mart.campaign_customer_response_features;

CREATE TABLE mart.campaign_customer_response_features AS
WITH eligible_recipients AS MATERIALIZED (
    SELECT
        response.household_key,
        response.campaign,
        response.description,
        response.start_day,
        response.end_day,
        response.redeemed_flag,
        response.pre_26w_sales,
        response.pre_26w_basket_count,
        response.pre_26w_purchase_day_count,
        response.pre_26w_purchase_week_count,
        response.pre_26w_average_basket_value,
        response.pre_26w_discount_amount,
        response.pre_26w_discounted_basket_count,
        response.pre_26w_discounted_basket_rate,
        response.pre_26w_retail_discount_amount,
        response.pre_26w_coupon_discount_amount,
        response.pre_8w_sales,
        response.pre_8w_basket_count,
        response.pre_8w_purchase_day_count,
        response.pre_8w_purchase_week_count,
        response.pre_8w_average_basket_value,
        response.previous_4w_sales,
        response.previous_4w_basket_count,
        response.recent_4w_sales,
        response.recent_4w_basket_count
    FROM mart.household_campaign_response AS response
    WHERE response.has_campaign_period_coverage
),
last_purchase AS (
    SELECT
        recipient.household_key,
        recipient.campaign,
        MAX(basket.day)::INTEGER AS pre_26w_last_purchase_day
    FROM eligible_recipients AS recipient
    LEFT JOIN mart.fact_basket AS basket
        ON basket.household_key = recipient.household_key
       AND basket.is_valid_purchase_basket
       AND basket.day BETWEEN recipient.start_day - 182 AND recipient.start_day - 1
    GROUP BY recipient.household_key, recipient.campaign
),
-- 현재 Campaign 시작 전에 종료된 Campaign만 과거 수신 이력으로 인정한다.
prior_campaign_relation AS MATERIALIZED (
    SELECT
        current.household_key,
        current.campaign AS current_campaign,
        current.start_day AS current_start_day,
        prior_recipient.campaign AS prior_campaign
    FROM eligible_recipients AS current
    JOIN mart.fact_campaign_household AS prior_recipient
        ON prior_recipient.household_key = current.household_key
       AND prior_recipient.campaign <> current.campaign
    JOIN mart.dim_campaign AS prior_campaign
        ON prior_campaign.campaign = prior_recipient.campaign
       AND prior_campaign.end_day < current.start_day
),
prior_campaign_totals AS (
    SELECT
        household_key,
        current_campaign,
        COUNT(*)::BIGINT AS prior_campaign_count
    FROM prior_campaign_relation
    GROUP BY household_key, current_campaign
),
prior_redemption_by_campaign AS (
    SELECT
        relation.household_key,
        relation.current_campaign,
        relation.prior_campaign,
        COUNT(redemption.redemption_day)::BIGINT AS redemption_count,
        MAX(redemption.redemption_day)::INTEGER AS last_redemption_day
    FROM prior_campaign_relation AS relation
    LEFT JOIN mart.fact_coupon_redemption AS redemption
        ON redemption.household_key = relation.household_key
       AND redemption.campaign = relation.prior_campaign
    GROUP BY relation.household_key, relation.current_campaign, relation.prior_campaign
),
prior_redemption_totals AS (
    SELECT
        household_key,
        current_campaign,
        SUM(redemption_count)::BIGINT AS prior_redemption_count,
        COUNT(*) FILTER (WHERE redemption_count > 0)::BIGINT
            AS prior_redeemed_campaign_count,
        MAX(last_redemption_day)::INTEGER AS last_prior_redemption_day
    FROM prior_redemption_by_campaign
    GROUP BY household_key, current_campaign
)
SELECT
    recipient.household_key,
    recipient.campaign,
    recipient.description,
    recipient.start_day,
    recipient.end_day,
    recipient.redeemed_flag,
    CASE WHEN recipient.redeemed_flag THEN 'REDEEMER' ELSE 'NON_REDEEMER' END
        AS response_group,
    purchase.pre_26w_last_purchase_day,
    recipient.start_day - purchase.pre_26w_last_purchase_day
        AS pre_26w_purchase_recency_days,
    recipient.pre_26w_basket_count,
    recipient.pre_26w_sales,
    recipient.pre_26w_purchase_day_count,
    recipient.pre_26w_purchase_week_count,
    recipient.pre_26w_average_basket_value,
    recipient.pre_26w_discount_amount,
    recipient.pre_26w_discounted_basket_count,
    recipient.pre_26w_discounted_basket_rate,
    recipient.pre_26w_retail_discount_amount,
    recipient.pre_26w_coupon_discount_amount,
    recipient.pre_8w_basket_count,
    recipient.pre_8w_sales,
    recipient.pre_8w_purchase_day_count,
    recipient.pre_8w_purchase_week_count,
    recipient.pre_8w_average_basket_value,
    recipient.previous_4w_basket_count,
    recipient.previous_4w_sales,
    recipient.recent_4w_basket_count,
    recipient.recent_4w_sales,
    recipient.recent_4w_basket_count - recipient.previous_4w_basket_count
        AS recent_vs_previous_4w_basket_difference,
    recipient.recent_4w_sales - recipient.previous_4w_sales
        AS recent_vs_previous_4w_sales_difference,
    COALESCE(prior_campaign.prior_campaign_count, 0)::BIGINT AS prior_campaign_count,
    COALESCE(prior_redemption.prior_redemption_count, 0)::BIGINT
        AS prior_redemption_count,
    COALESCE(prior_redemption.prior_redeemed_campaign_count, 0)::BIGINT
        AS prior_redeemed_campaign_count,
    COALESCE(prior_redemption.prior_redeemed_campaign_count, 0)::NUMERIC
        / NULLIF(prior_campaign.prior_campaign_count, 0)
        AS historical_campaign_redemption_rate,
    prior_redemption.last_prior_redemption_day,
    recipient.start_day - prior_redemption.last_prior_redemption_day
        AS days_since_last_prior_redemption
FROM eligible_recipients AS recipient
JOIN last_purchase AS purchase
    ON purchase.household_key = recipient.household_key
   AND purchase.campaign = recipient.campaign
LEFT JOIN prior_campaign_totals AS prior_campaign
    ON prior_campaign.household_key = recipient.household_key
   AND prior_campaign.current_campaign = recipient.campaign
LEFT JOIN prior_redemption_totals AS prior_redemption
    ON prior_redemption.household_key = recipient.household_key
   AND prior_redemption.current_campaign = recipient.campaign;

ALTER TABLE mart.campaign_customer_response_features
    ADD CONSTRAINT pk_campaign_customer_response_features
    PRIMARY KEY (household_key, campaign);

ALTER TABLE mart.campaign_customer_response_features
    ADD CONSTRAINT chk_campaign_customer_response_group
    CHECK (response_group IN ('REDEEMER', 'NON_REDEEMER'));

CREATE INDEX idx_campaign_customer_response_features_campaign
    ON mart.campaign_customer_response_features (campaign);

COMMIT;

ANALYZE mart.campaign_customer_response_features;

/* ============================================================
   23. Redeemer vs Non-Redeemer 고객 특성 비교
   ============================================================ */

-- 관측치 수와 실제 고유 Household 수를 구분해 표본 구조를 확인한다.
SELECT
    response_group,
    COUNT(*)::BIGINT AS observation_count,
    COUNT(DISTINCT household_key)::BIGINT AS distinct_household_count,
    COUNT(DISTINCT campaign)::BIGINT AS campaign_count
FROM mart.campaign_customer_response_features
GROUP BY response_group;

-- NULL의 의미를 보존하면서 핵심 Feature의 평균과 중앙값을 Long Format으로 비교한다.
WITH metric_values AS MATERIALIZED (
    SELECT
        feature.response_group,
        metric.metric_name,
        metric.metric_value
    FROM mart.campaign_customer_response_features AS feature
    CROSS JOIN LATERAL (VALUES
        ('pre_26w_purchase_recency_days', feature.pre_26w_purchase_recency_days::NUMERIC),
        ('pre_26w_basket_count', feature.pre_26w_basket_count::NUMERIC),
        ('pre_26w_sales', feature.pre_26w_sales::NUMERIC),
        ('pre_26w_purchase_day_count', feature.pre_26w_purchase_day_count::NUMERIC),
        ('pre_26w_purchase_week_count', feature.pre_26w_purchase_week_count::NUMERIC),
        ('pre_26w_average_basket_value', feature.pre_26w_average_basket_value::NUMERIC),
        ('pre_8w_basket_count', feature.pre_8w_basket_count::NUMERIC),
        ('pre_8w_sales', feature.pre_8w_sales::NUMERIC),
        ('previous_4w_basket_count', feature.previous_4w_basket_count::NUMERIC),
        ('recent_4w_basket_count', feature.recent_4w_basket_count::NUMERIC),
        ('previous_4w_sales', feature.previous_4w_sales::NUMERIC),
        ('recent_4w_sales', feature.recent_4w_sales::NUMERIC),
        ('recent_vs_previous_4w_basket_difference', feature.recent_vs_previous_4w_basket_difference::NUMERIC),
        ('recent_vs_previous_4w_sales_difference', feature.recent_vs_previous_4w_sales_difference::NUMERIC),
        ('pre_26w_retail_discount_amount', feature.pre_26w_retail_discount_amount::NUMERIC),
        ('pre_26w_coupon_discount_amount', feature.pre_26w_coupon_discount_amount::NUMERIC),
        ('pre_26w_discounted_basket_rate', feature.pre_26w_discounted_basket_rate::NUMERIC),
        ('prior_campaign_count', feature.prior_campaign_count::NUMERIC),
        ('prior_redemption_count', feature.prior_redemption_count::NUMERIC),
        ('prior_redeemed_campaign_count', feature.prior_redeemed_campaign_count::NUMERIC),
        ('historical_campaign_redemption_rate', feature.historical_campaign_redemption_rate::NUMERIC),
        ('days_since_last_prior_redemption', feature.days_since_last_prior_redemption::NUMERIC)
    ) AS metric(metric_name, metric_value)
),
metric_summary AS (
    SELECT
        metric_name,
        COUNT(metric_value) FILTER (WHERE response_group = 'REDEEMER')::BIGINT
            AS redeemer_non_null_count,
        COUNT(*) FILTER (
            WHERE response_group = 'REDEEMER' AND metric_value IS NULL
        )::BIGINT AS redeemer_null_count,
        COUNT(metric_value) FILTER (WHERE response_group = 'NON_REDEEMER')::BIGINT
            AS non_redeemer_non_null_count,
        COUNT(*) FILTER (
            WHERE response_group = 'NON_REDEEMER' AND metric_value IS NULL
        )::BIGINT AS non_redeemer_null_count,
        AVG(metric_value) FILTER (WHERE response_group = 'REDEEMER') AS redeemer_mean,
        AVG(metric_value) FILTER (WHERE response_group = 'NON_REDEEMER') AS non_redeemer_mean,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY metric_value)
            FILTER (WHERE response_group = 'REDEEMER') AS redeemer_median,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY metric_value)
            FILTER (WHERE response_group = 'NON_REDEEMER') AS non_redeemer_median
    FROM metric_values
    GROUP BY metric_name
)
SELECT
    metric_name,
    redeemer_non_null_count,
    redeemer_null_count,
    non_redeemer_non_null_count,
    non_redeemer_null_count,
    redeemer_mean,
    non_redeemer_mean,
    redeemer_median,
    non_redeemer_median,
    redeemer_mean - non_redeemer_mean AS mean_difference
FROM metric_summary;

/* ============================================================
   24. Campaign·Type별 반응 고객 특성 확인
   ============================================================ */

SELECT
    description,
    response_group,
    COUNT(*)::BIGINT AS observation_count,
    COUNT(DISTINCT household_key)::BIGINT AS distinct_household_count,
    COUNT(DISTINCT campaign)::BIGINT AS campaign_count,
    AVG(pre_26w_sales) AS average_pre_26w_sales,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pre_26w_sales)
        AS median_pre_26w_sales,
    AVG(pre_26w_basket_count) AS average_pre_26w_basket_count,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pre_26w_basket_count)
        AS median_pre_26w_basket_count,
    AVG(pre_8w_sales) AS average_pre_8w_sales,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pre_8w_sales)
        AS median_pre_8w_sales,
    AVG(pre_26w_coupon_discount_amount) AS average_pre_26w_coupon_discount_amount,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pre_26w_coupon_discount_amount)
        AS median_pre_26w_coupon_discount_amount,
    AVG(prior_campaign_count) AS average_prior_campaign_count,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY prior_campaign_count)
        AS median_prior_campaign_count,
    AVG(prior_redemption_count) AS average_prior_redemption_count,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY prior_redemption_count)
        AS median_prior_redemption_count
FROM mart.campaign_customer_response_features
GROUP BY description, response_group;

-- 같은 Campaign 안의 두 반응 그룹을 표본 수와 함께 비교한다.
SELECT
    campaign,
    description,
    response_group,
    COUNT(*)::BIGINT AS observation_count,
    AVG(pre_26w_sales) AS average_pre_26w_sales,
    AVG(pre_26w_basket_count) AS average_pre_26w_basket_count,
    AVG(pre_8w_sales) AS average_pre_8w_sales,
    AVG(pre_26w_coupon_discount_amount) AS average_pre_26w_coupon_discount_amount,
    AVG(prior_redemption_count) AS average_prior_redemption_count
FROM mart.campaign_customer_response_features
GROUP BY campaign, description, response_group;

/* ============================================================
   25. 고객 반응 Feature 품질 검증
   ============================================================ */

-- Coverage·Label·Recipient·Redeemer가 기존 Campaign Summary와 일치하는지 확인한다.
WITH feature_totals AS (
    SELECT
        COUNT(*)::BIGINT AS feature_observation_count,
        COUNT(*) FILTER (WHERE redeemed_flag)::BIGINT AS feature_redeemer_count,
        COUNT(*) FILTER (
            WHERE redeemed_flag IS NULL
               OR response_group IS NULL
               OR response_group NOT IN ('REDEEMER', 'NON_REDEEMER')
               OR response_group IS DISTINCT FROM
                    CASE WHEN redeemed_flag THEN 'REDEEMER' ELSE 'NON_REDEEMER' END
        )::BIGINT AS response_label_issue_count
    FROM mart.campaign_customer_response_features
),
summary_totals AS (
    SELECT
        SUM(recipient_count)::BIGINT AS summary_recipient_count,
        SUM(redeemer_count)::BIGINT AS summary_redeemer_count
    FROM mart.campaign_response_summary
),
coverage_check AS (
    SELECT COUNT(*)::BIGINT AS uncovered_campaign_observation_count
    FROM mart.campaign_customer_response_features AS feature
    JOIN mart.dim_campaign AS campaign
        ON campaign.campaign = feature.campaign
    WHERE NOT campaign.has_campaign_period_coverage
)
SELECT
    feature_observation_count,
    summary_recipient_count,
    feature_redeemer_count,
    summary_redeemer_count,
    response_label_issue_count,
    uncovered_campaign_observation_count,
    CASE
        WHEN feature_observation_count = summary_recipient_count
         AND feature_redeemer_count = summary_redeemer_count
         AND response_label_issue_count = 0
         AND uncovered_campaign_observation_count = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM feature_totals
CROSS JOIN summary_totals
CROSS JOIN coverage_check;

-- 시간누출과 Historical·Recency·할인·구매 Count 논리를 한 번에 확인한다.
SELECT
    COUNT(*) FILTER (
        WHERE pre_26w_last_purchase_day >= start_day
           OR last_prior_redemption_day >= start_day
    )::BIGINT AS future_information_issue_count,
    COUNT(*) FILTER (
        WHERE prior_campaign_count < 0
           OR prior_redemption_count < 0
           OR prior_redeemed_campaign_count < 0
           OR prior_redeemed_campaign_count > prior_campaign_count
           OR (historical_campaign_redemption_rate IS NOT NULL AND (
                  historical_campaign_redemption_rate < 0
               OR historical_campaign_redemption_rate > 1
              ))
           OR (prior_campaign_count = 0 AND historical_campaign_redemption_rate IS NOT NULL)
           OR (prior_campaign_count > 0 AND historical_campaign_redemption_rate IS NULL)
    )::BIGINT AS historical_feature_issue_count,
    COUNT(*) FILTER (
        WHERE (pre_26w_purchase_recency_days IS NOT NULL
               AND pre_26w_purchase_recency_days < 1)
           OR (days_since_last_prior_redemption IS NOT NULL
               AND days_since_last_prior_redemption < 1)
    )::BIGINT AS recency_issue_count,
    COUNT(*) FILTER (
        WHERE pre_26w_discounted_basket_rate IS NOT NULL
          AND (pre_26w_discounted_basket_rate < 0
               OR pre_26w_discounted_basket_rate > 1)
    )::BIGINT AS discount_rate_issue_count,
    COUNT(*) FILTER (
        WHERE pre_26w_basket_count < 0
           OR pre_26w_purchase_day_count < 0
           OR pre_26w_purchase_week_count < 0
           OR pre_8w_basket_count < 0
           OR previous_4w_basket_count < 0
           OR recent_4w_basket_count < 0
    )::BIGINT AS purchase_count_issue_count,
    CASE
        WHEN COUNT(*) FILTER (
            WHERE pre_26w_last_purchase_day >= start_day
               OR last_prior_redemption_day >= start_day
               OR prior_campaign_count < 0
               OR prior_redemption_count < 0
               OR prior_redeemed_campaign_count < 0
               OR prior_redeemed_campaign_count > prior_campaign_count
               OR (historical_campaign_redemption_rate IS NOT NULL AND (
                      historical_campaign_redemption_rate < 0
                   OR historical_campaign_redemption_rate > 1
                  ))
               OR (prior_campaign_count = 0 AND historical_campaign_redemption_rate IS NOT NULL)
               OR (prior_campaign_count > 0 AND historical_campaign_redemption_rate IS NULL)
               OR (pre_26w_purchase_recency_days IS NOT NULL
                   AND pre_26w_purchase_recency_days < 1)
               OR (days_since_last_prior_redemption IS NOT NULL
                   AND days_since_last_prior_redemption < 1)
               OR (pre_26w_discounted_basket_rate IS NOT NULL AND (
                      pre_26w_discounted_basket_rate < 0
                   OR pre_26w_discounted_basket_rate > 1
                  ))
               OR pre_26w_basket_count < 0
               OR pre_26w_purchase_day_count < 0
               OR pre_26w_purchase_week_count < 0
               OR pre_8w_basket_count < 0
               OR previous_4w_basket_count < 0
               OR recent_4w_basket_count < 0
        ) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM mart.campaign_customer_response_features;

/* ============================================================
   26. Coupon Category 분석 단위 확정
   ============================================================ */

-- Category는 실제 상환 상품이 아니라 Coupon이 적용 가능한 상품군을 뜻한다.
SELECT
    COUNT(*)::BIGINT AS bridge_product_row_count,
    COUNT(DISTINCT campaign)::BIGINT AS distinct_campaign_count,
    COUNT(DISTINCT coupon_upc)::BIGINT AS distinct_coupon_count,
    COUNT(DISTINCT department)::BIGINT AS distinct_department_count,
    COUNT(DISTINCT commodity_desc)::BIGINT AS distinct_commodity_count,
    COUNT(DISTINCT (department, commodity_desc))::BIGINT
        AS distinct_department_commodity_count,
    COUNT(*) FILTER (
        WHERE department IS NOT NULL AND commodity_desc IS NOT NULL
    )::BIGINT AS identifiable_category_row_count,
    COUNT(*) FILTER (
        WHERE department IS NULL OR commodity_desc IS NULL
    )::BIGINT AS unidentified_category_row_count,
    COUNT(*) FILTER (
        WHERE department IS NULL OR commodity_desc IS NULL
    )::NUMERIC / NULLIF(COUNT(*), 0) AS unidentified_category_row_rate,
    'INFO'::TEXT AS status
FROM mart.bridge_coupon_product;

WITH coupon_product_counts AS (
    SELECT campaign, coupon_upc, COUNT(*)::BIGINT AS eligible_product_count
    FROM mart.bridge_coupon_product
    GROUP BY campaign, coupon_upc
)
SELECT
    COUNT(*)::BIGINT AS coupon_count,
    AVG(eligible_product_count) AS average_eligible_product_count,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY eligible_product_count)
        AS median_eligible_product_count,
    MAX(eligible_product_count)::BIGINT AS maximum_eligible_product_count,
    'INFO'::TEXT AS status
FROM coupon_product_counts;

/* ============================================================
   27. Coupon별 적용 가능 Category Map 생성
   ============================================================ */

BEGIN;

DROP TABLE IF EXISTS mart.campaign_category_affinity_features;
DROP TABLE IF EXISTS mart.coupon_category_map;

CREATE TABLE mart.coupon_category_map AS
SELECT
    campaign,
    coupon_upc,
    department,
    commodity_desc,
    COUNT(DISTINCT product_id)::BIGINT AS eligible_product_count
FROM mart.bridge_coupon_product
WHERE department IS NOT NULL
  AND commodity_desc IS NOT NULL
GROUP BY campaign, coupon_upc, department, commodity_desc;

ALTER TABLE mart.coupon_category_map
    ADD CONSTRAINT pk_coupon_category_map
    PRIMARY KEY (campaign, coupon_upc, department, commodity_desc);

CREATE INDEX idx_coupon_category_map_campaign_category
    ON mart.coupon_category_map (campaign, department, commodity_desc);

-- Coupon 하나가 여러 적용 가능 Category를 가질 수 있는 정도를 확인한다.
WITH coupon_category_counts AS (
    SELECT campaign, coupon_upc, COUNT(*)::BIGINT AS eligible_category_count
    FROM mart.coupon_category_map
    GROUP BY campaign, coupon_upc
)
SELECT
    MIN(eligible_category_count)::BIGINT AS minimum_category_count,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY eligible_category_count)
        AS median_category_count,
    AVG(eligible_category_count) AS average_category_count,
    MAX(eligible_category_count)::BIGINT AS maximum_category_count,
    'INFO'::TEXT AS status
FROM coupon_category_counts;

/* ============================================================
   28. 고객별 Campaign Category Affinity 생성
   ============================================================ */

-- 개별 Coupon 노출이 아니라 Campaign 전체 Coupon Category Set과의 겹침을 계산한다.
CREATE TABLE mart.campaign_category_affinity_features AS
WITH eligible_recipients AS MATERIALIZED (
    SELECT
        household_key,
        campaign,
        description,
        start_day,
        end_day,
        redeemed_flag,
        response_group
    FROM mart.campaign_customer_response_features
),
campaign_category_set AS (
    SELECT campaign, department, commodity_desc
    FROM mart.coupon_category_map
    GROUP BY campaign, department, commodity_desc
),
pre26_category_purchases AS (
    SELECT
        recipient.household_key,
        recipient.campaign,
        product.department,
        product.commodity_desc,
        SUM(transaction_data.sales_value)::NUMERIC AS pre26_category_sales,
        MAX(transaction_data.day)::INTEGER AS last_category_purchase_day
    FROM eligible_recipients AS recipient
    JOIN base.transaction_data AS transaction_data
        ON transaction_data.household_key = recipient.household_key
       AND transaction_data.day BETWEEN recipient.start_day - 182 AND recipient.start_day - 1
       AND transaction_data.quantity > 0
       AND transaction_data.sales_value > 0
    JOIN base.product AS product
        ON product.product_id = transaction_data.product_id
       AND product.department IS NOT NULL
       AND product.commodity_desc IS NOT NULL
    GROUP BY
        recipient.household_key,
        recipient.campaign,
        product.department,
        product.commodity_desc
),
affinity_totals AS (
    SELECT
        purchase.household_key,
        purchase.campaign,
        SUM(purchase.pre26_category_sales)::NUMERIC AS pre26_total_paid_category_sales,
        COALESCE(SUM(purchase.pre26_category_sales) FILTER (
            WHERE category_set.campaign IS NOT NULL
        ), 0::NUMERIC) AS pre26_campaign_category_matched_sales,
        COUNT(*)::BIGINT AS pre26_purchased_category_count,
        COUNT(*) FILTER (WHERE category_set.campaign IS NOT NULL)::BIGINT
            AS pre26_campaign_matched_category_count,
        MAX(purchase.last_category_purchase_day)::INTEGER
            AS pre26_last_category_purchase_day
    FROM pre26_category_purchases AS purchase
    LEFT JOIN campaign_category_set AS category_set
        ON category_set.campaign = purchase.campaign
       AND category_set.department = purchase.department
       AND category_set.commodity_desc = purchase.commodity_desc
    GROUP BY purchase.household_key, purchase.campaign
)
SELECT
    recipient.household_key,
    recipient.campaign,
    recipient.description,
    recipient.start_day,
    recipient.end_day,
    recipient.redeemed_flag,
    recipient.response_group,
    totals.pre26_last_category_purchase_day,
    COALESCE(totals.pre26_total_paid_category_sales, 0::NUMERIC)
        AS pre26_total_paid_category_sales,
    COALESCE(totals.pre26_campaign_category_matched_sales, 0::NUMERIC)
        AS pre26_campaign_category_matched_sales,
    COALESCE(totals.pre26_purchased_category_count, 0)::BIGINT
        AS pre26_purchased_category_count,
    COALESCE(totals.pre26_campaign_matched_category_count, 0)::BIGINT
        AS pre26_campaign_matched_category_count,
    totals.pre26_campaign_category_matched_sales
        / NULLIF(totals.pre26_total_paid_category_sales, 0)
        AS campaign_category_sales_affinity,
    totals.pre26_campaign_matched_category_count::NUMERIC
        / NULLIF(totals.pre26_purchased_category_count, 0)
        AS campaign_category_count_affinity,
    CASE
        WHEN COALESCE(totals.pre26_purchased_category_count, 0) = 0 THEN NULL
        ELSE totals.pre26_campaign_matched_category_count > 0
    END AS has_pre26_campaign_category_purchase
FROM eligible_recipients AS recipient
LEFT JOIN affinity_totals AS totals
    ON totals.household_key = recipient.household_key
   AND totals.campaign = recipient.campaign;

ALTER TABLE mart.campaign_category_affinity_features
    ADD CONSTRAINT pk_campaign_category_affinity_features
    PRIMARY KEY (household_key, campaign);

CREATE INDEX idx_campaign_category_affinity_features_campaign
    ON mart.campaign_category_affinity_features (campaign);

COMMIT;

ANALYZE mart.coupon_category_map;
ANALYZE mart.campaign_category_affinity_features;

/* ============================================================
   29. Redeemer·Non-Redeemer Category Affinity 비교
   ============================================================ */

SELECT
    response_group,
    COUNT(*)::BIGINT AS observation_count,
    COUNT(DISTINCT household_key)::BIGINT AS distinct_household_count,
    COUNT(DISTINCT campaign)::BIGINT AS campaign_count,
    COUNT(campaign_category_sales_affinity)::BIGINT AS sales_affinity_non_null_count,
    COUNT(*) FILTER (WHERE campaign_category_sales_affinity IS NULL)::BIGINT
        AS sales_affinity_null_count,
    AVG(campaign_category_sales_affinity) AS average_campaign_category_sales_affinity,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY campaign_category_sales_affinity)
        AS median_campaign_category_sales_affinity,
    COUNT(campaign_category_count_affinity)::BIGINT AS count_affinity_non_null_count,
    COUNT(*) FILTER (WHERE campaign_category_count_affinity IS NULL)::BIGINT
        AS count_affinity_null_count,
    AVG(campaign_category_count_affinity) AS average_campaign_category_count_affinity,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY campaign_category_count_affinity)
        AS median_campaign_category_count_affinity,
    COUNT(*) FILTER (WHERE has_pre26_campaign_category_purchase)::BIGINT
        AS matched_category_purchase_observation_count,
    COUNT(*) FILTER (WHERE has_pre26_campaign_category_purchase)::NUMERIC
        / NULLIF(COUNT(has_pre26_campaign_category_purchase), 0)
        AS matched_category_purchase_rate_among_known_history
FROM mart.campaign_category_affinity_features
GROUP BY response_group;

-- Campaign Type별로 같은 Affinity 방향이 관찰되는지 표본 수와 함께 확인한다.
SELECT
    description,
    response_group,
    COUNT(*)::BIGINT AS observation_count,
    AVG(campaign_category_sales_affinity) AS average_campaign_category_sales_affinity,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY campaign_category_sales_affinity)
        AS median_campaign_category_sales_affinity,
    AVG(campaign_category_count_affinity) AS average_campaign_category_count_affinity,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY campaign_category_count_affinity)
        AS median_campaign_category_count_affinity,
    COUNT(*) FILTER (WHERE has_pre26_campaign_category_purchase)::NUMERIC
        / NULLIF(COUNT(has_pre26_campaign_category_purchase), 0)
        AS matched_category_purchase_rate_among_known_history
FROM mart.campaign_category_affinity_features
GROUP BY description, response_group;

-- Campaign별 결과는 순위가 아니라 반복되는 패턴을 확인하는 보조자료이다.
SELECT
    campaign,
    description,
    response_group,
    COUNT(*)::BIGINT AS observation_count,
    AVG(campaign_category_sales_affinity) AS average_campaign_category_sales_affinity,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY campaign_category_sales_affinity)
        AS median_campaign_category_sales_affinity
FROM mart.campaign_category_affinity_features
GROUP BY campaign, description, response_group;

/* ============================================================
   30. 상환 Coupon의 적용 가능 Category 분석
   ============================================================ */

-- Category Mention은 실제 구매 Category나 실제 Redemption 건수를 뜻하지 않는다.
WITH category_mentions AS (
    SELECT
        category.department,
        category.commodity_desc,
        COUNT(*)::BIGINT AS redemption_category_mention_count,
        COUNT(DISTINCT (redemption.campaign, redemption.coupon_upc))::BIGINT
            AS distinct_redeemed_coupon_count,
        COUNT(DISTINCT redemption.household_key)::BIGINT
            AS distinct_redeemer_household_count,
        COUNT(DISTINCT redemption.campaign)::BIGINT AS campaign_count
    FROM mart.fact_coupon_redemption AS redemption
    JOIN mart.coupon_category_map AS category
        ON category.campaign = redemption.campaign
       AND category.coupon_upc = redemption.coupon_upc
    GROUP BY category.department, category.commodity_desc
)
SELECT
    department,
    commodity_desc,
    redemption_category_mention_count,
    distinct_redeemed_coupon_count,
    distinct_redeemer_household_count,
    campaign_count,
    redemption_category_mention_count::NUMERIC
        / NULLIF(SUM(redemption_category_mention_count) OVER (), 0)
        AS redeemed_coupon_category_mention_share
FROM category_mentions;

-- 상환된 Coupon의 Category 수가 해석에 주는 불확실성을 확인한다.
WITH redeemed_coupons AS (
    SELECT campaign, coupon_upc
    FROM mart.fact_coupon_redemption
    GROUP BY campaign, coupon_upc
),
redeemed_coupon_breadth AS (
    SELECT
        coupon.campaign,
        coupon.coupon_upc,
        COUNT(category.commodity_desc)::BIGINT AS eligible_category_count
    FROM redeemed_coupons AS coupon
    LEFT JOIN mart.coupon_category_map AS category
        ON category.campaign = coupon.campaign
       AND category.coupon_upc = coupon.coupon_upc
    GROUP BY coupon.campaign, coupon.coupon_upc
)
SELECT
    COUNT(*)::BIGINT AS redeemed_coupon_count,
    COUNT(*) FILTER (WHERE eligible_category_count = 1)::BIGINT
        AS single_category_coupon_count,
    COUNT(*) FILTER (WHERE eligible_category_count > 1)::BIGINT
        AS multi_category_coupon_count,
    AVG(eligible_category_count) AS average_category_count,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY eligible_category_count)
        AS median_category_count,
    MAX(eligible_category_count)::BIGINT AS maximum_category_count,
    'INFO'::TEXT AS status
FROM redeemed_coupon_breadth;

/* ============================================================
   31. Category Affinity 품질 검증
   ============================================================ */

-- Category가 확인되지 않는 Coupon도 Map Coverage 결과에 남긴다.
WITH all_coupons AS (
    SELECT campaign, coupon_upc
    FROM mart.bridge_coupon_product
    GROUP BY campaign, coupon_upc
),
mapped_coupons AS (
    SELECT campaign, coupon_upc
    FROM mart.coupon_category_map
    GROUP BY campaign, coupon_upc
)
SELECT
    COUNT(*)::BIGINT AS total_distinct_coupon_count,
    COUNT(mapped.coupon_upc)::BIGINT AS coupon_with_valid_category_count,
    COUNT(*) FILTER (WHERE mapped.coupon_upc IS NULL)::BIGINT
        AS coupon_without_valid_category_count,
    'INFO'::TEXT AS status
FROM all_coupons AS coupon
LEFT JOIN mapped_coupons AS mapped
    ON mapped.campaign = coupon.campaign
   AND mapped.coupon_upc = coupon.coupon_upc;

-- Affinity Feature의 Grain과 Response Label을 기존 Feature Table과 대사한다.
WITH source_totals AS (
    SELECT
        COUNT(*)::BIGINT AS source_observation_count,
        COUNT(*) FILTER (WHERE redeemed_flag)::BIGINT AS source_redeemer_count
    FROM mart.campaign_customer_response_features
),
affinity_totals AS (
    SELECT
        COUNT(*)::BIGINT AS affinity_observation_count,
        COUNT(*) FILTER (WHERE redeemed_flag)::BIGINT AS affinity_redeemer_count
    FROM mart.campaign_category_affinity_features
)
SELECT
    source_observation_count,
    affinity_observation_count,
    source_redeemer_count,
    affinity_redeemer_count,
    CASE
        WHEN source_observation_count = affinity_observation_count
         AND source_redeemer_count = affinity_redeemer_count THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM source_totals
CROSS JOIN affinity_totals;

-- Affinity에 사용한 Campaign Category Set은 Campaign×Category Grain으로 유일해야 한다.
WITH campaign_category_set AS (
    SELECT campaign, department, commodity_desc
    FROM mart.coupon_category_map
    GROUP BY campaign, department, commodity_desc
)
SELECT
    COUNT(*)::BIGINT AS campaign_category_set_row_count,
    COUNT(DISTINCT (campaign, department, commodity_desc))::BIGINT
        AS distinct_campaign_category_count,
    CASE
        WHEN COUNT(*) = COUNT(DISTINCT (campaign, department, commodity_desc)) THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM campaign_category_set;

-- Affinity 범위·NULL 의미·JOIN 증폭·시간누출을 한 번에 확인한다.
SELECT
    COUNT(*) FILTER (
        WHERE (campaign_category_sales_affinity IS NOT NULL AND (
                  campaign_category_sales_affinity < 0
               OR campaign_category_sales_affinity > 1
              ))
           OR (campaign_category_count_affinity IS NOT NULL AND (
                  campaign_category_count_affinity < 0
               OR campaign_category_count_affinity > 1
              ))
    )::BIGINT AS affinity_range_issue_count,
    COUNT(*) FILTER (
        WHERE pre26_campaign_category_matched_sales > pre26_total_paid_category_sales
           OR pre26_campaign_matched_category_count > pre26_purchased_category_count
    )::BIGINT AS matched_value_issue_count,
    COUNT(*) FILTER (
        WHERE (pre26_total_paid_category_sales = 0
               AND campaign_category_sales_affinity IS NOT NULL)
           OR (pre26_total_paid_category_sales > 0
               AND campaign_category_sales_affinity IS NULL)
           OR (pre26_purchased_category_count = 0
               AND campaign_category_count_affinity IS NOT NULL)
           OR (pre26_purchased_category_count > 0
               AND campaign_category_count_affinity IS NULL)
    )::BIGINT AS affinity_null_semantics_issue_count,
    COUNT(*) FILTER (
        WHERE pre26_last_category_purchase_day >= start_day
    )::BIGINT AS future_information_issue_count,
    CASE
        WHEN COUNT(*) FILTER (
            WHERE (campaign_category_sales_affinity IS NOT NULL AND (
                      campaign_category_sales_affinity < 0
                   OR campaign_category_sales_affinity > 1
                  ))
               OR (campaign_category_count_affinity IS NOT NULL AND (
                      campaign_category_count_affinity < 0
                   OR campaign_category_count_affinity > 1
                  ))
               OR pre26_campaign_category_matched_sales > pre26_total_paid_category_sales
               OR pre26_campaign_matched_category_count > pre26_purchased_category_count
               OR (pre26_total_paid_category_sales = 0
                   AND campaign_category_sales_affinity IS NOT NULL)
               OR (pre26_total_paid_category_sales > 0
                   AND campaign_category_sales_affinity IS NULL)
               OR (pre26_purchased_category_count = 0
                   AND campaign_category_count_affinity IS NOT NULL)
               OR (pre26_purchased_category_count > 0
                   AND campaign_category_count_affinity IS NULL)
               OR pre26_last_category_purchase_day >= start_day
        ) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM mart.campaign_category_affinity_features;

-- Category Mention은 원본 Redemption을 변경하지 않는 정보성 1:N 결과이다.
WITH mention_count AS (
    SELECT COUNT(*)::BIGINT AS category_mention_count
    FROM mart.fact_coupon_redemption AS redemption
    JOIN mart.coupon_category_map AS category
        ON category.campaign = redemption.campaign
       AND category.coupon_upc = redemption.coupon_upc
),
redemption_count AS (
    SELECT COUNT(*)::BIGINT AS redemption_row_count
    FROM mart.fact_coupon_redemption
)
SELECT
    2318::BIGINT AS expected_redemption_row_count,
    redemption_row_count AS actual_redemption_row_count,
    category_mention_count,
    category_mention_count - redemption_row_count AS additional_category_mentions,
    CASE
        WHEN redemption_row_count = 2318 THEN 'INFO_EXPECTED_1_TO_N'
        ELSE 'FAIL'
    END AS status
FROM mention_count
CROSS JOIN redemption_count;

/* ============================================================
   32. PRE·DURING·POST 분석 대상 확정
   ============================================================ */

SELECT
    COUNT(*)::BIGINT AS total_campaign_count,
    COUNT(*) FILTER (WHERE has_full_behavior_coverage)::BIGINT
        AS full_coverage_campaign_count,
    COUNT(*) FILTER (WHERE NOT has_full_behavior_coverage)::BIGINT
        AS excluded_campaign_count,
    'INFO'::TEXT AS status
FROM mart.dim_campaign;

SELECT
    campaign,
    description,
    start_day,
    end_day,
    has_pre_8w_coverage,
    has_campaign_period_coverage,
    has_post_4w_coverage,
    has_full_behavior_coverage
FROM mart.dim_campaign
WHERE NOT has_full_behavior_coverage;

/* ============================================================
   33. 고객별 PRE·DURING·POST 구매행동 Feature 생성
   ============================================================ */

BEGIN;

DROP TABLE IF EXISTS mart.campaign_pre_during_post_features;

-- 기존 Basket KPI는 재사용하고 Product 수와 Campaign Category 구매금액만 추가 집계한다.
CREATE TABLE mart.campaign_pre_during_post_features AS
WITH eligible_recipients AS MATERIALIZED (
    SELECT
        response.household_key,
        response.campaign,
        response.description,
        response.start_day,
        response.end_day,
        response.campaign_duration,
        response.redeemed_flag,
        CASE WHEN response.redeemed_flag THEN 'REDEEMER' ELSE 'NON_REDEEMER' END
            AS response_group,
        response.pre_8w_sales,
        response.pre_8w_basket_count,
        response.pre_8w_purchase_day_count,
        response.campaign_sales AS during_sales,
        response.campaign_basket_count AS during_basket_count,
        response.campaign_purchase_day_count AS during_purchase_day_count,
        response.post_4w_sales,
        response.post_4w_basket_count,
        response.post_4w_purchase_day_count
    FROM mart.household_campaign_response AS response
    WHERE response.has_full_behavior_coverage
),
campaign_category_set AS (
    SELECT campaign, department, commodity_desc
    FROM mart.coupon_category_map
    GROUP BY campaign, department, commodity_desc
),
transaction_metrics AS (
    SELECT
        recipient.household_key,
        recipient.campaign,
        COUNT(DISTINCT transaction_data.product_id) FILTER (
            WHERE transaction_data.day BETWEEN recipient.start_day - 56 AND recipient.start_day - 1
        )::BIGINT AS pre_8w_product_count,
        COUNT(DISTINCT transaction_data.product_id) FILTER (
            WHERE transaction_data.day BETWEEN recipient.start_day AND recipient.end_day
        )::BIGINT AS during_product_count,
        COUNT(DISTINCT transaction_data.product_id) FILTER (
            WHERE transaction_data.day BETWEEN recipient.end_day + 1 AND recipient.end_day + 28
        )::BIGINT AS post_4w_product_count,
        COALESCE(SUM(transaction_data.sales_value) FILTER (
            WHERE transaction_data.day BETWEEN recipient.start_day - 56 AND recipient.start_day - 1
              AND category_set.campaign IS NOT NULL
        ), 0::NUMERIC) AS pre_8w_campaign_category_sales,
        COALESCE(SUM(transaction_data.sales_value) FILTER (
            WHERE transaction_data.day BETWEEN recipient.start_day AND recipient.end_day
              AND category_set.campaign IS NOT NULL
        ), 0::NUMERIC) AS during_campaign_category_sales,
        COALESCE(SUM(transaction_data.sales_value) FILTER (
            WHERE transaction_data.day BETWEEN recipient.end_day + 1 AND recipient.end_day + 28
              AND category_set.campaign IS NOT NULL
        ), 0::NUMERIC) AS post_4w_campaign_category_sales
    FROM eligible_recipients AS recipient
    LEFT JOIN base.transaction_data AS transaction_data
        ON transaction_data.household_key = recipient.household_key
       AND transaction_data.day BETWEEN recipient.start_day - 56 AND recipient.end_day + 28
       AND transaction_data.quantity > 0
       AND transaction_data.sales_value > 0
    LEFT JOIN base.product AS product
        ON product.product_id = transaction_data.product_id
    LEFT JOIN campaign_category_set AS category_set
        ON category_set.campaign = recipient.campaign
       AND category_set.department = product.department
       AND category_set.commodity_desc = product.commodity_desc
    GROUP BY recipient.household_key, recipient.campaign
),
raw_features AS (
    SELECT
        recipient.household_key,
        recipient.campaign,
        recipient.description,
        recipient.start_day,
        recipient.end_day,
        recipient.campaign_duration,
        TRUE AS has_full_behavior_coverage,
        recipient.redeemed_flag,
        recipient.response_group,
        recipient.start_day - 56 AS pre_start_day,
        recipient.start_day - 1 AS pre_end_day,
        recipient.start_day AS during_start_day,
        recipient.end_day AS during_end_day,
        recipient.end_day + 1 AS post_start_day,
        recipient.end_day + 28 AS post_end_day,
        56::INTEGER AS pre_period_days,
        recipient.campaign_duration::INTEGER AS during_period_days,
        28::INTEGER AS post_period_days,
        recipient.pre_8w_sales,
        recipient.during_sales,
        recipient.post_4w_sales,
        recipient.pre_8w_basket_count,
        recipient.during_basket_count,
        recipient.post_4w_basket_count,
        recipient.pre_8w_purchase_day_count,
        recipient.during_purchase_day_count,
        recipient.post_4w_purchase_day_count,
        recipient.pre_8w_sales / NULLIF(recipient.pre_8w_basket_count, 0)
            AS pre_8w_average_basket_value,
        recipient.during_sales / NULLIF(recipient.during_basket_count, 0)
            AS during_average_basket_value,
        recipient.post_4w_sales / NULLIF(recipient.post_4w_basket_count, 0)
            AS post_4w_average_basket_value,
        transaction.pre_8w_product_count,
        transaction.during_product_count,
        transaction.post_4w_product_count,
        transaction.pre_8w_campaign_category_sales,
        transaction.during_campaign_category_sales,
        transaction.post_4w_campaign_category_sales
    FROM eligible_recipients AS recipient
    JOIN transaction_metrics AS transaction
        ON transaction.household_key = recipient.household_key
       AND transaction.campaign = recipient.campaign
),
normalized_features AS (
    SELECT
        raw_features.*,
        pre_8w_sales / pre_period_days AS pre_sales_per_day,
        during_sales / NULLIF(during_period_days, 0) AS during_sales_per_day,
        post_4w_sales / post_period_days AS post_sales_per_day,
        pre_8w_basket_count::NUMERIC / pre_period_days AS pre_baskets_per_day,
        during_basket_count::NUMERIC / NULLIF(during_period_days, 0)
            AS during_baskets_per_day,
        post_4w_basket_count::NUMERIC / post_period_days AS post_baskets_per_day,
        pre_8w_purchase_day_count::NUMERIC / pre_period_days AS pre_purchase_day_rate,
        during_purchase_day_count::NUMERIC / NULLIF(during_period_days, 0)
            AS during_purchase_day_rate,
        post_4w_purchase_day_count::NUMERIC / post_period_days AS post_purchase_day_rate,
        pre_8w_campaign_category_sales / pre_period_days
            AS pre_campaign_category_sales_per_day,
        during_campaign_category_sales / NULLIF(during_period_days, 0)
            AS during_campaign_category_sales_per_day,
        post_4w_campaign_category_sales / post_period_days
            AS post_campaign_category_sales_per_day
    FROM raw_features
)
SELECT
    normalized_features.*,
    during_sales_per_day - pre_sales_per_day AS during_minus_pre_sales_per_day,
    post_sales_per_day - pre_sales_per_day AS post_minus_pre_sales_per_day,
    post_sales_per_day - during_sales_per_day AS post_minus_during_sales_per_day,
    during_baskets_per_day - pre_baskets_per_day AS during_minus_pre_baskets_per_day,
    post_baskets_per_day - pre_baskets_per_day AS post_minus_pre_baskets_per_day,
    post_baskets_per_day - during_baskets_per_day AS post_minus_during_baskets_per_day,
    during_purchase_day_rate - pre_purchase_day_rate
        AS during_minus_pre_purchase_day_rate,
    post_purchase_day_rate - pre_purchase_day_rate AS post_minus_pre_purchase_day_rate,
    post_purchase_day_rate - during_purchase_day_rate
        AS post_minus_during_purchase_day_rate
FROM normalized_features;

ALTER TABLE mart.campaign_pre_during_post_features
    ADD CONSTRAINT pk_campaign_pre_during_post_features
    PRIMARY KEY (household_key, campaign);

CREATE INDEX idx_campaign_pre_during_post_features_campaign
    ON mart.campaign_pre_during_post_features (campaign);

COMMIT;

ANALYZE mart.campaign_pre_during_post_features;

/* ============================================================
   34. 기간 길이를 보정한 구매행동 지표 생성
   ============================================================ */

-- PRE 56일·가변 DURING·POST 28일의 총액과 일평균을 함께 확인한다.
SELECT
    household_key,
    campaign,
    response_group,
    pre_period_days,
    during_period_days,
    post_period_days,
    pre_8w_sales,
    during_sales,
    post_4w_sales,
    pre_sales_per_day,
    during_sales_per_day,
    post_sales_per_day,
    pre_baskets_per_day,
    during_baskets_per_day,
    post_baskets_per_day,
    pre_purchase_day_rate,
    during_purchase_day_rate,
    post_purchase_day_rate
FROM mart.campaign_pre_during_post_features;

/* ============================================================
   35. Redeemer·Non-Redeemer 전·중·후 구매행동 비교
   ============================================================ */

SELECT
    response_group,
    COUNT(*)::BIGINT AS observation_count,
    COUNT(DISTINCT household_key)::BIGINT AS distinct_household_count,
    COUNT(DISTINCT campaign)::BIGINT AS campaign_count
FROM mart.campaign_pre_during_post_features
GROUP BY response_group;

-- 기간별 핵심 지표를 평균과 중앙값이 함께 보이는 Long Format으로 비교한다.
WITH metric_values AS MATERIALIZED (
    SELECT
        feature.response_group,
        metric.metric_name,
        metric.pre_value,
        metric.during_value,
        metric.post_value
    FROM mart.campaign_pre_during_post_features AS feature
    CROSS JOIN LATERAL (VALUES
        ('sales_per_day', feature.pre_sales_per_day, feature.during_sales_per_day,
         feature.post_sales_per_day),
        ('baskets_per_day', feature.pre_baskets_per_day, feature.during_baskets_per_day,
         feature.post_baskets_per_day),
        ('purchase_day_rate', feature.pre_purchase_day_rate, feature.during_purchase_day_rate,
         feature.post_purchase_day_rate),
        ('average_basket_value', feature.pre_8w_average_basket_value,
         feature.during_average_basket_value, feature.post_4w_average_basket_value),
        ('product_count', feature.pre_8w_product_count::NUMERIC,
         feature.during_product_count::NUMERIC, feature.post_4w_product_count::NUMERIC),
        ('campaign_category_sales_per_day', feature.pre_campaign_category_sales_per_day,
         feature.during_campaign_category_sales_per_day,
         feature.post_campaign_category_sales_per_day)
    ) AS metric(metric_name, pre_value, during_value, post_value)
)
SELECT
    response_group,
    metric_name,
    COUNT(*)::BIGINT AS observation_count,
    AVG(pre_value) AS pre_mean,
    AVG(during_value) AS during_mean,
    AVG(post_value) AS post_mean,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pre_value) AS pre_median,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY during_value) AS during_median,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY post_value) AS post_median,
    AVG(during_value - pre_value) AS during_minus_pre_mean,
    AVG(post_value - pre_value) AS post_minus_pre_mean,
    AVG(post_value - during_value) AS post_minus_during_mean
FROM metric_values
GROUP BY response_group, metric_name;

-- 일평균 구매금액의 증가·동일·감소 관측 비율을 임의 Threshold 없이 확인한다.
WITH comparisons AS (
    SELECT
        feature.response_group,
        comparison.comparison_name,
        comparison.difference
    FROM mart.campaign_pre_during_post_features AS feature
    CROSS JOIN LATERAL (VALUES
        ('DURING_MINUS_PRE', feature.during_minus_pre_sales_per_day),
        ('POST_MINUS_PRE', feature.post_minus_pre_sales_per_day),
        ('POST_MINUS_DURING', feature.post_minus_during_sales_per_day)
    ) AS comparison(comparison_name, difference)
)
SELECT
    response_group,
    comparison_name,
    COUNT(*)::BIGINT AS observation_count,
    COUNT(*) FILTER (WHERE difference > 0)::BIGINT AS increase_count,
    COUNT(*) FILTER (WHERE difference = 0)::BIGINT AS same_count,
    COUNT(*) FILTER (WHERE difference < 0)::BIGINT AS decrease_count,
    COUNT(*) FILTER (WHERE difference > 0)::NUMERIC / NULLIF(COUNT(*), 0)
        AS increase_rate
FROM comparisons
GROUP BY response_group, comparison_name;

/* ============================================================
   36. Campaign Type·Campaign별 행동변화 확인
   ============================================================ */

SELECT
    description,
    response_group,
    COUNT(*)::BIGINT AS observation_count,
    COUNT(DISTINCT campaign)::BIGINT AS campaign_count,
    AVG(pre_sales_per_day) AS average_pre_sales_per_day,
    AVG(during_sales_per_day) AS average_during_sales_per_day,
    AVG(post_sales_per_day) AS average_post_sales_per_day,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pre_sales_per_day)
        AS median_pre_sales_per_day,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY during_sales_per_day)
        AS median_during_sales_per_day,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY post_sales_per_day)
        AS median_post_sales_per_day,
    AVG(pre_baskets_per_day) AS average_pre_baskets_per_day,
    AVG(during_baskets_per_day) AS average_during_baskets_per_day,
    AVG(post_baskets_per_day) AS average_post_baskets_per_day,
    AVG(pre_8w_average_basket_value) AS average_pre_basket_value,
    AVG(during_average_basket_value) AS average_during_basket_value,
    AVG(post_4w_average_basket_value) AS average_post_basket_value,
    AVG(pre_campaign_category_sales_per_day)
        AS average_pre_campaign_category_sales_per_day,
    AVG(during_campaign_category_sales_per_day)
        AS average_during_campaign_category_sales_per_day,
    AVG(post_campaign_category_sales_per_day)
        AS average_post_campaign_category_sales_per_day
FROM mart.campaign_pre_during_post_features
GROUP BY description, response_group;

-- Campaign별 결과는 작은 표본의 우열이 아니라 패턴의 반복 여부를 확인한다.
SELECT
    campaign,
    description,
    response_group,
    COUNT(*)::BIGINT AS observation_count,
    AVG(pre_sales_per_day) AS pre_sales_per_day_mean,
    AVG(during_sales_per_day) AS during_sales_per_day_mean,
    AVG(post_sales_per_day) AS post_sales_per_day_mean,
    AVG(during_minus_pre_sales_per_day) AS during_minus_pre_mean,
    AVG(post_minus_pre_sales_per_day) AS post_minus_pre_mean
FROM mart.campaign_pre_during_post_features
GROUP BY campaign, description, response_group;

/* ============================================================
   37. PRE·DURING·POST 행동변화 품질 검증
   ============================================================ */

-- Coverage·Campaign 수·Recipient·Label을 기존 MART와 대사한다.
WITH expected AS (
    SELECT
        COUNT(*) FILTER (WHERE has_full_behavior_coverage)::BIGINT
            AS expected_campaign_count,
        25::BIGINT AS profiled_expected_campaign_count
    FROM mart.dim_campaign
),
source_totals AS (
    SELECT
        COUNT(*)::BIGINT AS expected_observation_count,
        COUNT(*) FILTER (WHERE redeemed_flag)::BIGINT AS expected_redeemer_count
    FROM mart.household_campaign_response
    WHERE has_full_behavior_coverage
),
feature_totals AS (
    SELECT
        COUNT(*)::BIGINT AS actual_observation_count,
        COUNT(DISTINCT campaign)::BIGINT AS actual_campaign_count,
        COUNT(*) FILTER (WHERE redeemed_flag)::BIGINT AS actual_redeemer_count,
        COUNT(*) FILTER (
            WHERE NOT has_full_behavior_coverage
               OR response_group NOT IN ('REDEEMER', 'NON_REDEEMER')
               OR response_group IS DISTINCT FROM
                    CASE WHEN redeemed_flag THEN 'REDEEMER' ELSE 'NON_REDEEMER' END
        )::BIGINT AS coverage_or_label_issue_count
    FROM mart.campaign_pre_during_post_features
)
SELECT
    profiled_expected_campaign_count,
    expected_campaign_count,
    actual_campaign_count,
    expected_observation_count,
    actual_observation_count,
    expected_redeemer_count,
    actual_redeemer_count,
    coverage_or_label_issue_count,
    CASE
        WHEN expected_campaign_count = actual_campaign_count
         AND profiled_expected_campaign_count = expected_campaign_count
         AND expected_observation_count = actual_observation_count
         AND expected_redeemer_count = actual_redeemer_count
         AND coverage_or_label_issue_count = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM expected
CROSS JOIN source_totals
CROSS JOIN feature_totals;

-- 기간 경계·일수·Count·ABV·일평균·구매일 비율을 한 번에 확인한다.
SELECT
    COUNT(*) FILTER (
        WHERE pre_start_day <> start_day - 56
           OR pre_end_day <> start_day - 1
           OR during_start_day <> start_day
           OR during_end_day <> end_day
           OR post_start_day <> end_day + 1
           OR post_end_day <> end_day + 28
           OR pre_end_day >= during_start_day
           OR during_end_day >= post_start_day
    )::BIGINT AS period_boundary_issue_count,
    COUNT(*) FILTER (
        WHERE pre_period_days <> 56
           OR post_period_days <> 28
           OR during_period_days <> campaign_duration
           OR during_period_days <= 0
    )::BIGINT AS period_day_issue_count,
    COUNT(*) FILTER (
        WHERE pre_8w_basket_count < 0
           OR during_basket_count < 0
           OR post_4w_basket_count < 0
           OR pre_8w_purchase_day_count < 0
           OR during_purchase_day_count < 0
           OR post_4w_purchase_day_count < 0
           OR pre_8w_product_count < 0
           OR during_product_count < 0
           OR post_4w_product_count < 0
    )::BIGINT AS negative_count_issue_count,
    COUNT(*) FILTER (
        WHERE (pre_8w_basket_count = 0 AND pre_8w_average_basket_value IS NOT NULL)
           OR (pre_8w_basket_count > 0 AND pre_8w_average_basket_value IS NULL)
           OR (during_basket_count = 0 AND during_average_basket_value IS NOT NULL)
           OR (during_basket_count > 0 AND during_average_basket_value IS NULL)
           OR (post_4w_basket_count = 0 AND post_4w_average_basket_value IS NOT NULL)
           OR (post_4w_basket_count > 0 AND post_4w_average_basket_value IS NULL)
    )::BIGINT AS average_basket_value_issue_count,
    COUNT(*) FILTER (
        WHERE pre_sales_per_day IS NULL
           OR during_sales_per_day IS NULL
           OR post_sales_per_day IS NULL
           OR pre_baskets_per_day IS NULL
           OR during_baskets_per_day IS NULL
           OR post_baskets_per_day IS NULL
           OR pre_purchase_day_rate IS NULL
           OR during_purchase_day_rate IS NULL
           OR post_purchase_day_rate IS NULL
           OR pre_purchase_day_rate NOT BETWEEN 0 AND 1
           OR during_purchase_day_rate NOT BETWEEN 0 AND 1
           OR post_purchase_day_rate NOT BETWEEN 0 AND 1
    )::BIGINT AS normalized_metric_issue_count,
    CASE
        WHEN COUNT(*) FILTER (
            WHERE pre_start_day <> start_day - 56
               OR pre_end_day <> start_day - 1
               OR during_start_day <> start_day
               OR during_end_day <> end_day
               OR post_start_day <> end_day + 1
               OR post_end_day <> end_day + 28
               OR pre_end_day >= during_start_day
               OR during_end_day >= post_start_day
               OR pre_period_days <> 56
               OR post_period_days <> 28
               OR during_period_days <> campaign_duration
               OR during_period_days <= 0
               OR pre_8w_basket_count < 0
               OR during_basket_count < 0
               OR post_4w_basket_count < 0
               OR pre_8w_purchase_day_count < 0
               OR during_purchase_day_count < 0
               OR post_4w_purchase_day_count < 0
               OR pre_8w_product_count < 0
               OR during_product_count < 0
               OR post_4w_product_count < 0
               OR (pre_8w_basket_count = 0 AND pre_8w_average_basket_value IS NOT NULL)
               OR (pre_8w_basket_count > 0 AND pre_8w_average_basket_value IS NULL)
               OR (during_basket_count = 0 AND during_average_basket_value IS NOT NULL)
               OR (during_basket_count > 0 AND during_average_basket_value IS NULL)
               OR (post_4w_basket_count = 0 AND post_4w_average_basket_value IS NOT NULL)
               OR (post_4w_basket_count > 0 AND post_4w_average_basket_value IS NULL)
               OR pre_sales_per_day IS NULL
               OR during_sales_per_day IS NULL
               OR post_sales_per_day IS NULL
               OR pre_baskets_per_day IS NULL
               OR during_baskets_per_day IS NULL
               OR post_baskets_per_day IS NULL
               OR pre_purchase_day_rate IS NULL
               OR during_purchase_day_rate IS NULL
               OR post_purchase_day_rate IS NULL
               OR pre_purchase_day_rate NOT BETWEEN 0 AND 1
               OR during_purchase_day_rate NOT BETWEEN 0 AND 1
               OR post_purchase_day_rate NOT BETWEEN 0 AND 1
        ) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM mart.campaign_pre_during_post_features;

-- Campaign Category Set이 고유해 Coupon 수만큼 거래가 증폭되지 않는지 확인한다.
WITH campaign_category_set AS (
    SELECT campaign, department, commodity_desc
    FROM mart.coupon_category_map
    GROUP BY campaign, department, commodity_desc
)
SELECT
    COUNT(*)::BIGINT AS campaign_category_set_row_count,
    COUNT(DISTINCT (campaign, department, commodity_desc))::BIGINT
        AS distinct_campaign_category_count,
    CASE
        WHEN COUNT(*) = COUNT(DISTINCT (campaign, department, commodity_desc)) THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM campaign_category_set;

-- 기존 Coupon Redemption Fact는 이번 구매행동 분석으로 변경되지 않아야 한다.
SELECT
    2318::BIGINT AS expected_redemption_row_count,
    COUNT(*)::BIGINT AS actual_redemption_row_count,
    CASE WHEN COUNT(*) = 2318 THEN 'PASS' ELSE 'FAIL' END AS status
FROM mart.fact_coupon_redemption;

/* ============================================================
   38. Historical Response 분석 기준 확정
   ============================================================ */

SELECT
    COUNT(*)::BIGINT AS observation_count,
    COUNT(DISTINCT household_key)::BIGINT AS distinct_household_count,
    COUNT(DISTINCT campaign)::BIGINT AS campaign_count,
    COUNT(*) FILTER (WHERE prior_campaign_count > 0)::BIGINT
        AS prior_campaign_exists_count,
    COUNT(*) FILTER (WHERE prior_campaign_count = 0)::BIGINT
        AS no_prior_campaign_count,
    COUNT(*) FILTER (WHERE prior_redeemed_campaign_count > 0)::BIGINT
        AS prior_redemption_exists_count,
    COUNT(*) FILTER (WHERE prior_redeemed_campaign_count = 0)::BIGINT
        AS no_prior_redemption_count,
    'INFO'::TEXT AS status
FROM mart.campaign_customer_response_features;

/* ============================================================
   39. Campaign 시점별 Historical Response Segment 생성
   ============================================================ */

BEGIN;

DROP TABLE IF EXISTS mart.campaign_historical_response_segments;

-- 현재 Campaign 결과가 아닌 시작 시점까지 확정된 과거 Feature만 Segment 정의에 사용한다.
CREATE TABLE mart.campaign_historical_response_segments AS
SELECT
    household_key,
    campaign,
    description,
    start_day,
    end_day,
    redeemed_flag,
    response_group,
    prior_campaign_count,
    prior_redemption_count,
    prior_redeemed_campaign_count,
    historical_campaign_redemption_rate,
    last_prior_redemption_day,
    days_since_last_prior_redemption,
    CASE
        WHEN prior_campaign_count = 0 THEN 'NO_HISTORY'
        WHEN prior_campaign_count > 0
         AND prior_redeemed_campaign_count = 0 THEN 'EXPOSED_NO_REDEMPTION'
        WHEN prior_redeemed_campaign_count = 1 THEN 'ONE_TIME_REDEEMER'
        WHEN prior_redeemed_campaign_count >= 2 THEN 'REPEAT_REDEEMER'
    END AS promotion_response_state
FROM mart.campaign_customer_response_features;

ALTER TABLE mart.campaign_historical_response_segments
    ADD CONSTRAINT pk_campaign_historical_response_segments
    PRIMARY KEY (household_key, campaign);

ALTER TABLE mart.campaign_historical_response_segments
    ADD CONSTRAINT chk_campaign_historical_response_state
    CHECK (promotion_response_state IN (
        'NO_HISTORY',
        'EXPOSED_NO_REDEMPTION',
        'ONE_TIME_REDEEMER',
        'REPEAT_REDEEMER'
    ));

COMMIT;

ANALYZE mart.campaign_historical_response_segments;

/* ============================================================
   40. Historical Segment별 현재 Campaign 반응 비교
   ============================================================ */

-- 현재 반응률은 항상 가구×Campaign 관측 수와 Redeemer 수를 함께 확인한다.
SELECT
    promotion_response_state,
    COUNT(*)::BIGINT AS observation_count,
    COUNT(DISTINCT household_key)::BIGINT AS distinct_household_count,
    COUNT(DISTINCT campaign)::BIGINT AS campaign_count,
    COUNT(*) FILTER (WHERE redeemed_flag)::BIGINT AS current_redeemer_count,
    COUNT(*) FILTER (WHERE NOT redeemed_flag)::BIGINT AS current_non_redeemer_count,
    COUNT(*) FILTER (WHERE redeemed_flag)::NUMERIC / NULLIF(COUNT(*), 0)
        AS current_redemption_rate,
    AVG(prior_campaign_count) AS average_prior_campaign_count,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY prior_campaign_count)
        AS median_prior_campaign_count,
    AVG(prior_redemption_count) AS average_prior_redemption_count,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY prior_redemption_count)
        AS median_prior_redemption_count,
    AVG(prior_redeemed_campaign_count) AS average_prior_redeemed_campaign_count,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY prior_redeemed_campaign_count)
        AS median_prior_redeemed_campaign_count,
    COUNT(historical_campaign_redemption_rate)::BIGINT
        AS historical_redemption_rate_non_null_count,
    AVG(historical_campaign_redemption_rate) AS average_historical_redemption_rate,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY historical_campaign_redemption_rate)
        AS median_historical_redemption_rate,
    COUNT(days_since_last_prior_redemption)::BIGINT
        AS prior_redemption_recency_non_null_count,
    AVG(days_since_last_prior_redemption) AS average_days_since_last_prior_redemption,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_since_last_prior_redemption)
        AS median_days_since_last_prior_redemption
FROM mart.campaign_historical_response_segments
GROUP BY promotion_response_state
ORDER BY CASE promotion_response_state
    WHEN 'NO_HISTORY' THEN 1
    WHEN 'EXPOSED_NO_REDEMPTION' THEN 2
    WHEN 'ONE_TIME_REDEEMER' THEN 3
    WHEN 'REPEAT_REDEEMER' THEN 4
END;

/* ============================================================
   41. Campaign Type별 Historical Segment 반응 비교
   ============================================================ */

SELECT
    description,
    promotion_response_state,
    COUNT(*)::BIGINT AS observation_count,
    COUNT(DISTINCT household_key)::BIGINT AS distinct_household_count,
    COUNT(DISTINCT campaign)::BIGINT AS campaign_count,
    COUNT(*) FILTER (WHERE redeemed_flag)::BIGINT AS current_redeemer_count,
    COUNT(*) FILTER (WHERE redeemed_flag)::NUMERIC / NULLIF(COUNT(*), 0)
        AS current_redemption_rate
FROM mart.campaign_historical_response_segments
GROUP BY description, promotion_response_state;

-- Campaign별 결과는 작은 표본의 순위가 아니라 Segment 패턴의 반복 여부를 확인한다.
SELECT
    campaign,
    description,
    promotion_response_state,
    COUNT(*)::BIGINT AS observation_count,
    COUNT(*) FILTER (WHERE redeemed_flag)::BIGINT AS current_redeemer_count,
    COUNT(*) FILTER (WHERE redeemed_flag)::NUMERIC / NULLIF(COUNT(*), 0)
        AS current_redemption_rate
FROM mart.campaign_historical_response_segments
GROUP BY campaign, description, promotion_response_state;

/* ============================================================
   42. Historical Response 품질 검증
   ============================================================ */

-- Grain·Campaign·현재 Response Label을 기존 Feature Table과 직접 대사한다.
WITH source_totals AS (
    SELECT
        COUNT(*)::BIGINT AS source_observation_count,
        COUNT(DISTINCT campaign)::BIGINT AS source_campaign_count,
        COUNT(*) FILTER (WHERE redeemed_flag)::BIGINT AS source_redeemer_count,
        COUNT(*) FILTER (WHERE NOT redeemed_flag)::BIGINT AS source_non_redeemer_count
    FROM mart.campaign_customer_response_features
),
segment_totals AS (
    SELECT
        COUNT(*)::BIGINT AS segment_observation_count,
        COUNT(DISTINCT campaign)::BIGINT AS segment_campaign_count,
        COUNT(*) FILTER (WHERE redeemed_flag)::BIGINT AS segment_redeemer_count,
        COUNT(*) FILTER (WHERE NOT redeemed_flag)::BIGINT AS segment_non_redeemer_count
    FROM mart.campaign_historical_response_segments
),
label_check AS (
    SELECT COUNT(*)::BIGINT AS label_mismatch_count
    FROM mart.campaign_customer_response_features AS source
    JOIN mart.campaign_historical_response_segments AS segment
        ON segment.household_key = source.household_key
       AND segment.campaign = source.campaign
    WHERE segment.redeemed_flag IS DISTINCT FROM source.redeemed_flag
       OR segment.response_group IS DISTINCT FROM source.response_group
)
SELECT
    source_observation_count,
    segment_observation_count,
    source_campaign_count,
    segment_campaign_count,
    source_redeemer_count,
    segment_redeemer_count,
    source_non_redeemer_count,
    segment_non_redeemer_count,
    label_mismatch_count,
    CASE
        WHEN source_observation_count = segment_observation_count
         AND source_campaign_count = segment_campaign_count
         AND source_redeemer_count = segment_redeemer_count
         AND source_non_redeemer_count = segment_non_redeemer_count
         AND label_mismatch_count = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM source_totals
CROSS JOIN segment_totals
CROSS JOIN label_check;

-- Segment 정의·과거 Count·Rate·Recency·시간누출을 한 번에 확인한다.
SELECT
    COUNT(*) FILTER (
        WHERE promotion_response_state IS NULL
           OR promotion_response_state NOT IN (
               'NO_HISTORY',
               'EXPOSED_NO_REDEMPTION',
               'ONE_TIME_REDEEMER',
               'REPEAT_REDEEMER'
           )
           OR (promotion_response_state = 'NO_HISTORY'
               AND prior_campaign_count <> 0)
           OR (promotion_response_state = 'EXPOSED_NO_REDEMPTION'
               AND NOT (prior_campaign_count > 0 AND prior_redeemed_campaign_count = 0))
           OR (promotion_response_state = 'ONE_TIME_REDEEMER'
               AND prior_redeemed_campaign_count <> 1)
           OR (promotion_response_state = 'REPEAT_REDEEMER'
               AND prior_redeemed_campaign_count < 2)
    )::BIGINT AS segment_definition_issue_count,
    COUNT(*) FILTER (
        WHERE prior_campaign_count < 0
           OR prior_redemption_count < 0
           OR prior_redeemed_campaign_count < 0
           OR prior_redeemed_campaign_count > prior_campaign_count
           OR (prior_redeemed_campaign_count > 0 AND prior_redemption_count = 0)
           OR (prior_redemption_count > 0 AND prior_redeemed_campaign_count = 0)
    )::BIGINT AS historical_count_issue_count,
    COUNT(*) FILTER (
        WHERE (promotion_response_state = 'NO_HISTORY'
               AND historical_campaign_redemption_rate IS NOT NULL)
           OR (promotion_response_state = 'EXPOSED_NO_REDEMPTION'
               AND historical_campaign_redemption_rate IS DISTINCT FROM 0::NUMERIC)
           OR (promotion_response_state IN ('ONE_TIME_REDEEMER', 'REPEAT_REDEEMER')
               AND (historical_campaign_redemption_rate IS NULL
                    OR historical_campaign_redemption_rate <= 0
                    OR historical_campaign_redemption_rate > 1))
    )::BIGINT AS historical_rate_issue_count,
    COUNT(*) FILTER (
        WHERE (promotion_response_state IN ('NO_HISTORY', 'EXPOSED_NO_REDEMPTION')
               AND (last_prior_redemption_day IS NOT NULL
                    OR days_since_last_prior_redemption IS NOT NULL))
           OR (promotion_response_state IN ('ONE_TIME_REDEEMER', 'REPEAT_REDEEMER')
               AND (last_prior_redemption_day IS NULL
                    OR days_since_last_prior_redemption IS NULL
                    OR days_since_last_prior_redemption < 1))
    )::BIGINT AS historical_recency_issue_count,
    COUNT(*) FILTER (
        WHERE last_prior_redemption_day >= start_day
    )::BIGINT AS future_information_issue_count,
    CASE
        WHEN COUNT(*) FILTER (
            WHERE promotion_response_state IS NULL
               OR promotion_response_state NOT IN (
                   'NO_HISTORY',
                   'EXPOSED_NO_REDEMPTION',
                   'ONE_TIME_REDEEMER',
                   'REPEAT_REDEEMER'
               )
               OR (promotion_response_state = 'NO_HISTORY'
                   AND prior_campaign_count <> 0)
               OR (promotion_response_state = 'EXPOSED_NO_REDEMPTION'
                   AND NOT (prior_campaign_count > 0 AND prior_redeemed_campaign_count = 0))
               OR (promotion_response_state = 'ONE_TIME_REDEEMER'
                   AND prior_redeemed_campaign_count <> 1)
               OR (promotion_response_state = 'REPEAT_REDEEMER'
                   AND prior_redeemed_campaign_count < 2)
               OR prior_campaign_count < 0
               OR prior_redemption_count < 0
               OR prior_redeemed_campaign_count < 0
               OR prior_redeemed_campaign_count > prior_campaign_count
               OR (prior_redeemed_campaign_count > 0 AND prior_redemption_count = 0)
               OR (prior_redemption_count > 0 AND prior_redeemed_campaign_count = 0)
               OR (promotion_response_state = 'NO_HISTORY'
                   AND historical_campaign_redemption_rate IS NOT NULL)
               OR (promotion_response_state = 'EXPOSED_NO_REDEMPTION'
                   AND historical_campaign_redemption_rate IS DISTINCT FROM 0::NUMERIC)
               OR (promotion_response_state IN ('ONE_TIME_REDEEMER', 'REPEAT_REDEEMER')
                   AND (historical_campaign_redemption_rate IS NULL
                        OR historical_campaign_redemption_rate <= 0
                        OR historical_campaign_redemption_rate > 1))
               OR (promotion_response_state IN ('NO_HISTORY', 'EXPOSED_NO_REDEMPTION')
                   AND (last_prior_redemption_day IS NOT NULL
                        OR days_since_last_prior_redemption IS NOT NULL))
               OR (promotion_response_state IN ('ONE_TIME_REDEEMER', 'REPEAT_REDEEMER')
                   AND (last_prior_redemption_day IS NULL
                        OR days_since_last_prior_redemption IS NULL
                        OR days_since_last_prior_redemption < 1))
               OR last_prior_redemption_day >= start_day
        ) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM mart.campaign_historical_response_segments;

-- 네 Segment 합과 prior Campaign 경험 유무를 기존 Feature와 대사한다.
WITH source_exposure AS (
    SELECT
        COUNT(*) FILTER (WHERE prior_campaign_count = 0)::BIGINT
            AS source_no_prior_campaign_count,
        COUNT(*) FILTER (WHERE prior_campaign_count > 0)::BIGINT
            AS source_prior_campaign_count
    FROM mart.campaign_customer_response_features
),
segment_exposure AS (
    SELECT
        COUNT(*)::BIGINT AS segment_total_count,
        COUNT(*) FILTER (WHERE promotion_response_state = 'NO_HISTORY')::BIGINT
            AS segment_no_prior_campaign_count,
        COUNT(*) FILTER (
            WHERE promotion_response_state IN (
                'EXPOSED_NO_REDEMPTION',
                'ONE_TIME_REDEEMER',
                'REPEAT_REDEEMER'
            )
        )::BIGINT AS segment_prior_campaign_count
    FROM mart.campaign_historical_response_segments
)
SELECT
    source_no_prior_campaign_count,
    segment_no_prior_campaign_count,
    source_prior_campaign_count,
    segment_prior_campaign_count,
    segment_total_count,
    segment_no_prior_campaign_count + segment_prior_campaign_count
        AS segment_state_sum,
    CASE
        WHEN source_no_prior_campaign_count = segment_no_prior_campaign_count
         AND source_prior_campaign_count = segment_prior_campaign_count
         AND segment_total_count =
             segment_no_prior_campaign_count + segment_prior_campaign_count THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM source_exposure
CROSS JOIN segment_exposure;

-- Segment별 현재 반응률은 0~1이며 Redeemer 수가 관측 수를 넘을 수 없다.
WITH segment_response AS (
    SELECT
        promotion_response_state,
        COUNT(*)::BIGINT AS observation_count,
        COUNT(*) FILTER (WHERE redeemed_flag)::BIGINT AS current_redeemer_count,
        COUNT(*) FILTER (WHERE redeemed_flag)::NUMERIC / NULLIF(COUNT(*), 0)
            AS current_redemption_rate
    FROM mart.campaign_historical_response_segments
    GROUP BY promotion_response_state
)
SELECT
    COUNT(*) FILTER (
        WHERE current_redeemer_count > observation_count
           OR current_redemption_rate NOT BETWEEN 0 AND 1
    )::BIGINT AS segment_response_issue_count,
    CASE
        WHEN COUNT(*) FILTER (
            WHERE current_redeemer_count > observation_count
               OR current_redemption_rate NOT BETWEEN 0 AND 1
        ) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM segment_response;

/* ============================================================
   43. 최종 CRM Priority 50가구 적재 준비
   ============================================================ */

DROP TABLE IF EXISTS mart.crm_priority_final;

CREATE TABLE mart.crm_priority_final (
    priority_rank                           INTEGER NOT NULL,
    household_key                           BIGINT NOT NULL,
    reference_week                          INTEGER NOT NULL,

    predicted_no_purchase_probability       DOUBLE PRECISION NOT NULL,
    risk_rank                               INTEGER NOT NULL,
    risk_rank_within_high_economic_value    NUMERIC(10, 0) NOT NULL,

    pre_window_monetary_26w                 NUMERIC(14, 2) NOT NULL,
    economic_value_rank                     NUMERIC(10, 0) NOT NULL,
    economic_value_percentile               DOUBLE PRECISION NOT NULL,
    is_high_economic_value_top20             BOOLEAN NOT NULL,

    pre_window_frequency_26w                NUMERIC(10, 0) NOT NULL,
    pre_window_recency_weeks_26w            NUMERIC(10, 0) NOT NULL,
    pre_window_rfm_value_index_26w           DOUBLE PRECISION NOT NULL,

    value_state                             TEXT NOT NULL,
    activity_state                          TEXT NOT NULL,
    customer_state                          TEXT NOT NULL,

    prior4_valid_basket_count               INTEGER NOT NULL,
    recent4_valid_basket_count              INTEGER NOT NULL,
    prior4_sales                            NUMERIC(14, 2) NOT NULL,
    recent4_sales                           NUMERIC(14, 2) NOT NULL,

    CONSTRAINT pk_crm_priority_final
        PRIMARY KEY (household_key),

    CONSTRAINT uq_crm_priority_final_rank
        UNIQUE (priority_rank)
);

/* ============================================================
   44. 최종 CRM Priority 적재 품질 검증
   ============================================================ */

-- 44-01. 행 수·고유 고객 수·순위 범위
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT household_key) AS distinct_household_count,
    COUNT(DISTINCT priority_rank) AS distinct_priority_rank_count,
    MIN(priority_rank) AS min_priority_rank,
    MAX(priority_rank) AS max_priority_rank
FROM mart.crm_priority_final;


/* ------------------------------------------------------------
   44-02. 기준주차 확인
   ------------------------------------------------------------ */

SELECT
    reference_week,
    COUNT(*) AS household_count
FROM mart.crm_priority_final
GROUP BY reference_week
ORDER BY reference_week;


/* ------------------------------------------------------------
   44-03. NULL 확인
   ------------------------------------------------------------ */

SELECT
    COUNT(*) FILTER (WHERE priority_rank IS NULL) AS priority_rank_null,
    COUNT(*) FILTER (WHERE household_key IS NULL) AS household_key_null,
    COUNT(*) FILTER (WHERE reference_week IS NULL) AS reference_week_null,
    COUNT(*) FILTER (
        WHERE predicted_no_purchase_probability IS NULL
    ) AS predicted_probability_null,
    COUNT(*) FILTER (
        WHERE pre_window_monetary_26w IS NULL
    ) AS monetary_null
FROM mart.crm_priority_final;


/* ------------------------------------------------------------
   44-04. 확률·순위·가치 범위 확인
   ------------------------------------------------------------ */

SELECT
    MIN(predicted_no_purchase_probability) AS min_probability,
    MAX(predicted_no_purchase_probability) AS max_probability,

    MIN(risk_rank_within_high_economic_value) AS min_value_group_risk_rank,
    MAX(risk_rank_within_high_economic_value) AS max_value_group_risk_rank,

    MIN(pre_window_monetary_26w) AS min_monetary_26w,
    MAX(pre_window_monetary_26w) AS max_monetary_26w,

    MIN(economic_value_percentile) AS min_economic_value_percentile,
    MAX(economic_value_percentile) AS max_economic_value_percentile
FROM mart.crm_priority_final;


/* ------------------------------------------------------------
   44-05. 최종 50가구 조건 확인
   ------------------------------------------------------------ */

SELECT
    COUNT(*) AS total_households,
    COUNT(*) FILTER (
        WHERE is_high_economic_value_top20 = TRUE
    ) AS high_economic_value_households,

    COUNT(*) FILTER (
        WHERE risk_rank_within_high_economic_value BETWEEN 1 AND 50
    ) AS priority_rank_within_value_group_households,

    COUNT(*) FILTER (
        WHERE predicted_no_purchase_probability < 0
           OR predicted_no_purchase_probability > 1
    ) AS invalid_probability_count
FROM mart.crm_priority_final;


/* ------------------------------------------------------------
   44-06. HOUSEHOLD_KEY 중복 확인
   ------------------------------------------------------------ */

SELECT
    household_key,
    COUNT(*) AS row_count
FROM mart.crm_priority_final
GROUP BY household_key
HAVING COUNT(*) > 1;


/* ------------------------------------------------------------
   44-07. Priority Rank 누락·중복 확인
   ------------------------------------------------------------ */

WITH expected_rank AS (
    SELECT generate_series(1, 50) AS priority_rank
)
SELECT
    e.priority_rank AS missing_priority_rank
FROM expected_rank e
LEFT JOIN mart.crm_priority_final c
    ON c.priority_rank = e.priority_rank
WHERE c.priority_rank IS NULL
ORDER BY e.priority_rank;


/* ------------------------------------------------------------
   44-08. 적재 결과 샘플
   ------------------------------------------------------------ */

SELECT
    priority_rank,
    household_key,
    reference_week,
    pre_window_monetary_26w,
    predicted_no_purchase_probability,
    risk_rank_within_high_economic_value,
    economic_value_percentile,
    activity_state,
    customer_state
FROM mart.crm_priority_final
ORDER BY priority_rank
LIMIT 10;


ANALYZE mart.crm_priority_final;

/* ============================================================
   45. CRM Priority 기준시점 확정
   ============================================================ */

-- 최종 CRM Priority는 mart.crm_priority_final의 Week 98 결과를 그대로 사용한다.
SELECT
    COUNT(*)::BIGINT AS priority_row_count,
    COUNT(DISTINCT household_key)::BIGINT AS distinct_household_count,
    COUNT(DISTINCT reference_week)::BIGINT AS distinct_reference_week_count,
    MIN(reference_week) AS minimum_reference_week,
    MAX(reference_week) AS maximum_reference_week
FROM mart.crm_priority_final;

-- crm_as_of_day는 주차를 일수로 환산하지 않고 기존 reference_end_day에서 구한다.
SELECT
    COUNT(*)::BIGINT AS priority_household_count,
    COUNT(reference.reference_end_day)::BIGINT AS mapped_reference_end_day_count,
    COUNT(DISTINCT reference.reference_end_day)::BIGINT AS distinct_crm_as_of_day_count,
    MIN(reference.reference_end_day) AS minimum_crm_as_of_day,
    MAX(reference.reference_end_day) AS maximum_crm_as_of_day
FROM mart.crm_priority_final AS priority
LEFT JOIN mart.household_reference_week AS reference
    ON reference.household_key = priority.household_key
   AND reference.reference_week = priority.reference_week;

/* ============================================================
   46. CRM 기준시점 Historical Response Snapshot 생성
   ============================================================ */

DROP TABLE IF EXISTS mart.crm_promotion_actionability;
DROP TABLE IF EXISTS mart.crm_historical_response_snapshot;

-- Redemption을 먼저 household × campaign으로 축소하여 Campaign 수가 상환 건수만큼
-- 증폭되지 않게 한다. CRM 기준일까지 종료된 Campaign과 그 안의 상환만 사용한다.
CREATE TABLE mart.crm_historical_response_snapshot AS
WITH priority_reference AS MATERIALIZED (
    SELECT
        priority.household_key,
        priority.reference_week,
        reference.reference_end_day AS crm_as_of_day
    FROM mart.crm_priority_final AS priority
    JOIN mart.household_reference_week AS reference
        ON reference.household_key = priority.household_key
       AND reference.reference_week = priority.reference_week
),
historical_campaign_relation AS MATERIALIZED (
    SELECT
        priority.household_key,
        recipient.campaign,
        priority.crm_as_of_day
    FROM priority_reference AS priority
    JOIN mart.fact_campaign_household AS recipient
        ON recipient.household_key = priority.household_key
    JOIN mart.dim_campaign AS campaign
        ON campaign.campaign = recipient.campaign
       AND campaign.end_day <= priority.crm_as_of_day
),
redemption_by_campaign AS MATERIALIZED (
    SELECT
        relation.household_key,
        relation.campaign,
        COUNT(*)::BIGINT AS campaign_redemption_count,
        MAX(redemption.redemption_day) AS campaign_last_redemption_day
    FROM historical_campaign_relation AS relation
    JOIN mart.fact_coupon_redemption AS redemption
        ON redemption.household_key = relation.household_key
       AND redemption.campaign = relation.campaign
       AND redemption.redemption_day <= relation.crm_as_of_day
    GROUP BY
        relation.household_key,
        relation.campaign
),
household_history AS (
    SELECT
        relation.household_key,
        COUNT(*)::BIGINT AS historical_campaign_count,
        COALESCE(SUM(redemption.campaign_redemption_count), 0)::BIGINT
            AS historical_redemption_count,
        COUNT(redemption.campaign)::BIGINT AS historical_redeemed_campaign_count,
        MAX(redemption.campaign_last_redemption_day)
            AS last_historical_redemption_day
    FROM historical_campaign_relation AS relation
    LEFT JOIN redemption_by_campaign AS redemption
        ON redemption.household_key = relation.household_key
       AND redemption.campaign = relation.campaign
    GROUP BY relation.household_key
),
features AS (
    SELECT
        priority.household_key,
        priority.reference_week,
        priority.crm_as_of_day,
        COALESCE(history.historical_campaign_count, 0)::BIGINT
            AS historical_campaign_count,
        COALESCE(history.historical_redemption_count, 0)::BIGINT
            AS historical_redemption_count,
        COALESCE(history.historical_redeemed_campaign_count, 0)::BIGINT
            AS historical_redeemed_campaign_count,
        COALESCE(history.historical_redeemed_campaign_count, 0)::NUMERIC
            / NULLIF(COALESCE(history.historical_campaign_count, 0), 0)
            AS historical_campaign_redemption_rate,
        history.last_historical_redemption_day,
        CASE
            WHEN history.last_historical_redemption_day IS NOT NULL
                THEN priority.crm_as_of_day - history.last_historical_redemption_day
        END::INTEGER AS days_since_last_historical_redemption
    FROM priority_reference AS priority
    LEFT JOIN household_history AS history
        ON history.household_key = priority.household_key
)
SELECT
    household_key,
    reference_week,
    crm_as_of_day,
    historical_campaign_count,
    historical_redemption_count,
    historical_redeemed_campaign_count,
    historical_campaign_redemption_rate,
    last_historical_redemption_day,
    days_since_last_historical_redemption,
    CASE
        WHEN historical_campaign_count = 0 THEN 'NO_HISTORY'
        WHEN historical_campaign_count > 0
         AND historical_redeemed_campaign_count = 0 THEN 'EXPOSED_NO_REDEMPTION'
        WHEN historical_redeemed_campaign_count = 1 THEN 'ONE_TIME_REDEEMER'
        WHEN historical_redeemed_campaign_count >= 2 THEN 'REPEAT_REDEEMER'
    END::TEXT AS promotion_response_state
FROM features;

ALTER TABLE mart.crm_historical_response_snapshot
    ADD CONSTRAINT pk_crm_historical_response_snapshot
        PRIMARY KEY (household_key),
    ADD CONSTRAINT chk_crm_historical_response_snapshot_state
        CHECK (promotion_response_state IN (
            'NO_HISTORY',
            'EXPOSED_NO_REDEMPTION',
            'ONE_TIME_REDEEMER',
            'REPEAT_REDEEMER'
        ));

ANALYZE mart.crm_historical_response_snapshot;

-- Week 98 Priority 고객의 CRM 기준시점 Historical Segment 분포이다.
SELECT
    promotion_response_state,
    COUNT(*)::BIGINT AS household_count
FROM mart.crm_historical_response_snapshot
GROUP BY promotion_response_state
ORDER BY CASE promotion_response_state
    WHEN 'NO_HISTORY' THEN 1
    WHEN 'EXPOSED_NO_REDEMPTION' THEN 2
    WHEN 'ONE_TIME_REDEEMER' THEN 3
    WHEN 'REPEAT_REDEEMER' THEN 4
END;

/* ============================================================
   47. CRM Priority·Historical Response 결합 확인
   ============================================================ */

WITH joined AS (
    SELECT
        priority.household_key,
        history.household_key AS history_household_key
    FROM mart.crm_priority_final AS priority
    LEFT JOIN mart.crm_historical_response_snapshot AS history
        ON history.household_key = priority.household_key
)
SELECT
    (SELECT COUNT(*)::BIGINT FROM mart.crm_priority_final)
        AS crm_priority_row_count,
    (SELECT COUNT(*)::BIGINT FROM mart.crm_historical_response_snapshot)
        AS historical_snapshot_row_count,
    COUNT(*)::BIGINT AS joined_row_count,
    COUNT(DISTINCT household_key)::BIGINT AS joined_distinct_household_count,
    COUNT(*) FILTER (WHERE history_household_key IS NULL)::BIGINT
        AS unmatched_history_count
FROM joined;

/* ============================================================
   48. CRM Promotion Actionability 생성
   ============================================================ */

-- 기존 Priority 값과 순위를 그대로 보존하고 Historical Response는 접근방식 설명에만 쓴다.
CREATE TABLE mart.crm_promotion_actionability AS
SELECT
    priority.priority_rank,
    priority.household_key,
    priority.reference_week,
    priority.predicted_no_purchase_probability,
    priority.risk_rank,
    priority.risk_rank_within_high_economic_value,
    priority.pre_window_monetary_26w,
    priority.economic_value_rank,
    priority.economic_value_percentile,
    priority.is_high_economic_value_top20,
    priority.pre_window_frequency_26w,
    priority.pre_window_recency_weeks_26w,
    priority.pre_window_rfm_value_index_26w,
    priority.value_state,
    priority.activity_state,
    priority.customer_state,
    priority.prior4_valid_basket_count,
    priority.recent4_valid_basket_count,
    priority.prior4_sales,
    priority.recent4_sales,
    history.crm_as_of_day,
    history.historical_campaign_count,
    history.historical_redemption_count,
    history.historical_redeemed_campaign_count,
    history.historical_campaign_redemption_rate,
    history.last_historical_redemption_day,
    history.days_since_last_historical_redemption,
    history.promotion_response_state,
    CASE history.promotion_response_state
        WHEN 'REPEAT_REDEEMER' THEN 'STRONG'
        WHEN 'ONE_TIME_REDEEMER' THEN 'MODERATE'
        WHEN 'EXPOSED_NO_REDEMPTION' THEN 'LOW_OBSERVED_RESPONSE'
        WHEN 'NO_HISTORY' THEN 'UNKNOWN'
    END::TEXT AS promotion_evidence_level,
    CASE history.promotion_response_state
        WHEN 'REPEAT_REDEEMER' THEN 'COUPON_PRIORITY'
        WHEN 'ONE_TIME_REDEEMER' THEN 'COUPON_TEST'
        WHEN 'NO_HISTORY' THEN 'TEST_AND_LEARN'
        WHEN 'EXPOSED_NO_REDEMPTION' THEN 'ALTERNATIVE_INTERVENTION'
    END::TEXT AS promotion_actionability
FROM mart.crm_priority_final AS priority
JOIN mart.crm_historical_response_snapshot AS history
    ON history.household_key = priority.household_key;

ALTER TABLE mart.crm_promotion_actionability
    ADD CONSTRAINT pk_crm_promotion_actionability PRIMARY KEY (household_key),
    ADD CONSTRAINT uq_crm_promotion_actionability_rank UNIQUE (priority_rank),
    ADD CONSTRAINT chk_crm_promotion_evidence_level CHECK (
        promotion_evidence_level IN (
            'STRONG', 'MODERATE', 'LOW_OBSERVED_RESPONSE', 'UNKNOWN'
        )
    ),
    ADD CONSTRAINT chk_crm_promotion_actionability CHECK (
        promotion_actionability IN (
            'COUPON_PRIORITY',
            'COUPON_TEST',
            'TEST_AND_LEARN',
            'ALTERNATIVE_INTERVENTION'
        )
    );

ANALYZE mart.crm_promotion_actionability;

/* ============================================================
   49. CRM Promotion Actionability 결과 요약
   ============================================================ */

-- 최종 Priority 고객의 Historical Segment 분포이다.
SELECT
    promotion_response_state,
    COUNT(*)::BIGINT AS household_count,
    COUNT(*)::NUMERIC
        / NULLIF((SELECT COUNT(*) FROM mart.crm_promotion_actionability), 0)
        AS share_of_priority_households
FROM mart.crm_promotion_actionability
GROUP BY promotion_response_state
ORDER BY CASE promotion_response_state
    WHEN 'NO_HISTORY' THEN 1
    WHEN 'EXPOSED_NO_REDEMPTION' THEN 2
    WHEN 'ONE_TIME_REDEEMER' THEN 3
    WHEN 'REPEAT_REDEEMER' THEN 4
END;

-- Actionability는 자동발송 결정이 아니라 CRM 담당자의 우선 검토 방향이다.
SELECT
    promotion_actionability,
    promotion_evidence_level,
    COUNT(*)::BIGINT AS household_count,
    COUNT(*)::NUMERIC
        / NULLIF((SELECT COUNT(*) FROM mart.crm_promotion_actionability), 0)
        AS share_of_priority_households
FROM mart.crm_promotion_actionability
GROUP BY promotion_actionability, promotion_evidence_level
ORDER BY CASE promotion_actionability
    WHEN 'COUPON_PRIORITY' THEN 1
    WHEN 'COUPON_TEST' THEN 2
    WHEN 'TEST_AND_LEARN' THEN 3
    WHEN 'ALTERNATIVE_INTERVENTION' THEN 4
END;

-- 큰 값의 영향을 함께 확인할 수 있도록 평균과 중앙값을 같이 출력한다.
SELECT
    promotion_actionability,
    COUNT(*)::BIGINT AS household_count,
    AVG(predicted_no_purchase_probability) AS mean_predicted_no_purchase_probability,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY predicted_no_purchase_probability
    ) AS median_predicted_no_purchase_probability,
    AVG(pre_window_monetary_26w) AS mean_pre_window_monetary_26w,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY pre_window_monetary_26w
    ) AS median_pre_window_monetary_26w,
    AVG(historical_campaign_count) AS mean_historical_campaign_count,
    AVG(historical_redeemed_campaign_count)
        AS mean_historical_redeemed_campaign_count,
    COUNT(historical_campaign_redemption_rate)::BIGINT
        AS historical_campaign_redemption_rate_non_null_count,
    AVG(historical_campaign_redemption_rate)
        AS mean_historical_campaign_redemption_rate,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY historical_campaign_redemption_rate
    ) AS median_historical_campaign_redemption_rate
FROM mart.crm_promotion_actionability
GROUP BY promotion_actionability
ORDER BY CASE promotion_actionability
    WHEN 'COUPON_PRIORITY' THEN 1
    WHEN 'COUPON_TEST' THEN 2
    WHEN 'TEST_AND_LEARN' THEN 3
    WHEN 'ALTERNATIVE_INTERVENTION' THEN 4
END;

-- 상환 Recency의 NULL을 0이나 임의의 큰 값으로 대체하지 않는다.
SELECT
    promotion_response_state,
    COUNT(*)::BIGINT AS household_count,
    COUNT(days_since_last_historical_redemption)::BIGINT AS recency_non_null_count,
    AVG(days_since_last_historical_redemption) AS mean_recency_days,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY days_since_last_historical_redemption
    ) AS median_recency_days
FROM mart.crm_promotion_actionability
GROUP BY promotion_response_state
ORDER BY CASE promotion_response_state
    WHEN 'NO_HISTORY' THEN 1
    WHEN 'EXPOSED_NO_REDEMPTION' THEN 2
    WHEN 'ONE_TIME_REDEEMER' THEN 3
    WHEN 'REPEAT_REDEEMER' THEN 4
END;

-- 기존 priority_rank를 변경하지 않은 최종 50가구 상세 결과이다.
SELECT
    priority_rank,
    household_key,
    predicted_no_purchase_probability,
    pre_window_monetary_26w,
    risk_rank_within_high_economic_value,
    historical_campaign_count,
    historical_redemption_count,
    historical_redeemed_campaign_count,
    historical_campaign_redemption_rate,
    days_since_last_historical_redemption,
    promotion_response_state,
    promotion_evidence_level,
    promotion_actionability
FROM mart.crm_promotion_actionability
ORDER BY priority_rank;

/* ============================================================
   50. CRM Promotion Actionability 품질 검증
   ============================================================ */

WITH
snapshot_counts AS (
    SELECT
        COUNT(*)::BIGINT AS row_count,
        COUNT(DISTINCT household_key)::BIGINT AS household_count,
        (COUNT(*) - COUNT(DISTINCT household_key))::BIGINT AS duplicate_count
    FROM mart.crm_historical_response_snapshot
),
actionability_counts AS (
    SELECT
        COUNT(*)::BIGINT AS row_count,
        COUNT(DISTINCT household_key)::BIGINT AS household_count,
        (COUNT(*) - COUNT(DISTINCT household_key))::BIGINT
            AS household_duplicate_count,
        (COUNT(*) - COUNT(DISTINCT priority_rank))::BIGINT
            AS priority_rank_duplicate_count
    FROM mart.crm_promotion_actionability
),
priority_counts AS (
    SELECT COUNT(*)::BIGINT AS row_count
    FROM mart.crm_priority_final
),
priority_preservation_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.crm_priority_final AS source
    FULL JOIN mart.crm_promotion_actionability AS result
        ON result.household_key = source.household_key
    WHERE source.household_key IS NULL
       OR result.household_key IS NULL
       OR result.priority_rank IS DISTINCT FROM source.priority_rank
       OR result.reference_week IS DISTINCT FROM source.reference_week
       OR result.predicted_no_purchase_probability
            IS DISTINCT FROM source.predicted_no_purchase_probability
       OR result.risk_rank IS DISTINCT FROM source.risk_rank
       OR result.risk_rank_within_high_economic_value
            IS DISTINCT FROM source.risk_rank_within_high_economic_value
       OR result.pre_window_monetary_26w
            IS DISTINCT FROM source.pre_window_monetary_26w
       OR result.economic_value_rank IS DISTINCT FROM source.economic_value_rank
       OR result.economic_value_percentile
            IS DISTINCT FROM source.economic_value_percentile
       OR result.is_high_economic_value_top20
            IS DISTINCT FROM source.is_high_economic_value_top20
),
snapshot_logic_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.crm_historical_response_snapshot
    WHERE crm_as_of_day IS NULL
       OR historical_campaign_count < 0
       OR historical_redemption_count < 0
       OR historical_redeemed_campaign_count < 0
       OR historical_redeemed_campaign_count > historical_campaign_count
       OR (historical_redeemed_campaign_count > 0
           AND historical_redemption_count = 0)
       OR (historical_redemption_count > 0
           AND historical_redeemed_campaign_count = 0)
       OR promotion_response_state IS NULL
       OR promotion_response_state NOT IN (
            'NO_HISTORY',
            'EXPOSED_NO_REDEMPTION',
            'ONE_TIME_REDEEMER',
            'REPEAT_REDEEMER'
       )
       OR (promotion_response_state = 'NO_HISTORY'
           AND (historical_campaign_count <> 0
                OR historical_campaign_redemption_rate IS NOT NULL))
       OR (promotion_response_state = 'EXPOSED_NO_REDEMPTION'
           AND (historical_campaign_count <= 0
                OR historical_redeemed_campaign_count <> 0
                OR historical_campaign_redemption_rate IS DISTINCT FROM 0::NUMERIC))
       OR (promotion_response_state = 'ONE_TIME_REDEEMER'
           AND (historical_redeemed_campaign_count <> 1
                OR historical_campaign_redemption_rate <= 0
                OR historical_campaign_redemption_rate > 1))
       OR (promotion_response_state = 'REPEAT_REDEEMER'
           AND (historical_redeemed_campaign_count < 2
                OR historical_campaign_redemption_rate <= 0
                OR historical_campaign_redemption_rate > 1))
       OR (promotion_response_state IN ('NO_HISTORY', 'EXPOSED_NO_REDEMPTION')
           AND (last_historical_redemption_day IS NOT NULL
                OR days_since_last_historical_redemption IS NOT NULL))
       OR (promotion_response_state IN ('ONE_TIME_REDEEMER', 'REPEAT_REDEEMER')
           AND (last_historical_redemption_day IS NULL
                OR days_since_last_historical_redemption IS NULL
                OR days_since_last_historical_redemption < 0))
),
as_of_issues AS (
    SELECT
        COUNT(*) FILTER (WHERE crm_as_of_day IS NULL)::BIGINT
            + CASE WHEN COUNT(DISTINCT crm_as_of_day) = 1 THEN 0 ELSE 1 END
            AS issue_count
    FROM mart.crm_historical_response_snapshot
),
historical_campaign_leakage AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.crm_historical_response_snapshot AS snapshot
    WHERE snapshot.historical_campaign_count IS DISTINCT FROM (
        SELECT COUNT(*)::BIGINT
        FROM mart.fact_campaign_household AS recipient
        JOIN mart.dim_campaign AS campaign
            ON campaign.campaign = recipient.campaign
        WHERE recipient.household_key = snapshot.household_key
          AND campaign.end_day <= snapshot.crm_as_of_day
    )
),
historical_redemption_leakage AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.crm_historical_response_snapshot AS snapshot
    JOIN mart.fact_campaign_household AS recipient
        ON recipient.household_key = snapshot.household_key
    JOIN mart.dim_campaign AS campaign
        ON campaign.campaign = recipient.campaign
       AND campaign.end_day <= snapshot.crm_as_of_day
    JOIN mart.fact_coupon_redemption AS redemption
        ON redemption.household_key = recipient.household_key
       AND redemption.campaign = recipient.campaign
    WHERE redemption.redemption_day > snapshot.crm_as_of_day
),
recipient_relation_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.crm_historical_response_snapshot AS snapshot
    JOIN mart.fact_coupon_redemption AS redemption
        ON redemption.household_key = snapshot.household_key
       AND redemption.redemption_day <= snapshot.crm_as_of_day
    JOIN mart.dim_campaign AS campaign
        ON campaign.campaign = redemption.campaign
       AND campaign.end_day <= snapshot.crm_as_of_day
    LEFT JOIN mart.fact_campaign_household AS recipient
        ON recipient.household_key = redemption.household_key
       AND recipient.campaign = redemption.campaign
    WHERE recipient.household_key IS NULL
),
mapping_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.crm_promotion_actionability
    WHERE promotion_evidence_level IS DISTINCT FROM CASE promotion_response_state
            WHEN 'REPEAT_REDEEMER' THEN 'STRONG'
            WHEN 'ONE_TIME_REDEEMER' THEN 'MODERATE'
            WHEN 'EXPOSED_NO_REDEMPTION' THEN 'LOW_OBSERVED_RESPONSE'
            WHEN 'NO_HISTORY' THEN 'UNKNOWN'
        END
       OR promotion_actionability IS DISTINCT FROM CASE promotion_response_state
            WHEN 'REPEAT_REDEEMER' THEN 'COUPON_PRIORITY'
            WHEN 'ONE_TIME_REDEEMER' THEN 'COUPON_TEST'
            WHEN 'NO_HISTORY' THEN 'TEST_AND_LEARN'
            WHEN 'EXPOSED_NO_REDEMPTION' THEN 'ALTERNATIVE_INTERVENTION'
        END
),
reference_week_issues AS (
    SELECT CASE
        WHEN COUNT(DISTINCT result.reference_week) =
             (SELECT COUNT(DISTINCT reference_week) FROM mart.crm_priority_final)
         AND MIN(result.reference_week) =
             (SELECT MIN(reference_week) FROM mart.crm_priority_final)
         AND MAX(result.reference_week) =
             (SELECT MAX(reference_week) FROM mart.crm_priority_final)
            THEN 0::BIGINT
        ELSE 1::BIGINT
    END AS issue_count
    FROM mart.crm_promotion_actionability AS result
),
segment_sum_issues AS (
    SELECT ABS(
        COUNT(*) - COUNT(*) FILTER (
            WHERE promotion_actionability IN (
                'COUPON_PRIORITY',
                'COUPON_TEST',
                'TEST_AND_LEARN',
                'ALTERNATIVE_INTERVENTION'
            )
        )
    )::BIGINT AS issue_count
    FROM mart.crm_promotion_actionability
)
SELECT
    check_name,
    CASE WHEN issue_count = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
    issue_count,
    detail
FROM (
    SELECT 'snapshot_row_count_reconciliation'::TEXT AS check_name,
           ABS(snapshot.row_count - priority.row_count)::BIGINT AS issue_count,
           'Snapshot 행 수 = 기존 CRM Priority 행 수'::TEXT AS detail
    FROM snapshot_counts AS snapshot CROSS JOIN priority_counts AS priority
    UNION ALL
    SELECT 'snapshot_household_grain', snapshot.duplicate_count,
           'Snapshot household_key 중복 0'
    FROM snapshot_counts AS snapshot
    UNION ALL
    SELECT 'actionability_row_count_reconciliation',
           ABS(actionability.row_count - priority.row_count)::BIGINT,
           'Actionability 행 수 = 기존 CRM Priority 행 수'
    FROM actionability_counts AS actionability CROSS JOIN priority_counts AS priority
    UNION ALL
    SELECT 'actionability_household_grain', household_duplicate_count,
           'Actionability household_key 중복 0'
    FROM actionability_counts
    UNION ALL
    SELECT 'actionability_priority_rank_unique', priority_rank_duplicate_count,
           '기존 priority_rank 중복 0'
    FROM actionability_counts
    UNION ALL
    SELECT 'crm_priority_value_preservation', issue_count,
           'Priority Rank·Risk·Monetary·기준주차 값 보존'
    FROM priority_preservation_issues
    UNION ALL
    SELECT 'snapshot_feature_logic', issue_count,
           'Historical Count·Rate·Segment·Recency 논리'
    FROM snapshot_logic_issues
    UNION ALL
    SELECT 'single_crm_as_of_day', issue_count,
           '모든 Priority 고객에 하나의 crm_as_of_day 매핑'
    FROM as_of_issues
    UNION ALL
    SELECT 'historical_campaign_leakage', issue_count,
           'end_day <= crm_as_of_day Campaign 수와 Snapshot Count 대사'
    FROM historical_campaign_leakage
    UNION ALL
    SELECT 'historical_redemption_leakage', issue_count,
           'Snapshot 사용 Redemption의 redemption_day <= crm_as_of_day'
    FROM historical_redemption_leakage
    UNION ALL
    SELECT 'historical_redemption_recipient_relation', issue_count,
           'Historical Redemption에 Campaign 수신 관계 존재'
    FROM recipient_relation_issues
    UNION ALL
    SELECT 'evidence_actionability_mapping', issue_count,
           'Segment별 Evidence·Actionability 규칙 일치'
    FROM mapping_issues
    UNION ALL
    SELECT 'reference_week_preservation', issue_count,
           'Actionability 기준주차가 기존 CRM Source와 일치'
    FROM reference_week_issues
    UNION ALL
    SELECT 'actionability_allowed_values_and_sum', issue_count,
           '네 Actionability 합 = 전체 Priority 고객'
    FROM segment_sum_issues
) AS checks
ORDER BY check_name;

/* ============================================================
   51. Week 98 전체 고객 Operational Snapshot 적재 준비
   ============================================================ */

-- Python save_revised_crm_outputs의 operational_columns 순서와 이름을 그대로 사용한다.
-- 정상 적재 후 52~57을 재실행해도 Source 2,500가구를 삭제하지 않는다.
CREATE TABLE IF NOT EXISTS mart.crm_week98_operational_snapshot (
    household_key BIGINT PRIMARY KEY,
    reference_week INTEGER,
    predicted_no_purchase_probability DOUBLE PRECISION,
    risk_rank BIGINT,
    risk_share_rank DOUBLE PRECISION,
    is_global_high_risk_top10 BOOLEAN,
    pre_window_monetary_26w DOUBLE PRECISION,
    economic_value_rank DOUBLE PRECISION,
    economic_value_percentile DOUBLE PRECISION,
    is_high_economic_value_top20 BOOLEAN,
    risk_rank_within_high_economic_value DOUBLE PRECISION,
    is_revised_crm_priority BOOLEAN,
    pre_window_rfm_value_index_26w DOUBLE PRECISION,
    value_state TEXT,
    activity_state TEXT,
    customer_state TEXT,
    CONSTRAINT chk_crm_week98_probability
        CHECK (predicted_no_purchase_probability BETWEEN 0 AND 1),
    CONSTRAINT chk_crm_week98_risk_share
        CHECK (risk_share_rank BETWEEN 0 AND 1),
    CONSTRAINT chk_crm_week98_economic_percentile
        CHECK (economic_value_percentile BETWEEN 0 AND 1)
);

SELECT COUNT(*) AS row_count, COUNT(DISTINCT household_key) AS household_count 
FROM mart.crm_week98_operational_snapshot;

/* ============================================================
   52. Week 98 Operational Snapshot 품질 검증
   ============================================================ */

-- \copy 적재 직후 통계정보를 갱신한다. Source 행은 변경하지 않는다.
ANALYZE mart.crm_week98_operational_snapshot;

/* ------------------------------------------------------------
   52-01. Source 행·기준주차·High Value Rank 구조
   ------------------------------------------------------------ */
SELECT
    COUNT(*)::BIGINT AS row_count,
    COUNT(DISTINCT household_key)::BIGINT AS distinct_household_count,
    (COUNT(*) - COUNT(DISTINCT household_key))::BIGINT
        AS duplicate_household_count,
    COUNT(DISTINCT reference_week)::BIGINT AS distinct_reference_week_count,
    MIN(reference_week) AS minimum_reference_week,
    MAX(reference_week) AS maximum_reference_week,
    COUNT(*) FILTER (WHERE is_high_economic_value_top20)::BIGINT
        AS high_economic_value_household_count,
    COUNT(*) FILTER (
        WHERE is_high_economic_value_top20
          AND risk_rank_within_high_economic_value IS NULL
    )::BIGINT AS high_value_risk_rank_null_count,
    COUNT(DISTINCT risk_rank_within_high_economic_value) FILTER (
        WHERE is_high_economic_value_top20
    )::BIGINT AS distinct_high_value_risk_rank_count,
    MIN(risk_rank_within_high_economic_value) FILTER (
        WHERE is_high_economic_value_top20
    ) AS minimum_high_value_risk_rank,
    MAX(risk_rank_within_high_economic_value) FILTER (
        WHERE is_high_economic_value_top20
    ) AS maximum_high_value_risk_rank
FROM mart.crm_week98_operational_snapshot;

/* ------------------------------------------------------------
   52-02. 핵심 컬럼 NULL·범위
   ------------------------------------------------------------ */
SELECT
    COUNT(*) FILTER (
        WHERE household_key IS NULL
           OR reference_week IS NULL
           OR predicted_no_purchase_probability IS NULL
           OR pre_window_monetary_26w IS NULL
           OR economic_value_rank IS NULL
           OR economic_value_percentile IS NULL
           OR is_high_economic_value_top20 IS NULL
    )::BIGINT AS core_null_issue_count,
    COUNT(*) FILTER (
        WHERE predicted_no_purchase_probability NOT BETWEEN 0 AND 1
    )::BIGINT AS probability_range_issue_count,
    COUNT(*) FILTER (
        WHERE is_high_economic_value_top20
          AND risk_rank_within_high_economic_value IS NULL
    )::BIGINT AS high_value_rank_null_issue_count
FROM mart.crm_week98_operational_snapshot;

/* ------------------------------------------------------------
   52-03. 신규 Top10 Household Set과 기존 최종 50가구 대사
   ------------------------------------------------------------ */
WITH high_value_count AS (
    SELECT COUNT(*)::BIGINT AS household_count
    FROM mart.crm_week98_operational_snapshot
    WHERE is_high_economic_value_top20
),
sensitivity_top10 AS (
    SELECT household_key
    FROM mart.crm_week98_operational_snapshot
    CROSS JOIN high_value_count
    WHERE is_high_economic_value_top20
      AND risk_rank_within_high_economic_value
          <= CEIL(high_value_count.household_count * 0.10)
),
set_difference AS (
    (SELECT household_key FROM sensitivity_top10
     EXCEPT
     SELECT household_key FROM mart.crm_priority_final)
    UNION ALL
    (SELECT household_key FROM mart.crm_priority_final
     EXCEPT
     SELECT household_key FROM sensitivity_top10)
)
SELECT
    (SELECT COUNT(*)::BIGINT FROM sensitivity_top10)
        AS sensitivity_top10_household_count,
    (SELECT COUNT(*)::BIGINT FROM mart.crm_priority_final)
        AS final_priority_household_count,
    COUNT(*)::BIGINT AS household_set_difference_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM set_difference;

/* ============================================================
   53. 경제적 가치고객 Historical Response Snapshot 생성
   ============================================================ */

DROP TABLE IF EXISTS mart.crm_priority_sensitivity_summary;
DROP TABLE IF EXISTS mart.crm_high_value_historical_snapshot;

-- 46단계와 동일한 시점·Campaign·Redemption·Segment 정의를 Top20 가치고객에 적용한다.
CREATE TABLE mart.crm_high_value_historical_snapshot AS
WITH high_value_reference AS MATERIALIZED (
    SELECT
        operational.household_key,
        operational.reference_week,
        reference.reference_end_day AS crm_as_of_day,
        operational.predicted_no_purchase_probability,
        operational.pre_window_monetary_26w,
        operational.economic_value_rank,
        operational.economic_value_percentile,
        operational.risk_rank_within_high_economic_value
    FROM mart.crm_week98_operational_snapshot AS operational
    JOIN mart.household_reference_week AS reference
        ON reference.household_key = operational.household_key
       AND reference.reference_week = operational.reference_week
    WHERE operational.is_high_economic_value_top20
),
historical_campaign_relation AS MATERIALIZED (
    SELECT
        high_value.household_key,
        recipient.campaign,
        high_value.crm_as_of_day
    FROM high_value_reference AS high_value
    JOIN mart.fact_campaign_household AS recipient
        ON recipient.household_key = high_value.household_key
    JOIN mart.dim_campaign AS campaign
        ON campaign.campaign = recipient.campaign
       AND campaign.end_day <= high_value.crm_as_of_day
),
redemption_by_campaign AS MATERIALIZED (
    SELECT
        relation.household_key,
        relation.campaign,
        COUNT(*)::BIGINT AS campaign_redemption_count,
        MAX(redemption.redemption_day) AS campaign_last_redemption_day
    FROM historical_campaign_relation AS relation
    JOIN mart.fact_coupon_redemption AS redemption
        ON redemption.household_key = relation.household_key
       AND redemption.campaign = relation.campaign
       AND redemption.redemption_day <= relation.crm_as_of_day
    GROUP BY relation.household_key, relation.campaign
),
household_history AS (
    SELECT
        relation.household_key,
        COUNT(*)::BIGINT AS historical_campaign_count,
        COALESCE(SUM(redemption.campaign_redemption_count), 0)::BIGINT
            AS historical_redemption_count,
        COUNT(redemption.campaign)::BIGINT AS historical_redeemed_campaign_count,
        MAX(redemption.campaign_last_redemption_day)
            AS last_historical_redemption_day
    FROM historical_campaign_relation AS relation
    LEFT JOIN redemption_by_campaign AS redemption
        ON redemption.household_key = relation.household_key
       AND redemption.campaign = relation.campaign
    GROUP BY relation.household_key
),
features AS (
    SELECT
        high_value.household_key,
        high_value.reference_week,
        high_value.crm_as_of_day,
        high_value.predicted_no_purchase_probability,
        high_value.pre_window_monetary_26w,
        high_value.economic_value_rank,
        high_value.economic_value_percentile,
        high_value.risk_rank_within_high_economic_value,
        COALESCE(history.historical_campaign_count, 0)::BIGINT
            AS historical_campaign_count,
        COALESCE(history.historical_redemption_count, 0)::BIGINT
            AS historical_redemption_count,
        COALESCE(history.historical_redeemed_campaign_count, 0)::BIGINT
            AS historical_redeemed_campaign_count,
        COALESCE(history.historical_redeemed_campaign_count, 0)::NUMERIC
            / NULLIF(COALESCE(history.historical_campaign_count, 0), 0)
            AS historical_campaign_redemption_rate,
        history.last_historical_redemption_day,
        CASE WHEN history.last_historical_redemption_day IS NOT NULL
            THEN high_value.crm_as_of_day - history.last_historical_redemption_day
        END::INTEGER AS days_since_last_historical_redemption
    FROM high_value_reference AS high_value
    LEFT JOIN household_history AS history
        ON history.household_key = high_value.household_key
)
SELECT
    features.*,
    CASE
        WHEN historical_campaign_count = 0 THEN 'NO_HISTORY'
        WHEN historical_campaign_count > 0
         AND historical_redeemed_campaign_count = 0 THEN 'EXPOSED_NO_REDEMPTION'
        WHEN historical_redeemed_campaign_count = 1 THEN 'ONE_TIME_REDEEMER'
        WHEN historical_redeemed_campaign_count >= 2 THEN 'REPEAT_REDEEMER'
    END::TEXT AS promotion_response_state
FROM features;

ALTER TABLE mart.crm_high_value_historical_snapshot
    ADD CONSTRAINT pk_crm_high_value_historical_snapshot PRIMARY KEY (household_key),
    ADD CONSTRAINT chk_crm_high_value_historical_snapshot_state CHECK (
        promotion_response_state IN (
            'NO_HISTORY', 'EXPOSED_NO_REDEMPTION',
            'ONE_TIME_REDEEMER', 'REPEAT_REDEEMER'
        )
    );

ANALYZE mart.crm_high_value_historical_snapshot;

/* ============================================================
   54. Risk Cutoff 민감도 Cohort 생성
   ============================================================ */

CREATE TABLE mart.crm_priority_sensitivity_summary AS
WITH cutoff_config AS (
    SELECT *
    FROM (VALUES
        ('CUMULATIVE'::TEXT, 'TOP_10'::TEXT, 0.00::NUMERIC, 0.10::NUMERIC, 1),
        ('CUMULATIVE', 'TOP_20', 0.00::NUMERIC, 0.20::NUMERIC, 2),
        ('CUMULATIVE', 'TOP_30', 0.00::NUMERIC, 0.30::NUMERIC, 3),
        ('CUMULATIVE', 'TOP_40', 0.00::NUMERIC, 0.40::NUMERIC, 4),
        ('CUMULATIVE', 'TOP_50', 0.00::NUMERIC, 0.50::NUMERIC, 5),
        ('BAND', 'BAND_00_10', 0.00::NUMERIC, 0.10::NUMERIC, 1),
        ('BAND', 'BAND_10_20', 0.10::NUMERIC, 0.20::NUMERIC, 2),
        ('BAND', 'BAND_20_30', 0.20::NUMERIC, 0.30::NUMERIC, 3),
        ('BAND', 'BAND_30_40', 0.30::NUMERIC, 0.40::NUMERIC, 4),
        ('BAND', 'BAND_40_50', 0.40::NUMERIC, 0.50::NUMERIC, 5)
    ) AS config(analysis_type, cohort_label, cutoff_lower, cutoff_upper, cohort_order)
),
high_value_count AS (
    SELECT COUNT(*)::BIGINT AS household_count
    FROM mart.crm_high_value_historical_snapshot
),
cohort_members AS MATERIALIZED (
    SELECT
        config.analysis_type,
        config.cohort_label,
        config.cutoff_lower,
        config.cutoff_upper,
        config.cohort_order,
        snapshot.*
    FROM cutoff_config AS config
    CROSS JOIN high_value_count
    JOIN mart.crm_high_value_historical_snapshot AS snapshot
      ON snapshot.risk_rank_within_high_economic_value
            > CASE WHEN config.analysis_type = 'BAND'
                THEN CEIL(high_value_count.household_count * config.cutoff_lower)
                ELSE 0
              END
     AND snapshot.risk_rank_within_high_economic_value
            <= CEIL(high_value_count.household_count * config.cutoff_upper)
),
states AS (
    SELECT * FROM (VALUES
        ('NO_HISTORY'::TEXT),
        ('EXPOSED_NO_REDEMPTION'),
        ('ONE_TIME_REDEEMER'),
        ('REPEAT_REDEEMER')
    ) AS state(promotion_response_state)
),
cohort_totals AS (
    SELECT
        analysis_type, cohort_label, cutoff_lower, cutoff_upper, cohort_order,
        COUNT(*)::BIGINT AS cohort_household_count
    FROM cohort_members
    GROUP BY analysis_type, cohort_label, cutoff_lower, cutoff_upper, cohort_order
),
state_statistics AS (
    SELECT
        analysis_type,
        cohort_label,
        promotion_response_state,
        COUNT(*)::BIGINT AS state_household_count,
        AVG(predicted_no_purchase_probability)
            AS mean_predicted_no_purchase_probability,
        PERCENTILE_CONT(0.50) WITHIN GROUP (
            ORDER BY predicted_no_purchase_probability
        ) AS median_predicted_no_purchase_probability,
        AVG(pre_window_monetary_26w) AS mean_pre_window_monetary_26w,
        PERCENTILE_CONT(0.50) WITHIN GROUP (
            ORDER BY pre_window_monetary_26w
        ) AS median_pre_window_monetary_26w,
        AVG(historical_campaign_count) AS mean_historical_campaign_count,
        AVG(historical_redeemed_campaign_count)
            AS mean_historical_redeemed_campaign_count
    FROM cohort_members
    GROUP BY analysis_type, cohort_label, promotion_response_state
),
summary AS (
    SELECT
        total.analysis_type,
        total.cohort_label,
        total.cutoff_lower,
        total.cutoff_upper,
        total.cohort_order,
        total.cohort_household_count,
        state.promotion_response_state,
        COALESCE(statistics.state_household_count, 0)::BIGINT AS state_household_count,
        COALESCE(statistics.state_household_count, 0)::NUMERIC
            / NULLIF(total.cohort_household_count, 0) AS state_share,
        statistics.mean_predicted_no_purchase_probability,
        statistics.median_predicted_no_purchase_probability,
        statistics.mean_pre_window_monetary_26w,
        statistics.median_pre_window_monetary_26w,
        statistics.mean_historical_campaign_count,
        statistics.mean_historical_redeemed_campaign_count
    FROM cohort_totals AS total
    CROSS JOIN states AS state
    LEFT JOIN state_statistics AS statistics
        ON statistics.analysis_type = total.analysis_type
       AND statistics.cohort_label = total.cohort_label
       AND statistics.promotion_response_state = state.promotion_response_state
),
top10 AS (
    SELECT promotion_response_state, state_share
    FROM summary
    WHERE analysis_type = 'CUMULATIVE'
      AND cohort_label = 'TOP_10'
)
SELECT
    summary.*,
    CASE WHEN summary.analysis_type = 'CUMULATIVE'
        THEN (summary.state_share - top10.state_share) * 100
    END AS share_difference_vs_top10_pp
FROM summary
LEFT JOIN top10
    ON top10.promotion_response_state = summary.promotion_response_state;

ALTER TABLE mart.crm_priority_sensitivity_summary
    ADD CONSTRAINT pk_crm_priority_sensitivity_summary
        PRIMARY KEY (analysis_type, cohort_label, promotion_response_state),
    ADD CONSTRAINT chk_crm_priority_sensitivity_analysis_type
        CHECK (analysis_type IN ('CUMULATIVE', 'BAND')),
    ADD CONSTRAINT chk_crm_priority_sensitivity_share
        CHECK (state_share BETWEEN 0 AND 1);

ANALYZE mart.crm_priority_sensitivity_summary;

/* ============================================================
   55. Risk Cutoff 민감도 결과 요약
   ============================================================ */

/* ------------------------------------------------------------
   55-01. Cumulative Top10~Top50 Segment 분포
   ------------------------------------------------------------ */
SELECT
    cohort_label,
    MAX(cohort_household_count) AS cohort_household_count,
    MAX(state_household_count) FILTER (WHERE promotion_response_state = 'NO_HISTORY')
        AS no_history_count,
    MAX(state_share) FILTER (WHERE promotion_response_state = 'NO_HISTORY')
        AS no_history_share,
    MAX(state_household_count) FILTER (
        WHERE promotion_response_state = 'EXPOSED_NO_REDEMPTION'
    ) AS exposed_no_redemption_count,
    MAX(state_share) FILTER (
        WHERE promotion_response_state = 'EXPOSED_NO_REDEMPTION'
    ) AS exposed_no_redemption_share,
    MAX(state_household_count) FILTER (
        WHERE promotion_response_state = 'ONE_TIME_REDEEMER'
    ) AS one_time_redeemer_count,
    MAX(state_share) FILTER (
        WHERE promotion_response_state = 'ONE_TIME_REDEEMER'
    ) AS one_time_redeemer_share,
    MAX(state_household_count) FILTER (
        WHERE promotion_response_state = 'REPEAT_REDEEMER'
    ) AS repeat_redeemer_count,
    MAX(state_share) FILTER (
        WHERE promotion_response_state = 'REPEAT_REDEEMER'
    ) AS repeat_redeemer_share
FROM mart.crm_priority_sensitivity_summary
WHERE analysis_type = 'CUMULATIVE'
GROUP BY cohort_label, cohort_order
ORDER BY cohort_order;

/* ------------------------------------------------------------
   55-02. Cumulative Top10~Top50 Ever Redeemer 비중
   ------------------------------------------------------------ */
SELECT
    cohort_label,
    MAX(cohort_household_count) AS cohort_household_count,
    SUM(state_household_count) FILTER (
        WHERE promotion_response_state IN ('ONE_TIME_REDEEMER', 'REPEAT_REDEEMER')
    )::BIGINT AS ever_redeemer_count,
    SUM(state_household_count) FILTER (
        WHERE promotion_response_state IN ('ONE_TIME_REDEEMER', 'REPEAT_REDEEMER')
    )::NUMERIC / NULLIF(MAX(cohort_household_count), 0) AS ever_redeemer_share
FROM mart.crm_priority_sensitivity_summary
WHERE analysis_type = 'CUMULATIVE'
GROUP BY cohort_label, cohort_order
ORDER BY cohort_order;

/* ------------------------------------------------------------
   55-03. Cutoff별 Risk / Monetary 요약
   ------------------------------------------------------------ */
WITH cohort_limits AS (
    SELECT cohort_label, cutoff_upper, cohort_order,
           MAX(cohort_household_count) AS cohort_household_count
    FROM mart.crm_priority_sensitivity_summary
    WHERE analysis_type = 'CUMULATIVE'
    GROUP BY cohort_label, cutoff_upper, cohort_order
),
high_value_count AS (
    SELECT COUNT(*)::BIGINT AS household_count
    FROM mart.crm_high_value_historical_snapshot
)
SELECT
    limits.cohort_label,
    limits.cohort_household_count,
    AVG(snapshot.predicted_no_purchase_probability)
        AS mean_predicted_no_purchase_probability,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY snapshot.predicted_no_purchase_probability
    ) AS median_predicted_no_purchase_probability,
    AVG(snapshot.pre_window_monetary_26w) AS mean_pre_window_monetary_26w,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY snapshot.pre_window_monetary_26w
    ) AS median_pre_window_monetary_26w
FROM cohort_limits AS limits
CROSS JOIN high_value_count
JOIN mart.crm_high_value_historical_snapshot AS snapshot
  ON snapshot.risk_rank_within_high_economic_value
        <= CEIL(high_value_count.household_count * limits.cutoff_upper)
GROUP BY limits.cohort_label, limits.cohort_household_count, limits.cohort_order
ORDER BY limits.cohort_order;

/* ------------------------------------------------------------
   55-04. Top10 대비 Segment 비중 차이와 최대 절대 변화 %p
   ------------------------------------------------------------ */
SELECT
    cohort_label,
    promotion_response_state,
    state_share,
    share_difference_vs_top10_pp,
    MAX(ABS(share_difference_vs_top10_pp)) OVER (PARTITION BY cohort_label)
        AS max_abs_segment_share_difference_pp
FROM mart.crm_priority_sensitivity_summary
WHERE analysis_type = 'CUMULATIVE'
ORDER BY cohort_order,
    CASE promotion_response_state
        WHEN 'NO_HISTORY' THEN 1
        WHEN 'EXPOSED_NO_REDEMPTION' THEN 2
        WHEN 'ONE_TIME_REDEEMER' THEN 3
        WHEN 'REPEAT_REDEEMER' THEN 4
    END;

/* ------------------------------------------------------------
   55-05. 비중첩 Risk Band Segment 분포
   ------------------------------------------------------------ */
SELECT
    cohort_label,
    MAX(cohort_household_count) AS cohort_household_count,
    MAX(state_share) FILTER (WHERE promotion_response_state = 'NO_HISTORY')
        AS no_history_share,
    MAX(state_share) FILTER (
        WHERE promotion_response_state = 'EXPOSED_NO_REDEMPTION'
    ) AS exposed_no_redemption_share,
    MAX(state_share) FILTER (
        WHERE promotion_response_state = 'ONE_TIME_REDEEMER'
    ) AS one_time_redeemer_share,
    MAX(state_share) FILTER (
        WHERE promotion_response_state = 'REPEAT_REDEEMER'
    ) AS repeat_redeemer_share,
    SUM(state_household_count) FILTER (
        WHERE promotion_response_state IN ('ONE_TIME_REDEEMER', 'REPEAT_REDEEMER')
    )::NUMERIC / NULLIF(MAX(cohort_household_count), 0) AS ever_redeemer_share,
    SUM(mean_predicted_no_purchase_probability * state_household_count)
        / NULLIF(SUM(state_household_count), 0) AS mean_predicted_no_purchase_probability,
    SUM(mean_pre_window_monetary_26w * state_household_count)
        / NULLIF(SUM(state_household_count), 0) AS mean_pre_window_monetary_26w
FROM mart.crm_priority_sensitivity_summary
WHERE analysis_type = 'BAND'
GROUP BY cohort_label, cohort_order
ORDER BY cohort_order;

/* ============================================================
   56. Risk Cutoff 민감도 품질 검증
   ============================================================ */

WITH
operational_issues AS (
    SELECT
        (COUNT(*) - COUNT(DISTINCT household_key))
        + COUNT(*) FILTER (
            WHERE reference_week IS NULL
               OR predicted_no_purchase_probability IS NULL
               OR pre_window_monetary_26w IS NULL
               OR economic_value_rank IS NULL
               OR economic_value_percentile IS NULL
               OR is_high_economic_value_top20 IS NULL
               OR predicted_no_purchase_probability NOT BETWEEN 0 AND 1
        )
        + CASE WHEN COUNT(DISTINCT reference_week) =
                    (SELECT COUNT(DISTINCT reference_week)
                     FROM mart.crm_priority_final)
                 AND MIN(reference_week) =
                    (SELECT MIN(reference_week) FROM mart.crm_priority_final)
                 AND MAX(reference_week) =
                    (SELECT MAX(reference_week) FROM mart.crm_priority_final)
            THEN 0 ELSE 1 END AS issue_count
    FROM mart.crm_week98_operational_snapshot
),
high_value_issues AS (
    SELECT
        (COUNT(*) - COUNT(DISTINCT household_key))
        + COUNT(*) FILTER (WHERE risk_rank_within_high_economic_value IS NULL)
        + (COUNT(*) - COUNT(DISTINCT risk_rank_within_high_economic_value))
            AS issue_count
    FROM mart.crm_week98_operational_snapshot
    WHERE is_high_economic_value_top20
),
high_value_count AS (
    SELECT COUNT(*)::BIGINT AS household_count
    FROM mart.crm_high_value_historical_snapshot
),
new_top10 AS (
    SELECT household_key
    FROM mart.crm_high_value_historical_snapshot
    CROSS JOIN high_value_count
    WHERE risk_rank_within_high_economic_value
        <= CEIL(high_value_count.household_count * 0.10)
),
top10_set_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count FROM (
        (SELECT household_key FROM new_top10 EXCEPT
         SELECT household_key FROM mart.crm_priority_final)
        UNION ALL
        (SELECT household_key FROM mart.crm_priority_final EXCEPT
         SELECT household_key FROM new_top10)
    ) AS differences
),
top10_history_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM new_top10
    JOIN mart.crm_high_value_historical_snapshot AS current USING (household_key)
    LEFT JOIN mart.crm_historical_response_snapshot AS prior USING (household_key)
    WHERE prior.household_key IS NULL
       OR current.historical_campaign_count
            IS DISTINCT FROM prior.historical_campaign_count
       OR current.historical_redemption_count
            IS DISTINCT FROM prior.historical_redemption_count
       OR current.historical_redeemed_campaign_count
            IS DISTINCT FROM prior.historical_redeemed_campaign_count
       OR current.historical_campaign_redemption_rate
            IS DISTINCT FROM prior.historical_campaign_redemption_rate
       OR current.last_historical_redemption_day
            IS DISTINCT FROM prior.last_historical_redemption_day
       OR current.days_since_last_historical_redemption
            IS DISTINCT FROM prior.days_since_last_historical_redemption
       OR current.promotion_response_state
            IS DISTINCT FROM prior.promotion_response_state
),
top10_segment_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count FROM (
        (SELECT promotion_response_state, COUNT(*)::BIGINT AS household_count
         FROM mart.crm_high_value_historical_snapshot
         WHERE household_key IN (SELECT household_key FROM new_top10)
         GROUP BY promotion_response_state
         EXCEPT
         SELECT promotion_response_state, COUNT(*)::BIGINT
         FROM mart.crm_promotion_actionability
         GROUP BY promotion_response_state)
        UNION ALL
        (SELECT promotion_response_state, COUNT(*)::BIGINT AS household_count
         FROM mart.crm_promotion_actionability
         GROUP BY promotion_response_state
         EXCEPT
         SELECT promotion_response_state, COUNT(*)::BIGINT
         FROM mart.crm_high_value_historical_snapshot
         WHERE household_key IN (SELECT household_key FROM new_top10)
         GROUP BY promotion_response_state)
    ) AS differences
),
historical_grain_issues AS (
    SELECT ABS(
        COUNT(*) - (SELECT COUNT(*) FROM mart.crm_week98_operational_snapshot
                    WHERE is_high_economic_value_top20)
    ) + (COUNT(*) - COUNT(DISTINCT household_key)) AS issue_count
    FROM mart.crm_high_value_historical_snapshot
),
historical_logic_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.crm_high_value_historical_snapshot
    WHERE crm_as_of_day IS NULL
       OR historical_redeemed_campaign_count > historical_campaign_count
       OR (historical_redeemed_campaign_count > 0 AND historical_redemption_count = 0)
       OR (historical_redemption_count > 0 AND historical_redeemed_campaign_count = 0)
       OR promotion_response_state IS NULL
       OR promotion_response_state NOT IN (
            'NO_HISTORY', 'EXPOSED_NO_REDEMPTION',
            'ONE_TIME_REDEEMER', 'REPEAT_REDEEMER'
       )
       OR (promotion_response_state = 'NO_HISTORY'
           AND historical_campaign_redemption_rate IS NOT NULL)
       OR (promotion_response_state = 'EXPOSED_NO_REDEMPTION'
           AND historical_campaign_redemption_rate IS DISTINCT FROM 0::NUMERIC)
       OR (promotion_response_state IN ('ONE_TIME_REDEEMER', 'REPEAT_REDEEMER')
           AND (last_historical_redemption_day IS NULL
                OR days_since_last_historical_redemption < 0))
),
as_of_issues AS (
    SELECT COUNT(*) FILTER (WHERE crm_as_of_day IS NULL)
        + CASE WHEN COUNT(DISTINCT crm_as_of_day) = 1 THEN 0 ELSE 1 END AS issue_count
    FROM mart.crm_high_value_historical_snapshot
),
campaign_cutoff_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.crm_high_value_historical_snapshot AS snapshot
    WHERE snapshot.historical_campaign_count IS DISTINCT FROM (
        SELECT COUNT(*)::BIGINT
        FROM mart.fact_campaign_household AS recipient
        JOIN mart.dim_campaign AS campaign USING (campaign)
        WHERE recipient.household_key = snapshot.household_key
          AND campaign.end_day <= snapshot.crm_as_of_day
    )
),
redemption_cutoff_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.crm_high_value_historical_snapshot AS snapshot
    JOIN mart.fact_campaign_household AS recipient
        ON recipient.household_key = snapshot.household_key
    JOIN mart.dim_campaign AS campaign
        ON campaign.campaign = recipient.campaign
       AND campaign.end_day <= snapshot.crm_as_of_day
    JOIN mart.fact_coupon_redemption AS redemption
        ON redemption.household_key = recipient.household_key
       AND redemption.campaign = recipient.campaign
    WHERE redemption.redemption_day > snapshot.crm_as_of_day
),
cohort_checks AS (
    SELECT
        analysis_type,
        cohort_order,
        MAX(cohort_household_count) AS cohort_household_count,
        SUM(state_household_count) AS state_household_count,
        SUM(state_share) AS state_share
    FROM mart.crm_priority_sensitivity_summary
    GROUP BY analysis_type, cohort_order
),
cumulative_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM cohort_checks AS current
    LEFT JOIN cohort_checks AS prior
        ON prior.analysis_type = 'CUMULATIVE'
       AND prior.cohort_order = current.cohort_order - 1
    WHERE current.analysis_type = 'CUMULATIVE'
      AND (current.state_household_count <> current.cohort_household_count
           OR ABS(current.state_share - 1) > 0.000000001
           OR (prior.cohort_order IS NOT NULL
               AND current.cohort_household_count <= prior.cohort_household_count))
),
band_issues AS (
    SELECT
        COUNT(*) FILTER (
            WHERE analysis_type = 'BAND'
              AND (state_household_count <> cohort_household_count
                   OR ABS(state_share - 1) > 0.000000001)
        )
        + CASE WHEN
            (SELECT SUM(cohort_household_count)
             FROM cohort_checks WHERE analysis_type = 'BAND') =
            (SELECT cohort_household_count
             FROM cohort_checks
             WHERE analysis_type = 'CUMULATIVE' AND cohort_order = 5)
          THEN 0 ELSE 1 END AS issue_count
    FROM cohort_checks
)
SELECT
    check_name,
    CASE WHEN issue_count = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
    issue_count::BIGINT,
    detail
FROM (
    SELECT 'operational_source_integrity'::TEXT AS check_name, issue_count,
           'Source Grain·NULL·Probability 범위'::TEXT AS detail FROM operational_issues
    UNION ALL SELECT 'high_value_rank_integrity', issue_count,
           'High Value Grain·Risk Rank NULL·중복' FROM high_value_issues
    UNION ALL SELECT 'top10_household_set_reconciliation', issue_count,
           '신규 Top10과 기존 최종 Priority Household Set 일치' FROM top10_set_issues
    UNION ALL SELECT 'top10_historical_feature_reconciliation', issue_count,
           '신규 Top10과 기존 Historical Snapshot Feature 일치' FROM top10_history_issues
    UNION ALL SELECT 'top10_segment_reconciliation', issue_count,
           '신규 Top10과 기존 Actionability Segment 분포 일치' FROM top10_segment_issues
    UNION ALL SELECT 'high_value_historical_grain', issue_count,
           'High Value Source와 Snapshot 행 수·Grain 일치' FROM historical_grain_issues
    UNION ALL SELECT 'historical_feature_logic', issue_count,
           'Historical Count·Segment·Rate·Recency 논리' FROM historical_logic_issues
    UNION ALL SELECT 'single_crm_as_of_day', issue_count,
           'High Value 전체에 하나의 crm_as_of_day 매핑' FROM as_of_issues
    UNION ALL SELECT 'historical_campaign_cutoff', issue_count,
           'end_day <= crm_as_of_day Campaign 수 대사' FROM campaign_cutoff_issues
    UNION ALL SELECT 'historical_redemption_cutoff', issue_count,
           'redemption_day <= crm_as_of_day' FROM redemption_cutoff_issues
    UNION ALL SELECT 'cumulative_cohort_integrity', issue_count,
           '누적 Cohort 증가·Segment 합·Share 합' FROM cumulative_issues
    UNION ALL SELECT 'risk_band_integrity', issue_count,
           '비중첩 Band Segment 합·Share 합' FROM band_issues
) AS checks
ORDER BY check_name;

/* ============================================================
   57. Python 시각화용 SQL 결과 Export 준비
   ============================================================ */

-- 01_campaign_type_response.csv
SELECT
    description AS campaign_type,
    SUM(recipient_count)::BIGINT AS recipient_observation_count,
    SUM(redeemer_count)::BIGINT AS redeemer_observation_count,
    SUM(redeemer_count)::NUMERIC / NULLIF(SUM(recipient_count), 0) AS redemption_rate
FROM mart.campaign_response_summary
GROUP BY description
ORDER BY description;

-- 02_historical_response_rate.csv
SELECT
    promotion_response_state,
    COUNT(*)::BIGINT AS observation_count,
    COUNT(*) FILTER (WHERE redeemed_flag)::BIGINT AS current_redeemer_count,
    COUNT(*) FILTER (WHERE redeemed_flag)::NUMERIC / NULLIF(COUNT(*), 0)
        AS current_redemption_rate
FROM mart.campaign_historical_response_segments
GROUP BY promotion_response_state
ORDER BY CASE promotion_response_state
    WHEN 'NO_HISTORY' THEN 1 WHEN 'EXPOSED_NO_REDEMPTION' THEN 2
    WHEN 'ONE_TIME_REDEEMER' THEN 3 WHEN 'REPEAT_REDEEMER' THEN 4 END;

-- 03_pre_during_post_sales.csv
SELECT
    response_group,
    AVG(pre_sales_per_day) AS pre_sales_per_day_mean,
    AVG(during_sales_per_day) AS during_sales_per_day_mean,
    AVG(post_sales_per_day) AS post_sales_per_day_mean,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY pre_sales_per_day)
        AS pre_sales_per_day_median,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY during_sales_per_day)
        AS during_sales_per_day_median,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY post_sales_per_day)
        AS post_sales_per_day_median
FROM mart.campaign_pre_during_post_features
GROUP BY response_group
ORDER BY response_group;

-- 04_crm_actionability_summary.csv
SELECT
    promotion_actionability,
    promotion_evidence_level,
    COUNT(*)::BIGINT AS household_count,
    COUNT(*)::NUMERIC / NULLIF(
        (SELECT COUNT(*) FROM mart.crm_promotion_actionability), 0
    ) AS share_of_priority_households
FROM mart.crm_promotion_actionability
GROUP BY promotion_actionability, promotion_evidence_level
ORDER BY promotion_actionability;

-- 05_crm_sensitivity_summary.csv
SELECT
    cohort_label,
    cutoff_upper,
    cohort_household_count,
    promotion_response_state,
    state_household_count,
    state_share,
    share_difference_vs_top10_pp
FROM mart.crm_priority_sensitivity_summary
WHERE analysis_type = 'CUMULATIVE'
ORDER BY cohort_order, promotion_response_state;

-- 06_crm_actionability_customers.csv
SELECT
    priority_rank,
    household_key,
    predicted_no_purchase_probability,
    pre_window_monetary_26w,
    risk_rank_within_high_economic_value,
    historical_campaign_count,
    historical_redeemed_campaign_count,
    historical_campaign_redemption_rate,
    days_since_last_historical_redemption,
    promotion_response_state,
    promotion_evidence_level,
    promotion_actionability
FROM mart.crm_promotion_actionability
ORDER BY priority_rank;