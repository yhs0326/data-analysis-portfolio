/* ============================================================
   01. RAW 스키마 생성
   ============================================================ */

CREATE SCHEMA IF NOT EXISTS raw;

/* ============================================================
   02. RAW 테이블 생성
   ============================================================ */

CREATE TABLE IF NOT EXISTS raw.transaction_data (
    household_key       TEXT,
    basket_id           TEXT,
    day                 TEXT,
    product_id          TEXT,
    quantity            TEXT,
    sales_value         TEXT,
    store_id            TEXT,
    retail_disc         TEXT,
    trans_time          TEXT,
    week_no             TEXT,
    coupon_disc         TEXT,
    coupon_match_disc   TEXT,
    source_row_id       BIGINT GENERATED ALWAYS AS IDENTITY,
    source_file         TEXT DEFAULT 'transaction_data.csv',
    load_batch_id       TEXT DEFAULT current_setting('raw.load_batch_id', true),
    loaded_at           TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);


CREATE TABLE IF NOT EXISTS raw.product (
    product_id           TEXT,
    manufacturer         TEXT,
    department           TEXT,
    brand                TEXT,
    commodity_desc       TEXT,
    sub_commodity_desc   TEXT,
    curr_size_of_product TEXT,
    source_row_id        BIGINT GENERATED ALWAYS AS IDENTITY,
    source_file          TEXT DEFAULT 'product.csv',
    load_batch_id        TEXT DEFAULT current_setting('raw.load_batch_id', true),
    loaded_at            TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);


select count (*) from raw.transaction_data;
SELECT COUNT(*) FROM raw.product;

/* ============================================================
   04. RAW 적재 결과 검증
   ============================================================ */

/*
Python 프로파일링의 file_summary.csv에서 확인한 row_count를 아래 NULL 대신 입력한다.
예: 123456::BIGINT AS expected_transaction_rows
값을 확인할 수 없거나 아직 입력하지 않은 경우 NULL::BIGINT를 유지한다.
*/
WITH validation_config AS (
    SELECT
        NULL::BIGINT AS expected_transaction_rows,
        NULL::BIGINT AS expected_product_rows
),
batch_counts AS (
    SELECT
        'raw.transaction_data'::TEXT AS table_name,
        load_batch_id,
        source_file,
        COUNT(*)::BIGINT AS loaded_row_count,
        MAX(loaded_at) AS latest_loaded_at
    FROM raw.transaction_data
    GROUP BY load_batch_id, source_file

    UNION ALL

    SELECT
        'raw.product'::TEXT AS table_name,
        load_batch_id,
        source_file,
        COUNT(*)::BIGINT AS loaded_row_count,
        MAX(loaded_at) AS latest_loaded_at
    FROM raw.product
    GROUP BY load_batch_id, source_file
),
ranked_batches AS (
    SELECT
        batch_counts.*,
        SUM(loaded_row_count) OVER (PARTITION BY table_name) AS table_total_row_count,
        DENSE_RANK() OVER (ORDER BY latest_loaded_at DESC, load_batch_id DESC) AS recency_rank
    FROM batch_counts
),
configured AS (
    SELECT
        ranked_batches.*,
        CASE table_name
            WHEN 'raw.transaction_data' THEN expected_transaction_rows
            WHEN 'raw.product' THEN expected_product_rows
        END AS expected_csv_row_count
    FROM ranked_batches
    CROSS JOIN validation_config
)
SELECT
    table_name,
    table_total_row_count,
    load_batch_id,
    source_file,
    loaded_row_count,
    (recency_rank = 1) AS is_most_recent_batch,
    CASE
        WHEN recency_rank <> 1 THEN NULL
        WHEN expected_csv_row_count IS NULL THEN 'NOT_CONFIGURED'
        WHEN loaded_row_count = expected_csv_row_count THEN 'PASS'
        ELSE 'FAIL'
    END AS expected_row_count_status,
    expected_csv_row_count
FROM configured
ORDER BY latest_loaded_at DESC, table_name, source_file, load_batch_id;

-- 거래 핵심 컬럼과 적재 이력의 NULL·빈 문자열 및 source_row_id 중복을 한 번의 스캔으로 확인한다.
SELECT
    COUNT(*)::BIGINT AS total_row_count,
    COUNT(*) FILTER (WHERE household_key IS NULL)::BIGINT AS household_key_null_count,
    COUNT(*) FILTER (WHERE household_key = '')::BIGINT AS household_key_empty_count,
    COUNT(*) FILTER (WHERE basket_id IS NULL)::BIGINT AS basket_id_null_count,
    COUNT(*) FILTER (WHERE basket_id = '')::BIGINT AS basket_id_empty_count,
    COUNT(*) FILTER (WHERE product_id IS NULL)::BIGINT AS product_id_null_count,
    COUNT(*) FILTER (WHERE product_id = '')::BIGINT AS product_id_empty_count,
    COUNT(*) FILTER (WHERE source_file IS NULL)::BIGINT AS source_file_null_count,
    COUNT(*) FILTER (WHERE load_batch_id IS NULL)::BIGINT AS load_batch_id_null_count,
    COUNT(*) FILTER (WHERE loaded_at IS NULL)::BIGINT AS loaded_at_null_count,
    (COUNT(source_row_id) - COUNT(DISTINCT source_row_id))::BIGINT
        AS source_row_id_duplicate_count
FROM raw.transaction_data;


BEGIN;

UPDATE raw.transaction_data
SET load_batch_id = 'raw-load-initial-20260731'
WHERE load_batch_id IS NULL;

UPDATE raw.product
SET load_batch_id = 'raw-load-initial-20260731'
WHERE load_batch_id IS NULL;

COMMIT;

SELECT COUNT(*) AS load_batch_id_null_count
FROM raw.transaction_data
WHERE load_batch_id IS NULL;

SELECT COUNT(*) AS load_batch_id_null_count
FROM raw.product
WHERE load_batch_id IS NULL;

-- 상품 핵심 컬럼과 적재 이력의 NULL·빈 문자열 및 source_row_id 중복을 한 번의 스캔으로 확인한다.
SELECT
    COUNT(*)::BIGINT AS total_row_count,
    COUNT(*) FILTER (WHERE product_id IS NULL)::BIGINT AS product_id_null_count,
    COUNT(*) FILTER (WHERE product_id = '')::BIGINT AS product_id_empty_count,
    COUNT(*) FILTER (WHERE source_file IS NULL)::BIGINT AS source_file_null_count,
    COUNT(*) FILTER (WHERE load_batch_id IS NULL)::BIGINT AS load_batch_id_null_count,
    COUNT(*) FILTER (WHERE loaded_at IS NULL)::BIGINT AS loaded_at_null_count,
    (COUNT(source_row_id) - COUNT(DISTINCT source_row_id))::BIGINT
        AS source_row_id_duplicate_count
FROM raw.product;

-- product_id 중복은 삭제 대상이 아니라 현황 확인 대상이며 NULL과 빈 문자열은 제외한다.
WITH product_id_counts AS (
    SELECT
        product_id,
        COUNT(*)::BIGINT AS row_count
    FROM raw.product
    WHERE product_id IS NOT NULL
      AND product_id <> ''
    GROUP BY product_id
)
SELECT
    COUNT(*) FILTER (WHERE row_count > 1)::BIGINT AS duplicated_product_id_count,
    COALESCE(SUM(row_count - 1) FILTER (WHERE row_count > 1), 0)::BIGINT
        AS duplicate_extra_row_count,
    COALESCE(MAX(row_count), 0)::BIGINT AS maximum_rows_per_product_id
FROM product_id_counts;

-- 두 RAW 테이블의 실제 컬럼명, 자료형, nullable 여부와 컬럼 순서를 확인한다.
SELECT
    table_schema,
    table_name,
    ordinal_position,
    column_name,
    data_type,
    is_nullable,
    column_default,
    is_identity
FROM information_schema.columns
WHERE table_schema = 'raw'
  AND table_name IN ('transaction_data', 'product')
ORDER BY table_name, ordinal_position;

-- 거래에는 있지만 상품에는 없는 비결측·비어 있지 않은 고유 product_id 수를 확인한다.
WITH transaction_product_ids AS (
    SELECT DISTINCT product_id
    FROM raw.transaction_data
    WHERE product_id IS NOT NULL
      AND product_id <> ''
),
product_product_ids AS (
    SELECT DISTINCT product_id
    FROM raw.product
    WHERE product_id IS NOT NULL
      AND product_id <> ''
)
SELECT COUNT(*)::BIGINT AS unmatched_transaction_product_id_count
FROM transaction_product_ids AS transaction_ids
WHERE NOT EXISTS (
    SELECT 1
    FROM product_product_ids AS product_ids
    WHERE product_ids.product_id = transaction_ids.product_id
);

/* ============================================================
   05. BASE 변환 전 품질검증
   ============================================================ */

/* 아래 필수검증에서 FAIL이 한 건이라도 나오면 06~07 구간을 실행하지 않는다. */

-- 거래 변환 대상 전체를 한 번의 RAW 스캔으로 검사한다.
WITH candidates AS (
    SELECT candidate.column_name, candidate.raw_value, candidate.target_type
    FROM raw.transaction_data
    CROSS JOIN LATERAL (VALUES
        ('household_key', household_key, 'BIGINT'),
        ('basket_id', basket_id, 'BIGINT'),
        ('day', day, 'INTEGER'),
        ('product_id', product_id, 'BIGINT'),
        ('quantity', quantity, 'INTEGER'),
        ('store_id', store_id, 'BIGINT'),
        ('trans_time', trans_time, 'INTEGER'),
        ('week_no', week_no, 'INTEGER'),
        ('sales_value', sales_value, 'NUMERIC'),
        ('retail_disc', retail_disc, 'NUMERIC'),
        ('coupon_disc', coupon_disc, 'NUMERIC'),
        ('coupon_match_disc', coupon_match_disc, 'NUMERIC')
    ) AS candidate(column_name, raw_value, target_type)
),
classified AS (
    SELECT column_name, raw_value, target_type,
           raw_value IS NULL AS is_null,
           raw_value IS NOT NULL AND BTRIM(raw_value) = '' AS is_empty,
           CASE
               WHEN raw_value IS NULL OR BTRIM(raw_value) = '' THEN FALSE
               WHEN target_type IN ('BIGINT', 'INTEGER') THEN BTRIM(raw_value) !~ '^[+-]?[0-9]+$'
               ELSE BTRIM(raw_value) !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$'
           END AS is_invalid_format,
           CASE
               WHEN raw_value IS NULL OR BTRIM(raw_value) = '' THEN FALSE
               WHEN target_type IN ('BIGINT', 'INTEGER') AND BTRIM(raw_value) ~ '^[+-]?[0-9]+$' THEN
                   CASE
                       WHEN target_type = 'BIGINT'
                            AND LENGTH(REGEXP_REPLACE(BTRIM(raw_value), '^[+-]?0*', '')) > 19 THEN TRUE
                       WHEN target_type = 'INTEGER'
                            AND LENGTH(REGEXP_REPLACE(BTRIM(raw_value), '^[+-]?0*', '')) > 10 THEN TRUE
                       WHEN target_type = 'BIGINT' THEN
                           BTRIM(raw_value)::NUMERIC NOT BETWEEN -9223372036854775808 AND 9223372036854775807
                       ELSE BTRIM(raw_value)::NUMERIC NOT BETWEEN -2147483648 AND 2147483647
                   END
               ELSE FALSE
           END AS is_out_of_range
    FROM candidates
)
SELECT
    'transaction_' || column_name || '_conversion' AS check_name,
    CASE WHEN COUNT(*) FILTER (WHERE is_invalid_format OR is_out_of_range) = 0
         THEN 'PASS' ELSE 'FAIL' END AS status,
    COUNT(*) FILTER (WHERE is_invalid_format OR is_out_of_range)::BIGINT AS issue_count,
    format('NULL=%s, empty=%s, invalid_format=%s, out_of_range=%s',
           COUNT(*) FILTER (WHERE is_null),
           COUNT(*) FILTER (WHERE is_empty),
           COUNT(*) FILTER (WHERE is_invalid_format),
           COUNT(*) FILTER (WHERE is_out_of_range)) AS detail
FROM classified
GROUP BY column_name
ORDER BY column_name;

-- 상품 변환 검증과 TEXT→BIGINT product_id 충돌을 한 번의 상품 스캔으로 확인한다.
WITH product_source AS MATERIALIZED (
    SELECT source_row_id, product_id, manufacturer,
           NULLIF(BTRIM(product_id), '') AS product_id_trimmed
    FROM raw.product
),
candidates AS (
    SELECT candidate.column_name, candidate.raw_value
    FROM product_source
    CROSS JOIN LATERAL (VALUES
        ('product_id', product_id),
        ('manufacturer', manufacturer)
    ) AS candidate(column_name, raw_value)
),
classified AS (
    SELECT column_name, raw_value,
           raw_value IS NULL AS is_null,
           raw_value IS NOT NULL AND BTRIM(raw_value) = '' AS is_empty,
           raw_value IS NOT NULL AND BTRIM(raw_value) <> ''
               AND BTRIM(raw_value) !~ '^[+-]?[0-9]+$' AS is_invalid_format,
           CASE
               WHEN raw_value IS NULL OR BTRIM(raw_value) = ''
                    OR BTRIM(raw_value) !~ '^[+-]?[0-9]+$' THEN FALSE
               WHEN LENGTH(REGEXP_REPLACE(BTRIM(raw_value), '^[+-]?0*', '')) > 19 THEN TRUE
               ELSE BTRIM(raw_value)::NUMERIC NOT BETWEEN -9223372036854775808 AND 9223372036854775807
           END AS is_out_of_range
    FROM candidates
),
conversion_checks AS (
    SELECT 'product_' || column_name || '_conversion' AS check_name,
           COUNT(*) FILTER (WHERE is_invalid_format OR is_out_of_range)::BIGINT AS issue_count,
           format('NULL=%s, empty=%s, invalid_format=%s, out_of_range=%s',
                  COUNT(*) FILTER (WHERE is_null),
                  COUNT(*) FILTER (WHERE is_empty),
                  COUNT(*) FILTER (WHERE is_invalid_format),
                  COUNT(*) FILTER (WHERE is_out_of_range)) AS detail
    FROM classified
    GROUP BY column_name
),
convertible_products AS (
    SELECT product_id_trimmed::BIGINT AS typed_product_id,
           COUNT(DISTINCT product_id_trimmed)::BIGINT AS original_text_count
    FROM product_source
    WHERE product_id_trimmed ~ '^[+-]?[0-9]+$'
      AND LENGTH(REGEXP_REPLACE(product_id_trimmed, '^[+-]?0*', '')) <= 19
      AND product_id_trimmed::NUMERIC BETWEEN -9223372036854775808 AND 9223372036854775807
    GROUP BY product_id_trimmed::BIGINT
),
collision_check AS (
    SELECT 'product_id_bigint_collision'::TEXT AS check_name,
           COUNT(*) FILTER (WHERE original_text_count > 1)::BIGINT AS issue_count,
           '서로 다른 원본 TEXT product_id가 동일한 BIGINT로 변환되는 키 수'::TEXT AS detail
    FROM convertible_products
)
SELECT check_name,
       CASE WHEN issue_count = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       issue_count,
       detail
FROM conversion_checks
UNION ALL
SELECT check_name,
       CASE WHEN issue_count = 0 THEN 'PASS' ELSE 'FAIL' END,
       issue_count,
       detail
FROM collision_check
ORDER BY check_name;

/* ============================================================
   06. BASE 스키마 및 Typed Staging 테이블 생성
   ============================================================ */

BEGIN;

CREATE SCHEMA IF NOT EXISTS base;

CREATE TABLE base.transaction_data (
    household_key       BIGINT,
    basket_id           BIGINT,
    day                 INTEGER,
    product_id          BIGINT,
    quantity            INTEGER,
    sales_value         NUMERIC,
    store_id            BIGINT,
    retail_disc         NUMERIC,
    trans_time          INTEGER,
    week_no             INTEGER,
    coupon_disc         NUMERIC,
    coupon_match_disc   NUMERIC,
    source_row_id       BIGINT PRIMARY KEY,
    source_file         TEXT,
    load_batch_id       TEXT,
    loaded_at           TIMESTAMPTZ,
    base_loaded_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE base.product (
    product_id           BIGINT PRIMARY KEY,
    manufacturer         BIGINT,
    department           TEXT,
    brand                TEXT,
    commodity_desc       TEXT,
    sub_commodity_desc   TEXT,
    curr_size_of_product TEXT,
    source_row_id        BIGINT UNIQUE,
    source_file          TEXT,
    load_batch_id        TEXT,
    loaded_at            TIMESTAMPTZ,
    base_loaded_at       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

/* ============================================================
   07. RAW → BASE 데이터 적재
   ============================================================ */

INSERT INTO base.transaction_data (
    household_key, basket_id, day, product_id, quantity, sales_value,
    store_id, retail_disc, trans_time, week_no, coupon_disc, coupon_match_disc,
    source_row_id, source_file, load_batch_id, loaded_at
)
SELECT
    NULLIF(BTRIM(household_key), '')::BIGINT,
    NULLIF(BTRIM(basket_id), '')::BIGINT,
    NULLIF(BTRIM(day), '')::INTEGER,
    NULLIF(BTRIM(product_id), '')::BIGINT,
    NULLIF(BTRIM(quantity), '')::INTEGER,
    NULLIF(BTRIM(sales_value), '')::NUMERIC,
    NULLIF(BTRIM(store_id), '')::BIGINT,
    NULLIF(BTRIM(retail_disc), '')::NUMERIC,
    NULLIF(BTRIM(trans_time), '')::INTEGER,
    NULLIF(BTRIM(week_no), '')::INTEGER,
    NULLIF(BTRIM(coupon_disc), '')::NUMERIC,
    NULLIF(BTRIM(coupon_match_disc), '')::NUMERIC,
    source_row_id,
    NULLIF(BTRIM(source_file), ''),
    NULLIF(BTRIM(load_batch_id), ''),
    loaded_at
FROM raw.transaction_data;

INSERT INTO base.product (
    product_id, manufacturer, department, brand, commodity_desc,
    sub_commodity_desc, curr_size_of_product,
    source_row_id, source_file, load_batch_id, loaded_at
)
SELECT
    NULLIF(BTRIM(product_id), '')::BIGINT,
    NULLIF(BTRIM(manufacturer), '')::BIGINT,
    NULLIF(BTRIM(department), ''),
    NULLIF(BTRIM(brand), ''),
    NULLIF(BTRIM(commodity_desc), ''),
    NULLIF(BTRIM(sub_commodity_desc), ''),
    NULLIF(BTRIM(curr_size_of_product), ''),
    source_row_id,
    NULLIF(BTRIM(source_file), ''),
    NULLIF(BTRIM(load_batch_id), ''),
    loaded_at
FROM raw.product;

CREATE INDEX idx_base_transaction_basket_id
    ON base.transaction_data (basket_id);
CREATE INDEX idx_base_transaction_product_id
    ON base.transaction_data (product_id);
CREATE INDEX idx_base_transaction_household_week
    ON base.transaction_data (household_key, week_no);
CREATE INDEX idx_base_transaction_household_day
    ON base.transaction_data (household_key, day);

COMMIT;

ANALYZE base.transaction_data;
ANALYZE base.product;

/* ============================================================
   08. BASE 적재 결과 검증
   ============================================================ */

-- 거래 lineage와 수량·금액 합계를 RAW·BASE 각 한 번의 스캔과 source_row_id 조인으로 대사한다.
WITH reconciliation AS (
    SELECT raw_data.source_row_id AS raw_source_row_id,
           base_data.source_row_id AS base_source_row_id,
           raw_data.household_key AS raw_household_key,
           raw_data.basket_id AS raw_basket_id,
           raw_data.product_id AS raw_product_id,
           raw_data.day AS raw_day,
           raw_data.week_no AS raw_week_no,
           raw_data.quantity AS raw_quantity,
           raw_data.sales_value AS raw_sales_value,
           raw_data.retail_disc AS raw_retail_disc,
           raw_data.coupon_disc AS raw_coupon_disc,
           raw_data.coupon_match_disc AS raw_coupon_match_disc,
           base_data.household_key, base_data.basket_id, base_data.product_id,
           base_data.day, base_data.week_no, base_data.quantity,
           base_data.sales_value, base_data.retail_disc,
           base_data.coupon_disc, base_data.coupon_match_disc
    FROM raw.transaction_data AS raw_data
    FULL JOIN base.transaction_data AS base_data USING (source_row_id)
),
summary AS (
    SELECT COUNT(raw_source_row_id)::BIGINT AS raw_row_count,
           COUNT(base_source_row_id)::BIGINT AS base_row_count,
           COUNT(*) FILTER (WHERE raw_source_row_id IS NOT NULL AND base_source_row_id IS NULL)::BIGINT AS missing_in_base,
           COUNT(*) FILTER (WHERE raw_source_row_id IS NULL AND base_source_row_id IS NOT NULL)::BIGINT AS extra_in_base,
           COUNT(*) FILTER (
               WHERE raw_source_row_id IS NOT NULL AND base_source_row_id IS NOT NULL
                 AND (household_key IS DISTINCT FROM NULLIF(BTRIM(raw_household_key), '')::BIGINT
                   OR basket_id IS DISTINCT FROM NULLIF(BTRIM(raw_basket_id), '')::BIGINT
                   OR product_id IS DISTINCT FROM NULLIF(BTRIM(raw_product_id), '')::BIGINT
                   OR day IS DISTINCT FROM NULLIF(BTRIM(raw_day), '')::INTEGER
                   OR week_no IS DISTINCT FROM NULLIF(BTRIM(raw_week_no), '')::INTEGER)
           )::BIGINT AS key_mismatch_count,
           SUM(NULLIF(BTRIM(raw_quantity), '')::NUMERIC) AS raw_quantity_sum,
           SUM(quantity::NUMERIC) AS base_quantity_sum,
           SUM(NULLIF(BTRIM(raw_sales_value), '')::NUMERIC) AS raw_sales_value_sum,
           SUM(sales_value) AS base_sales_value_sum,
           SUM(NULLIF(BTRIM(raw_retail_disc), '')::NUMERIC) AS raw_retail_disc_sum,
           SUM(retail_disc) AS base_retail_disc_sum,
           SUM(NULLIF(BTRIM(raw_coupon_disc), '')::NUMERIC) AS raw_coupon_disc_sum,
           SUM(coupon_disc) AS base_coupon_disc_sum,
           SUM(NULLIF(BTRIM(raw_coupon_match_disc), '')::NUMERIC) AS raw_coupon_match_disc_sum,
           SUM(coupon_match_disc) AS base_coupon_match_disc_sum
    FROM reconciliation
),
checks AS (
    SELECT check_name, issue_count, detail
    FROM summary
    CROSS JOIN LATERAL (VALUES
        ('transaction_row_count_match', ABS(raw_row_count - base_row_count),
         format('RAW=%s, BASE=%s', raw_row_count, base_row_count)),
        ('transaction_source_row_missing', missing_in_base, 'RAW에는 있으나 BASE에는 없는 source_row_id'),
        ('transaction_source_row_extra', extra_in_base, 'BASE에만 존재하는 source_row_id'),
        ('transaction_core_key_match', key_mismatch_count, '고객·장바구니·상품·day·week_no 변환 불일치'),
        ('quantity_sum_match', CASE WHEN raw_quantity_sum IS DISTINCT FROM base_quantity_sum THEN 1 ELSE 0 END,
         format('RAW=%s, BASE=%s', raw_quantity_sum, base_quantity_sum)),
        ('sales_value_sum_match', CASE WHEN raw_sales_value_sum IS DISTINCT FROM base_sales_value_sum THEN 1 ELSE 0 END,
         format('RAW=%s, BASE=%s', raw_sales_value_sum, base_sales_value_sum)),
        ('retail_disc_sum_match', CASE WHEN raw_retail_disc_sum IS DISTINCT FROM base_retail_disc_sum THEN 1 ELSE 0 END,
         format('RAW=%s, BASE=%s', raw_retail_disc_sum, base_retail_disc_sum)),
        ('coupon_disc_sum_match', CASE WHEN raw_coupon_disc_sum IS DISTINCT FROM base_coupon_disc_sum THEN 1 ELSE 0 END,
         format('RAW=%s, BASE=%s', raw_coupon_disc_sum, base_coupon_disc_sum)),
        ('coupon_match_disc_sum_match', CASE WHEN raw_coupon_match_disc_sum IS DISTINCT FROM base_coupon_match_disc_sum THEN 1 ELSE 0 END,
         format('RAW=%s, BASE=%s', raw_coupon_match_disc_sum, base_coupon_match_disc_sum))
    ) AS check_value(check_name, issue_count, detail)
)
SELECT check_name,
       CASE WHEN issue_count = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       issue_count::BIGINT,
       detail
FROM checks
ORDER BY check_name;

-- 상품 lineage는 작은 상품 테이블을 한 번 대사한다.
WITH summary AS (
    SELECT COUNT(raw_data.source_row_id)::BIGINT AS raw_row_count,
           COUNT(base_data.source_row_id)::BIGINT AS base_row_count,
           COUNT(*) FILTER (WHERE raw_data.source_row_id IS NOT NULL AND base_data.source_row_id IS NULL)::BIGINT AS missing_in_base,
           COUNT(*) FILTER (WHERE raw_data.source_row_id IS NULL AND base_data.source_row_id IS NOT NULL)::BIGINT AS extra_in_base,
           COUNT(*) FILTER (
               WHERE raw_data.source_row_id IS NOT NULL AND base_data.source_row_id IS NOT NULL
                 AND base_data.product_id IS DISTINCT FROM NULLIF(BTRIM(raw_data.product_id), '')::BIGINT
           )::BIGINT AS key_mismatch_count
    FROM raw.product AS raw_data
    FULL JOIN base.product AS base_data USING (source_row_id)
)
SELECT check_name,
       CASE WHEN issue_count = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       issue_count::BIGINT,
       detail
FROM summary
CROSS JOIN LATERAL (VALUES
    ('product_row_count_match', ABS(raw_row_count - base_row_count), format('RAW=%s, BASE=%s', raw_row_count, base_row_count)),
    ('product_source_row_missing', missing_in_base, 'RAW에는 있으나 BASE에는 없는 source_row_id'),
    ('product_source_row_extra', extra_in_base, 'BASE에만 존재하는 source_row_id'),
    ('product_key_match', key_mismatch_count, 'product_id 변환 불일치')
) AS check_value(check_name, issue_count, detail)
ORDER BY check_name;

-- 한 번의 GROUPING SETS 집계로 exact duplicate, 거래 grain, 장바구니 일관성을 계산한다.
WITH grouped AS MATERIALIZED (
    SELECT GROUPING(day) AS day_grouped,
           GROUPING(household_key) AS household_grouped,
           basket_id,
           COUNT(*)::BIGINT AS row_count,
           MIN(household_key) AS min_household, MAX(household_key) AS max_household,
           MIN(day) AS min_day, MAX(day) AS max_day,
           MIN(week_no) AS min_week, MAX(week_no) AS max_week,
           MIN(store_id) AS min_store, MAX(store_id) AS max_store,
           MIN(trans_time) AS min_time, MAX(trans_time) AS max_time
    FROM base.transaction_data
    GROUP BY GROUPING SETS (
        (household_key, basket_id, day, product_id, quantity, sales_value,
         store_id, retail_disc, trans_time, week_no, coupon_disc, coupon_match_disc),
        (household_key, basket_id, product_id),
        (basket_id)
    )
),
summary AS (
    SELECT COALESCE(SUM(row_count - 1) FILTER (WHERE day_grouped = 0 AND row_count > 1), 0)::BIGINT AS exact_duplicate_extra_rows,
           COALESCE(SUM(row_count - 1) FILTER (WHERE day_grouped = 1 AND household_grouped = 0 AND row_count > 1), 0)::BIGINT AS grain_duplicate_extra_rows,
           COUNT(*) FILTER (WHERE household_grouped = 1 AND basket_id IS NOT NULL AND min_household IS DISTINCT FROM max_household)::BIGINT AS household_issues,
           COUNT(*) FILTER (WHERE household_grouped = 1 AND basket_id IS NOT NULL AND min_day IS DISTINCT FROM max_day)::BIGINT AS day_issues,
           COUNT(*) FILTER (WHERE household_grouped = 1 AND basket_id IS NOT NULL AND min_week IS DISTINCT FROM max_week)::BIGINT AS week_issues,
           COUNT(*) FILTER (WHERE household_grouped = 1 AND basket_id IS NOT NULL AND min_store IS DISTINCT FROM max_store)::BIGINT AS store_issues,
           COUNT(*) FILTER (WHERE household_grouped = 1 AND basket_id IS NOT NULL AND min_time IS DISTINCT FROM max_time)::BIGINT AS time_issues
    FROM grouped
)
SELECT check_name,
       CASE WHEN issue_count = 0 THEN 'PASS'
            WHEN check_name = 'basket_multiple_household' THEN 'FAIL'
            ELSE 'WARN' END AS status,
       issue_count::BIGINT,
       detail
FROM summary
CROSS JOIN LATERAL (VALUES
    ('transaction_exact_duplicate_extra_rows', exact_duplicate_extra_rows, '12개 분석 컬럼이 같은 추가 행 수; 삭제하지 않음'),
    ('household_basket_product_duplicate_extra_rows', grain_duplicate_extra_rows, '고객·장바구니·상품 조합 추가 행 수; 합산하지 않음'),
    ('basket_multiple_household', household_issues, '여러 고객에 연결된 basket_id 수'),
    ('basket_multiple_day', day_issues, '여러 day에 연결된 basket_id 수'),
    ('basket_multiple_week', week_issues, '여러 week_no에 연결된 basket_id 수'),
    ('basket_multiple_store', store_issues, '여러 store_id에 연결된 basket_id 수'),
    ('basket_multiple_time', time_issues, '여러 trans_time에 연결된 basket_id 수')
) AS check_value(check_name, issue_count, detail)
ORDER BY check_name;


-- 분석값 범위, 부호, HHMM을 한 번의 BASE 스캔으로 집계한 뒤 행 형태로 출력한다.
WITH summary AS (
    SELECT MIN(day) AS min_day, MAX(day) AS max_day,
           MIN(week_no) AS min_week_no, MAX(week_no) AS max_week_no,
           MIN(quantity) AS min_quantity, MAX(quantity) AS max_quantity,
           MIN(sales_value) AS min_sales_value, MAX(sales_value) AS max_sales_value,
           MIN(retail_disc) AS min_retail_disc, MAX(retail_disc) AS max_retail_disc,
           MIN(coupon_disc) AS min_coupon_disc, MAX(coupon_disc) AS max_coupon_disc,
           MIN(coupon_match_disc) AS min_coupon_match_disc, MAX(coupon_match_disc) AS max_coupon_match_disc,
           COUNT(*) FILTER (WHERE quantity <= 0)::BIGINT AS nonpositive_quantity,
           COUNT(*) FILTER (WHERE sales_value < 0)::BIGINT AS negative_sales,
           COUNT(*) FILTER (WHERE sales_value = 0)::BIGINT AS zero_sales,
           COUNT(*) FILTER (WHERE retail_disc < 0)::BIGINT AS retail_negative,
           COUNT(*) FILTER (WHERE retail_disc = 0)::BIGINT AS retail_zero,
           COUNT(*) FILTER (WHERE retail_disc > 0)::BIGINT AS retail_positive,
           COUNT(*) FILTER (WHERE coupon_disc < 0)::BIGINT AS coupon_negative,
           COUNT(*) FILTER (WHERE coupon_disc = 0)::BIGINT AS coupon_zero,
           COUNT(*) FILTER (WHERE coupon_disc > 0)::BIGINT AS coupon_positive,
           COUNT(*) FILTER (WHERE coupon_match_disc < 0)::BIGINT AS match_negative,
           COUNT(*) FILTER (WHERE coupon_match_disc = 0)::BIGINT AS match_zero,
           COUNT(*) FILTER (WHERE coupon_match_disc > 0)::BIGINT AS match_positive,
           COUNT(*) FILTER (WHERE trans_time IS NOT NULL
                              AND (trans_time NOT BETWEEN 0 AND 2359 OR MOD(trans_time, 100) > 59))::BIGINT AS invalid_hhmm
    FROM base.transaction_data
)
SELECT check_name,
       CASE WHEN fail_condition THEN 'FAIL'
            WHEN warn_condition THEN 'WARN'
            ELSE 'PASS' END AS status,
       issue_count,
       detail
FROM summary
CROSS JOIN LATERAL (VALUES
    ('day_range', FALSE, FALSE, 0::BIGINT, format('min=%s, max=%s; 상대 관찰일 번호', min_day, max_day)),
    ('week_no_range', FALSE, FALSE, 0::BIGINT, format('min=%s, max=%s', min_week_no, max_week_no)),
    ('quantity_range', FALSE, nonpositive_quantity > 0, nonpositive_quantity, format('min=%s, max=%s, quantity<=0=%s', min_quantity, max_quantity, nonpositive_quantity)),
    ('sales_value_range', FALSE, negative_sales + zero_sales > 0, negative_sales + zero_sales, format('min=%s, max=%s, negative=%s, zero=%s', min_sales_value, max_sales_value, negative_sales, zero_sales)),
    ('retail_disc_distribution', FALSE, FALSE, 0::BIGINT, format('min=%s, max=%s, negative=%s, zero=%s, positive=%s', min_retail_disc, max_retail_disc, retail_negative, retail_zero, retail_positive)),
    ('coupon_disc_distribution', FALSE, FALSE, 0::BIGINT, format('min=%s, max=%s, negative=%s, zero=%s, positive=%s', min_coupon_disc, max_coupon_disc, coupon_negative, coupon_zero, coupon_positive)),
    ('coupon_match_disc_distribution', FALSE, FALSE, 0::BIGINT, format('min=%s, max=%s, negative=%s, zero=%s, positive=%s', min_coupon_match_disc, max_coupon_match_disc, match_negative, match_zero, match_positive)),
    ('trans_time_valid_hhmm', invalid_hhmm > 0, FALSE, invalid_hhmm, '0000~2359이며 분 값이 00~59인지 확인')
) AS check_value(check_name, fail_condition, warn_condition, issue_count, detail)
ORDER BY check_name;


-----------------0값이 어떤 형태인지 확인--------------------
SELECT
    COUNT(*) FILTER (
        WHERE quantity = 0
          AND sales_value = 0
    ) AS quantity_zero_sales_zero,

    COUNT(*) FILTER (
        WHERE quantity = 0
          AND sales_value > 0
    ) AS quantity_zero_sales_positive,

    COUNT(*) FILTER (
        WHERE quantity > 0
          AND sales_value = 0
    ) AS quantity_positive_sales_zero,

    COUNT(*) FILTER (
        WHERE quantity > 0
          AND sales_value > 0
    ) AS quantity_positive_sales_positive,

    COUNT(*) FILTER (
        WHERE quantity < 0
    ) AS quantity_negative,

    COUNT(*) FILTER (
        WHERE sales_value < 0
    ) AS sales_value_negative
FROM base.transaction_data;


----------------할인값과 함께 확인-----------------
SELECT
    quantity,
    sales_value,
    retail_disc,
    coupon_disc,
    coupon_match_disc,
    COUNT(*) AS row_count
FROM base.transaction_data
WHERE quantity = 0
   OR sales_value = 0
GROUP BY
    quantity,
    sales_value,
    retail_disc,
    coupon_disc,
    coupon_match_disc
ORDER BY row_count DESC
LIMIT 30;


------------------최대 수량 89,638 확인-------------------
SELECT
    t.household_key,
    t.basket_id,
    t.week_no,
    t.day,
    t.product_id,
    t.quantity,
    t.sales_value,
    p.department,
    p.commodity_desc,
    p.sub_commodity_desc
FROM base.transaction_data AS t
LEFT JOIN base.product AS p
    ON t.product_id = p.product_id
WHERE t.quantity >= 100
ORDER BY t.quantity DESC
LIMIT 100;

-- 거래 상품 연결과 카테고리 결측을 각각 한 번만 집계한다.
WITH mapping AS (
    SELECT COUNT(*)::BIGINT AS transaction_count,
           COUNT(product.product_id)::BIGINT AS matched_count
    FROM base.transaction_data AS transaction_data
    LEFT JOIN base.product AS product USING (product_id)
),
category_nulls AS (
    SELECT COUNT(*) FILTER (WHERE department IS NULL)::BIGINT AS department_nulls,
           COUNT(*) FILTER (WHERE brand IS NULL)::BIGINT AS brand_nulls,
           COUNT(*) FILTER (WHERE commodity_desc IS NULL)::BIGINT AS commodity_nulls,
           COUNT(*) FILTER (WHERE sub_commodity_desc IS NULL)::BIGINT AS sub_commodity_nulls,
           COUNT(*) FILTER (WHERE curr_size_of_product IS NULL)::BIGINT AS size_nulls
    FROM base.product
)
SELECT check_name,
       CASE WHEN fail_condition AND issue_count > 0 THEN 'FAIL'
            WHEN issue_count > 0 THEN 'WARN'
            ELSE 'PASS' END AS status,
       issue_count,
       detail
FROM mapping
CROSS JOIN category_nulls
CROSS JOIN LATERAL (VALUES
    ('transaction_product_mapping', TRUE, transaction_count - matched_count,
     format('전체 거래=%s, 연결=%s, 매핑률=%s%%', transaction_count, matched_count,
            ROUND(100 * matched_count::NUMERIC / NULLIF(transaction_count, 0), 6))),
    ('product_department_null', FALSE, department_nulls, '카테고리 분석용 department NULL 수'),
    ('product_brand_null', FALSE, brand_nulls, '카테고리 분석용 brand NULL 수'),
    ('product_commodity_desc_null', FALSE, commodity_nulls, '카테고리 분석용 commodity_desc NULL 수'),
    ('product_sub_commodity_desc_null', FALSE, sub_commodity_nulls, '카테고리 분석용 sub_commodity_desc NULL 수'),
    ('product_curr_size_null', FALSE, size_nulls, '카테고리 분석용 curr_size_of_product NULL 수')
) AS check_value(check_name, fail_condition, issue_count, detail)
ORDER BY check_name;

-- ============================================================
-- 카테고리 결측 상품의 거래 영향 확인
-- ============================================================
WITH affected_products AS (
    SELECT
        product_id,
        department,
        commodity_desc,
        sub_commodity_desc
    FROM base.product
    WHERE department IS NULL
       OR commodity_desc IS NULL
       OR sub_commodity_desc IS NULL
)
SELECT
    COUNT(DISTINCT p.product_id) AS category_null_product_count,

    COUNT(DISTINCT p.product_id) FILTER (
        WHERE p.department IS NULL
          AND p.commodity_desc IS NULL
          AND p.sub_commodity_desc IS NULL
    ) AS all_category_null_product_count,

    COUNT(DISTINCT t.product_id) AS used_product_count,
    COUNT(t.product_id) AS transaction_row_count,
    COUNT(DISTINCT t.basket_id) AS basket_count,
    COUNT(DISTINCT t.household_key) AS household_count,
    COALESCE(SUM(t.sales_value), 0) AS total_sales

FROM affected_products AS p
LEFT JOIN base.transaction_data AS t
    ON p.product_id = t.product_id;


-- ============================================================
-- 03_mart_fact_kpi
-- 장바구니 Fact, 가구×주차 Fact, 주간 KPI
-- ============================================================

-- 03-1. MART 스키마 및 재실행 준비
BEGIN;

CREATE SCHEMA IF NOT EXISTS mart;

DROP TABLE IF EXISTS mart.weekly_kpi;
DROP TABLE IF EXISTS mart.fact_household_week;
DROP TABLE IF EXISTS mart.fact_basket;

-- 03-2. mart.fact_basket 생성
CREATE TABLE mart.fact_basket AS
WITH line_data AS (
    SELECT
        transaction_data.household_key,
        transaction_data.basket_id,
        transaction_data.day,
        transaction_data.week_no,
        transaction_data.store_id,
        transaction_data.trans_time,
        transaction_data.product_id,
        transaction_data.quantity,
        transaction_data.sales_value,
        transaction_data.retail_disc,
        transaction_data.coupon_disc,
        transaction_data.coupon_match_disc,
        product.department,
        product.commodity_desc,
        product.sub_commodity_desc,
        transaction_data.quantity > 0
            AND transaction_data.sales_value > 0 AS is_paid_line,
        COALESCE(transaction_data.retail_disc, 0) <> 0
            OR COALESCE(transaction_data.coupon_disc, 0) <> 0
            OR COALESCE(transaction_data.coupon_match_disc, 0) <> 0 AS has_discount,
        UPPER(TRIM(product.sub_commodity_desc)) = 'GASOLINE-REG UNLEADED' AS is_fuel,
        product.department IS NULL
            OR product.commodity_desc IS NULL
            OR product.sub_commodity_desc IS NULL AS has_unknown_category
    FROM base.transaction_data AS transaction_data
    LEFT JOIN base.product AS product
        ON product.product_id = transaction_data.product_id
)
SELECT
    MIN(household_key) AS household_key,
    basket_id,
    MIN(day) AS day,
    MIN(week_no) AS week_no,
    MIN(store_id) AS store_id,
    MIN(trans_time) AS trans_time,
    COUNT(*)::BIGINT AS total_line_count,
    COALESCE(SUM(sales_value), 0::NUMERIC) AS basket_sales,
    COALESCE(SUM(sales_value) FILTER (WHERE is_paid_line), 0::NUMERIC) AS paid_line_sales,
    COALESCE(SUM(sales_value) FILTER (
        WHERE quantity = 0 AND sales_value > 0
    ), 0::NUMERIC) AS zero_quantity_sales_amount,
    COUNT(*) FILTER (WHERE is_paid_line)::BIGINT AS paid_line_count,
    COUNT(DISTINCT product_id) FILTER (WHERE is_paid_line)::BIGINT AS paid_product_count,
    COUNT(DISTINCT department) FILTER (
        WHERE is_paid_line AND department IS NOT NULL
    )::BIGINT AS paid_department_count,
    COUNT(DISTINCT commodity_desc) FILTER (
        WHERE is_paid_line AND commodity_desc IS NOT NULL
    )::BIGINT AS paid_commodity_count,
    COALESCE(SUM(quantity) FILTER (
        WHERE is_paid_line
          AND is_fuel IS NOT TRUE
    ), 0)::BIGINT AS paid_merchandise_quantity,
    COALESCE(SUM(quantity) FILTER (
        WHERE is_paid_line
          AND is_fuel IS TRUE
    ), 0)::BIGINT AS fuel_quantity_raw,
    COALESCE(SUM(
        GREATEST(-COALESCE(retail_disc, 0), 0)
        + GREATEST(-COALESCE(coupon_disc, 0), 0)
        + GREATEST(-COALESCE(coupon_match_disc, 0), 0)
    ), 0::NUMERIC) AS discount_amount,
    COUNT(*) FILTER (
        WHERE quantity > 0 AND sales_value = 0 AND has_discount
    )::BIGINT AS discounted_zero_sales_line_count,
    COALESCE(SUM(quantity) FILTER (
        WHERE quantity > 0 AND sales_value = 0 AND has_discount
    ), 0)::BIGINT AS discounted_zero_sales_quantity,
    COUNT(*) FILTER (
        WHERE quantity > 0 AND sales_value = 0 AND NOT has_discount
    )::BIGINT AS unexplained_zero_sales_line_count,
    COALESCE(SUM(quantity) FILTER (
        WHERE quantity > 0 AND sales_value = 0 AND NOT has_discount
    ), 0)::BIGINT AS unexplained_zero_sales_quantity,
    COUNT(*) FILTER (
        WHERE quantity = 0 AND sales_value > 0
    )::BIGINT AS zero_quantity_sale_line_count,
    COUNT(*) FILTER (
        WHERE quantity = 0 AND sales_value = 0 AND NOT has_discount
    )::BIGINT AS zero_activity_line_count,
    COUNT(*) FILTER (
        WHERE quantity = 0 AND sales_value = 0 AND has_discount
    )::BIGINT AS discount_adjustment_line_count,
    COUNT(*) FILTER (WHERE has_unknown_category)::BIGINT AS unknown_category_line_count,
    BOOL_OR(has_unknown_category) AS has_unknown_category_item,
    BOOL_OR(is_paid_line) AS is_valid_purchase_basket
FROM line_data
GROUP BY basket_id;

ALTER TABLE mart.fact_basket
    ADD CONSTRAINT pk_fact_basket PRIMARY KEY (basket_id);

-- 03-3. fact_basket 인덱스 및 통계
CREATE INDEX idx_fact_basket_household_key
    ON mart.fact_basket (household_key);
CREATE INDEX idx_fact_basket_week_no
    ON mart.fact_basket (week_no);
CREATE INDEX idx_fact_basket_household_week
    ON mart.fact_basket (household_key, week_no);
CREATE INDEX idx_fact_basket_valid_purchase
    ON mart.fact_basket (is_valid_purchase_basket);

ANALYZE mart.fact_basket;

-- 03-4. mart.fact_household_week 생성
CREATE TABLE mart.fact_household_week AS
WITH observed_household_weeks AS MATERIALIZED (
    SELECT transaction_data.household_key, transaction_data.week_no
    FROM base.transaction_data AS transaction_data
    WHERE transaction_data.household_key IS NOT NULL
      AND transaction_data.week_no IS NOT NULL
    GROUP BY transaction_data.household_key, transaction_data.week_no
),
households AS (
    SELECT household_key
    FROM observed_household_weeks
    GROUP BY household_key
),
weeks AS (
    SELECT week_no
    FROM observed_household_weeks
    GROUP BY week_no
),
household_week_grid AS (
    SELECT households.household_key, weeks.week_no
    FROM households
    CROSS JOIN weeks
),
basket_metrics AS (
    SELECT
        fact_basket.household_key,
        fact_basket.week_no,
        COUNT(*)::BIGINT AS recorded_basket_count,
        COUNT(*) FILTER (WHERE fact_basket.is_valid_purchase_basket)::BIGINT AS valid_basket_count,
        COUNT(*) FILTER (WHERE NOT fact_basket.is_valid_purchase_basket)::BIGINT AS invalid_basket_count,
        COUNT(DISTINCT fact_basket.day) FILTER (
            WHERE fact_basket.is_valid_purchase_basket
        )::BIGINT AS purchase_day_count,
        COALESCE(SUM(fact_basket.basket_sales) FILTER (
            WHERE fact_basket.is_valid_purchase_basket
        ), 0::NUMERIC) AS weekly_sales,
        COALESCE(SUM(fact_basket.paid_line_sales) FILTER (
            WHERE fact_basket.is_valid_purchase_basket
        ), 0::NUMERIC) AS paid_line_sales,
        COALESCE(SUM(fact_basket.paid_merchandise_quantity) FILTER (
            WHERE fact_basket.is_valid_purchase_basket
        ), 0)::BIGINT AS paid_merchandise_quantity,
        COALESCE(SUM(fact_basket.fuel_quantity_raw) FILTER (
            WHERE fact_basket.is_valid_purchase_basket
        ), 0)::BIGINT AS fuel_quantity_raw,
        COALESCE(SUM(fact_basket.discount_amount) FILTER (
            WHERE fact_basket.is_valid_purchase_basket
        ), 0::NUMERIC) AS discount_amount,
        COALESCE(SUM(fact_basket.discounted_zero_sales_line_count), 0)::BIGINT
            AS discounted_zero_sales_line_count,
        COALESCE(SUM(fact_basket.unexplained_zero_sales_line_count), 0)::BIGINT
            AS unexplained_zero_sales_line_count,
        COALESCE(SUM(fact_basket.zero_quantity_sale_line_count), 0)::BIGINT
            AS zero_quantity_sale_line_count,
        COALESCE(SUM(fact_basket.zero_activity_line_count), 0)::BIGINT
            AS zero_activity_line_count,
        COALESCE(SUM(fact_basket.discount_adjustment_line_count), 0)::BIGINT
            AS discount_adjustment_line_count,
        COALESCE(SUM(fact_basket.unknown_category_line_count), 0)::BIGINT
            AS unknown_category_line_count,
        BOOL_OR(fact_basket.has_unknown_category_item) AS has_unknown_category_item
    FROM mart.fact_basket AS fact_basket
    GROUP BY fact_basket.household_key, fact_basket.week_no
),
paid_distinct_counts AS (
    SELECT
        transaction_data.household_key,
        transaction_data.week_no,
        COUNT(DISTINCT transaction_data.product_id)::BIGINT AS paid_product_count,
        COUNT(DISTINCT product.department) FILTER (
            WHERE product.department IS NOT NULL
        )::BIGINT AS paid_department_count,
        COUNT(DISTINCT product.commodity_desc) FILTER (
            WHERE product.commodity_desc IS NOT NULL
        )::BIGINT AS paid_commodity_count
    FROM base.transaction_data AS transaction_data
    LEFT JOIN base.product AS product
        ON product.product_id = transaction_data.product_id
    WHERE transaction_data.quantity > 0
      AND transaction_data.sales_value > 0
      AND transaction_data.household_key IS NOT NULL
      AND transaction_data.week_no IS NOT NULL
    GROUP BY transaction_data.household_key, transaction_data.week_no
),
combined AS (
    SELECT
        household_week_grid.household_key,
        household_week_grid.week_no,
        COALESCE(basket_metrics.recorded_basket_count, 0)::BIGINT AS recorded_basket_count,
        COALESCE(basket_metrics.valid_basket_count, 0)::BIGINT AS valid_basket_count,
        COALESCE(basket_metrics.invalid_basket_count, 0)::BIGINT AS invalid_basket_count,
        COALESCE(basket_metrics.purchase_day_count, 0)::BIGINT AS purchase_day_count,
        COALESCE(basket_metrics.weekly_sales, 0::NUMERIC) AS weekly_sales,
        COALESCE(basket_metrics.paid_line_sales, 0::NUMERIC) AS paid_line_sales,
        COALESCE(basket_metrics.paid_merchandise_quantity, 0)::BIGINT AS paid_merchandise_quantity,
        COALESCE(basket_metrics.fuel_quantity_raw, 0)::BIGINT AS fuel_quantity_raw,
        COALESCE(paid_distinct_counts.paid_product_count, 0)::BIGINT AS paid_product_count,
        COALESCE(paid_distinct_counts.paid_department_count, 0)::BIGINT AS paid_department_count,
        COALESCE(paid_distinct_counts.paid_commodity_count, 0)::BIGINT AS paid_commodity_count,
        COALESCE(basket_metrics.discount_amount, 0::NUMERIC) AS discount_amount,
        COALESCE(basket_metrics.discounted_zero_sales_line_count, 0)::BIGINT
            AS discounted_zero_sales_line_count,
        COALESCE(basket_metrics.unexplained_zero_sales_line_count, 0)::BIGINT
            AS unexplained_zero_sales_line_count,
        COALESCE(basket_metrics.zero_quantity_sale_line_count, 0)::BIGINT
            AS zero_quantity_sale_line_count,
        COALESCE(basket_metrics.zero_activity_line_count, 0)::BIGINT
            AS zero_activity_line_count,
        COALESCE(basket_metrics.discount_adjustment_line_count, 0)::BIGINT
            AS discount_adjustment_line_count,
        COALESCE(basket_metrics.unknown_category_line_count, 0)::BIGINT
            AS unknown_category_line_count,
        COALESCE(basket_metrics.has_unknown_category_item, FALSE) AS has_unknown_category_item
    FROM household_week_grid
    LEFT JOIN basket_metrics
        ON basket_metrics.household_key = household_week_grid.household_key
       AND basket_metrics.week_no = household_week_grid.week_no
    LEFT JOIN paid_distinct_counts
        ON paid_distinct_counts.household_key = household_week_grid.household_key
       AND paid_distinct_counts.week_no = household_week_grid.week_no
)
SELECT
    household_key,
    week_no,
    recorded_basket_count,
    valid_basket_count,
    invalid_basket_count,
    purchase_day_count,
    weekly_sales,
    paid_line_sales,
    COALESCE(
        weekly_sales / NULLIF(valid_basket_count, 0),
        0::NUMERIC
    ) AS average_basket_value,
    paid_merchandise_quantity,
    fuel_quantity_raw,
    paid_product_count,
    paid_department_count,
    paid_commodity_count,
    discount_amount,
    discounted_zero_sales_line_count,
    unexplained_zero_sales_line_count,
    zero_quantity_sale_line_count,
    zero_activity_line_count,
    discount_adjustment_line_count,
    unknown_category_line_count,
    has_unknown_category_item,
    valid_basket_count > 0 AS has_valid_purchase
FROM combined;

ALTER TABLE mart.fact_household_week
    ADD CONSTRAINT pk_fact_household_week PRIMARY KEY (household_key, week_no);

-- 03-5. fact_household_week 인덱스 및 통계
CREATE INDEX idx_fact_household_week_week_no
    ON mart.fact_household_week (week_no);
CREATE INDEX idx_fact_household_week_valid_purchase
    ON mart.fact_household_week (has_valid_purchase);
CREATE INDEX idx_fact_household_week_week_valid
    ON mart.fact_household_week (week_no, has_valid_purchase);

ANALYZE mart.fact_household_week;

-- 03-6. mart.weekly_kpi 생성
CREATE TABLE mart.weekly_kpi AS
WITH household_week_metrics AS (
    SELECT
        fact_household_week.week_no,
        COUNT(*)::BIGINT AS total_household_count,
        COUNT(*) FILTER (
            WHERE fact_household_week.valid_basket_count > 0
        )::BIGINT AS active_household_count,
        COALESCE(SUM(fact_household_week.valid_basket_count), 0)::BIGINT AS valid_basket_count,
        COALESCE(SUM(fact_household_week.weekly_sales), 0::NUMERIC) AS weekly_sales,
        COALESCE(SUM(fact_household_week.purchase_day_count), 0)::BIGINT
            AS household_purchase_day_count,
        COALESCE(SUM(fact_household_week.paid_merchandise_quantity), 0)::BIGINT
            AS paid_merchandise_quantity,
        COALESCE(SUM(fact_household_week.fuel_quantity_raw), 0)::BIGINT AS fuel_quantity_raw,
        COALESCE(SUM(fact_household_week.discount_amount), 0::NUMERIC) AS discount_amount,
        COALESCE(SUM(fact_household_week.discounted_zero_sales_line_count), 0)::BIGINT
            AS discounted_zero_sales_line_count,
        COALESCE(SUM(fact_household_week.unexplained_zero_sales_line_count), 0)::BIGINT
            AS unexplained_zero_sales_line_count,
        COALESCE(SUM(fact_household_week.zero_quantity_sale_line_count), 0)::BIGINT
            AS zero_quantity_sale_line_count,
        COALESCE(SUM(fact_household_week.zero_activity_line_count), 0)::BIGINT
            AS zero_activity_line_count,
        COALESCE(SUM(fact_household_week.discount_adjustment_line_count), 0)::BIGINT
            AS discount_adjustment_line_count,
        COALESCE(SUM(fact_household_week.unknown_category_line_count), 0)::BIGINT
            AS unknown_category_line_count,
        COUNT(*) FILTER (
            WHERE fact_household_week.unknown_category_line_count > 0
        )::BIGINT AS unknown_category_household_count
    FROM mart.fact_household_week AS fact_household_week
    GROUP BY fact_household_week.week_no
),
weekly_paid_distinct_counts AS (
    SELECT
        transaction_data.week_no,
        COUNT(DISTINCT transaction_data.product_id)::BIGINT AS weekly_paid_product_count,
        COUNT(DISTINCT product.department) FILTER (
            WHERE product.department IS NOT NULL
        )::BIGINT AS weekly_paid_department_count,
        COUNT(DISTINCT product.commodity_desc) FILTER (
            WHERE product.commodity_desc IS NOT NULL
        )::BIGINT AS weekly_paid_commodity_count
    FROM base.transaction_data AS transaction_data
    LEFT JOIN base.product AS product
        ON product.product_id = transaction_data.product_id
    WHERE transaction_data.quantity > 0
      AND transaction_data.sales_value > 0
      AND transaction_data.week_no IS NOT NULL
    GROUP BY transaction_data.week_no
)
SELECT
    household_week_metrics.week_no,
    household_week_metrics.total_household_count,
    household_week_metrics.active_household_count,
    COALESCE(
        household_week_metrics.active_household_count::NUMERIC
            / NULLIF(household_week_metrics.total_household_count, 0),
        0::NUMERIC
    ) AS active_household_rate,
    household_week_metrics.valid_basket_count,
    household_week_metrics.weekly_sales,
    COALESCE(
        household_week_metrics.weekly_sales
            / NULLIF(household_week_metrics.active_household_count, 0),
        0::NUMERIC
    ) AS sales_per_active_household,
    COALESCE(
        household_week_metrics.weekly_sales
            / NULLIF(household_week_metrics.valid_basket_count, 0),
        0::NUMERIC
    ) AS average_basket_value,
    COALESCE(
        household_week_metrics.valid_basket_count::NUMERIC
            / NULLIF(household_week_metrics.active_household_count, 0),
        0::NUMERIC
    ) AS average_baskets_per_active_household,
    household_week_metrics.household_purchase_day_count,
    household_week_metrics.paid_merchandise_quantity,
    household_week_metrics.fuel_quantity_raw,
    COALESCE(weekly_paid_distinct_counts.weekly_paid_product_count, 0)::BIGINT
        AS weekly_paid_product_count,
    COALESCE(weekly_paid_distinct_counts.weekly_paid_department_count, 0)::BIGINT
        AS weekly_paid_department_count,
    COALESCE(weekly_paid_distinct_counts.weekly_paid_commodity_count, 0)::BIGINT
        AS weekly_paid_commodity_count,
    household_week_metrics.discount_amount,
    household_week_metrics.discounted_zero_sales_line_count,
    household_week_metrics.unexplained_zero_sales_line_count,
    household_week_metrics.zero_quantity_sale_line_count,
    household_week_metrics.zero_activity_line_count,
    household_week_metrics.discount_adjustment_line_count,
    household_week_metrics.unknown_category_line_count,
    household_week_metrics.unknown_category_household_count
FROM household_week_metrics
LEFT JOIN weekly_paid_distinct_counts
    ON weekly_paid_distinct_counts.week_no = household_week_metrics.week_no;

ALTER TABLE mart.weekly_kpi
    ADD CONSTRAINT pk_weekly_kpi PRIMARY KEY (week_no);

-- 03-7. weekly_kpi 인덱스 및 통계
ANALYZE mart.weekly_kpi;

COMMIT;

-- 03-8. MART 최종 검증
WITH base_summary AS MATERIALIZED (
    SELECT
        COUNT(*)::BIGINT AS base_line_count,
        COUNT(DISTINCT basket_id)::BIGINT AS base_basket_count,
        COUNT(DISTINCT household_key)::BIGINT AS base_household_count,
        COUNT(DISTINCT week_no)::BIGINT AS base_week_count,
        COALESCE(SUM(sales_value), 0::NUMERIC) AS base_sales,
        COUNT(*) FILTER (WHERE quantity > 0 AND sales_value > 0)::BIGINT AS paid_line_count,
        COUNT(*) FILTER (WHERE quantity > 0 AND sales_value = 0)::BIGINT AS positive_quantity_zero_sales_count,
        COUNT(*) FILTER (WHERE quantity = 0 AND sales_value > 0)::BIGINT AS zero_quantity_positive_sales_count,
        COUNT(*) FILTER (WHERE quantity = 0 AND sales_value = 0)::BIGINT AS zero_activity_count,
        COUNT(DISTINCT basket_id) FILTER (
            WHERE quantity > 0 AND sales_value > 0
        )::BIGINT AS expected_valid_basket_count
    FROM base.transaction_data
),
category_fuel_summary AS MATERIALIZED (
    SELECT
        COUNT(*) FILTER (
            WHERE product.department IS NULL
               OR product.commodity_desc IS NULL
               OR product.sub_commodity_desc IS NULL
        )::BIGINT AS expected_unknown_category_lines,
        COALESCE(SUM(transaction_data.quantity) FILTER (
            WHERE transaction_data.quantity > 0
              AND transaction_data.sales_value > 0
              AND UPPER(TRIM(product.sub_commodity_desc)) = 'GASOLINE-REG UNLEADED'
        ), 0)::BIGINT AS expected_fuel_quantity,
        COALESCE(SUM(transaction_data.quantity) FILTER (
            WHERE transaction_data.quantity > 0
              AND transaction_data.sales_value > 0
        ), 0)::BIGINT AS expected_total_paid_quantity
    FROM base.transaction_data AS transaction_data
    LEFT JOIN base.product AS product
        ON product.product_id = transaction_data.product_id
),
basket_summary AS MATERIALIZED (
    SELECT
        COUNT(*)::BIGINT AS basket_row_count,
        COUNT(DISTINCT basket_id)::BIGINT AS basket_distinct_key_count,
        COUNT(*) FILTER (WHERE basket_id IS NULL)::BIGINT AS basket_null_key_count,
        COALESCE(SUM(basket_sales), 0::NUMERIC) AS basket_sales,
        COUNT(*) FILTER (WHERE is_valid_purchase_basket)::BIGINT AS valid_basket_count,
        COALESCE(SUM(basket_sales) FILTER (
            WHERE is_valid_purchase_basket
        ), 0::NUMERIC) AS valid_basket_sales,
        COALESCE(SUM(unknown_category_line_count), 0)::BIGINT AS unknown_category_lines,
        COALESCE(SUM(paid_merchandise_quantity), 0)::BIGINT AS merchandise_quantity,
        COALESCE(SUM(fuel_quantity_raw), 0)::BIGINT AS fuel_quantity
    FROM mart.fact_basket
),
household_week_summary AS MATERIALIZED (
    SELECT
        COUNT(*)::BIGINT AS household_week_row_count,
        COUNT(DISTINCT (household_key, week_no))::BIGINT AS household_week_distinct_key_count,
        COUNT(*) FILTER (WHERE household_key IS NULL OR week_no IS NULL)::BIGINT
            AS household_week_null_key_count,
        COALESCE(SUM(weekly_sales), 0::NUMERIC) AS household_week_sales
    FROM mart.fact_household_week
),
weekly_summary AS MATERIALIZED (
    SELECT
        COUNT(*)::BIGINT AS weekly_row_count,
        COUNT(*) FILTER (WHERE week_no IS NULL)::BIGINT AS weekly_null_key_count,
        COALESCE(SUM(weekly_sales), 0::NUMERIC) AS weekly_sales
    FROM mart.weekly_kpi
),
checks AS (
    SELECT check_name, severity, issue_count, detail
    FROM base_summary
    CROSS JOIN category_fuel_summary
    CROSS JOIN basket_summary
    CROSS JOIN household_week_summary
    CROSS JOIN weekly_summary
    CROSS JOIN LATERAL (VALUES
        ('fact_basket_row_count', 'FAIL', ABS(basket_row_count - base_basket_count),
         format('fact_basket=%s, base distinct basket_id=%s', basket_row_count, base_basket_count)),
        ('fact_basket_sales_reconciliation', 'FAIL',
         CASE WHEN basket_sales IS DISTINCT FROM base_sales THEN 1 ELSE 0 END,
         format('fact_basket=%s, base=%s', basket_sales, base_sales)),
        ('fact_basket_primary_key', 'FAIL',
         (basket_row_count - basket_distinct_key_count) + basket_null_key_count,
         'basket_id 중복 및 NULL 수'),
        ('fact_household_week_dense_row_count', 'FAIL',
         ABS(household_week_row_count - (base_household_count * base_week_count)),
         format('actual=%s, households×weeks=%s', household_week_row_count,
                base_household_count * base_week_count)),
        ('fact_household_week_primary_key', 'FAIL',
         (household_week_row_count - household_week_distinct_key_count) + household_week_null_key_count,
         'household_key×week_no 중복 및 NULL 수'),
        ('valid_purchase_basket_count', 'FAIL',
         ABS(valid_basket_count - expected_valid_basket_count),
         format('fact_basket=%s, paid-line basket=%s', valid_basket_count, expected_valid_basket_count)),
        ('household_week_sales_reconciliation', 'FAIL',
         CASE WHEN household_week_sales IS DISTINCT FROM valid_basket_sales THEN 1 ELSE 0 END,
         format('household_week=%s, valid baskets=%s', household_week_sales, valid_basket_sales)),
        ('weekly_kpi_row_count', 'FAIL', ABS(weekly_row_count - base_week_count),
         format('weekly_kpi=%s, base distinct week_no=%s', weekly_row_count, base_week_count)),
        ('weekly_kpi_sales_reconciliation', 'FAIL',
         CASE WHEN weekly_sales IS DISTINCT FROM household_week_sales THEN 1 ELSE 0 END,
         format('weekly_kpi=%s, household_week=%s', weekly_sales, household_week_sales)),
        ('transaction_type_partition', 'FAIL',
         ABS((paid_line_count + positive_quantity_zero_sales_count
              + zero_quantity_positive_sales_count + zero_activity_count) - base_line_count),
         format('classified=%s, base=%s',
                paid_line_count + positive_quantity_zero_sales_count
                + zero_quantity_positive_sales_count + zero_activity_count,
                base_line_count)),
        ('reference_paid_line_count', 'WARN', ABS(paid_line_count - 2576815::BIGINT),
         format('actual=%s, reference=2576815', paid_line_count)),
        ('reference_positive_quantity_zero_sales', 'WARN',
         ABS(positive_quantity_zero_sales_count - 4451::BIGINT),
         format('actual=%s, reference=4451', positive_quantity_zero_sales_count)),
        ('reference_zero_quantity_positive_sales', 'WARN',
         ABS(zero_quantity_positive_sales_count - 67::BIGINT),
         format('actual=%s, reference=67', zero_quantity_positive_sales_count)),
        ('reference_zero_activity', 'WARN', ABS(zero_activity_count - 14399::BIGINT),
         format('actual=%s, reference=14399', zero_activity_count)),
        ('unknown_category_line_reconciliation', 'FAIL',
         ABS(unknown_category_lines - expected_unknown_category_lines),
         format('fact_basket=%s, base joined product=%s', unknown_category_lines, expected_unknown_category_lines)),
        ('fuel_quantity_reconciliation', 'FAIL',
         CASE WHEN fuel_quantity IS DISTINCT FROM expected_fuel_quantity THEN 1 ELSE 0 END,
         format('fact_basket fuel=%s, expected fuel=%s', fuel_quantity, expected_fuel_quantity)),
        ('paid_quantity_partition', 'FAIL',
         CASE WHEN merchandise_quantity + fuel_quantity IS DISTINCT FROM expected_total_paid_quantity
              THEN 1 ELSE 0 END,
         format('merchandise+fuel=%s, total paid quantity=%s',
                merchandise_quantity + fuel_quantity, expected_total_paid_quantity)),
        ('fact_basket_required_keys', 'FAIL', basket_null_key_count,
         'fact_basket basket_id NULL 수'),
        ('fact_household_week_required_keys', 'FAIL', household_week_null_key_count,
         'fact_household_week household_key 또는 week_no NULL 수'),
        ('weekly_kpi_required_keys', 'FAIL', weekly_null_key_count,
         'weekly_kpi week_no NULL 수')
    ) AS check_value(check_name, severity, issue_count, detail)
)
SELECT
    check_name,
    CASE
        WHEN issue_count = 0 THEN 'PASS'
        WHEN severity = 'WARN' THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    issue_count::BIGINT AS issue_count,
    detail
FROM checks
ORDER BY check_name;

-- ============================================================
-- 04_mart_household_reference_week
-- 가구 × 기준주차의 최근 26주 RFM 및 최근 8주 활동변화
-- ============================================================

-- 04-1. 선행 테이블 확인
-- 선행 테이블은 이전 단계에서 검증 완료되었으므로 별도 DO 블록을 실행하지 않는다.

-- 04-2. 재실행 준비
BEGIN;
CREATE SCHEMA IF NOT EXISTS mart;
DROP TABLE IF EXISTS mart.household_reference_week;
-- 04-3. 기준주차·주차 달력·가구 그리드
CREATE TABLE mart.household_reference_week AS
WITH week_calendar AS MATERIALIZED (
    SELECT week_no, MIN(day)::INTEGER AS week_start_day, MAX(day)::INTEGER AS week_end_day
    FROM base.transaction_data
    WHERE week_no IS NOT NULL AND day IS NOT NULL
    GROUP BY week_no
),
week_bounds AS (
    SELECT MIN(week_no)::INTEGER AS min_week, MAX(week_no)::INTEGER AS max_week
    FROM mart.weekly_kpi
),
reference_weeks AS MATERIALIZED (
    SELECT c.week_no::INTEGER AS reference_week, c.week_end_day AS reference_end_day,
           b.min_week, b.max_week
    FROM week_calendar c CROSS JOIN week_bounds b
    WHERE c.week_no BETWEEN b.min_week + 25 AND b.max_week - 4
      AND NOT EXISTS (
          SELECT 1 FROM generate_series(c.week_no - 25, c.week_no + 4) required_week
          WHERE NOT EXISTS (SELECT 1 FROM week_calendar present WHERE present.week_no = required_week)
      )
),
households AS MATERIALIZED (
    SELECT household_key FROM mart.fact_household_week
    WHERE household_key IS NOT NULL GROUP BY household_key
),
analysis_grid AS MATERIALIZED (
    SELECT h.household_key, r.reference_week, r.reference_end_day,
           r.reference_week - 25 AS observation_start_week,
           r.reference_week AS observation_end_week,
           r.reference_week - 7 AS prior4_start_week,
           r.reference_week - 4 AS prior4_end_week,
           r.reference_week - 3 AS recent4_start_week,
           r.reference_week AS recent4_end_week,
           TRUE AS has_complete_26w_window, TRUE AS has_complete_future_4w_window
    FROM households h CROSS JOIN reference_weeks r
),
-- 04-4. 최근 26주 및 4주 구간 구매집계
weekly_window AS MATERIALIZED (
    SELECT g.household_key, g.reference_week, g.reference_end_day,
           g.observation_start_week, g.observation_end_week,
           g.prior4_start_week, g.prior4_end_week, g.recent4_start_week, g.recent4_end_week,
           g.has_complete_26w_window, g.has_complete_future_4w_window,
           SUM(w.recorded_basket_count)::BIGINT AS recorded_basket_count_26w,
           SUM(w.valid_basket_count)::BIGINT AS frequency_26w,
           SUM(w.invalid_basket_count)::BIGINT AS invalid_basket_count_26w,
           COUNT(*) FILTER (WHERE w.valid_basket_count > 0)::BIGINT AS purchase_week_count_26w,
           SUM(w.purchase_day_count)::BIGINT AS purchase_day_count_26w,
           SUM(w.weekly_sales)::NUMERIC AS monetary_26w,
           SUM(w.paid_line_sales)::NUMERIC AS paid_line_sales_26w,
           SUM(w.paid_merchandise_quantity)::BIGINT AS paid_merchandise_quantity_26w,
           SUM(w.fuel_quantity_raw)::BIGINT AS fuel_quantity_raw_26w,
           SUM(w.discount_amount)::NUMERIC AS discount_amount_26w,
           SUM(w.discounted_zero_sales_line_count)::BIGINT AS discounted_zero_sales_line_count_26w,
           SUM(w.unexplained_zero_sales_line_count)::BIGINT AS unexplained_zero_sales_line_count_26w,
           SUM(w.zero_quantity_sale_line_count)::BIGINT AS zero_quantity_sale_line_count_26w,
           SUM(w.zero_activity_line_count)::BIGINT AS zero_activity_line_count_26w,
           SUM(w.discount_adjustment_line_count)::BIGINT AS discount_adjustment_line_count_26w,
           SUM(w.unknown_category_line_count)::BIGINT AS unknown_category_line_count_26w,
           BOOL_OR(w.has_unknown_category_item) AS has_unknown_category_26w,
           SUM(w.valid_basket_count) FILTER (WHERE w.week_no BETWEEN g.prior4_start_week AND g.prior4_end_week)::BIGINT AS prior4_valid_basket_count,
           COUNT(*) FILTER (WHERE w.week_no BETWEEN g.prior4_start_week AND g.prior4_end_week AND w.valid_basket_count > 0)::BIGINT AS prior4_purchase_week_count,
           SUM(w.purchase_day_count) FILTER (WHERE w.week_no BETWEEN g.prior4_start_week AND g.prior4_end_week)::BIGINT AS prior4_purchase_day_count,
           SUM(w.weekly_sales) FILTER (WHERE w.week_no BETWEEN g.prior4_start_week AND g.prior4_end_week)::NUMERIC AS prior4_sales,
           SUM(w.paid_line_sales) FILTER (WHERE w.week_no BETWEEN g.prior4_start_week AND g.prior4_end_week)::NUMERIC AS prior4_paid_line_sales,
           SUM(w.paid_merchandise_quantity) FILTER (WHERE w.week_no BETWEEN g.prior4_start_week AND g.prior4_end_week)::BIGINT AS prior4_paid_merchandise_quantity,
           SUM(w.fuel_quantity_raw) FILTER (WHERE w.week_no BETWEEN g.prior4_start_week AND g.prior4_end_week)::BIGINT AS prior4_fuel_quantity_raw,
           SUM(w.discount_amount) FILTER (WHERE w.week_no BETWEEN g.prior4_start_week AND g.prior4_end_week)::NUMERIC AS prior4_discount_amount,
           SUM(w.valid_basket_count) FILTER (WHERE w.week_no BETWEEN g.recent4_start_week AND g.recent4_end_week)::BIGINT AS recent4_valid_basket_count,
           COUNT(*) FILTER (WHERE w.week_no BETWEEN g.recent4_start_week AND g.recent4_end_week AND w.valid_basket_count > 0)::BIGINT AS recent4_purchase_week_count,
           SUM(w.purchase_day_count) FILTER (WHERE w.week_no BETWEEN g.recent4_start_week AND g.recent4_end_week)::BIGINT AS recent4_purchase_day_count,
           SUM(w.weekly_sales) FILTER (WHERE w.week_no BETWEEN g.recent4_start_week AND g.recent4_end_week)::NUMERIC AS recent4_sales,
           SUM(w.paid_line_sales) FILTER (WHERE w.week_no BETWEEN g.recent4_start_week AND g.recent4_end_week)::NUMERIC AS recent4_paid_line_sales,
           SUM(w.paid_merchandise_quantity) FILTER (WHERE w.week_no BETWEEN g.recent4_start_week AND g.recent4_end_week)::BIGINT AS recent4_paid_merchandise_quantity,
           SUM(w.fuel_quantity_raw) FILTER (WHERE w.week_no BETWEEN g.recent4_start_week AND g.recent4_end_week)::BIGINT AS recent4_fuel_quantity_raw,
           SUM(w.discount_amount) FILTER (WHERE w.week_no BETWEEN g.recent4_start_week AND g.recent4_end_week)::NUMERIC AS recent4_discount_amount
    FROM analysis_grid g
    JOIN mart.fact_household_week w ON w.household_key = g.household_key
      AND w.week_no BETWEEN g.observation_start_week AND g.observation_end_week
    GROUP BY g.household_key, g.reference_week, g.reference_end_day,
             g.observation_start_week, g.observation_end_week, g.prior4_start_week,
             g.prior4_end_week, g.recent4_start_week, g.recent4_end_week,
             g.has_complete_26w_window, g.has_complete_future_4w_window
),
last_purchase AS (
    SELECT g.household_key, g.reference_week, MAX(b.week_no)::INTEGER AS last_purchase_week_26w,
           MAX(b.day)::INTEGER AS last_purchase_day_26w
    FROM analysis_grid g JOIN mart.fact_basket b ON b.household_key = g.household_key
      AND b.week_no BETWEEN g.observation_start_week AND g.observation_end_week
      AND b.is_valid_purchase_basket
    GROUP BY g.household_key, g.reference_week
),
-- 04-5. 정확한 상품·카테고리 DISTINCT 집계
paid_line_keys AS MATERIALIZED (
    SELECT DISTINCT t.household_key, t.week_no, t.product_id,
           p.department, p.commodity_desc
    FROM base.transaction_data t
    LEFT JOIN base.product p ON p.product_id = t.product_id
    WHERE t.quantity > 0 AND t.sales_value > 0
      AND t.household_key IS NOT NULL AND t.week_no IS NOT NULL
),
diversity AS (
    SELECT g.household_key, g.reference_week,
           COUNT(DISTINCT l.product_id)::BIGINT AS paid_product_count_26w,
           COUNT(DISTINCT l.department) FILTER (WHERE l.department IS NOT NULL)::BIGINT AS paid_department_count_26w,
           COUNT(DISTINCT l.commodity_desc) FILTER (WHERE l.commodity_desc IS NOT NULL)::BIGINT AS paid_commodity_count_26w,
           COUNT(DISTINCT l.product_id) FILTER (WHERE l.week_no BETWEEN g.prior4_start_week AND g.prior4_end_week)::BIGINT AS prior4_paid_product_count,
           COUNT(DISTINCT l.department) FILTER (WHERE l.department IS NOT NULL AND l.week_no BETWEEN g.prior4_start_week AND g.prior4_end_week)::BIGINT AS prior4_paid_department_count,
           COUNT(DISTINCT l.commodity_desc) FILTER (WHERE l.commodity_desc IS NOT NULL AND l.week_no BETWEEN g.prior4_start_week AND g.prior4_end_week)::BIGINT AS prior4_paid_commodity_count,
           COUNT(DISTINCT l.product_id) FILTER (WHERE l.week_no BETWEEN g.recent4_start_week AND g.recent4_end_week)::BIGINT AS recent4_paid_product_count,
           COUNT(DISTINCT l.department) FILTER (WHERE l.department IS NOT NULL AND l.week_no BETWEEN g.recent4_start_week AND g.recent4_end_week)::BIGINT AS recent4_paid_department_count,
           COUNT(DISTINCT l.commodity_desc) FILTER (WHERE l.commodity_desc IS NOT NULL AND l.week_no BETWEEN g.recent4_start_week AND g.recent4_end_week)::BIGINT AS recent4_paid_commodity_count
    FROM analysis_grid g LEFT JOIN paid_line_keys l ON l.household_key = g.household_key
      AND l.week_no BETWEEN g.observation_start_week AND g.observation_end_week
    GROUP BY g.household_key, g.reference_week
),
-- 04-6. RFM 원지표와 활동변화 계산
raw_metrics AS (
    SELECT w.household_key,
           w.reference_week,
           w.reference_end_day,
           w.observation_start_week,
           w.observation_end_week,
           w.prior4_start_week,
           w.prior4_end_week,
           w.recent4_start_week,
           w.recent4_end_week,
           w.has_complete_26w_window,
           w.has_complete_future_4w_window,
           w.recorded_basket_count_26w,
           w.frequency_26w,
           w.invalid_basket_count_26w,
           w.purchase_week_count_26w,
           w.purchase_day_count_26w,
           w.monetary_26w,
           w.paid_line_sales_26w,
           w.paid_merchandise_quantity_26w,
           w.fuel_quantity_raw_26w,
           w.discount_amount_26w,
           w.discounted_zero_sales_line_count_26w,
           w.unexplained_zero_sales_line_count_26w,
           w.zero_quantity_sale_line_count_26w,
           w.zero_activity_line_count_26w,
           w.discount_adjustment_line_count_26w,
           w.unknown_category_line_count_26w,
           w.has_unknown_category_26w,
           w.prior4_valid_basket_count,
           w.prior4_purchase_week_count,
           w.prior4_purchase_day_count,
           w.prior4_sales,
           w.prior4_paid_line_sales,
           w.prior4_paid_merchandise_quantity,
           w.prior4_fuel_quantity_raw,
           w.prior4_discount_amount,
           w.recent4_valid_basket_count,
           w.recent4_purchase_week_count,
           w.recent4_purchase_day_count,
           w.recent4_sales,
           w.recent4_paid_line_sales,
           w.recent4_paid_merchandise_quantity,
           w.recent4_fuel_quantity_raw,
           w.recent4_discount_amount,
           l.last_purchase_week_26w, l.last_purchase_day_26w,
           d.paid_product_count_26w, d.paid_department_count_26w, d.paid_commodity_count_26w,
           d.prior4_paid_product_count, d.prior4_paid_department_count, d.prior4_paid_commodity_count,
           d.recent4_paid_product_count, d.recent4_paid_department_count, d.recent4_paid_commodity_count
    FROM weekly_window w LEFT JOIN last_purchase l USING (household_key, reference_week)
    JOIN diversity d USING (household_key, reference_week)
),
calculated AS (
    SELECT r.household_key,
           r.reference_week,
           r.reference_end_day,
           r.observation_start_week,
           r.observation_end_week,
           r.prior4_start_week,
           r.prior4_end_week,
           r.recent4_start_week,
           r.recent4_end_week,
           r.has_complete_26w_window,
           r.has_complete_future_4w_window,
           r.recorded_basket_count_26w,
           r.frequency_26w,
           r.invalid_basket_count_26w,
           r.purchase_week_count_26w,
           r.purchase_day_count_26w,
           r.monetary_26w,
           r.paid_line_sales_26w,
           r.paid_merchandise_quantity_26w,
           r.fuel_quantity_raw_26w,
           r.discount_amount_26w,
           r.discounted_zero_sales_line_count_26w,
           r.unexplained_zero_sales_line_count_26w,
           r.zero_quantity_sale_line_count_26w,
           r.zero_activity_line_count_26w,
           r.discount_adjustment_line_count_26w,
           r.unknown_category_line_count_26w,
           r.has_unknown_category_26w,
           r.prior4_valid_basket_count,
           r.prior4_purchase_week_count,
           r.prior4_purchase_day_count,
           r.prior4_sales,
           r.prior4_paid_line_sales,
           r.prior4_paid_merchandise_quantity,
           r.prior4_fuel_quantity_raw,
           r.prior4_discount_amount,
           r.recent4_valid_basket_count,
           r.recent4_purchase_week_count,
           r.recent4_purchase_day_count,
           r.recent4_sales,
           r.recent4_paid_line_sales,
           r.recent4_paid_merchandise_quantity,
           r.recent4_fuel_quantity_raw,
           r.recent4_discount_amount,
           r.last_purchase_week_26w,
           r.last_purchase_day_26w,
           r.paid_product_count_26w,
           r.paid_department_count_26w,
           r.paid_commodity_count_26w,
           r.prior4_paid_product_count,
           r.prior4_paid_department_count,
           r.prior4_paid_commodity_count,
           r.recent4_paid_product_count,
           r.recent4_paid_department_count,
           r.recent4_paid_commodity_count,
           frequency_26w > 0 AS has_purchase_26w,
           CASE WHEN frequency_26w > 0 THEN reference_week - last_purchase_week_26w END::INTEGER AS recency_weeks_26w,
           CASE WHEN frequency_26w > 0 THEN reference_end_day - last_purchase_day_26w END::INTEGER AS recency_days_26w,
           purchase_week_count_26w::NUMERIC / 26::NUMERIC AS active_week_rate_26w,
           monetary_26w / NULLIF(frequency_26w, 0) AS average_basket_value_26w,
           monetary_26w / 26::NUMERIC AS average_weekly_sales_26w,
           monetary_26w / NULLIF(purchase_week_count_26w, 0) AS average_sales_per_active_week_26w,
           discount_amount_26w / NULLIF(paid_line_sales_26w + discount_amount_26w, 0) AS discount_rate_proxy_26w,
           prior4_valid_basket_count > 0 AS prior4_has_purchase,
           prior4_sales / NULLIF(prior4_valid_basket_count, 0) AS prior4_average_basket_value,
           recent4_valid_basket_count > 0 AS recent4_has_purchase,
           recent4_sales / NULLIF(recent4_valid_basket_count, 0) AS recent4_average_basket_value
    FROM raw_metrics r
),
changes AS (
    SELECT c.household_key,
      c.reference_week,
      c.reference_end_day,
      c.observation_start_week,
      c.observation_end_week,
      c.prior4_start_week,
      c.prior4_end_week,
      c.recent4_start_week,
      c.recent4_end_week,
      c.has_complete_26w_window,
      c.has_complete_future_4w_window,
      c.recorded_basket_count_26w,
      c.frequency_26w,
      c.invalid_basket_count_26w,
      c.purchase_week_count_26w,
      c.purchase_day_count_26w,
      c.monetary_26w,
      c.paid_line_sales_26w,
      c.paid_merchandise_quantity_26w,
      c.fuel_quantity_raw_26w,
      c.discount_amount_26w,
      c.discounted_zero_sales_line_count_26w,
      c.unexplained_zero_sales_line_count_26w,
      c.zero_quantity_sale_line_count_26w,
      c.zero_activity_line_count_26w,
      c.discount_adjustment_line_count_26w,
      c.unknown_category_line_count_26w,
      c.has_unknown_category_26w,
      c.prior4_valid_basket_count,
      c.prior4_purchase_week_count,
      c.prior4_purchase_day_count,
      c.prior4_sales,
      c.prior4_paid_line_sales,
      c.prior4_paid_merchandise_quantity,
      c.prior4_fuel_quantity_raw,
      c.prior4_discount_amount,
      c.recent4_valid_basket_count,
      c.recent4_purchase_week_count,
      c.recent4_purchase_day_count,
      c.recent4_sales,
      c.recent4_paid_line_sales,
      c.recent4_paid_merchandise_quantity,
      c.recent4_fuel_quantity_raw,
      c.recent4_discount_amount,
      c.last_purchase_week_26w,
      c.last_purchase_day_26w,
      c.paid_product_count_26w,
      c.paid_department_count_26w,
      c.paid_commodity_count_26w,
      c.prior4_paid_product_count,
      c.prior4_paid_department_count,
      c.prior4_paid_commodity_count,
      c.recent4_paid_product_count,
      c.recent4_paid_department_count,
      c.recent4_paid_commodity_count,
      c.has_purchase_26w,
      c.recency_weeks_26w,
      c.recency_days_26w,
      c.active_week_rate_26w,
      c.average_basket_value_26w,
      c.average_weekly_sales_26w,
      c.average_sales_per_active_week_26w,
      c.discount_rate_proxy_26w,
      c.prior4_has_purchase,
      c.prior4_average_basket_value,
      c.recent4_has_purchase,
      c.recent4_average_basket_value,
      recent4_valid_basket_count-prior4_valid_basket_count AS basket_count_change,
      recent4_purchase_week_count-prior4_purchase_week_count AS purchase_week_count_change,
      recent4_purchase_day_count-prior4_purchase_day_count AS purchase_day_count_change,
      recent4_sales-prior4_sales AS sales_change,
      recent4_paid_line_sales-prior4_paid_line_sales AS paid_line_sales_change,
      recent4_average_basket_value-prior4_average_basket_value AS average_basket_value_change,
      recent4_paid_product_count-prior4_paid_product_count AS paid_product_count_change,
      recent4_paid_department_count-prior4_paid_department_count AS paid_department_count_change,
      recent4_paid_commodity_count-prior4_paid_commodity_count AS paid_commodity_count_change,
      recent4_discount_amount-prior4_discount_amount AS discount_amount_change,
      recent4_valid_basket_count::NUMERIC/NULLIF(prior4_valid_basket_count,0)-1 AS basket_count_change_rate,
      recent4_sales/NULLIF(prior4_sales,0)-1 AS sales_change_rate,
      recent4_paid_line_sales/NULLIF(prior4_paid_line_sales,0)-1 AS paid_line_sales_change_rate,
      recent4_average_basket_value/NULLIF(prior4_average_basket_value,0)-1 AS average_basket_value_change_rate,
      recent4_paid_product_count::NUMERIC/NULLIF(prior4_paid_product_count,0)-1 AS paid_product_count_change_rate,
      recent4_paid_department_count::NUMERIC/NULLIF(prior4_paid_department_count,0)-1 AS paid_department_count_change_rate,
      recent4_paid_commodity_count::NUMERIC/NULLIF(prior4_paid_commodity_count,0)-1 AS paid_commodity_count_change_rate,
      recent4_discount_amount/NULLIF(prior4_discount_amount,0)-1 AS discount_amount_change_rate
    FROM calculated c
),
states AS (
    SELECT x.household_key,
      x.reference_week,
      x.reference_end_day,
      x.observation_start_week,
      x.observation_end_week,
      x.prior4_start_week,
      x.prior4_end_week,
      x.recent4_start_week,
      x.recent4_end_week,
      x.has_complete_26w_window,
      x.has_complete_future_4w_window,
      x.recorded_basket_count_26w,
      x.frequency_26w,
      x.invalid_basket_count_26w,
      x.purchase_week_count_26w,
      x.purchase_day_count_26w,
      x.monetary_26w,
      x.paid_line_sales_26w,
      x.paid_merchandise_quantity_26w,
      x.fuel_quantity_raw_26w,
      x.discount_amount_26w,
      x.discounted_zero_sales_line_count_26w,
      x.unexplained_zero_sales_line_count_26w,
      x.zero_quantity_sale_line_count_26w,
      x.zero_activity_line_count_26w,
      x.discount_adjustment_line_count_26w,
      x.unknown_category_line_count_26w,
      x.has_unknown_category_26w,
      x.prior4_valid_basket_count,
      x.prior4_purchase_week_count,
      x.prior4_purchase_day_count,
      x.prior4_sales,
      x.prior4_paid_line_sales,
      x.prior4_paid_merchandise_quantity,
      x.prior4_fuel_quantity_raw,
      x.prior4_discount_amount,
      x.recent4_valid_basket_count,
      x.recent4_purchase_week_count,
      x.recent4_purchase_day_count,
      x.recent4_sales,
      x.recent4_paid_line_sales,
      x.recent4_paid_merchandise_quantity,
      x.recent4_fuel_quantity_raw,
      x.recent4_discount_amount,
      x.last_purchase_week_26w,
      x.last_purchase_day_26w,
      x.paid_product_count_26w,
      x.paid_department_count_26w,
      x.paid_commodity_count_26w,
      x.prior4_paid_product_count,
      x.prior4_paid_department_count,
      x.prior4_paid_commodity_count,
      x.recent4_paid_product_count,
      x.recent4_paid_department_count,
      x.recent4_paid_commodity_count,
      x.has_purchase_26w,
      x.recency_weeks_26w,
      x.recency_days_26w,
      x.active_week_rate_26w,
      x.average_basket_value_26w,
      x.average_weekly_sales_26w,
      x.average_sales_per_active_week_26w,
      x.discount_rate_proxy_26w,
      x.prior4_has_purchase,
      x.prior4_average_basket_value,
      x.recent4_has_purchase,
      x.recent4_average_basket_value,
      x.basket_count_change,
      x.purchase_week_count_change,
      x.purchase_day_count_change,
      x.sales_change,
      x.paid_line_sales_change,
      x.average_basket_value_change,
      x.paid_product_count_change,
      x.paid_department_count_change,
      x.paid_commodity_count_change,
      x.discount_amount_change,
      x.basket_count_change_rate,
      x.sales_change_rate,
      x.paid_line_sales_change_rate,
      x.average_basket_value_change_rate,
      x.paid_product_count_change_rate,
      x.paid_department_count_change_rate,
      x.paid_commodity_count_change_rate,
      x.discount_amount_change_rate,
      CASE WHEN prior4_valid_basket_count>0 THEN 'COMPARABLE' WHEN recent4_valid_basket_count>0 THEN 'FROM_ZERO' ELSE 'BOTH_ZERO' END AS basket_change_denominator_status,
      CASE WHEN prior4_sales>0 THEN 'COMPARABLE' WHEN recent4_sales>0 THEN 'FROM_ZERO' ELSE 'BOTH_ZERO' END AS sales_change_denominator_status,
      CASE WHEN prior4_paid_line_sales>0 THEN 'COMPARABLE' WHEN recent4_paid_line_sales>0 THEN 'FROM_ZERO' ELSE 'BOTH_ZERO' END AS paid_line_sales_change_denominator_status,
      CASE WHEN COALESCE(prior4_average_basket_value,0)>0 THEN 'COMPARABLE' WHEN COALESCE(recent4_average_basket_value,0)>0 THEN 'FROM_ZERO' ELSE 'BOTH_ZERO' END AS average_basket_change_denominator_status,
      CASE WHEN prior4_paid_product_count>0 THEN 'COMPARABLE' WHEN recent4_paid_product_count>0 THEN 'FROM_ZERO' ELSE 'BOTH_ZERO' END AS product_change_denominator_status,
      CASE WHEN prior4_paid_department_count>0 THEN 'COMPARABLE' WHEN recent4_paid_department_count>0 THEN 'FROM_ZERO' ELSE 'BOTH_ZERO' END AS department_change_denominator_status,
      CASE WHEN prior4_paid_commodity_count>0 THEN 'COMPARABLE' WHEN recent4_paid_commodity_count>0 THEN 'FROM_ZERO' ELSE 'BOTH_ZERO' END AS commodity_change_denominator_status,
      CASE WHEN prior4_discount_amount>0 THEN 'COMPARABLE' WHEN recent4_discount_amount>0 THEN 'FROM_ZERO' ELSE 'BOTH_ZERO' END AS discount_change_denominator_status,
      CASE WHEN prior4_valid_basket_count=0 AND recent4_valid_basket_count=0 THEN 'NO_ACTIVITY_8W'
           WHEN prior4_valid_basket_count=0 THEN 'REACTIVATED'
           WHEN recent4_valid_basket_count=0 THEN 'BECAME_INACTIVE' ELSE 'ACTIVE_BOTH_4W' END AS activity_transition_base
    FROM changes x
),
flagged AS (
    SELECT s.household_key,
      s.reference_week,
      s.reference_end_day,
      s.observation_start_week,
      s.observation_end_week,
      s.prior4_start_week,
      s.prior4_end_week,
      s.recent4_start_week,
      s.recent4_end_week,
      s.has_complete_26w_window,
      s.has_complete_future_4w_window,
      s.recorded_basket_count_26w,
      s.frequency_26w,
      s.invalid_basket_count_26w,
      s.purchase_week_count_26w,
      s.purchase_day_count_26w,
      s.monetary_26w,
      s.paid_line_sales_26w,
      s.paid_merchandise_quantity_26w,
      s.fuel_quantity_raw_26w,
      s.discount_amount_26w,
      s.discounted_zero_sales_line_count_26w,
      s.unexplained_zero_sales_line_count_26w,
      s.zero_quantity_sale_line_count_26w,
      s.zero_activity_line_count_26w,
      s.discount_adjustment_line_count_26w,
      s.unknown_category_line_count_26w,
      s.has_unknown_category_26w,
      s.prior4_valid_basket_count,
      s.prior4_purchase_week_count,
      s.prior4_purchase_day_count,
      s.prior4_sales,
      s.prior4_paid_line_sales,
      s.prior4_paid_merchandise_quantity,
      s.prior4_fuel_quantity_raw,
      s.prior4_discount_amount,
      s.recent4_valid_basket_count,
      s.recent4_purchase_week_count,
      s.recent4_purchase_day_count,
      s.recent4_sales,
      s.recent4_paid_line_sales,
      s.recent4_paid_merchandise_quantity,
      s.recent4_fuel_quantity_raw,
      s.recent4_discount_amount,
      s.last_purchase_week_26w,
      s.last_purchase_day_26w,
      s.paid_product_count_26w,
      s.paid_department_count_26w,
      s.paid_commodity_count_26w,
      s.prior4_paid_product_count,
      s.prior4_paid_department_count,
      s.prior4_paid_commodity_count,
      s.recent4_paid_product_count,
      s.recent4_paid_department_count,
      s.recent4_paid_commodity_count,
      s.has_purchase_26w,
      s.recency_weeks_26w,
      s.recency_days_26w,
      s.active_week_rate_26w,
      s.average_basket_value_26w,
      s.average_weekly_sales_26w,
      s.average_sales_per_active_week_26w,
      s.discount_rate_proxy_26w,
      s.prior4_has_purchase,
      s.prior4_average_basket_value,
      s.recent4_has_purchase,
      s.recent4_average_basket_value,
      s.basket_count_change,
      s.purchase_week_count_change,
      s.purchase_day_count_change,
      s.sales_change,
      s.paid_line_sales_change,
      s.average_basket_value_change,
      s.paid_product_count_change,
      s.paid_department_count_change,
      s.paid_commodity_count_change,
      s.discount_amount_change,
      s.basket_count_change_rate,
      s.sales_change_rate,
      s.paid_line_sales_change_rate,
      s.average_basket_value_change_rate,
      s.paid_product_count_change_rate,
      s.paid_department_count_change_rate,
      s.paid_commodity_count_change_rate,
      s.discount_amount_change_rate,
      s.basket_change_denominator_status,
      s.sales_change_denominator_status,
      s.paid_line_sales_change_denominator_status,
      s.average_basket_change_denominator_status,
      s.product_change_denominator_status,
      s.department_change_denominator_status,
      s.commodity_change_denominator_status,
      s.discount_change_denominator_status,
      s.activity_transition_base,
      activity_transition_base='ACTIVE_BOTH_4W' AND (basket_count_change<0 OR sales_change<0) AS has_any_activity_decline_raw,
      activity_transition_base='ACTIVE_BOTH_4W' AND basket_count_change<0 AND sales_change<0 AS has_both_frequency_and_sales_decline_raw
    FROM states s
),
-- 04-7. 동률 보존형 RFM 상대순위
ranked_purchasers AS (
    SELECT household_key, reference_week,
      CUME_DIST() OVER (PARTITION BY reference_week ORDER BY recency_days_26w DESC)::NUMERIC AS recency_percentile_26w,
      CUME_DIST() OVER (PARTITION BY reference_week ORDER BY frequency_26w ASC)::NUMERIC AS frequency_percentile_26w,
      CUME_DIST() OVER (PARTITION BY reference_week ORDER BY monetary_26w ASC)::NUMERIC AS monetary_percentile_26w
    FROM flagged WHERE has_purchase_26w
)
-- 04-8. 최종 컬럼 선택 및 mart.household_reference_week 생성 완료
SELECT
       f.household_key,
       f.reference_week,
       f.reference_end_day,
       f.observation_start_week,
       f.observation_end_week,
       f.prior4_start_week,
       f.prior4_end_week,
       f.recent4_start_week,
       f.recent4_end_week,
       f.has_complete_26w_window,
       f.has_complete_future_4w_window,
       f.has_purchase_26w,
       f.last_purchase_week_26w,
       f.last_purchase_day_26w,
       f.recency_weeks_26w,
       f.recency_days_26w,
       f.frequency_26w,
       f.monetary_26w,
       f.recorded_basket_count_26w,
       f.invalid_basket_count_26w,
       f.purchase_week_count_26w,
       f.purchase_day_count_26w,
       f.active_week_rate_26w,
       f.paid_line_sales_26w,
       f.average_basket_value_26w,
       f.average_weekly_sales_26w,
       f.average_sales_per_active_week_26w,
       f.paid_merchandise_quantity_26w,
       f.fuel_quantity_raw_26w,
       f.discount_amount_26w,
       f.discount_rate_proxy_26w,
       f.paid_product_count_26w,
       f.paid_department_count_26w,
       f.paid_commodity_count_26w,
       f.discounted_zero_sales_line_count_26w,
       f.unexplained_zero_sales_line_count_26w,
       f.zero_quantity_sale_line_count_26w,
       f.zero_activity_line_count_26w,
       f.discount_adjustment_line_count_26w,
       f.unknown_category_line_count_26w,
       f.has_unknown_category_26w,
       f.prior4_has_purchase,
       f.prior4_valid_basket_count,
       f.prior4_purchase_week_count,
       f.prior4_purchase_day_count,
       f.prior4_sales,
       f.prior4_paid_line_sales,
       f.prior4_average_basket_value,
       f.prior4_paid_merchandise_quantity,
       f.prior4_fuel_quantity_raw,
       f.prior4_discount_amount,
       f.prior4_paid_product_count,
       f.prior4_paid_department_count,
       f.prior4_paid_commodity_count,
       f.recent4_has_purchase,
       f.recent4_valid_basket_count,
       f.recent4_purchase_week_count,
       f.recent4_purchase_day_count,
       f.recent4_sales,
       f.recent4_paid_line_sales,
       f.recent4_average_basket_value,
       f.recent4_paid_merchandise_quantity,
       f.recent4_fuel_quantity_raw,
       f.recent4_discount_amount,
       f.recent4_paid_product_count,
       f.recent4_paid_department_count,
       f.recent4_paid_commodity_count,
       f.basket_count_change,
       f.purchase_week_count_change,
       f.purchase_day_count_change,
       f.sales_change,
       f.paid_line_sales_change,
       f.average_basket_value_change,
       f.paid_product_count_change,
       f.paid_department_count_change,
       f.paid_commodity_count_change,
       f.discount_amount_change,
       f.basket_count_change_rate,
       f.sales_change_rate,
       f.paid_line_sales_change_rate,
       f.average_basket_value_change_rate,
       f.paid_product_count_change_rate,
       f.paid_department_count_change_rate,
       f.paid_commodity_count_change_rate,
       f.discount_amount_change_rate,
       f.basket_change_denominator_status,
       f.sales_change_denominator_status,
       f.paid_line_sales_change_denominator_status,
       f.average_basket_change_denominator_status,
       f.product_change_denominator_status,
       f.department_change_denominator_status,
       f.commodity_change_denominator_status,
       f.discount_change_denominator_status,
       f.activity_transition_base,
       f.has_any_activity_decline_raw,
       f.has_both_frequency_and_sales_decline_raw,
       p.recency_percentile_26w,
       p.frequency_percentile_26w,
       p.monetary_percentile_26w,
       (p.frequency_percentile_26w + p.monetary_percentile_26w) / 2::NUMERIC AS fm_value_index_26w,
       (p.recency_percentile_26w + p.frequency_percentile_26w + p.monetary_percentile_26w) / 3::NUMERIC AS rfm_value_index_26w
FROM flagged f LEFT JOIN ranked_purchasers p USING (household_key, reference_week);

-- 04-9. 기본키·인덱스·통계
ALTER TABLE mart.household_reference_week ADD PRIMARY KEY (household_key, reference_week);
CREATE INDEX idx_hrw_reference_purchase ON mart.household_reference_week(reference_week, has_purchase_26w);
CREATE INDEX idx_hrw_reference_transition ON mart.household_reference_week(reference_week, activity_transition_base);
CREATE INDEX idx_hrw_reference_decline
    ON mart.household_reference_week (reference_week)
    WHERE has_any_activity_decline_raw;
ANALYZE mart.household_reference_week;
COMMIT;

-- 04-10. 최종 검증
WITH dynamic_bounds AS (
    SELECT MIN(week_no) + 25 AS min_reference_week,
           MAX(week_no) - 4 AS max_reference_week,
           (MAX(week_no) - 4 - (MIN(week_no) + 25) + 1)::BIGINT AS reference_week_count,
           (SELECT COUNT(DISTINCT household_key)::BIGINT FROM mart.fact_household_week) AS household_count
    FROM mart.weekly_kpi
),
table_summary AS MATERIALIZED (
    SELECT COUNT(*)::BIGINT AS row_count,
           COUNT(DISTINCT reference_week)::BIGINT AS reference_week_count,
           MIN(reference_week) AS min_reference_week,
           MAX(reference_week) AS max_reference_week,
           (COUNT(*) - COUNT(DISTINCT (household_key, reference_week)))::BIGINT AS duplicate_count,
           COUNT(*) FILTER (WHERE household_key IS NULL OR reference_week IS NULL)::BIGINT AS null_key_count,
           COUNT(*) FILTER (
               WHERE observation_start_week <> reference_week - 25
                  OR observation_end_week <> reference_week
                  OR prior4_start_week <> reference_week - 7
                  OR prior4_end_week <> reference_week - 4
                  OR recent4_start_week <> reference_week - 3
                  OR recent4_end_week <> reference_week
                  OR NOT has_complete_26w_window
                  OR NOT has_complete_future_4w_window
                  OR last_purchase_week_26w > reference_week
           )::BIGINT AS window_leakage_issues,
           COUNT(*) FILTER (
               WHERE (has_purchase_26w AND (
                         frequency_26w <= 0 OR last_purchase_week_26w IS NULL
                         OR last_purchase_day_26w IS NULL OR recency_weeks_26w IS NULL
                         OR recency_days_26w IS NULL OR recency_weeks_26w NOT BETWEEN 0 AND 25
                         OR recency_days_26w < 0))
                  OR (NOT has_purchase_26w AND (
                         frequency_26w <> 0 OR monetary_26w <> 0
                         OR last_purchase_week_26w IS NOT NULL OR last_purchase_day_26w IS NOT NULL
                         OR recency_weeks_26w IS NOT NULL OR recency_days_26w IS NOT NULL))
           )::BIGINT AS recency_issues,
           COUNT(*) FILTER (
               WHERE activity_transition_base <> CASE
                         WHEN prior4_valid_basket_count = 0 AND recent4_valid_basket_count = 0 THEN 'NO_ACTIVITY_8W'
                         WHEN prior4_valid_basket_count = 0 THEN 'REACTIVATED'
                         WHEN recent4_valid_basket_count = 0 THEN 'BECAME_INACTIVE'
                         ELSE 'ACTIVE_BOTH_4W' END
                  OR has_any_activity_decline_raw IS DISTINCT FROM (
                         prior4_valid_basket_count > 0 AND recent4_valid_basket_count > 0
                         AND (basket_count_change < 0 OR sales_change < 0))
                  OR has_both_frequency_and_sales_decline_raw IS DISTINCT FROM (
                         prior4_valid_basket_count > 0 AND recent4_valid_basket_count > 0
                         AND basket_count_change < 0 AND sales_change < 0)
           )::BIGINT AS transition_issues
    FROM mart.household_reference_week
),
denominator_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.household_reference_week h
    CROSS JOIN LATERAL (VALUES
        (h.prior4_valid_basket_count::NUMERIC, h.recent4_valid_basket_count::NUMERIC,
         h.basket_count_change_rate, h.basket_change_denominator_status),
        (h.prior4_sales, h.recent4_sales, h.sales_change_rate, h.sales_change_denominator_status),
        (h.prior4_paid_line_sales, h.recent4_paid_line_sales,
         h.paid_line_sales_change_rate, h.paid_line_sales_change_denominator_status),
        (h.prior4_paid_product_count::NUMERIC, h.recent4_paid_product_count::NUMERIC,
         h.paid_product_count_change_rate, h.product_change_denominator_status),
        (h.prior4_paid_department_count::NUMERIC, h.recent4_paid_department_count::NUMERIC,
         h.paid_department_count_change_rate, h.department_change_denominator_status),
        (h.prior4_paid_commodity_count::NUMERIC, h.recent4_paid_commodity_count::NUMERIC,
         h.paid_commodity_count_change_rate, h.commodity_change_denominator_status),
        (h.prior4_discount_amount, h.recent4_discount_amount,
         h.discount_amount_change_rate, h.discount_change_denominator_status)
    ) v(prior_value, recent_value, change_rate, denominator_status)
    WHERE (prior_value = 0 AND (
              change_rate IS NOT NULL
              OR denominator_status <> CASE WHEN recent_value > 0 THEN 'FROM_ZERO' ELSE 'BOTH_ZERO' END))
       OR (prior_value > 0 AND (
              change_rate IS DISTINCT FROM recent_value / prior_value - 1
              OR denominator_status <> 'COMPARABLE'))
),
source_rollup AS (
    SELECT r.reference_week,
           SUM(w.valid_basket_count)::BIGINT AS frequency_26w,
           SUM(w.weekly_sales)::NUMERIC AS monetary_26w,
           SUM(w.valid_basket_count) FILTER (
               WHERE w.week_no BETWEEN r.reference_week - 3 AND r.reference_week
           )::BIGINT AS recent4_frequency,
           SUM(w.weekly_sales) FILTER (
               WHERE w.week_no BETWEEN r.reference_week - 3 AND r.reference_week
           )::NUMERIC AS recent4_sales,
           SUM((w.valid_basket_count > 0)::INTEGER) FILTER (
               WHERE w.week_no BETWEEN r.reference_week - 3 AND r.reference_week
           )::BIGINT AS recent4_purchase_weeks,
           SUM(w.valid_basket_count) FILTER (
               WHERE w.week_no BETWEEN r.reference_week - 7 AND r.reference_week - 4
           )::BIGINT AS prior4_frequency,
           SUM(w.weekly_sales) FILTER (
               WHERE w.week_no BETWEEN r.reference_week - 7 AND r.reference_week - 4
           )::NUMERIC AS prior4_sales,
           SUM((w.valid_basket_count > 0)::INTEGER) FILTER (
               WHERE w.week_no BETWEEN r.reference_week - 7 AND r.reference_week - 4
           )::BIGINT AS prior4_purchase_weeks
    FROM (SELECT DISTINCT reference_week FROM mart.household_reference_week) r
    JOIN mart.fact_household_week w
      ON w.week_no BETWEEN r.reference_week - 25 AND r.reference_week
    GROUP BY r.reference_week
),
target_rollup AS (
    SELECT reference_week,
           SUM(frequency_26w)::BIGINT AS frequency_26w,
           SUM(monetary_26w)::NUMERIC AS monetary_26w,
           SUM(recent4_valid_basket_count)::BIGINT AS recent4_frequency,
           SUM(recent4_sales)::NUMERIC AS recent4_sales,
           SUM(recent4_purchase_week_count)::BIGINT AS recent4_purchase_weeks,
           SUM(prior4_valid_basket_count)::BIGINT AS prior4_frequency,
           SUM(prior4_sales)::NUMERIC AS prior4_sales,
           SUM(prior4_purchase_week_count)::BIGINT AS prior4_purchase_weeks
    FROM mart.household_reference_week
    GROUP BY reference_week
),
reconciliation AS (
    SELECT COUNT(*) FILTER (
               WHERE s.frequency_26w <> t.frequency_26w
                  OR s.monetary_26w <> t.monetary_26w
           )::BIGINT AS rfm_issues,
           COUNT(*) FILTER (
               WHERE s.recent4_frequency <> t.recent4_frequency
                  OR s.recent4_sales <> t.recent4_sales
                  OR s.recent4_purchase_weeks <> t.recent4_purchase_weeks
                  OR s.prior4_frequency <> t.prior4_frequency
                  OR s.prior4_sales <> t.prior4_sales
                  OR s.prior4_purchase_weeks <> t.prior4_purchase_weeks
           )::BIGINT AS recent_prior_issues
    FROM source_rollup s
    JOIN target_rollup t USING (reference_week)
),
checks AS (
    SELECT v.check_name, v.severity, v.issue_count, v.detail
    FROM dynamic_bounds b
    CROSS JOIN table_summary a
    CROSS JOIN denominator_issues d
    CROSS JOIN reconciliation r
    CROSS JOIN LATERAL (VALUES
        ('dynamic_reference_range',
         CASE WHEN a.min_reference_week = b.min_reference_week
                    AND a.max_reference_week = b.max_reference_week
                    AND a.reference_week_count = b.reference_week_count
                   THEN CASE WHEN a.min_reference_week = 26 AND a.max_reference_week = 98
                                   AND a.reference_week_count = 73 THEN 'PASS' ELSE 'WARN' END
              ELSE 'FAIL' END,
         CASE WHEN a.min_reference_week = b.min_reference_week
                    AND a.max_reference_week = b.max_reference_week
                    AND a.reference_week_count = b.reference_week_count THEN 0 ELSE 1 END::BIGINT,
         format('actual=%s~%s (%s), dynamic=%s~%s (%s)', a.min_reference_week,
                a.max_reference_week, a.reference_week_count, b.min_reference_week,
                b.max_reference_week, b.reference_week_count)),
        ('dense_row_count', 'FAIL',
         ABS(a.row_count - b.household_count * b.reference_week_count),
         format('actual=%s, expected=%s', a.row_count, b.household_count * b.reference_week_count)),
        ('primary_key_integrity', 'FAIL', a.duplicate_count + a.null_key_count,
         'household_key·reference_week NULL 또는 중복'),
        ('window_integrity_and_future_leakage', 'FAIL', a.window_leakage_issues,
         '관찰창 경계·완전성 및 reference_week 이후 정보 사용'),
        ('recency_integrity', 'FAIL', a.recency_issues,
         '구매 여부와 Recency 값의 정합성'),
        ('rfm_reconciliation', 'FAIL', r.rfm_issues,
         '기준주차별 최근 26주 Frequency·Monetary 대사'),
        ('recent4_prior4_reconciliation', 'FAIL', r.recent_prior_issues,
         '기준주차별 최근 4주·직전 4주 빈도·매출·활동주차 대사'),
        ('denominator_and_activity_transition', 'FAIL', d.issue_count + a.transition_issues,
         '변화율 분모 상태와 기본 활동전이·원시 감소 플래그 정합성')
    ) v(check_name, severity, issue_count, detail)
)
SELECT
    check_name,
    CASE
        WHEN issue_count = 0 AND severity = 'WARN' THEN 'WARN'
        WHEN issue_count = 0 THEN 'PASS'
        WHEN severity = 'WARN' THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    issue_count,
    detail
FROM checks
ORDER BY check_name;


----------"denominator_and_activity_transition" fail 원인 확인----------
SELECT
    COUNT(*) FILTER (
        WHERE prior4_average_basket_value IS NOT NULL
          AND prior4_average_basket_value > 0
          AND recent4_average_basket_value IS NULL
          AND average_basket_value_change_rate IS NULL
    ) AS average_basket_undefined_count,

    COUNT(*) FILTER (
        WHERE activity_transition_base IS DISTINCT FROM
            CASE
                WHEN prior4_valid_basket_count = 0
                 AND recent4_valid_basket_count = 0
                    THEN 'NO_ACTIVITY_8W'
                WHEN prior4_valid_basket_count = 0
                    THEN 'REACTIVATED'
                WHEN recent4_valid_basket_count = 0
                    THEN 'BECAME_INACTIVE'
                ELSE 'ACTIVE_BOTH_4W'
            END
    ) AS transition_mismatch_count,

    COUNT(*) FILTER (
        WHERE has_any_activity_decline_raw IS DISTINCT FROM (
            prior4_valid_basket_count > 0
            AND recent4_valid_basket_count > 0
            AND (
                basket_count_change < 0
                OR sales_change < 0
            )
        )
    ) AS any_decline_mismatch_count,

    COUNT(*) FILTER (
        WHERE has_both_frequency_and_sales_decline_raw IS DISTINCT FROM (
            prior4_valid_basket_count > 0
            AND recent4_valid_basket_count > 0
            AND basket_count_change < 0
            AND sales_change < 0
        )
    ) AS both_decline_mismatch_count

FROM mart.household_reference_week;

-- ============================================================
-- 05_reference_week_diagnostics
-- RFM·활동변화 분포 및 상태 임계값 진단
-- ============================================================

-- 05-1. 재실행 준비
BEGIN;
CREATE SCHEMA IF NOT EXISTS mart;
DROP TABLE IF EXISTS mart.diag_reference_week_threshold_sensitivity;
DROP TABLE IF EXISTS mart.diag_reference_week_rfm_ties;
DROP TABLE IF EXISTS mart.diag_reference_week_denominator_profile;
DROP TABLE IF EXISTS mart.diag_reference_week_state_profile;
DROP TABLE IF EXISTS mart.diag_reference_week_metric_profile;
DROP TABLE IF EXISTS mart.diag_reference_week_overview;

-- 05-2. 전체 진단 개요
CREATE TABLE mart.diag_reference_week_overview AS
WITH s AS MATERIALIZED (
 SELECT COUNT(*)::BIGINT n,COUNT(DISTINCT household_key)::BIGINT hh,COUNT(DISTINCT reference_week)::BIGINT weeks,
 MIN(reference_week) min_week,MAX(reference_week) max_week,
 COUNT(*) FILTER(WHERE has_purchase_26w)::BIGINT purchasers,
 COUNT(*) FILTER(WHERE NOT has_purchase_26w)::BIGINT nonpurchasers,
 COUNT(*) FILTER(WHERE activity_transition_base='NO_ACTIVITY_8W')::BIGINT no_activity,
 COUNT(*) FILTER(WHERE activity_transition_base='REACTIVATED')::BIGINT reactivated,
 COUNT(*) FILTER(WHERE activity_transition_base='BECAME_INACTIVE')::BIGINT inactive,
 COUNT(*) FILTER(WHERE activity_transition_base='ACTIVE_BOTH_4W')::BIGINT active_both,
 COUNT(*) FILTER(WHERE has_any_activity_decline_raw)::BIGINT any_decline,
 COUNT(*) FILTER(WHERE has_both_frequency_and_sales_decline_raw)::BIGINT both_decline
 FROM mart.household_reference_week
)
SELECT n source_row_count,hh distinct_household_count,weeks reference_week_count,min_week min_reference_week,max_week max_reference_week,
 purchasers purchaser_26w_row_count,purchasers::NUMERIC/NULLIF(n,0) purchaser_26w_share,
 nonpurchasers no_purchase_26w_row_count,nonpurchasers::NUMERIC/NULLIF(n,0) no_purchase_26w_share,
 no_activity no_activity_8w_count,no_activity::NUMERIC/NULLIF(n,0) no_activity_8w_share,
 reactivated reactivated_count,reactivated::NUMERIC/NULLIF(n,0) reactivated_share,
 inactive became_inactive_count,inactive::NUMERIC/NULLIF(n,0) became_inactive_share,
 active_both active_both_4w_count,active_both::NUMERIC/NULLIF(n,0) active_both_4w_share,
 any_decline any_activity_decline_raw_count,any_decline::NUMERIC/NULLIF(n,0) any_activity_decline_raw_share,
 both_decline both_frequency_sales_decline_raw_count,both_decline::NUMERIC/NULLIF(n,0) both_frequency_sales_decline_raw_share
FROM s;

-- 05-3. 핵심 지표 분포
CREATE TABLE mart.diag_reference_week_metric_profile AS
WITH source AS MATERIALIZED (SELECT household_key,has_purchase_26w,activity_transition_base,
 recency_days_26w,recency_weeks_26w,frequency_26w,monetary_26w,purchase_week_count_26w,purchase_day_count_26w,active_week_rate_26w,average_basket_value_26w,average_weekly_sales_26w,average_sales_per_active_week_26w,paid_product_count_26w,paid_department_count_26w,paid_commodity_count_26w,discount_rate_proxy_26w,fm_value_index_26w,rfm_value_index_26w,
 prior4_valid_basket_count,recent4_valid_basket_count,prior4_sales,recent4_sales,basket_count_change,purchase_week_count_change,purchase_day_count_change,sales_change,paid_line_sales_change,average_basket_value_change,paid_product_count_change,paid_department_count_change,paid_commodity_count_change,basket_count_change_rate,sales_change_rate,paid_line_sales_change_rate,average_basket_value_change_rate,paid_product_count_change_rate,paid_department_count_change_rate,paid_commodity_count_change_rate FROM mart.household_reference_week),
long AS (SELECT v.population,v.metric_name,v.metric_value FROM source s CROSS JOIN LATERAL(VALUES
 ('PURCHASERS_26W','recency_days_26w',s.recency_days_26w::NUMERIC,s.has_purchase_26w),('PURCHASERS_26W','recency_weeks_26w',s.recency_weeks_26w::NUMERIC,s.has_purchase_26w),('PURCHASERS_26W','frequency_26w',s.frequency_26w::NUMERIC,s.has_purchase_26w),('PURCHASERS_26W','monetary_26w',s.monetary_26w,s.has_purchase_26w),('PURCHASERS_26W','purchase_week_count_26w',s.purchase_week_count_26w::NUMERIC,s.has_purchase_26w),('PURCHASERS_26W','purchase_day_count_26w',s.purchase_day_count_26w::NUMERIC,s.has_purchase_26w),('PURCHASERS_26W','active_week_rate_26w',s.active_week_rate_26w,s.has_purchase_26w),('PURCHASERS_26W','average_basket_value_26w',s.average_basket_value_26w,s.has_purchase_26w),('PURCHASERS_26W','average_weekly_sales_26w',s.average_weekly_sales_26w,s.has_purchase_26w),('PURCHASERS_26W','average_sales_per_active_week_26w',s.average_sales_per_active_week_26w,s.has_purchase_26w),('PURCHASERS_26W','paid_product_count_26w',s.paid_product_count_26w::NUMERIC,s.has_purchase_26w),('PURCHASERS_26W','paid_department_count_26w',s.paid_department_count_26w::NUMERIC,s.has_purchase_26w),('PURCHASERS_26W','paid_commodity_count_26w',s.paid_commodity_count_26w::NUMERIC,s.has_purchase_26w),('PURCHASERS_26W','discount_rate_proxy_26w',s.discount_rate_proxy_26w,s.has_purchase_26w),('PURCHASERS_26W','fm_value_index_26w',s.fm_value_index_26w,s.has_purchase_26w),('PURCHASERS_26W','rfm_value_index_26w',s.rfm_value_index_26w,s.has_purchase_26w),
 ('ACTIVE_BOTH_4W','prior4_valid_basket_count',s.prior4_valid_basket_count::NUMERIC,s.activity_transition_base='ACTIVE_BOTH_4W'),('ACTIVE_BOTH_4W','recent4_valid_basket_count',s.recent4_valid_basket_count::NUMERIC,s.activity_transition_base='ACTIVE_BOTH_4W'),('ACTIVE_BOTH_4W','prior4_sales',s.prior4_sales,s.activity_transition_base='ACTIVE_BOTH_4W'),('ACTIVE_BOTH_4W','recent4_sales',s.recent4_sales,s.activity_transition_base='ACTIVE_BOTH_4W'),('ACTIVE_BOTH_4W','basket_count_change',s.basket_count_change::NUMERIC,s.activity_transition_base='ACTIVE_BOTH_4W'),('ACTIVE_BOTH_4W','purchase_week_count_change',s.purchase_week_count_change::NUMERIC,s.activity_transition_base='ACTIVE_BOTH_4W'),('ACTIVE_BOTH_4W','purchase_day_count_change',s.purchase_day_count_change::NUMERIC,s.activity_transition_base='ACTIVE_BOTH_4W'),('ACTIVE_BOTH_4W','sales_change',s.sales_change,s.activity_transition_base='ACTIVE_BOTH_4W'),('ACTIVE_BOTH_4W','paid_line_sales_change',s.paid_line_sales_change,s.activity_transition_base='ACTIVE_BOTH_4W'),('ACTIVE_BOTH_4W','average_basket_value_change',s.average_basket_value_change,s.activity_transition_base='ACTIVE_BOTH_4W'),('ACTIVE_BOTH_4W','paid_product_count_change',s.paid_product_count_change::NUMERIC,s.activity_transition_base='ACTIVE_BOTH_4W'),('ACTIVE_BOTH_4W','paid_department_count_change',s.paid_department_count_change::NUMERIC,s.activity_transition_base='ACTIVE_BOTH_4W'),('ACTIVE_BOTH_4W','paid_commodity_count_change',s.paid_commodity_count_change::NUMERIC,s.activity_transition_base='ACTIVE_BOTH_4W'),('ACTIVE_BOTH_4W','basket_count_change_rate',s.basket_count_change_rate,s.activity_transition_base='ACTIVE_BOTH_4W'),('ACTIVE_BOTH_4W','sales_change_rate',s.sales_change_rate,s.activity_transition_base='ACTIVE_BOTH_4W'),('ACTIVE_BOTH_4W','paid_line_sales_change_rate',s.paid_line_sales_change_rate,s.activity_transition_base='ACTIVE_BOTH_4W'),('ACTIVE_BOTH_4W','average_basket_value_change_rate',s.average_basket_value_change_rate,s.activity_transition_base='ACTIVE_BOTH_4W'),('ACTIVE_BOTH_4W','paid_product_count_change_rate',s.paid_product_count_change_rate,s.activity_transition_base='ACTIVE_BOTH_4W'),('ACTIVE_BOTH_4W','paid_department_count_change_rate',s.paid_department_count_change_rate,s.activity_transition_base='ACTIVE_BOTH_4W'),('ACTIVE_BOTH_4W','paid_commodity_count_change_rate',s.paid_commodity_count_change_rate,s.activity_transition_base='ACTIVE_BOTH_4W'))v(population,metric_name,metric_value,eligible) WHERE v.eligible)
SELECT population,metric_name,COUNT(*)::BIGINT eligible_row_count,COUNT(metric_value)::BIGINT non_null_count,COUNT(*)-COUNT(metric_value) null_count,COUNT(*)FILTER(WHERE metric_value=0)::BIGINT zero_count,COUNT(*)FILTER(WHERE metric_value<0)::BIGINT negative_count,MIN(metric_value) minimum_value,
 PERCENTILE_CONT(.01)WITHIN GROUP(ORDER BY metric_value) percentile_01,PERCENTILE_CONT(.05)WITHIN GROUP(ORDER BY metric_value) percentile_05,PERCENTILE_CONT(.10)WITHIN GROUP(ORDER BY metric_value) percentile_10,PERCENTILE_CONT(.25)WITHIN GROUP(ORDER BY metric_value) percentile_25,PERCENTILE_CONT(.50)WITHIN GROUP(ORDER BY metric_value) percentile_50,PERCENTILE_CONT(.75)WITHIN GROUP(ORDER BY metric_value) percentile_75,PERCENTILE_CONT(.90)WITHIN GROUP(ORDER BY metric_value) percentile_90,PERCENTILE_CONT(.95)WITHIN GROUP(ORDER BY metric_value) percentile_95,PERCENTILE_CONT(.99)WITHIN GROUP(ORDER BY metric_value) percentile_99,MAX(metric_value) maximum_value,AVG(metric_value) mean_value,STDDEV_SAMP(metric_value) stddev_value FROM long GROUP BY population,metric_name;

-- 05-4. 활동전이 상태 분포
CREATE TABLE mart.diag_reference_week_state_profile AS
WITH g AS(SELECT GROUPING(reference_week) gr,reference_week,activity_transition_base,COUNT(*)::BIGINT n,COUNT(DISTINCT household_key)::BIGINT hh,COUNT(*)FILTER(WHERE has_purchase_26w)::BIGINT buyers,COUNT(*)FILTER(WHERE NOT has_purchase_26w)::BIGINT nonbuyers,COUNT(*)FILTER(WHERE has_any_activity_decline_raw)::BIGINT anyd,COUNT(*)FILTER(WHERE has_both_frequency_and_sales_decline_raw)::BIGINT bothd,AVG(recency_days_26w) ar,AVG(frequency_26w) af,PERCENTILE_CONT(.5)WITHIN GROUP(ORDER BY frequency_26w) mf,AVG(monetary_26w) am,PERCENTILE_CONT(.5)WITHIN GROUP(ORDER BY monetary_26w) mm,AVG(rfm_value_index_26w) ai,PERCENTILE_CONT(.5)WITHIN GROUP(ORDER BY rfm_value_index_26w) mi FROM mart.household_reference_week GROUP BY GROUPING SETS((activity_transition_base),(reference_week,activity_transition_base))),t AS(SELECT gr,reference_week,activity_transition_base,n,hh,buyers,nonbuyers,anyd,bothd,ar,af,mf,am,mm,ai,mi,SUM(n)OVER(PARTITION BY gr,reference_week) denom FROM g)
SELECT CASE WHEN gr=1 THEN 'ALL' ELSE 'REFERENCE_WEEK' END aggregation_level,CASE WHEN gr=1 THEN NULL ELSE reference_week END reference_week,activity_transition_base,n snapshot_row_count,hh distinct_household_count,n::NUMERIC/NULLIF(denom,0) share_within_period,buyers purchaser_26w_count,nonbuyers no_purchase_26w_count,anyd any_activity_decline_raw_count,bothd both_frequency_sales_decline_raw_count,ar average_recency_days_26w,af average_frequency_26w,mf median_frequency_26w,am average_monetary_26w,mm median_monetary_26w,ai average_rfm_value_index_26w,mi median_rfm_value_index_26w FROM t;

-- 05-5. 변화율 분모 상태
CREATE TABLE mart.diag_reference_week_denominator_profile AS
WITH l AS(SELECT v.metric_name,v.denominator_status,v.rate FROM mart.household_reference_week h CROSS JOIN LATERAL(VALUES('basket_count_change_rate',h.basket_change_denominator_status,h.basket_count_change_rate),('sales_change_rate',h.sales_change_denominator_status,h.sales_change_rate),('paid_line_sales_change_rate',h.paid_line_sales_change_denominator_status,h.paid_line_sales_change_rate),('average_basket_value_change_rate',h.average_basket_change_denominator_status,h.average_basket_value_change_rate),('paid_product_count_change_rate',h.product_change_denominator_status,h.paid_product_count_change_rate),('paid_department_count_change_rate',h.department_change_denominator_status,h.paid_department_count_change_rate),('paid_commodity_count_change_rate',h.commodity_change_denominator_status,h.paid_commodity_count_change_rate),('discount_amount_change_rate',h.discount_change_denominator_status,h.discount_amount_change_rate))v(metric_name,denominator_status,rate)),g AS(SELECT metric_name,denominator_status,COUNT(*)::BIGINT n,COUNT(rate)::BIGINT defined FROM l GROUP BY metric_name,denominator_status)
SELECT metric_name,denominator_status,n row_count,n::NUMERIC/NULLIF(SUM(n)OVER(PARTITION BY metric_name),0) row_share,defined defined_rate_count,n-defined undefined_rate_count,defined::NUMERIC/NULLIF(n,0) defined_rate_share FROM g;

-- 05-6. RFM 동률 진단
CREATE TABLE mart.diag_reference_week_rfm_ties AS
WITH l AS MATERIALIZED(SELECT h.reference_week,v.metric_name,v.raw_value,v.percentile_value FROM mart.household_reference_week h CROSS JOIN LATERAL(VALUES('recency_days_26w',h.recency_days_26w::NUMERIC,h.recency_percentile_26w),('frequency_26w',h.frequency_26w::NUMERIC,h.frequency_percentile_26w),('monetary_26w',h.monetary_26w,h.monetary_percentile_26w))v(metric_name,raw_value,percentile_value) WHERE h.has_purchase_26w),ties AS(SELECT reference_week,metric_name,raw_value,COUNT(*)::BIGINT tie_count FROM l GROUP BY reference_week,metric_name,raw_value),summary AS(SELECT reference_week,metric_name,SUM(tie_count)::BIGINT purchaser_row_count,COUNT(*)::BIGINT distinct_raw_value_count,MAX(tie_count)::BIGINT largest_tie_count,SUM(tie_count)FILTER(WHERE tie_count>=2)::BIGINT tied_row_count FROM ties GROUP BY reference_week,metric_name),pct AS(SELECT reference_week,metric_name,COUNT(DISTINCT percentile_value)::BIGINT distinct_percentile_value_count FROM l GROUP BY reference_week,metric_name)
SELECT s.reference_week,s.metric_name,s.purchaser_row_count,s.distinct_raw_value_count,p.distinct_percentile_value_count,s.largest_tie_count,s.largest_tie_count::NUMERIC/NULLIF(s.purchaser_row_count,0) largest_tie_share,s.tied_row_count,s.tied_row_count::NUMERIC/NULLIF(s.purchaser_row_count,0) tied_row_share FROM summary s JOIN pct p USING(reference_week,metric_name);

-- 05-7. 가치·활동감소 기준 민감도
-- cutoff와 규칙은 최종 분류가 아닌 대상 규모 비교용 진단 후보다.
CREATE TABLE mart.diag_reference_week_threshold_sensitivity AS
WITH expanded AS (
SELECT h.household_key,
    h.reference_week,
    h.frequency_26w,
    h.monetary_26w,
    h.rfm_value_index_26w,
    c.value_cutoff,
    r.activity_rule,
    r.eligible,
    r.decline,
    (h.has_purchase_26w
    AND h.rfm_value_index_26w>=c.value_cutoff) high_value
FROM mart.household_reference_week h
    CROSS
JOIN (
    VALUES (.70::NUMERIC),
    (.80::NUMERIC),
    (.90::NUMERIC))c(value_cutoff)
    CROSS
JOIN LATERAL (
    VALUES ('BECAME_INACTIVE_ONLY',
    h.prior4_valid_basket_count>0,
    h.activity_transition_base='BECAME_INACTIVE'),
    ('ACTIVE_BOTH_ANY_RAW',
    h.activity_transition_base='ACTIVE_BOTH_4W',
    h.has_any_activity_decline_raw),
    ('ACTIVE_BOTH_BOTH_RAW',
    h.activity_transition_base='ACTIVE_BOTH_4W',
    h.has_both_frequency_and_sales_decline_raw),
    ('INACTIVE_OR_ANY_RAW',
    h.prior4_valid_basket_count>0,
    h.activity_transition_base='BECAME_INACTIVE' OR(h.activity_transition_base='ACTIVE_BOTH_4W'
    AND h.has_any_activity_decline_raw)),
    ('INACTIVE_OR_BOTH_RAW',
    h.prior4_valid_basket_count>0,
    h.activity_transition_base='BECAME_INACTIVE' OR(h.activity_transition_base='ACTIVE_BOTH_4W'
    AND h.has_both_frequency_and_sales_decline_raw)),
    ('INACTIVE_OR_SALES_RATE_LE_20',
    h.prior4_valid_basket_count>0,
    h.activity_transition_base='BECAME_INACTIVE' OR(h.activity_transition_base='ACTIVE_BOTH_4W'
    AND h.sales_change_denominator_status='COMPARABLE'
    AND h.sales_change_rate<=-.20)),
    ('INACTIVE_OR_SALES_RATE_LE_30',
    h.prior4_valid_basket_count>0,
    h.activity_transition_base='BECAME_INACTIVE' OR(h.activity_transition_base='ACTIVE_BOTH_4W'
    AND h.sales_change_denominator_status='COMPARABLE'
    AND h.sales_change_rate<=-.30)),
    ('INACTIVE_OR_SALES_RATE_LE_50',
    h.prior4_valid_basket_count>0,
    h.activity_transition_base='BECAME_INACTIVE' OR(h.activity_transition_base='ACTIVE_BOTH_4W'
    AND h.sales_change_denominator_status='COMPARABLE'
    AND h.sales_change_rate<=-.50)),
    ('INACTIVE_OR_BOTH_RATE_LE_20',
    h.prior4_valid_basket_count>0,
    h.activity_transition_base='BECAME_INACTIVE' OR(h.activity_transition_base='ACTIVE_BOTH_4W'
    AND h.basket_change_denominator_status='COMPARABLE'
    AND h.sales_change_denominator_status='COMPARABLE'
    AND h.basket_count_change_rate<=-.20
    AND h.sales_change_rate<=-.20)),
    ('INACTIVE_OR_BOTH_RATE_LE_30',
    h.prior4_valid_basket_count>0,
    h.activity_transition_base='BECAME_INACTIVE' OR(h.activity_transition_base='ACTIVE_BOTH_4W'
    AND h.basket_change_denominator_status='COMPARABLE'
    AND h.sales_change_denominator_status='COMPARABLE'
    AND h.basket_count_change_rate<=-.30
    AND h.sales_change_rate<=-.30)),
    ('INACTIVE_OR_BOTH_RATE_LE_50',
    h.prior4_valid_basket_count>0,
    h.activity_transition_base='BECAME_INACTIVE' OR(h.activity_transition_base='ACTIVE_BOTH_4W'
    AND h.basket_change_denominator_status='COMPARABLE'
    AND h.sales_change_denominator_status='COMPARABLE'
    AND h.basket_count_change_rate<=-.50
    AND h.sales_change_rate<=-.50)))r(activity_rule,
    eligible,
    decline)),
    g AS(
SELECT GROUPING(reference_week)gr,
    reference_week,
    value_cutoff,
    activity_rule,
    COUNT(*)::BIGINT total,
    COUNT(*)
    FILTER (
WHERE eligible)::BIGINT eligible,
    COUNT(*)
    FILTER (
WHERE decline)::BIGINT declined,
    COUNT(*)
    FILTER (
WHERE high_value)::BIGINT high,
    COUNT(*)
    FILTER (
WHERE high_value
    AND decline)::BIGINT AS high_value_decline_count,
    AVG(frequency_26w)
    FILTER (
WHERE high_value
    AND decline)af,
    AVG(monetary_26w)
    FILTER (
WHERE high_value
    AND decline)am,
    AVG(rfm_value_index_26w)
    FILTER (
WHERE high_value
    AND decline)ai
FROM expanded
GROUP BY GROUPING SETS ((value_cutoff,
    activity_rule),
    (reference_week,
    value_cutoff,
    activity_rule)))
SELECT
    CASE
    WHEN gr=1
    THEN 'ALL'
    ELSE 'REFERENCE_WEEK'
    END aggregation_level,
    CASE
    WHEN gr=1
    THEN NULL
    ELSE reference_week
    END reference_week,
    value_cutoff,
    activity_rule,
    total total_row_count,
    eligible eligible_row_count,
    declined activity_decline_count,
    declined::NUMERIC/NULLIF(eligible,
    0) activity_decline_share_of_eligible,
    high high_value_count,
    high::NUMERIC/NULLIF(total,
    0) high_value_share,
    high_value_decline_count AS high_value_activity_decline_count,
    high_value_decline_count::NUMERIC/NULLIF(high,
    0) high_value_activity_decline_share_of_high_value,
    high_value_decline_count::NUMERIC/NULLIF(total,
    0) high_value_activity_decline_share_of_all,
    af average_frequency_26w_of_high_value_decline,
    am average_monetary_26w_of_high_value_decline,
    ai average_rfm_value_index_26w_of_high_value_decline
FROM g;

-- 05-8. 진단 테이블 통계
ANALYZE mart.diag_reference_week_overview;

ANALYZE mart.diag_reference_week_metric_profile;

ANALYZE mart.diag_reference_week_state_profile;

ANALYZE mart.diag_reference_week_denominator_profile;

ANALYZE mart.diag_reference_week_rfm_ties;

ANALYZE mart.diag_reference_week_threshold_sensitivity;
COMMIT;

-- 05-9. 필수 검증
WITH source_summary AS (
SELECT COUNT(*)::BIGINT AS source_row_count
FROM mart.household_reference_week
    ),
    overview_summary AS (
SELECT COUNT(*)::BIGINT AS overview_row_count,
    MAX(source_row_count)::BIGINT AS source_row_count,
    MAX(reference_week_count)::BIGINT AS reference_week_count,
    MAX(distinct_household_count)::BIGINT AS distinct_household_count
FROM mart.diag_reference_week_overview
    ),
    metric_profile_issues AS (
SELECT
    CASE
    WHEN COUNT(*) = 0
    THEN 1
    ELSE 0
    END + COUNT(*)
    FILTER (
WHERE population NOT IN ('PURCHASERS_26W',
    'ACTIVE_BOTH_4W')
    OR eligible_row_count <= 0
    OR eligible_row_count < non_null_count
    OR non_null_count + null_count <> eligible_row_count
    OR zero_count < 0
    OR negative_count < 0
    OR zero_count > non_null_count
    OR negative_count > non_null_count
    OR (minimum_value IS NOT NULL
    AND percentile_01 IS NOT NULL
    AND minimum_value > percentile_01)
    OR (percentile_01 IS NOT NULL
    AND percentile_05 IS NOT NULL
    AND percentile_01 > percentile_05)
    OR (percentile_05 IS NOT NULL
    AND percentile_10 IS NOT NULL
    AND percentile_05 > percentile_10)
    OR (percentile_10 IS NOT NULL
    AND percentile_25 IS NOT NULL
    AND percentile_10 > percentile_25)
    OR (percentile_25 IS NOT NULL
    AND percentile_50 IS NOT NULL
    AND percentile_25 > percentile_50)
    OR (percentile_50 IS NOT NULL
    AND percentile_75 IS NOT NULL
    AND percentile_50 > percentile_75)
    OR (percentile_75 IS NOT NULL
    AND percentile_90 IS NOT NULL
    AND percentile_75 > percentile_90)
    OR (percentile_90 IS NOT NULL
    AND percentile_95 IS NOT NULL
    AND percentile_90 > percentile_95)
    OR (percentile_95 IS NOT NULL
    AND percentile_99 IS NOT NULL
    AND percentile_95 > percentile_99)
    OR (percentile_99 IS NOT NULL
    AND maximum_value IS NOT NULL
    AND percentile_99 > maximum_value)
    )::BIGINT AS issue_count
FROM mart.diag_reference_week_metric_profile
    ),
    source_week_counts AS (
SELECT reference_week,
    COUNT(*)::BIGINT AS row_count
FROM mart.household_reference_week
GROUP BY reference_week
    ),
    state_week_counts AS (
SELECT reference_week,
    SUM(snapshot_row_count)::BIGINT AS row_count,
    SUM(share_within_period)::NUMERIC AS share_sum
FROM mart.diag_reference_week_state_profile
WHERE aggregation_level = 'REFERENCE_WEEK'
GROUP BY reference_week
    ),
    state_profile_issues AS (
SELECT COUNT(*)
    FILTER (
WHERE aggregation_level NOT IN ('ALL',
    'REFERENCE_WEEK')
    OR activity_transition_base IS NULL
    OR activity_transition_base NOT IN ('NO_ACTIVITY_8W',
    'REACTIVATED',
    'BECAME_INACTIVE',
    'ACTIVE_BOTH_4W')
    OR snapshot_row_count <= 0)::BIGINT
    +
    CASE
    WHEN COUNT(*)
    FILTER (
WHERE aggregation_level = 'ALL') = 0
    THEN 1
    ELSE 0
    END +
    CASE
    WHEN COUNT(*)
    FILTER (
WHERE aggregation_level = 'REFERENCE_WEEK') = 0
    THEN 1
    ELSE 0
    END +
    CASE
    WHEN COALESCE(SUM(snapshot_row_count)
    FILTER (
WHERE aggregation_level = 'ALL'),
    0)
    <> (
SELECT source_row_count
FROM source_summary)
    THEN 1
    ELSE 0
    END +
    CASE
    WHEN ABS(COALESCE(SUM(share_within_period)
    FILTER (
WHERE aggregation_level = 'ALL'),
    0) - 1::NUMERIC) > 1e-12
    THEN 1
    ELSE 0
    END + (
SELECT COUNT(*)
FROM source_week_counts source_counts
    FULL
JOIN state_week_counts state_counts USING (reference_week)
WHERE source_counts.row_count IS DISTINCT
FROM state_counts.row_count
    OR ABS(COALESCE(state_counts.share_sum,
    0) - 1::NUMERIC) > 1e-12)
    AS issue_count
FROM mart.diag_reference_week_state_profile
    ),
    denominator_groups AS (
SELECT metric_name,
    SUM(row_count)::BIGINT AS row_count,
    SUM(row_share)::NUMERIC AS share_sum
FROM mart.diag_reference_week_denominator_profile
GROUP BY metric_name
    ),
    denominator_profile_issues AS (
SELECT
    CASE
    WHEN COUNT(*) = 0
    THEN 1
    ELSE 0
    END + COUNT(*)
    FILTER (
WHERE denominator_status IS NULL
    OR denominator_status NOT IN ('COMPARABLE',
    'FROM_ZERO',
    'BOTH_ZERO')
    OR metric_name NOT IN ('basket_count_change_rate',
    'sales_change_rate',
    'paid_line_sales_change_rate',
    'average_basket_value_change_rate',
    'paid_product_count_change_rate',
    'paid_department_count_change_rate',
    'paid_commodity_count_change_rate',
    'discount_amount_change_rate')
    OR defined_rate_count + undefined_rate_count <> row_count
    OR (defined_rate_share IS NOT NULL
    AND defined_rate_share NOT BETWEEN 0
    AND 1))::BIGINT
    + (
SELECT COUNT(*)
FROM denominator_groups
WHERE row_count <> (
SELECT source_row_count
FROM source_summary)
    OR ABS(share_sum - 1::NUMERIC) > 1e-12) AS issue_count
FROM mart.diag_reference_week_denominator_profile
    ),
    rfm_tie_issues AS (
SELECT
    CASE
    WHEN COUNT(*) = 0
    THEN 1
    ELSE 0
    END + COUNT(*)
    FILTER (
WHERE metric_name NOT IN ('recency_days_26w',
    'frequency_26w',
    'monetary_26w')
    OR purchaser_row_count <= 0
    OR distinct_raw_value_count <= 0
    OR distinct_percentile_value_count <= 0
    OR largest_tie_count > purchaser_row_count
    OR tied_row_count > purchaser_row_count
    OR largest_tie_share NOT BETWEEN 0
    AND 1
    OR tied_row_share NOT BETWEEN 0
    AND 1)::BIGINT
    + (
SELECT COUNT(*)
FROM (
SELECT reference_week
FROM mart.diag_reference_week_rfm_ties
GROUP BY reference_week
HAVING COUNT(DISTINCT metric_name) <> 3
    ) missing_metrics) AS issue_count
FROM mart.diag_reference_week_rfm_ties
    ),
    threshold_group_issues AS (
SELECT COUNT(*)::BIGINT AS issue_count
FROM (
SELECT aggregation_level,
    reference_week,
    value_cutoff,
    COUNT(*)::BIGINT AS rule_count
FROM mart.diag_reference_week_threshold_sensitivity
GROUP BY aggregation_level,
    reference_week,
    value_cutoff
HAVING COUNT(*) <> 11
    OR COUNT(DISTINCT activity_rule) <> 11
    ) invalid_groups
    ),
    threshold_issues AS (
SELECT
    CASE
    WHEN COUNT(*) = 0
    THEN 1
    ELSE 0
    END + COUNT(*)
    FILTER (
WHERE value_cutoff NOT IN (0.70::NUMERIC,
    0.80::NUMERIC,
    0.90::NUMERIC)
    OR activity_rule IS NULL
    OR activity_rule NOT IN ('BECAME_INACTIVE_ONLY',
    'ACTIVE_BOTH_ANY_RAW',
    'ACTIVE_BOTH_BOTH_RAW',
    'INACTIVE_OR_ANY_RAW',
    'INACTIVE_OR_BOTH_RAW',
    'INACTIVE_OR_SALES_RATE_LE_20',
    'INACTIVE_OR_SALES_RATE_LE_30',
    'INACTIVE_OR_SALES_RATE_LE_50',
    'INACTIVE_OR_BOTH_RATE_LE_20',
    'INACTIVE_OR_BOTH_RATE_LE_30',
    'INACTIVE_OR_BOTH_RATE_LE_50')
    OR aggregation_level NOT IN ('ALL',
    'REFERENCE_WEEK')
    OR activity_decline_count > eligible_row_count
    OR high_value_activity_decline_count > activity_decline_count
    OR high_value_activity_decline_count > high_value_count
    OR eligible_row_count > total_row_count
    OR high_value_count > total_row_count
    OR (activity_decline_share_of_eligible IS NOT NULL
    AND activity_decline_share_of_eligible NOT BETWEEN 0
    AND 1)
    OR (high_value_share IS NOT NULL
    AND high_value_share NOT BETWEEN 0
    AND 1)
    OR (high_value_activity_decline_share_of_high_value IS NOT NULL
    AND high_value_activity_decline_share_of_high_value NOT BETWEEN 0
    AND 1)
    OR (high_value_activity_decline_share_of_all IS NOT NULL
    AND high_value_activity_decline_share_of_all NOT BETWEEN 0
    AND 1))::BIGINT
    +
    CASE
    WHEN COUNT(*)
    FILTER (
WHERE aggregation_level = 'ALL') <> 33
    THEN 1
    ELSE 0
    END +
    CASE
    WHEN COUNT(*)
    FILTER (
WHERE aggregation_level = 'REFERENCE_WEEK') = 0
    THEN 1
    ELSE 0
    END + (
SELECT issue_count
FROM threshold_group_issues) AS issue_count
FROM mart.diag_reference_week_threshold_sensitivity
    ),
    checks AS (
SELECT 'diagnostics_source_nonempty'::TEXT AS check_name,
    ((
SELECT
    CASE
    WHEN source_row_count > 0
    THEN 0
    ELSE 1
    END FROM source_summary)
    + (
SELECT
    CASE
    WHEN overview_row_count = 1
    THEN 0
    ELSE 1
    END +
    CASE
    WHEN source_row_count = (
SELECT source_row_count
FROM source_summary)
    THEN 0
    ELSE 1
    END +
    CASE
    WHEN reference_week_count > 0
    THEN 0
    ELSE 1
    END +
    CASE
    WHEN distinct_household_count > 0
    THEN 0
    ELSE 1
    END FROM overview_summary))::BIGINT AS issue_count,
    '원천 및 overview 행 수 대사'::TEXT AS detail
UNION ALL
SELECT 'metric_profile_integrity',
    issue_count,
    '지표 프로파일 건수·NULL·분위수 순서'
FROM metric_profile_issues
UNION ALL
SELECT 'state_share_integrity',
    issue_count,
    '활동상태별 행 수 및 비율 대사'
FROM state_profile_issues
UNION ALL
SELECT 'denominator_profile_integrity',
    issue_count,
    '변화율 분모 상태와 정의 여부'
FROM denominator_profile_issues
UNION ALL
SELECT 'rfm_tie_integrity',
    issue_count,
    'RFM 동률 집계 범위'
FROM rfm_tie_issues
UNION ALL
SELECT 'threshold_sensitivity_integrity',
    issue_count,
    'cutoff·11개 규칙·집계수준 및 수치관계'
FROM threshold_issues
    )
SELECT check_name,
    CASE
    WHEN issue_count = 0
    THEN 'PASS'
    ELSE 'FAIL'
    END AS status,
    issue_count,
    detail
FROM checks
ORDER BY check_name;

-- 05-10. 최종 확인용 조회
-- 05-10-1. 전체 진단 개요
SELECT source_row_count,
    distinct_household_count,
    reference_week_count,
    min_reference_week,
    max_reference_week,
    purchaser_26w_row_count,
    purchaser_26w_share,
    no_purchase_26w_row_count,
    no_purchase_26w_share,
    no_activity_8w_count,
    no_activity_8w_share,
    reactivated_count,
    reactivated_share,
    became_inactive_count,
    became_inactive_share,
    active_both_4w_count,
    active_both_4w_share,
    any_activity_decline_raw_count,
    any_activity_decline_raw_share,
    both_frequency_sales_decline_raw_count,
    both_frequency_sales_decline_raw_share
FROM mart.diag_reference_week_overview;

-- 05-10-2. 핵심 지표 분포
SELECT population,
    metric_name,
    eligible_row_count,
    non_null_count,
    null_count,
    zero_count,
    negative_count,
    minimum_value,
    percentile_01,
    percentile_05,
    percentile_10,
    percentile_25,
    percentile_50,
    percentile_75,
    percentile_90,
    percentile_95,
    percentile_99,
    maximum_value,
    mean_value,
    stddev_value
FROM mart.diag_reference_week_metric_profile
ORDER BY population,
    metric_name;
	
-- 05-10-3. 전체 활동상태 분포
SELECT aggregation_level,
    reference_week,
    activity_transition_base,
    snapshot_row_count,
    distinct_household_count,
    share_within_period,
    purchaser_26w_count,
    no_purchase_26w_count,
    any_activity_decline_raw_count,
    both_frequency_sales_decline_raw_count,
    average_recency_days_26w,
    average_frequency_26w,
    median_frequency_26w,
    average_monetary_26w,
    median_monetary_26w,
    average_rfm_value_index_26w,
    median_rfm_value_index_26w
FROM mart.diag_reference_week_state_profile
WHERE aggregation_level='ALL'
ORDER BY snapshot_row_count DESC;

-- 05-10-4. 변화율 분모 상태
SELECT metric_name,
    denominator_status,
    row_count,
    row_share,
    defined_rate_count,
    undefined_rate_count,
    defined_rate_share
FROM mart.diag_reference_week_denominator_profile
ORDER BY metric_name,
    denominator_status;
	
-- 05-10-5. RFM 동률 상위 기준주차
SELECT reference_week,
    metric_name,
    purchaser_row_count,
    distinct_raw_value_count,
    distinct_percentile_value_count,
    largest_tie_count,
    largest_tie_share,
    tied_row_count,
    tied_row_share
FROM mart.diag_reference_week_rfm_ties
ORDER BY largest_tie_share DESC,
    reference_week,
    metric_name
LIMIT 30;

-- 05-10-6. 전체 임계값 민감도
SELECT aggregation_level,
    reference_week,
    value_cutoff,
    activity_rule,
    total_row_count,
    eligible_row_count,
    activity_decline_count,
    activity_decline_share_of_eligible,
    high_value_count,
    high_value_share,
    high_value_activity_decline_count,
    high_value_activity_decline_share_of_high_value,
    high_value_activity_decline_share_of_all,
    average_frequency_26w_of_high_value_decline,
    average_monetary_26w_of_high_value_decline,
    average_rfm_value_index_26w_of_high_value_decline
FROM mart.diag_reference_week_threshold_sensitivity
WHERE aggregation_level='ALL'
ORDER BY value_cutoff,
    activity_rule;
	
-- 05-10-7. 기준주차별 민감도 안정성
SELECT activity_rule,
    value_cutoff,
    COUNT(DISTINCT reference_week)::BIGINT reference_week_count,
    AVG(activity_decline_share_of_eligible) average_activity_decline_share,
    MIN(activity_decline_share_of_eligible) minimum_activity_decline_share,
    MAX(activity_decline_share_of_eligible) maximum_activity_decline_share,
    STDDEV_SAMP(activity_decline_share_of_eligible) stddev_activity_decline_share,
    AVG(high_value_activity_decline_share_of_high_value) average_high_value_decline_share,
    MIN(high_value_activity_decline_share_of_high_value) minimum_high_value_decline_share,
    MAX(high_value_activity_decline_share_of_high_value) maximum_high_value_decline_share,
    STDDEV_SAMP(high_value_activity_decline_share_of_high_value) stddev_high_value_decline_share
FROM mart.diag_reference_week_threshold_sensitivity
WHERE aggregation_level='REFERENCE_WEEK'
GROUP BY activity_rule,
    value_cutoff
ORDER BY activity_rule,
    value_cutoff;


-- ==================================================
-- 05B. 활동변화 기간 4주·6주·8주 비교 진단
-- ==================================================

BEGIN;

DROP TABLE IF EXISTS mart.diag_activity_window_agreement;
DROP TABLE IF EXISTS mart.diag_activity_window_stability;
DROP TABLE IF EXISTS mart.diag_activity_window_threshold_sensitivity;
DROP TABLE IF EXISTS mart.diag_activity_window_metric_profile;
DROP TABLE IF EXISTS mart.diag_activity_window_overview;
DROP TABLE IF EXISTS mart.activity_window_comparison;

-- 05B-01. 활동비교 기간 설정
-- 05B-02. 활동기간별 가구-기준주차 테이블 생성
-- 05B-03. 활동전이 및 변화율 계산
-- 05B-04. 다음 4주 구매 여부 라벨 생성
-- future4 컬럼은 모델 목표변수이며 입력변수로 사용하지 않는다.
-- 기준주차 이후 정보는 과거 활동지표에 사용하지 않으며, 기간 선택은 Python Train·Validation에서 수행한다.
CREATE TABLE mart.activity_window_comparison AS
WITH window_candidates(window_weeks) AS (
    VALUES
        (4),
        (6),
        (8)
),

expanded_grid AS (
    SELECT
        reference_data.household_key,
        reference_data.reference_week,
        candidate.window_weeks,
        reference_data.reference_week - (2 * candidate.window_weeks) + 1 AS prior_start_week,
        reference_data.reference_week - candidate.window_weeks AS prior_end_week,
        reference_data.reference_week - candidate.window_weeks + 1 AS recent_start_week,
        reference_data.reference_week AS recent_end_week,
        reference_data.reference_week + 1 AS future4_start_week,
        reference_data.reference_week + 4 AS future4_end_week,
        reference_data.has_purchase_26w,
        reference_data.recency_weeks_26w,
        reference_data.recency_days_26w,
        reference_data.frequency_26w,
        reference_data.monetary_26w,
        reference_data.fm_value_index_26w,
        reference_data.rfm_value_index_26w,
        prior_value.fm_value_index_26w AS pre_window_fm_value_index_26w,
        prior_value.rfm_value_index_26w AS pre_window_rfm_value_index_26w,
        prior_value.household_key IS NOT NULL AS has_pre_window_snapshot,
        prior_value.rfm_value_index_26w IS NOT NULL AS has_pre_window_value_history
    FROM mart.household_reference_week AS reference_data
    CROSS JOIN window_candidates AS candidate
    LEFT JOIN mart.household_reference_week AS prior_value
        ON prior_value.household_key = reference_data.household_key
       AND prior_value.reference_week = reference_data.reference_week - candidate.window_weeks
),

grid_with_common_flag AS (
    SELECT
        expanded_grid.household_key,
        expanded_grid.reference_week,
        expanded_grid.window_weeks,
        expanded_grid.prior_start_week,
        expanded_grid.prior_end_week,
        expanded_grid.recent_start_week,
        expanded_grid.recent_end_week,
        expanded_grid.future4_start_week,
        expanded_grid.future4_end_week,
        expanded_grid.has_purchase_26w,
        expanded_grid.recency_weeks_26w,
        expanded_grid.recency_days_26w,
        expanded_grid.frequency_26w,
        expanded_grid.monetary_26w,
        expanded_grid.fm_value_index_26w,
        expanded_grid.rfm_value_index_26w,
        expanded_grid.pre_window_fm_value_index_26w,
        expanded_grid.pre_window_rfm_value_index_26w,
        expanded_grid.has_pre_window_snapshot,
        expanded_grid.has_pre_window_value_history,
        BOOL_AND(expanded_grid.has_pre_window_snapshot) OVER (
            PARTITION BY
                expanded_grid.household_key,
                expanded_grid.reference_week
        ) AS is_common_comparison_row
    FROM expanded_grid
),

period_sums AS (
    SELECT
        grid.household_key,
        grid.reference_week,
        grid.window_weeks,
        SUM(weekly.valid_basket_count) FILTER (
            WHERE weekly.week_no BETWEEN grid.prior_start_week AND grid.prior_end_week
        )::BIGINT AS prior_valid_basket_count,
        SUM(weekly.weekly_sales) FILTER (
            WHERE weekly.week_no BETWEEN grid.prior_start_week AND grid.prior_end_week
        )::NUMERIC AS prior_sales,
        SUM(weekly.valid_basket_count) FILTER (
            WHERE weekly.week_no BETWEEN grid.recent_start_week AND grid.recent_end_week
        )::BIGINT AS recent_valid_basket_count,
        SUM(weekly.weekly_sales) FILTER (
            WHERE weekly.week_no BETWEEN grid.recent_start_week AND grid.recent_end_week
        )::NUMERIC AS recent_sales,
        SUM(weekly.valid_basket_count) FILTER (
            WHERE weekly.week_no BETWEEN grid.future4_start_week AND grid.future4_end_week
        )::BIGINT AS future4_valid_basket_count
    FROM grid_with_common_flag AS grid
    JOIN mart.fact_household_week AS weekly
        ON weekly.household_key = grid.household_key
       AND weekly.week_no BETWEEN grid.prior_start_week AND grid.future4_end_week
    GROUP BY
        grid.household_key,
        grid.reference_week,
        grid.window_weeks
),

aggregated_data AS (
    SELECT
        grid.household_key,
        grid.reference_week,
        grid.window_weeks,
        grid.prior_start_week,
        grid.prior_end_week,
        grid.recent_start_week,
        grid.recent_end_week,
        grid.future4_start_week,
        grid.future4_end_week,
        grid.has_purchase_26w,
        grid.recency_weeks_26w,
        grid.recency_days_26w,
        grid.frequency_26w,
        grid.monetary_26w,
        grid.fm_value_index_26w,
        grid.rfm_value_index_26w,
        grid.pre_window_fm_value_index_26w,
        grid.pre_window_rfm_value_index_26w,
        grid.has_pre_window_snapshot,
        grid.has_pre_window_value_history,
        grid.is_common_comparison_row,
        sums.prior_valid_basket_count,
        sums.prior_sales,
        sums.recent_valid_basket_count,
        sums.recent_sales,
        sums.future4_valid_basket_count
    FROM grid_with_common_flag AS grid
    JOIN period_sums AS sums
        USING (
            household_key,
            reference_week,
            window_weeks
        )
),

changes AS (
    SELECT
        aggregated_data.household_key,
        aggregated_data.reference_week,
        aggregated_data.window_weeks,
        aggregated_data.prior_start_week,
        aggregated_data.prior_end_week,
        aggregated_data.recent_start_week,
        aggregated_data.recent_end_week,
        aggregated_data.future4_start_week,
        aggregated_data.future4_end_week,
        aggregated_data.has_purchase_26w,
        aggregated_data.recency_weeks_26w,
        aggregated_data.recency_days_26w,
        aggregated_data.frequency_26w,
        aggregated_data.monetary_26w,
        aggregated_data.fm_value_index_26w,
        aggregated_data.rfm_value_index_26w,
        aggregated_data.pre_window_fm_value_index_26w,
        aggregated_data.pre_window_rfm_value_index_26w,
        aggregated_data.has_pre_window_snapshot,
        aggregated_data.has_pre_window_value_history,
        aggregated_data.is_common_comparison_row,
        aggregated_data.prior_valid_basket_count,
        aggregated_data.prior_sales,
        aggregated_data.recent_valid_basket_count,
        aggregated_data.recent_sales,
        aggregated_data.future4_valid_basket_count,
        aggregated_data.recent_valid_basket_count - aggregated_data.prior_valid_basket_count AS basket_count_change,
        aggregated_data.recent_sales - aggregated_data.prior_sales AS sales_change,
        aggregated_data.recent_valid_basket_count::NUMERIC
            / NULLIF(aggregated_data.prior_valid_basket_count, 0) - 1 AS basket_count_change_rate,
        aggregated_data.recent_sales / NULLIF(aggregated_data.prior_sales, 0) - 1 AS sales_change_rate
    FROM aggregated_data
),

states AS (
    SELECT
        changes.household_key,
        changes.reference_week,
        changes.window_weeks,
        changes.prior_start_week,
        changes.prior_end_week,
        changes.recent_start_week,
        changes.recent_end_week,
        changes.future4_start_week,
        changes.future4_end_week,
        changes.has_purchase_26w,
        changes.recency_weeks_26w,
        changes.recency_days_26w,
        changes.frequency_26w,
        changes.monetary_26w,
        changes.fm_value_index_26w,
        changes.rfm_value_index_26w,
        changes.pre_window_rfm_value_index_26w,
        changes.pre_window_fm_value_index_26w,
        changes.has_pre_window_snapshot,
        changes.has_pre_window_value_history,
        changes.is_common_comparison_row,
        changes.prior_valid_basket_count,
        changes.prior_sales,
        changes.recent_valid_basket_count,
        changes.recent_sales,
        changes.basket_count_change,
        changes.sales_change,
        changes.basket_count_change_rate,
        changes.sales_change_rate,
        changes.future4_valid_basket_count,
        CASE
            WHEN changes.prior_valid_basket_count > 0 THEN 'COMPARABLE'
            WHEN changes.recent_valid_basket_count > 0 THEN 'FROM_ZERO'
            ELSE 'BOTH_ZERO'
        END AS basket_change_denominator_status,
        CASE
            WHEN changes.prior_sales > 0 THEN 'COMPARABLE'
            WHEN changes.recent_sales > 0 THEN 'FROM_ZERO'
            ELSE 'BOTH_ZERO'
        END AS sales_change_denominator_status,
        CASE
            WHEN changes.prior_valid_basket_count = 0
             AND changes.recent_valid_basket_count = 0
            THEN 'NO_ACTIVITY_BOTH_WINDOWS'
            WHEN changes.prior_valid_basket_count = 0 THEN 'REACTIVATED'
            WHEN changes.recent_valid_basket_count = 0 THEN 'BECAME_INACTIVE'
            ELSE 'ACTIVE_BOTH_WINDOWS'
        END AS activity_transition
    FROM changes
)
SELECT
    states.household_key,
    states.reference_week,
    states.window_weeks,
    states.prior_start_week,
    states.prior_end_week,
    states.recent_start_week,
    states.recent_end_week,
    states.future4_start_week,
    states.future4_end_week,
    states.has_purchase_26w,
    states.recency_weeks_26w,
    states.recency_days_26w,
    states.frequency_26w,
    states.monetary_26w,
    states.fm_value_index_26w,
    states.rfm_value_index_26w,
    states.pre_window_rfm_value_index_26w,
    states.pre_window_fm_value_index_26w,
    states.has_pre_window_snapshot,
    states.has_pre_window_value_history,
    states.is_common_comparison_row,
    states.prior_valid_basket_count,
    states.prior_sales,
    states.recent_valid_basket_count,
    states.recent_sales,
    states.basket_count_change,
    states.sales_change,
    states.basket_count_change_rate,
    states.sales_change_rate,
    states.basket_change_denominator_status,
    states.sales_change_denominator_status,
    states.activity_transition,
    states.activity_transition = 'ACTIVE_BOTH_WINDOWS'
        AND (states.basket_count_change < 0 OR states.sales_change < 0) AS has_any_activity_decline_raw,
    states.activity_transition = 'ACTIVE_BOTH_WINDOWS'
        AND states.basket_count_change < 0 AND states.sales_change < 0 AS has_both_frequency_and_sales_decline_raw,
    states.future4_valid_basket_count,
    states.future4_valid_basket_count > 0 AS future4_has_purchase,
    states.future4_valid_basket_count = 0 AS future4_no_purchase
FROM states;

ALTER TABLE mart.activity_window_comparison
    ADD CONSTRAINT pk_activity_window_comparison
    PRIMARY KEY (
        household_key,
        reference_week,
        window_weeks
    );

ALTER TABLE mart.activity_window_comparison
    ADD CONSTRAINT chk_activity_window_weeks
    CHECK (
        window_weeks IN (4, 6, 8)
    );

CREATE INDEX idx_activity_window_reference
    ON mart.activity_window_comparison (
        reference_week,
        window_weeks
    );
CREATE INDEX idx_activity_window_transition
    ON mart.activity_window_comparison (
        window_weeks,
        activity_transition
    );

ANALYZE mart.activity_window_comparison;

-- 05B-05. 기간별 전체 분포 진단
CREATE TABLE mart.diag_activity_window_overview AS
WITH summary AS (
    SELECT
        window_weeks,
        COUNT(*)::BIGINT AS source_row_count,
        COUNT(DISTINCT household_key)::BIGINT AS distinct_household_count,
        COUNT(DISTINCT reference_week)::BIGINT AS reference_week_count,
        MIN(reference_week) AS min_reference_week,
        MAX(reference_week) AS max_reference_week,
        COUNT(*) FILTER (
            WHERE activity_transition = 'NO_ACTIVITY_BOTH_WINDOWS'
        )::BIGINT AS no_activity_count,
        COUNT(*) FILTER (
            WHERE activity_transition = 'REACTIVATED'
        )::BIGINT AS reactivated_count,
        COUNT(*) FILTER (
            WHERE activity_transition = 'BECAME_INACTIVE'
        )::BIGINT AS became_inactive_count,
        COUNT(*) FILTER (
            WHERE activity_transition = 'ACTIVE_BOTH_WINDOWS'
        )::BIGINT AS active_both_count,
        COUNT(*) FILTER (
            WHERE has_any_activity_decline_raw
        )::BIGINT AS any_decline_count,
        COUNT(*) FILTER (
            WHERE has_both_frequency_and_sales_decline_raw
        )::BIGINT AS both_decline_count
    FROM mart.activity_window_comparison
    GROUP BY window_weeks
)
SELECT
    window_weeks,
    source_row_count,
    distinct_household_count,
    reference_week_count,
    min_reference_week,
    max_reference_week,
    no_activity_count,
    no_activity_count::NUMERIC / NULLIF(source_row_count, 0) AS no_activity_share,
    reactivated_count,
    reactivated_count::NUMERIC / NULLIF(source_row_count, 0) AS reactivated_share,
    became_inactive_count,
    became_inactive_count::NUMERIC / NULLIF(source_row_count, 0) AS became_inactive_share,
    active_both_count,
    active_both_count::NUMERIC / NULLIF(source_row_count, 0) AS active_both_share,
    any_decline_count AS any_activity_decline_raw_count,
    any_decline_count::NUMERIC / NULLIF(source_row_count, 0) AS any_activity_decline_raw_share,
    both_decline_count AS both_activity_decline_raw_count,
    both_decline_count::NUMERIC / NULLIF(source_row_count, 0) AS both_activity_decline_raw_share
FROM summary;

CREATE TABLE mart.diag_activity_window_metric_profile AS
WITH long_metrics AS (
    SELECT
        comparison.window_weeks,
        metric.metric_name,
        metric.metric_value
    FROM mart.activity_window_comparison AS comparison
    CROSS JOIN LATERAL (
        VALUES
            (
                'basket_count_change_rate',
                comparison.basket_count_change_rate
            ),
            (
                'sales_change_rate',
                comparison.sales_change_rate
            )
    ) AS metric(metric_name, metric_value)
    WHERE comparison.activity_transition = 'ACTIVE_BOTH_WINDOWS'
)
SELECT
    window_weeks,
    metric_name,
    COUNT(*)::BIGINT AS eligible_row_count,
    COUNT(metric_value)::BIGINT AS non_null_count,
    (COUNT(*) - COUNT(metric_value))::BIGINT AS null_count,
    COUNT(*) FILTER (
            WHERE metric_value = 0
        )::BIGINT AS zero_count,
    COUNT(*) FILTER (
            WHERE metric_value < 0
        )::BIGINT AS negative_count,
    MIN(metric_value) AS minimum_value,
    PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY metric_value) AS percentile_01,
    PERCENTILE_CONT(0.05) WITHIN GROUP (ORDER BY metric_value) AS percentile_05,
    PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY metric_value) AS percentile_10,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY metric_value) AS percentile_25,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY metric_value) AS percentile_50,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY metric_value) AS percentile_75,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY metric_value) AS percentile_90,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY metric_value) AS percentile_95,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY metric_value) AS percentile_99,
    MAX(metric_value) AS maximum_value,
    AVG(metric_value) AS mean_value,
    STDDEV_SAMP(metric_value) AS stddev_value
FROM long_metrics
GROUP BY
    window_weeks,
    metric_name;

-- 05B-06. 동일 임계값 민감도 비교
-- PRE_WINDOW_RFM 0.80은 기간 비교 중 가치기준을 동일하게 유지하기 위한 잠정 기준이다.
CREATE TABLE mart.diag_activity_window_threshold_sensitivity AS
WITH expanded AS (
    SELECT
        comparison.reference_week,
        comparison.window_weeks,
        rule.activity_rule,
        'PRE_WINDOW_RFM'::TEXT AS value_basis,
        0.80::NUMERIC AS value_cutoff,
        comparison.frequency_26w,
        comparison.monetary_26w,
        comparison.pre_window_rfm_value_index_26w AS value_index,
        rule.eligible,
        rule.decline,
        comparison.has_pre_window_value_history
            AND comparison.pre_window_rfm_value_index_26w >= 0.80::NUMERIC AS high_value
    FROM mart.activity_window_comparison AS comparison
    CROSS JOIN LATERAL (
        VALUES
            (
                'BECAME_INACTIVE_ONLY',
                comparison.prior_valid_basket_count > 0,
                comparison.activity_transition = 'BECAME_INACTIVE'
            ),
            (
                'INACTIVE_OR_SALES_RATE_LE_30',
                comparison.prior_valid_basket_count > 0,
                comparison.activity_transition = 'BECAME_INACTIVE'
                    OR (
                        comparison.activity_transition = 'ACTIVE_BOTH_WINDOWS'
                        AND comparison.sales_change_denominator_status = 'COMPARABLE'
                        AND comparison.sales_change_rate <= -0.30
                    )
            ),
            (
                'INACTIVE_OR_BOTH_RATE_LE_30',
                comparison.prior_valid_basket_count > 0,
                comparison.activity_transition = 'BECAME_INACTIVE'
                    OR (
                        comparison.activity_transition = 'ACTIVE_BOTH_WINDOWS'
                        AND comparison.basket_change_denominator_status = 'COMPARABLE'
                        AND comparison.sales_change_denominator_status = 'COMPARABLE'
                        AND comparison.basket_count_change_rate <= -0.30
                        AND comparison.sales_change_rate <= -0.30
                    )
            ),
            (
                'INACTIVE_OR_BOTH_RATE_LE_50',
                comparison.prior_valid_basket_count > 0,
                comparison.activity_transition = 'BECAME_INACTIVE'
                    OR (
                        comparison.activity_transition = 'ACTIVE_BOTH_WINDOWS'
                        AND comparison.basket_change_denominator_status = 'COMPARABLE'
                        AND comparison.sales_change_denominator_status = 'COMPARABLE'
                        AND comparison.basket_count_change_rate <= -0.50
                        AND comparison.sales_change_rate <= -0.50
                    )
            )
    ) AS rule(activity_rule, eligible, decline)
    WHERE comparison.is_common_comparison_row
),

grouped AS (
    SELECT
        GROUPING(reference_week) AS reference_grouped,
        reference_week,
        window_weeks,
        activity_rule,
        value_basis,
        value_cutoff,
        COUNT(*)::BIGINT AS total_count,
        COUNT(*) FILTER (
            WHERE eligible
        )::BIGINT AS eligible_count,
        COUNT(*) FILTER (
            WHERE eligible AND decline
        )::BIGINT AS decline_count,
        COUNT(*) FILTER (
            WHERE high_value
        )::BIGINT AS high_count,
        COUNT(*) FILTER (
            WHERE high_value AND eligible AND decline
        )::BIGINT AS high_decline_count,
        AVG(value_index) FILTER (
            WHERE high_value AND eligible AND decline
        ) AS average_value,
        AVG(frequency_26w) FILTER (
            WHERE high_value AND eligible AND decline
        ) AS average_frequency,
        AVG(monetary_26w) FILTER (
            WHERE high_value AND eligible AND decline
        ) AS average_monetary
    FROM expanded
    GROUP BY GROUPING SETS (
        (window_weeks, activity_rule, value_basis, value_cutoff),
        (reference_week, window_weeks, activity_rule, value_basis, value_cutoff)
    )
)
SELECT
    CASE WHEN reference_grouped = 1 THEN 'ALL' ELSE 'REFERENCE_WEEK' END AS aggregation_level,
    CASE WHEN reference_grouped = 1 THEN NULL ELSE reference_week END AS reference_week,
    window_weeks,
    activity_rule,
    value_basis,
    value_cutoff,
    total_count AS total_row_count,
    eligible_count AS eligible_row_count,
    decline_count AS activity_decline_count,
    decline_count::NUMERIC / NULLIF(eligible_count, 0) AS activity_decline_share_of_eligible,
    high_count AS high_value_count,
    high_count::NUMERIC / NULLIF(total_count, 0) AS high_value_share,
    high_decline_count AS high_value_activity_decline_count,
    high_decline_count::NUMERIC / NULLIF(high_count, 0) AS high_value_activity_decline_share_of_high_value,
    high_decline_count::NUMERIC / NULLIF(total_count, 0) AS high_value_activity_decline_share_of_all,
    average_value AS average_value_index_of_high_value_decline,
    average_frequency AS average_frequency_26w_of_high_value_decline,
    average_monetary AS average_monetary_26w_of_high_value_decline
FROM grouped;

ANALYZE mart.diag_activity_window_threshold_sensitivity;

-- 05B-07. 기준주차별 안정성 비교
CREATE TABLE mart.diag_activity_window_stability AS
SELECT
    window_weeks,
    activity_rule,
    value_basis,
    value_cutoff,
    COUNT(DISTINCT reference_week)::BIGINT AS reference_week_count,
    AVG(activity_decline_share_of_eligible) AS average_activity_decline_share,
    MIN(activity_decline_share_of_eligible) AS minimum_activity_decline_share,
    MAX(activity_decline_share_of_eligible) AS maximum_activity_decline_share,
    STDDEV_SAMP(activity_decline_share_of_eligible) AS stddev_activity_decline_share,
    AVG(high_value_activity_decline_share_of_high_value) AS average_high_value_decline_share,
    MIN(high_value_activity_decline_share_of_high_value) AS minimum_high_value_decline_share,
    MAX(high_value_activity_decline_share_of_high_value) AS maximum_high_value_decline_share,
    STDDEV_SAMP(high_value_activity_decline_share_of_high_value) AS stddev_high_value_decline_share
FROM mart.diag_activity_window_threshold_sensitivity
WHERE aggregation_level = 'REFERENCE_WEEK'
GROUP BY
    window_weeks,
    activity_rule,
    value_basis,
    value_cutoff;

-- 05B-08. 기간 간 고객 분류 일치도
CREATE TABLE mart.diag_activity_window_agreement AS
WITH rule_flags AS (
    SELECT
        comparison.household_key,
        comparison.reference_week,
        comparison.window_weeks,
        rule.activity_rule,
        rule.eligible,
        rule.decline
    FROM mart.activity_window_comparison AS comparison
    CROSS JOIN LATERAL (
        VALUES
            (
                'BECAME_INACTIVE_ONLY',
                comparison.prior_valid_basket_count > 0,
                comparison.activity_transition = 'BECAME_INACTIVE'
            ),
            (
                'INACTIVE_OR_SALES_RATE_LE_30',
                comparison.prior_valid_basket_count > 0,
                comparison.activity_transition = 'BECAME_INACTIVE'
                    OR (
                        comparison.activity_transition = 'ACTIVE_BOTH_WINDOWS'
                        AND comparison.sales_change_denominator_status = 'COMPARABLE'
                        AND comparison.sales_change_rate <= -0.30
                    )
            ),
            (
                'INACTIVE_OR_BOTH_RATE_LE_30',
                comparison.prior_valid_basket_count > 0,
                comparison.activity_transition = 'BECAME_INACTIVE'
                    OR (
                        comparison.activity_transition = 'ACTIVE_BOTH_WINDOWS'
                        AND comparison.basket_change_denominator_status = 'COMPARABLE'
                        AND comparison.sales_change_denominator_status = 'COMPARABLE'
                        AND comparison.basket_count_change_rate <= -0.30
                        AND comparison.sales_change_rate <= -0.30
                    )
            ),
            (
                'INACTIVE_OR_BOTH_RATE_LE_50',
                comparison.prior_valid_basket_count > 0,
                comparison.activity_transition = 'BECAME_INACTIVE'
                    OR (
                        comparison.activity_transition = 'ACTIVE_BOTH_WINDOWS'
                        AND comparison.basket_change_denominator_status = 'COMPARABLE'
                        AND comparison.sales_change_denominator_status = 'COMPARABLE'
                        AND comparison.basket_count_change_rate <= -0.50
                        AND comparison.sales_change_rate <= -0.50
                    )
            )
    ) AS rule(activity_rule, eligible, decline)
    WHERE comparison.is_common_comparison_row
),

window_pairs(first_window_weeks, second_window_weeks) AS (
    VALUES
        (4, 6),
        (4, 8),
        (6, 8)
),

paired AS (
    SELECT
        first_flags.activity_rule,
        pair.first_window_weeks,
        pair.second_window_weeks,
        first_flags.eligible AS first_eligible,
        second_flags.eligible AS second_eligible,
        first_flags.decline AS first_decline,
        second_flags.decline AS second_decline
    FROM window_pairs AS pair
    JOIN rule_flags AS first_flags
        ON first_flags.window_weeks = pair.first_window_weeks
    JOIN rule_flags AS second_flags
        ON second_flags.household_key = first_flags.household_key
       AND second_flags.reference_week = first_flags.reference_week
       AND second_flags.activity_rule = first_flags.activity_rule
       AND second_flags.window_weeks = pair.second_window_weeks
),

summary AS (
    SELECT
        first_window_weeks,
        second_window_weeks,
        activity_rule,
        COUNT(*) FILTER (
            WHERE first_eligible AND second_eligible
        )::BIGINT AS eligible_both,
        COUNT(*) FILTER (
            WHERE first_eligible AND second_eligible AND first_decline
        )::BIGINT AS first_count,
        COUNT(*) FILTER (
            WHERE first_eligible AND second_eligible AND second_decline
        )::BIGINT AS second_count,
        COUNT(*) FILTER (
            WHERE first_eligible AND second_eligible AND first_decline AND second_decline
        )::BIGINT AS both_count
    FROM paired
    GROUP BY
        first_window_weeks,
        second_window_weeks,
        activity_rule
)
SELECT
    first_window_weeks,
    second_window_weeks,
    activity_rule,
    eligible_both AS eligible_in_both_count,
    first_count AS flagged_in_first_count,
    second_count AS flagged_in_second_count,
    both_count AS flagged_in_both_count,
    first_count - both_count AS flagged_only_in_first_count,
    second_count - both_count AS flagged_only_in_second_count,
    both_count::NUMERIC / NULLIF(first_count + second_count - both_count, 0) AS jaccard_similarity
FROM summary;

ANALYZE mart.diag_activity_window_overview;
ANALYZE mart.diag_activity_window_metric_profile;
ANALYZE mart.diag_activity_window_stability;
ANALYZE mart.diag_activity_window_agreement;

COMMIT;

-- 05B-09. 정합성 검증
DROP TABLE IF EXISTS pg_temp.activity_window_validation;
CREATE TEMP TABLE activity_window_validation AS
WITH source_counts AS (
    SELECT
        (SELECT COUNT(*)::BIGINT FROM mart.household_reference_week) AS reference_count,
        (SELECT COUNT(*)::BIGINT FROM mart.fact_household_week) AS weekly_count,
        (SELECT COUNT(*)::BIGINT FROM mart.activity_window_comparison) AS comparison_count
),

comparison_summary AS (
    SELECT
        COUNT(*) FILTER (
            WHERE household_key IS NULL OR reference_week IS NULL OR window_weeks IS NULL
        )::BIGINT AS null_keys,
        (COUNT(*) - COUNT(DISTINCT (household_key, reference_week, window_weeks)))::BIGINT AS duplicate_keys,
        COUNT(*) FILTER (WHERE window_weeks NOT IN (4, 6, 8))::BIGINT AS invalid_windows,
        COUNT(*) FILTER (WHERE prior_start_week <> reference_week - (2 * window_weeks) + 1
            OR prior_end_week <> reference_week - window_weeks
            OR recent_start_week <> reference_week - window_weeks + 1
            OR recent_end_week <> reference_week
            OR future4_start_week <> reference_week + 1
            OR future4_end_week <> reference_week + 4)::BIGINT AS boundary_issues,
        COUNT(*) FILTER (
            WHERE prior_end_week > reference_week OR recent_end_week > reference_week
        )::BIGINT AS leakage_issues,
        COUNT(*) FILTER (WHERE (prior_valid_basket_count > 0
            AND (basket_change_denominator_status <> 'COMPARABLE'
            OR basket_count_change_rate IS DISTINCT FROM recent_valid_basket_count::NUMERIC / prior_valid_basket_count - 1))
            OR (prior_valid_basket_count = 0
            AND (basket_count_change_rate IS NOT NULL
            OR basket_change_denominator_status <> CASE WHEN recent_valid_basket_count > 0 THEN 'FROM_ZERO' ELSE 'BOTH_ZERO' END))
            OR (prior_sales > 0
            AND (sales_change_denominator_status <> 'COMPARABLE'
            OR sales_change_rate IS DISTINCT FROM recent_sales / prior_sales - 1))
            OR (prior_sales = 0
            AND (sales_change_rate IS NOT NULL
            OR sales_change_denominator_status <> CASE WHEN recent_sales > 0 THEN 'FROM_ZERO' ELSE 'BOTH_ZERO' END)))::BIGINT AS denominator_issues,
        COUNT(*) FILTER (
            WHERE activity_transition <> CASE WHEN prior_valid_basket_count = 0
                AND recent_valid_basket_count = 0 THEN 'NO_ACTIVITY_BOTH_WINDOWS' WHEN prior_valid_basket_count = 0 THEN 'REACTIVATED' WHEN recent_valid_basket_count = 0 THEN 'BECAME_INACTIVE' ELSE 'ACTIVE_BOTH_WINDOWS' END
        )::BIGINT AS transition_issues,
        COUNT(*) FILTER (WHERE has_any_activity_decline_raw IS DISTINCT FROM (activity_transition = 'ACTIVE_BOTH_WINDOWS'
            AND (basket_count_change < 0
            OR sales_change < 0))
            OR has_both_frequency_and_sales_decline_raw IS DISTINCT FROM (activity_transition = 'ACTIVE_BOTH_WINDOWS'
            AND basket_count_change < 0
            AND sales_change < 0))::BIGINT AS flag_issues,
        COUNT(*) FILTER (WHERE future4_has_purchase IS NULL
            OR future4_no_purchase IS NULL
            OR future4_has_purchase = future4_no_purchase
            OR future4_has_purchase IS DISTINCT FROM (future4_valid_basket_count > 0)
            OR future4_no_purchase IS DISTINCT FROM (future4_valid_basket_count = 0))::BIGINT AS label_issues
    FROM mart.activity_window_comparison
),

future_consistency AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM (SELECT household_key, reference_week FROM mart.activity_window_comparison GROUP BY household_key, reference_week HAVING COUNT(DISTINCT (future4_valid_basket_count, future4_has_purchase, future4_no_purchase)) <> 1) invalid
),

four_week_reconciliation AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.activity_window_comparison comparison
    JOIN mart.household_reference_week existing USING (household_key, reference_week)
    WHERE comparison.window_weeks = 4
        AND (comparison.prior_valid_basket_count IS DISTINCT FROM existing.prior4_valid_basket_count
        OR comparison.recent_valid_basket_count IS DISTINCT FROM existing.recent4_valid_basket_count
        OR comparison.prior_sales IS DISTINCT FROM existing.prior4_sales
        OR comparison.recent_sales IS DISTINCT FROM existing.recent4_sales
        OR comparison.basket_count_change IS DISTINCT FROM existing.basket_count_change
        OR comparison.sales_change IS DISTINCT FROM existing.sales_change
        OR comparison.basket_count_change_rate IS DISTINCT FROM existing.basket_count_change_rate
        OR comparison.sales_change_rate IS DISTINCT FROM existing.sales_change_rate
        OR comparison.basket_change_denominator_status IS DISTINCT FROM existing.basket_change_denominator_status
        OR comparison.sales_change_denominator_status IS DISTINCT FROM existing.sales_change_denominator_status
        OR comparison.activity_transition IS DISTINCT FROM CASE existing.activity_transition_base WHEN 'NO_ACTIVITY_8W' THEN 'NO_ACTIVITY_BOTH_WINDOWS' WHEN 'ACTIVE_BOTH_4W' THEN 'ACTIVE_BOTH_WINDOWS' ELSE existing.activity_transition_base END
        OR comparison.has_any_activity_decline_raw IS DISTINCT FROM existing.has_any_activity_decline_raw
        OR comparison.has_both_frequency_and_sales_decline_raw IS DISTINCT FROM existing.has_both_frequency_and_sales_decline_raw)
),

rfm_reconciliation AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.activity_window_comparison comparison
    JOIN mart.household_reference_week existing USING (household_key, reference_week)
    WHERE comparison.has_purchase_26w IS DISTINCT FROM existing.has_purchase_26w
        OR comparison.recency_weeks_26w IS DISTINCT FROM existing.recency_weeks_26w
        OR comparison.recency_days_26w IS DISTINCT FROM existing.recency_days_26w
        OR comparison.frequency_26w IS DISTINCT FROM existing.frequency_26w
        OR comparison.monetary_26w IS DISTINCT FROM existing.monetary_26w
        OR comparison.fm_value_index_26w IS DISTINCT FROM existing.fm_value_index_26w
        OR comparison.rfm_value_index_26w IS DISTINCT FROM existing.rfm_value_index_26w
),

common_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM (SELECT household_key, reference_week FROM mart.activity_window_comparison GROUP BY household_key, reference_week HAVING BOOL_OR(is_common_comparison_row) IS DISTINCT FROM BOOL_AND(has_pre_window_snapshot)
        OR (BOOL_OR(is_common_comparison_row)
        AND (COUNT(*) <> 3
        OR COUNT(DISTINCT window_weeks) <> 3))) invalid
),

diagnostic_issues AS (
    SELECT
        COUNT(*) FILTER (
            WHERE no_activity_share NOT BETWEEN 0
                AND 1
                OR reactivated_share NOT BETWEEN 0
                AND 1
                OR became_inactive_share NOT BETWEEN 0
                AND 1
                OR active_both_share NOT BETWEEN 0
                AND 1
                OR any_activity_decline_raw_share NOT BETWEEN 0
                AND 1
                OR both_activity_decline_raw_share NOT BETWEEN 0
                AND 1
        )::BIGINT AS overview_issues,
        (SELECT COUNT(*) FROM mart.diag_activity_window_threshold_sensitivity WHERE (activity_decline_share_of_eligible IS NOT NULL
            AND activity_decline_share_of_eligible NOT BETWEEN 0
            AND 1)
            OR (high_value_share IS NOT NULL
            AND high_value_share NOT BETWEEN 0
            AND 1)
            OR (high_value_activity_decline_share_of_high_value IS NOT NULL
            AND high_value_activity_decline_share_of_high_value NOT BETWEEN 0
            AND 1)
            OR (high_value_activity_decline_share_of_all IS NOT NULL
            AND high_value_activity_decline_share_of_all NOT BETWEEN 0
            AND 1))::BIGINT AS threshold_issues
    FROM mart.diag_activity_window_overview
),

checks AS (
    SELECT
        'source_nonempty'::TEXT check_name,
        'FAIL'::TEXT severity,
        CASE WHEN reference_count>0 AND weekly_count>0 THEN 0 ELSE 1 END::BIGINT issue_count,
        '기존 원천 비어 있음 여부'::TEXT detail
    FROM source_counts
    UNION ALL

    SELECT
        'expected_row_count',
        'FAIL',
        ABS(comparison_count-reference_count*3),
        '원천 행 수 × 3'
    FROM source_counts
    UNION ALL

    SELECT
        'primary_key_integrity',
        'FAIL',
        null_keys+duplicate_keys,
        '복합키 NULL·중복'
    FROM comparison_summary
    UNION ALL

    SELECT 'window_value_integrity','FAIL',invalid_windows,'기간 후보 허용값' FROM comparison_summary
    UNION ALL

    SELECT
        'window_boundary_integrity',
        'FAIL',
        boundary_issues,
        '기간 경계 일반식'
    FROM comparison_summary
    UNION ALL

    SELECT 'future_leakage','FAIL',leakage_issues,'과거 활동기간 종료' FROM comparison_summary
    UNION ALL

    SELECT
        'denominator_integrity',
        'FAIL',
        denominator_issues,
        '장바구니·매출 변화율 분모'
    FROM comparison_summary
    UNION ALL

    SELECT
        'activity_transition_integrity',
        'FAIL',
        transition_issues,
        '활동전이 상태'
    FROM comparison_summary
    UNION ALL

    SELECT 'raw_decline_flag_integrity','FAIL',flag_issues,'원시 감소 플래그' FROM comparison_summary
    UNION ALL

    SELECT 'future4_label_integrity','FAIL',label_issues,'목표 라벨' FROM comparison_summary
    UNION ALL

    SELECT
        'future4_same_across_windows',
        'FAIL',
        issue_count,
        '기간별 목표 라벨 동일성'
    FROM future_consistency
    UNION ALL

    SELECT
        'existing_4week_reconciliation',
        'FAIL',
        issue_count,
        '기존 4주 대사'
    FROM four_week_reconciliation
    UNION ALL

    SELECT 'current_rfm_reconciliation','FAIL',issue_count,'현재 RFM 대사' FROM rfm_reconciliation
    UNION ALL

    SELECT 'common_comparison_integrity','FAIL',issue_count,'과거 스냅샷 기반 공통행' FROM common_issues
    UNION ALL

    SELECT
        'diagnostic_share_integrity',
        'FAIL',
        overview_issues+threshold_issues,
        '진단 비율 범위'
    FROM diagnostic_issues
    UNION ALL

    SELECT
        'threshold_rule_coverage',
        'FAIL',
        CASE WHEN COUNT(*) FILTER(WHERE aggregation_level='ALL')=12 AND COUNT(DISTINCT window_weeks)=3 AND COUNT(DISTINCT activity_rule)=4 AND COUNT(DISTINCT value_basis)=1 AND COUNT(DISTINCT value_cutoff)=1 THEN 0 ELSE 1 END,
        '3×4×1×1 조합'
    FROM mart.diag_activity_window_threshold_sensitivity
    UNION ALL

    SELECT
        'stability_nonempty',
        'FAIL',
        CASE WHEN COUNT(*)>0 THEN 0 ELSE 1 END,
        '안정성 행 존재'
    FROM mart.diag_activity_window_stability
    UNION ALL

    SELECT
        'agreement_pair_integrity',
        'FAIL',
        COUNT(*) FILTER(WHERE jaccard_similarity IS NOT NULL AND jaccard_similarity NOT BETWEEN 0 AND 1)+CASE WHEN COUNT(*)=12 AND COUNT(DISTINCT(first_window_weeks,second_window_weeks))=3 AND COUNT(DISTINCT activity_rule)=4 THEN 0 ELSE 1 END,
        '3개 기간쌍·4개 규칙'
    FROM mart.diag_activity_window_agreement
)
SELECT
    check_name,
    severity,
    issue_count,
    detail,
    CASE WHEN issue_count=0 THEN 'PASS' WHEN severity='WARN' THEN 'WARN' ELSE 'FAIL' END status
FROM checks
UNION ALL
SELECT
    'validation_fail_summary',
    'FAIL',
    COALESCE(SUM(issue_count) FILTER(WHERE issue_count>0),0),
    format('FAIL checks=%s, FAIL issue_count sum=%s',COUNT(*) FILTER(WHERE issue_count>0),COALESCE(SUM(issue_count) FILTER(WHERE issue_count>0),0)),
    CASE WHEN COUNT(*) FILTER(WHERE issue_count>0)=0 THEN 'PASS' ELSE 'FAIL' END
FROM checks
ORDER BY check_name;

-- 05B-10. 결과 확인
-- 05B-10-01. 기간별 전체 개요
SELECT
    window_weeks,
    source_row_count,
    distinct_household_count,
    reference_week_count,
    min_reference_week,
    max_reference_week,
    no_activity_count,
    no_activity_share,
    reactivated_count,
    reactivated_share,
    became_inactive_count,
    became_inactive_share,
    active_both_count,
    active_both_share,
    any_activity_decline_raw_count,
    any_activity_decline_raw_share,
    both_activity_decline_raw_count,
    both_activity_decline_raw_share
FROM mart.diag_activity_window_overview
ORDER BY window_weeks;

-- 05B-10-02. 구매횟수·구매금액 변화율 분포
SELECT
    window_weeks,
    metric_name,
    eligible_row_count,
    negative_count,
    percentile_25,
    percentile_50,
    percentile_75,
    mean_value,
    stddev_value
FROM mart.diag_activity_window_metric_profile
WHERE metric_name IN ('basket_count_change_rate','sales_change_rate')
ORDER BY
    window_weeks,
    metric_name;

-- 05B-10-03. 임계값별 전체 비교
SELECT
    aggregation_level,
    reference_week,
    window_weeks,
    activity_rule,
    value_basis,
    value_cutoff,
    total_row_count,
    eligible_row_count,
    activity_decline_count,
    activity_decline_share_of_eligible,
    high_value_count,
    high_value_share,
    high_value_activity_decline_count,
    high_value_activity_decline_share_of_high_value,
    high_value_activity_decline_share_of_all,
    average_value_index_of_high_value_decline,
    average_frequency_26w_of_high_value_decline,
    average_monetary_26w_of_high_value_decline
FROM mart.diag_activity_window_threshold_sensitivity
WHERE aggregation_level='ALL'
ORDER BY
    value_basis,
    activity_rule,
    value_cutoff,
    window_weeks;

-- 05B-10-04. 핵심 후보 간단 비교
SELECT
    window_weeks,
    activity_rule,
    eligible_row_count,
    activity_decline_count,
    activity_decline_share_of_eligible,
    high_value_count,
    high_value_activity_decline_count,
    high_value_activity_decline_share_of_high_value,
    high_value_activity_decline_share_of_all,
    average_value_index_of_high_value_decline,
    average_frequency_26w_of_high_value_decline,
    average_monetary_26w_of_high_value_decline
FROM mart.diag_activity_window_threshold_sensitivity
WHERE aggregation_level='ALL'
  AND value_basis='PRE_WINDOW_RFM'
  AND value_cutoff=0.80::NUMERIC
  AND activity_rule IN (
        'BECAME_INACTIVE_ONLY',
        'INACTIVE_OR_SALES_RATE_LE_30',
        'INACTIVE_OR_BOTH_RATE_LE_30',
        'INACTIVE_OR_BOTH_RATE_LE_50'
    )
ORDER BY
    window_weeks,
    activity_rule;

-- 05B-10-05. 기준주차별 안정성
SELECT
    window_weeks,
    activity_rule,
    average_activity_decline_share,
    minimum_activity_decline_share,
    maximum_activity_decline_share,
    stddev_activity_decline_share,
    average_high_value_decline_share,
    minimum_high_value_decline_share,
    maximum_high_value_decline_share,
    stddev_high_value_decline_share
FROM mart.diag_activity_window_stability
WHERE value_basis='PRE_WINDOW_RFM'
  AND value_cutoff=0.80::NUMERIC
  AND activity_rule IN (
        'INACTIVE_OR_SALES_RATE_LE_30',
        'INACTIVE_OR_BOTH_RATE_LE_30',
        'INACTIVE_OR_BOTH_RATE_LE_50'
    )
ORDER BY
    window_weeks,
    activity_rule;

-- 05B-10-06. 기간 간 분류 일치도
SELECT
    first_window_weeks,
    second_window_weeks,
    activity_rule,
    eligible_in_both_count,
    flagged_in_first_count,
    flagged_in_second_count,
    flagged_in_both_count,
    flagged_only_in_first_count,
    flagged_only_in_second_count,
    jaccard_similarity
FROM mart.diag_activity_window_agreement
ORDER BY
    activity_rule,
    first_window_weeks,
    second_window_weeks;

-- 05B-10-07. 정합성 검증 결과
SELECT
    check_name,
    severity,
    issue_count,
    detail,
    status
FROM activity_window_validation
ORDER BY check_name;

-- ==================================================
-- 06. 가구 × 기준주차 가치·활동상태 확정
-- ==================================================

BEGIN;

DROP TABLE IF EXISTS mart.diag_customer_value_state_shift;
DROP TABLE IF EXISTS mart.diag_customer_state_stability;
DROP TABLE IF EXISTS mart.diag_customer_state_by_week;
DROP TABLE IF EXISTS mart.diag_customer_state_overview;
DROP TABLE IF EXISTS mart.customer_state;

-- 06-01. 상태 기준 및 임계값 설정
-- 06-02. 최근 4주 활동정보와 활동감소 이전 구매가치 결합
-- 06-03. 구매가치 상태 정의
-- 06-04. 활동상태 정의
-- 06-05. 최종 고객상태 생성
CREATE TABLE mart.customer_state AS
WITH parameters AS (
    SELECT
        4::INTEGER AS activity_window_weeks,
        'PRE_WINDOW_RFM'::TEXT AS value_basis,
        0.80::NUMERIC AS value_cutoff_used,
        -0.30::NUMERIC AS moderate_decline_cutoff_used,
        -0.50::NUMERIC AS strong_decline_cutoff_used
),

source_with_pre_window AS (
    SELECT
        current_value.household_key,
        current_value.reference_week,
        parameters.activity_window_weeks,
        parameters.value_basis,
        parameters.value_cutoff_used,
        parameters.moderate_decline_cutoff_used,
        parameters.strong_decline_cutoff_used,
        current_value.has_purchase_26w AS current_has_purchase_26w,
        current_value.recency_weeks_26w AS current_recency_weeks_26w,
        current_value.recency_days_26w AS current_recency_days_26w,
        current_value.frequency_26w AS current_frequency_26w,
        current_value.monetary_26w AS current_monetary_26w,
        current_value.fm_value_index_26w AS current_fm_value_index_26w,
        current_value.rfm_value_index_26w AS current_rfm_value_index_26w,
        prior_value.household_key IS NOT NULL AS pre_window_has_snapshot,
        prior_value.has_purchase_26w AS pre_window_has_purchase_26w,
        prior_value.recency_weeks_26w AS pre_window_recency_weeks_26w,
        prior_value.recency_days_26w AS pre_window_recency_days_26w,
        prior_value.frequency_26w AS pre_window_frequency_26w,
        prior_value.monetary_26w AS pre_window_monetary_26w,
        prior_value.fm_value_index_26w AS pre_window_fm_value_index_26w,
        prior_value.rfm_value_index_26w AS pre_window_rfm_value_index_26w,
        current_value.prior4_valid_basket_count,
        current_value.recent4_valid_basket_count,
        current_value.prior4_sales,
        current_value.recent4_sales,
        current_value.basket_count_change,
        current_value.sales_change,
        current_value.basket_count_change_rate,
        current_value.sales_change_rate,
        current_value.basket_change_denominator_status,
        current_value.sales_change_denominator_status,
        current_value.activity_transition_base
    FROM mart.household_reference_week AS current_value
    CROSS JOIN parameters
    LEFT JOIN mart.household_reference_week AS prior_value
        ON prior_value.household_key = current_value.household_key
       AND prior_value.reference_week = current_value.reference_week - parameters.activity_window_weeks
),

value_states AS (
    SELECT
        source_with_pre_window.*,
        CASE
            WHEN NOT pre_window_has_snapshot THEN 'NO_PRE_WINDOW_SNAPSHOT'
            WHEN NOT pre_window_has_purchase_26w
              OR pre_window_rfm_value_index_26w IS NULL
            THEN 'NO_RECENT_VALUE_HISTORY'
            WHEN pre_window_rfm_value_index_26w >= value_cutoff_used THEN 'HIGH_VALUE'
            ELSE 'OTHER_VALUE'
        END AS value_state,
        CASE
            WHEN NOT current_has_purchase_26w
              OR current_rfm_value_index_26w IS NULL
            THEN 'NO_CURRENT_PURCHASE_26W'
            WHEN current_rfm_value_index_26w >= value_cutoff_used THEN 'CURRENT_HIGH_VALUE'
            ELSE 'CURRENT_OTHER_VALUE'
        END AS current_value_state
    FROM source_with_pre_window
),

activity_states AS (
    SELECT
        value_states.*,
        CASE activity_transition_base
            WHEN 'NO_ACTIVITY_8W' THEN 'NO_ACTIVITY_BOTH_WINDOWS'
            WHEN 'ACTIVE_BOTH_4W' THEN 'ACTIVE_BOTH_WINDOWS'
            ELSE activity_transition_base
        END AS activity_transition,
        CASE
            WHEN prior4_valid_basket_count = 0
             AND recent4_valid_basket_count = 0
            THEN 'NO_ACTIVITY_BOTH_WINDOWS'
            WHEN prior4_valid_basket_count = 0 THEN 'REACTIVATED'
            WHEN recent4_valid_basket_count = 0 THEN 'BECAME_INACTIVE'
            WHEN basket_change_denominator_status = 'COMPARABLE'
             AND sales_change_denominator_status = 'COMPARABLE'
             AND basket_count_change_rate <= strong_decline_cutoff_used
             AND sales_change_rate <= strong_decline_cutoff_used
            THEN 'ACTIVE_BOTH_VERY_STRONG_DECLINE'
            WHEN basket_change_denominator_status = 'COMPARABLE'
             AND sales_change_denominator_status = 'COMPARABLE'
             AND basket_count_change_rate <= moderate_decline_cutoff_used
             AND sales_change_rate <= moderate_decline_cutoff_used
            THEN 'ACTIVE_BOTH_STRONG_DECLINE'
            WHEN sales_change_denominator_status = 'COMPARABLE'
             AND sales_change_rate <= moderate_decline_cutoff_used
            THEN 'ACTIVE_BOTH_SALES_DECLINE'
            ELSE 'ACTIVE_BOTH_NO_MAJOR_DECLINE'
        END AS activity_state
    FROM value_states
),

candidate_flags AS (
    SELECT
        activity_states.*,
        activity_state = 'BECAME_INACTIVE' AS is_became_inactive,
        activity_state IN (
            'ACTIVE_BOTH_VERY_STRONG_DECLINE',
            'ACTIVE_BOTH_STRONG_DECLINE',
            'ACTIVE_BOTH_SALES_DECLINE'
        ) AS is_sales_decline_30,
        activity_state IN (
            'ACTIVE_BOTH_VERY_STRONG_DECLINE',
            'ACTIVE_BOTH_STRONG_DECLINE'
        ) AS is_both_decline_30,
        activity_state = 'ACTIVE_BOTH_VERY_STRONG_DECLINE' AS is_both_decline_50,
        activity_state IN (
            'BECAME_INACTIVE',
            'ACTIVE_BOTH_VERY_STRONG_DECLINE',
            'ACTIVE_BOTH_STRONG_DECLINE',
            'ACTIVE_BOTH_SALES_DECLINE'
        ) AS is_broad_activity_decline_candidate,
        activity_state IN (
            'BECAME_INACTIVE',
            'ACTIVE_BOTH_VERY_STRONG_DECLINE',
            'ACTIVE_BOTH_STRONG_DECLINE'
        ) AS is_strong_activity_decline_candidate
    FROM activity_states
),

final_states AS (
    SELECT
        candidate_flags.*,
        CASE
            WHEN value_state IN (
                'NO_PRE_WINDOW_SNAPSHOT',
                'NO_RECENT_VALUE_HISTORY'
            ) THEN 'INSUFFICIENT_VALUE_HISTORY'
            WHEN value_state = 'HIGH_VALUE'
             AND activity_state = 'NO_ACTIVITY_BOTH_WINDOWS'
            THEN 'HIGH_VALUE_LONG_INACTIVE'
            WHEN value_state = 'HIGH_VALUE'
             AND activity_state = 'REACTIVATED'
            THEN 'HIGH_VALUE_REACTIVATED'
            WHEN value_state = 'HIGH_VALUE'
             AND activity_state = 'BECAME_INACTIVE'
            THEN 'HIGH_VALUE_BECAME_INACTIVE'
            WHEN value_state = 'HIGH_VALUE'
             AND activity_state = 'ACTIVE_BOTH_VERY_STRONG_DECLINE'
            THEN 'HIGH_VALUE_VERY_STRONG_DECLINE'
            WHEN value_state = 'HIGH_VALUE'
             AND activity_state = 'ACTIVE_BOTH_STRONG_DECLINE'
            THEN 'HIGH_VALUE_STRONG_DECLINE'
            WHEN value_state = 'HIGH_VALUE'
             AND activity_state = 'ACTIVE_BOTH_SALES_DECLINE'
            THEN 'HIGH_VALUE_SALES_DECLINE'
            WHEN value_state = 'HIGH_VALUE' THEN 'HIGH_VALUE_ACTIVE'
            WHEN activity_state = 'NO_ACTIVITY_BOTH_WINDOWS' THEN 'OTHER_VALUE_LONG_INACTIVE'
            WHEN activity_state = 'REACTIVATED' THEN 'OTHER_VALUE_REACTIVATED'
            WHEN activity_state = 'BECAME_INACTIVE' THEN 'OTHER_VALUE_BECAME_INACTIVE'
            WHEN activity_state = 'ACTIVE_BOTH_VERY_STRONG_DECLINE'
            THEN 'OTHER_VALUE_VERY_STRONG_DECLINE'
            WHEN activity_state = 'ACTIVE_BOTH_STRONG_DECLINE'
            THEN 'OTHER_VALUE_STRONG_DECLINE'
            WHEN activity_state = 'ACTIVE_BOTH_SALES_DECLINE'
            THEN 'OTHER_VALUE_SALES_DECLINE'
            ELSE 'OTHER_VALUE_ACTIVE'
        END AS customer_state
    FROM candidate_flags
)
SELECT
    household_key,
    reference_week,
    activity_window_weeks,
    value_basis,
    value_cutoff_used,
    moderate_decline_cutoff_used,
    strong_decline_cutoff_used,
    current_has_purchase_26w,
    current_recency_weeks_26w,
    current_recency_days_26w,
    current_frequency_26w,
    current_monetary_26w,
    current_fm_value_index_26w,
    current_rfm_value_index_26w,
    current_value_state,
    pre_window_has_snapshot,
    pre_window_has_purchase_26w,
    pre_window_recency_weeks_26w,
    pre_window_recency_days_26w,
    pre_window_frequency_26w,
    pre_window_monetary_26w,
    pre_window_fm_value_index_26w,
    pre_window_rfm_value_index_26w,
    value_state,
    prior4_valid_basket_count,
    recent4_valid_basket_count,
    prior4_sales,
    recent4_sales,
    basket_count_change,
    sales_change,
    basket_count_change_rate,
    sales_change_rate,
    basket_change_denominator_status,
    sales_change_denominator_status,
    activity_transition,
    activity_state,
    is_became_inactive,
    is_sales_decline_30,
    is_both_decline_30,
    is_both_decline_50,
    is_broad_activity_decline_candidate,
    is_strong_activity_decline_candidate,
    customer_state,
    value_state = 'HIGH_VALUE'
        AND is_broad_activity_decline_candidate AS is_high_value_activity_decline_candidate,
    value_state = 'HIGH_VALUE'
        AND is_strong_activity_decline_candidate AS is_high_value_strong_decline_candidate,
    value_state = 'HIGH_VALUE'
        AND activity_state = 'BECAME_INACTIVE' AS is_high_value_became_inactive_candidate
FROM final_states;

ALTER TABLE mart.customer_state
    ADD CONSTRAINT pk_customer_state
    PRIMARY KEY (
        household_key,
        reference_week
    );

ALTER TABLE mart.customer_state
    ADD CONSTRAINT chk_customer_state_window
    CHECK (activity_window_weeks = 4),
    ADD CONSTRAINT chk_customer_state_value_cutoff
    CHECK (value_cutoff_used = 0.80),
    ADD CONSTRAINT chk_customer_state_moderate_cutoff
    CHECK (moderate_decline_cutoff_used = -0.30),
    ADD CONSTRAINT chk_customer_state_strong_cutoff
    CHECK (strong_decline_cutoff_used = -0.50),
    ADD CONSTRAINT chk_customer_state_value_state
    CHECK (value_state IN (
        'NO_PRE_WINDOW_SNAPSHOT',
        'NO_RECENT_VALUE_HISTORY',
        'HIGH_VALUE',
        'OTHER_VALUE'
    )),
    ADD CONSTRAINT chk_customer_state_current_value_state
    CHECK (current_value_state IN (
        'NO_CURRENT_PURCHASE_26W',
        'CURRENT_HIGH_VALUE',
        'CURRENT_OTHER_VALUE'
    )),
    ADD CONSTRAINT chk_customer_state_activity_state
    CHECK (activity_state IN (
        'NO_ACTIVITY_BOTH_WINDOWS',
        'REACTIVATED',
        'BECAME_INACTIVE',
        'ACTIVE_BOTH_VERY_STRONG_DECLINE',
        'ACTIVE_BOTH_STRONG_DECLINE',
        'ACTIVE_BOTH_SALES_DECLINE',
        'ACTIVE_BOTH_NO_MAJOR_DECLINE'
    )),
    ADD CONSTRAINT chk_customer_state_final_state
    CHECK (customer_state IN (
        'INSUFFICIENT_VALUE_HISTORY',
        'HIGH_VALUE_LONG_INACTIVE',
        'HIGH_VALUE_REACTIVATED',
        'HIGH_VALUE_BECAME_INACTIVE',
        'HIGH_VALUE_VERY_STRONG_DECLINE',
        'HIGH_VALUE_STRONG_DECLINE',
        'HIGH_VALUE_SALES_DECLINE',
        'HIGH_VALUE_ACTIVE',
        'OTHER_VALUE_LONG_INACTIVE',
        'OTHER_VALUE_REACTIVATED',
        'OTHER_VALUE_BECAME_INACTIVE',
        'OTHER_VALUE_VERY_STRONG_DECLINE',
        'OTHER_VALUE_STRONG_DECLINE',
        'OTHER_VALUE_SALES_DECLINE',
        'OTHER_VALUE_ACTIVE'
    ));

CREATE INDEX idx_customer_state_reference_state
    ON mart.customer_state (
        reference_week,
        customer_state
    );

CREATE INDEX idx_customer_state_reference_value_activity
    ON mart.customer_state (
        reference_week,
        value_state,
        activity_state
    );

ANALYZE mart.customer_state;

-- 06-06. 상태 분포 진단
CREATE TABLE mart.diag_customer_state_overview AS
WITH long_states AS (
    SELECT
        customer.household_key,
        customer.reference_week,
        dimension_data.dimension_type,
        dimension_data.dimension_value
    FROM mart.customer_state AS customer
    CROSS JOIN LATERAL (
        VALUES
            ('VALUE_STATE', customer.value_state),
            ('CURRENT_VALUE_STATE', customer.current_value_state),
            ('ACTIVITY_STATE', customer.activity_state),
            ('CUSTOMER_STATE', customer.customer_state)
    ) AS dimension_data(
        dimension_type,
        dimension_value
    )
),

totals AS (
    SELECT COUNT(*)::BIGINT AS total_row_count
    FROM mart.customer_state
)
SELECT
    long_states.dimension_type,
    long_states.dimension_value,
    COUNT(*)::BIGINT AS state_row_count,
    COUNT(*)::NUMERIC / NULLIF(totals.total_row_count, 0) AS state_share,
    COUNT(DISTINCT long_states.household_key)::BIGINT AS distinct_household_count,
    COUNT(DISTINCT long_states.reference_week)::BIGINT AS reference_week_count,
    MIN(long_states.reference_week) AS min_reference_week,
    MAX(long_states.reference_week) AS max_reference_week
FROM long_states
CROSS JOIN totals
GROUP BY
    long_states.dimension_type,
    long_states.dimension_value,
    totals.total_row_count;

ANALYZE mart.diag_customer_state_overview;

-- 06-07. 기준주차별 상태 안정성 진단
CREATE TABLE mart.diag_customer_state_by_week AS
WITH weekly_totals AS (
    SELECT
        reference_week,
        COUNT(*)::BIGINT AS reference_week_total_count
    FROM mart.customer_state
    GROUP BY reference_week
),

dimension_catalog AS (
    SELECT
        dimension_data.dimension_type,
        dimension_data.dimension_value
    FROM (
        VALUES
            ('VALUE_STATE', 'NO_PRE_WINDOW_SNAPSHOT'),
            ('VALUE_STATE', 'NO_RECENT_VALUE_HISTORY'),
            ('VALUE_STATE', 'HIGH_VALUE'),
            ('VALUE_STATE', 'OTHER_VALUE'),
            ('CURRENT_VALUE_STATE', 'NO_CURRENT_PURCHASE_26W'),
            ('CURRENT_VALUE_STATE', 'CURRENT_HIGH_VALUE'),
            ('CURRENT_VALUE_STATE', 'CURRENT_OTHER_VALUE'),
            ('ACTIVITY_STATE', 'NO_ACTIVITY_BOTH_WINDOWS'),
            ('ACTIVITY_STATE', 'REACTIVATED'),
            ('ACTIVITY_STATE', 'BECAME_INACTIVE'),
            ('ACTIVITY_STATE', 'ACTIVE_BOTH_VERY_STRONG_DECLINE'),
            ('ACTIVITY_STATE', 'ACTIVE_BOTH_STRONG_DECLINE'),
            ('ACTIVITY_STATE', 'ACTIVE_BOTH_SALES_DECLINE'),
            ('ACTIVITY_STATE', 'ACTIVE_BOTH_NO_MAJOR_DECLINE'),
            ('CUSTOMER_STATE', 'INSUFFICIENT_VALUE_HISTORY'),
            ('CUSTOMER_STATE', 'HIGH_VALUE_LONG_INACTIVE'),
            ('CUSTOMER_STATE', 'HIGH_VALUE_REACTIVATED'),
            ('CUSTOMER_STATE', 'HIGH_VALUE_BECAME_INACTIVE'),
            ('CUSTOMER_STATE', 'HIGH_VALUE_VERY_STRONG_DECLINE'),
            ('CUSTOMER_STATE', 'HIGH_VALUE_STRONG_DECLINE'),
            ('CUSTOMER_STATE', 'HIGH_VALUE_SALES_DECLINE'),
            ('CUSTOMER_STATE', 'HIGH_VALUE_ACTIVE'),
            ('CUSTOMER_STATE', 'OTHER_VALUE_LONG_INACTIVE'),
            ('CUSTOMER_STATE', 'OTHER_VALUE_REACTIVATED'),
            ('CUSTOMER_STATE', 'OTHER_VALUE_BECAME_INACTIVE'),
            ('CUSTOMER_STATE', 'OTHER_VALUE_VERY_STRONG_DECLINE'),
            ('CUSTOMER_STATE', 'OTHER_VALUE_STRONG_DECLINE'),
            ('CUSTOMER_STATE', 'OTHER_VALUE_SALES_DECLINE'),
            ('CUSTOMER_STATE', 'OTHER_VALUE_ACTIVE')
    ) AS dimension_data(
        dimension_type,
        dimension_value
    )
),

long_states AS (
    SELECT
        customer.reference_week,
        dimension_data.dimension_type,
        dimension_data.dimension_value
    FROM mart.customer_state AS customer
    CROSS JOIN LATERAL (
        VALUES
            ('VALUE_STATE', customer.value_state),
            ('CURRENT_VALUE_STATE', customer.current_value_state),
            ('ACTIVITY_STATE', customer.activity_state),
            ('CUSTOMER_STATE', customer.customer_state)
    ) AS dimension_data(
        dimension_type,
        dimension_value
    )
),

observed AS (
    SELECT
        reference_week,
        dimension_type,
        dimension_value,
        COUNT(*)::BIGINT AS state_row_count
    FROM long_states
    GROUP BY
        reference_week,
        dimension_type,
        dimension_value
)
SELECT
    weekly_totals.reference_week,
    dimension_catalog.dimension_type,
    dimension_catalog.dimension_value,
    COALESCE(observed.state_row_count, 0)::BIGINT AS state_row_count,
    weekly_totals.reference_week_total_count,
    COALESCE(observed.state_row_count, 0)::NUMERIC
        / NULLIF(weekly_totals.reference_week_total_count, 0) AS state_share_in_week
FROM weekly_totals
CROSS JOIN dimension_catalog
LEFT JOIN observed
    ON observed.reference_week = weekly_totals.reference_week
   AND observed.dimension_type = dimension_catalog.dimension_type
   AND observed.dimension_value = dimension_catalog.dimension_value;

ANALYZE mart.diag_customer_state_by_week;

CREATE TABLE mart.diag_customer_state_stability AS
SELECT
    dimension_type,
    dimension_value,
    COUNT(DISTINCT reference_week)::BIGINT AS reference_week_count,
    AVG(state_share_in_week) AS average_state_share,
    MIN(state_share_in_week) AS minimum_state_share,
    MAX(state_share_in_week) AS maximum_state_share,
    STDDEV_SAMP(state_share_in_week) AS stddev_state_share
FROM mart.diag_customer_state_by_week
GROUP BY
    dimension_type,
    dimension_value;

ANALYZE mart.diag_customer_state_stability;

CREATE TABLE mart.diag_customer_value_state_shift AS
WITH totals AS (
    SELECT COUNT(*)::BIGINT AS total_row_count
    FROM mart.customer_state
)
SELECT
    customer.current_value_state,
    customer.value_state,
    COUNT(*)::BIGINT AS row_count,
    COUNT(*)::NUMERIC / NULLIF(totals.total_row_count, 0) AS share_of_all,
    COUNT(DISTINCT customer.household_key)::BIGINT AS distinct_household_count,
    COUNT(*) FILTER (
        WHERE customer.value_state = 'HIGH_VALUE'
          AND customer.current_value_state <> 'CURRENT_HIGH_VALUE'
    )::BIGINT AS high_pre_window_but_not_current_high_count,
    COUNT(*) FILTER (
        WHERE customer.current_value_state = 'CURRENT_HIGH_VALUE'
          AND customer.value_state <> 'HIGH_VALUE'
    )::BIGINT AS current_high_but_not_pre_window_high_count
FROM mart.customer_state AS customer
CROSS JOIN totals
GROUP BY
    customer.current_value_state,
    customer.value_state,
    totals.total_row_count;

ANALYZE mart.diag_customer_value_state_shift;

COMMIT;

-- 06-08. 정합성 검증
DROP TABLE IF EXISTS pg_temp.customer_state_validation;

CREATE TEMP TABLE customer_state_validation AS
WITH source_counts AS (
    SELECT
        (SELECT COUNT(*)::BIGINT FROM mart.household_reference_week) AS source_count,
        (SELECT COUNT(*)::BIGINT FROM mart.customer_state) AS customer_count
),

customer_summary AS (
    SELECT
        COUNT(*) FILTER (
            WHERE household_key IS NULL
               OR reference_week IS NULL
        )::BIGINT AS null_key_count,
        (COUNT(*) - COUNT(DISTINCT (household_key, reference_week)))::BIGINT AS duplicate_count,
        COUNT(*) FILTER (
            WHERE activity_window_weeks <> 4
        )::BIGINT AS fixed_window_issues,
        COUNT(*) FILTER (
            WHERE value_cutoff_used <> 0.80
               OR moderate_decline_cutoff_used <> -0.30
               OR strong_decline_cutoff_used <> -0.50
        )::BIGINT AS threshold_issues,
        COUNT(*) FILTER (
            WHERE value_state IS NULL
               OR current_value_state IS NULL
               OR activity_state IS NULL
               OR customer_state IS NULL
        )::BIGINT AS null_state_issues,
        COUNT(*) FILTER (
            WHERE is_became_inactive IS DISTINCT FROM (activity_state = 'BECAME_INACTIVE')
               OR is_sales_decline_30 IS DISTINCT FROM (activity_state IN (
                    'ACTIVE_BOTH_VERY_STRONG_DECLINE',
                    'ACTIVE_BOTH_STRONG_DECLINE',
                    'ACTIVE_BOTH_SALES_DECLINE'
                ))
               OR is_both_decline_30 IS DISTINCT FROM (activity_state IN (
                    'ACTIVE_BOTH_VERY_STRONG_DECLINE',
                    'ACTIVE_BOTH_STRONG_DECLINE'
                ))
               OR is_both_decline_50 IS DISTINCT FROM (
                    activity_state = 'ACTIVE_BOTH_VERY_STRONG_DECLINE'
                )
               OR is_broad_activity_decline_candidate IS DISTINCT FROM (activity_state IN (
                    'BECAME_INACTIVE',
                    'ACTIVE_BOTH_VERY_STRONG_DECLINE',
                    'ACTIVE_BOTH_STRONG_DECLINE',
                    'ACTIVE_BOTH_SALES_DECLINE'
                ))
               OR is_strong_activity_decline_candidate IS DISTINCT FROM (activity_state IN (
                    'BECAME_INACTIVE',
                    'ACTIVE_BOTH_VERY_STRONG_DECLINE',
                    'ACTIVE_BOTH_STRONG_DECLINE'
                ))
               OR is_high_value_activity_decline_candidate IS DISTINCT FROM (
                    value_state = 'HIGH_VALUE'
                    AND is_broad_activity_decline_candidate
                )
               OR is_high_value_strong_decline_candidate IS DISTINCT FROM (
                    value_state = 'HIGH_VALUE'
                    AND is_strong_activity_decline_candidate
                )
               OR is_high_value_became_inactive_candidate IS DISTINCT FROM (
                    value_state = 'HIGH_VALUE'
                    AND activity_state = 'BECAME_INACTIVE'
                )
        )::BIGINT AS candidate_flag_issues
    FROM mart.customer_state
),

current_reconciliation AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.customer_state AS customer
    JOIN mart.household_reference_week AS source
        ON source.household_key = customer.household_key
       AND source.reference_week = customer.reference_week
    WHERE customer.current_has_purchase_26w IS DISTINCT FROM source.has_purchase_26w
       OR customer.current_recency_weeks_26w IS DISTINCT FROM source.recency_weeks_26w
       OR customer.current_recency_days_26w IS DISTINCT FROM source.recency_days_26w
       OR customer.current_frequency_26w IS DISTINCT FROM source.frequency_26w
       OR customer.current_monetary_26w IS DISTINCT FROM source.monetary_26w
       OR customer.current_fm_value_index_26w IS DISTINCT FROM source.fm_value_index_26w
       OR customer.current_rfm_value_index_26w IS DISTINCT FROM source.rfm_value_index_26w
),

activity_reconciliation AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.customer_state AS customer
    JOIN mart.household_reference_week AS source
        ON source.household_key = customer.household_key
       AND source.reference_week = customer.reference_week
    WHERE customer.prior4_valid_basket_count IS DISTINCT FROM source.prior4_valid_basket_count
       OR customer.recent4_valid_basket_count IS DISTINCT FROM source.recent4_valid_basket_count
       OR customer.prior4_sales IS DISTINCT FROM source.prior4_sales
       OR customer.recent4_sales IS DISTINCT FROM source.recent4_sales
       OR customer.basket_count_change IS DISTINCT FROM source.basket_count_change
       OR customer.sales_change IS DISTINCT FROM source.sales_change
       OR customer.basket_count_change_rate IS DISTINCT FROM source.basket_count_change_rate
       OR customer.sales_change_rate IS DISTINCT FROM source.sales_change_rate
       OR customer.basket_change_denominator_status IS DISTINCT FROM source.basket_change_denominator_status
       OR customer.sales_change_denominator_status IS DISTINCT FROM source.sales_change_denominator_status
),

comparison_reconciliation AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.customer_state AS customer
    LEFT JOIN mart.activity_window_comparison AS comparison_4w
        ON comparison_4w.household_key = customer.household_key
       AND comparison_4w.reference_week = customer.reference_week
       AND comparison_4w.window_weeks = 4
    WHERE comparison_4w.household_key IS NULL
       OR customer.prior4_valid_basket_count IS DISTINCT FROM comparison_4w.prior_valid_basket_count
       OR customer.recent4_valid_basket_count IS DISTINCT FROM comparison_4w.recent_valid_basket_count
       OR customer.prior4_sales IS DISTINCT FROM comparison_4w.prior_sales
       OR customer.recent4_sales IS DISTINCT FROM comparison_4w.recent_sales
       OR customer.basket_count_change IS DISTINCT FROM comparison_4w.basket_count_change
       OR customer.sales_change IS DISTINCT FROM comparison_4w.sales_change
       OR customer.basket_count_change_rate IS DISTINCT FROM comparison_4w.basket_count_change_rate
       OR customer.sales_change_rate IS DISTINCT FROM comparison_4w.sales_change_rate
       OR customer.activity_transition IS DISTINCT FROM comparison_4w.activity_transition
),

snapshot_reconciliation AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.customer_state AS customer
    LEFT JOIN mart.household_reference_week AS prior_value
        ON prior_value.household_key = customer.household_key
       AND prior_value.reference_week = customer.reference_week - 4
    WHERE customer.pre_window_has_snapshot IS DISTINCT FROM (prior_value.household_key IS NOT NULL)
       OR customer.pre_window_has_purchase_26w IS DISTINCT FROM prior_value.has_purchase_26w
       OR customer.pre_window_recency_weeks_26w IS DISTINCT FROM prior_value.recency_weeks_26w
       OR customer.pre_window_recency_days_26w IS DISTINCT FROM prior_value.recency_days_26w
       OR customer.pre_window_frequency_26w IS DISTINCT FROM prior_value.frequency_26w
       OR customer.pre_window_monetary_26w IS DISTINCT FROM prior_value.monetary_26w
       OR customer.pre_window_fm_value_index_26w IS DISTINCT FROM prior_value.fm_value_index_26w
       OR customer.pre_window_rfm_value_index_26w IS DISTINCT FROM prior_value.rfm_value_index_26w
),

state_integrity AS (
    SELECT
        COUNT(*) FILTER (
            WHERE value_state IS DISTINCT FROM CASE
                WHEN NOT pre_window_has_snapshot THEN 'NO_PRE_WINDOW_SNAPSHOT'
                WHEN NOT pre_window_has_purchase_26w
                  OR pre_window_rfm_value_index_26w IS NULL
                THEN 'NO_RECENT_VALUE_HISTORY'
                WHEN pre_window_rfm_value_index_26w >= value_cutoff_used THEN 'HIGH_VALUE'
                ELSE 'OTHER_VALUE'
            END
        )::BIGINT AS value_state_issues,
        COUNT(*) FILTER (
            WHERE current_value_state IS DISTINCT FROM CASE
                WHEN NOT current_has_purchase_26w
                  OR current_rfm_value_index_26w IS NULL
                THEN 'NO_CURRENT_PURCHASE_26W'
                WHEN current_rfm_value_index_26w >= value_cutoff_used THEN 'CURRENT_HIGH_VALUE'
                ELSE 'CURRENT_OTHER_VALUE'
            END
        )::BIGINT AS current_value_state_issues,
        COUNT(*) FILTER (
            WHERE activity_state IS DISTINCT FROM CASE
                WHEN prior4_valid_basket_count = 0
                 AND recent4_valid_basket_count = 0
                THEN 'NO_ACTIVITY_BOTH_WINDOWS'
                WHEN prior4_valid_basket_count = 0 THEN 'REACTIVATED'
                WHEN recent4_valid_basket_count = 0 THEN 'BECAME_INACTIVE'
                WHEN basket_change_denominator_status = 'COMPARABLE'
                 AND sales_change_denominator_status = 'COMPARABLE'
                 AND basket_count_change_rate <= strong_decline_cutoff_used
                 AND sales_change_rate <= strong_decline_cutoff_used
                THEN 'ACTIVE_BOTH_VERY_STRONG_DECLINE'
                WHEN basket_change_denominator_status = 'COMPARABLE'
                 AND sales_change_denominator_status = 'COMPARABLE'
                 AND basket_count_change_rate <= moderate_decline_cutoff_used
                 AND sales_change_rate <= moderate_decline_cutoff_used
                THEN 'ACTIVE_BOTH_STRONG_DECLINE'
                WHEN sales_change_denominator_status = 'COMPARABLE'
                 AND sales_change_rate <= moderate_decline_cutoff_used
                THEN 'ACTIVE_BOTH_SALES_DECLINE'
                ELSE 'ACTIVE_BOTH_NO_MAJOR_DECLINE'
            END
        )::BIGINT AS activity_state_issues,
        COUNT(*) FILTER (
            WHERE customer_state IS DISTINCT FROM CASE
                WHEN value_state IN ('NO_PRE_WINDOW_SNAPSHOT', 'NO_RECENT_VALUE_HISTORY')
                THEN 'INSUFFICIENT_VALUE_HISTORY'
                WHEN value_state = 'HIGH_VALUE' THEN CASE activity_state
                    WHEN 'NO_ACTIVITY_BOTH_WINDOWS' THEN 'HIGH_VALUE_LONG_INACTIVE'
                    WHEN 'REACTIVATED' THEN 'HIGH_VALUE_REACTIVATED'
                    WHEN 'BECAME_INACTIVE' THEN 'HIGH_VALUE_BECAME_INACTIVE'
                    WHEN 'ACTIVE_BOTH_VERY_STRONG_DECLINE' THEN 'HIGH_VALUE_VERY_STRONG_DECLINE'
                    WHEN 'ACTIVE_BOTH_STRONG_DECLINE' THEN 'HIGH_VALUE_STRONG_DECLINE'
                    WHEN 'ACTIVE_BOTH_SALES_DECLINE' THEN 'HIGH_VALUE_SALES_DECLINE'
                    ELSE 'HIGH_VALUE_ACTIVE'
                END
                ELSE CASE activity_state
                    WHEN 'NO_ACTIVITY_BOTH_WINDOWS' THEN 'OTHER_VALUE_LONG_INACTIVE'
                    WHEN 'REACTIVATED' THEN 'OTHER_VALUE_REACTIVATED'
                    WHEN 'BECAME_INACTIVE' THEN 'OTHER_VALUE_BECAME_INACTIVE'
                    WHEN 'ACTIVE_BOTH_VERY_STRONG_DECLINE' THEN 'OTHER_VALUE_VERY_STRONG_DECLINE'
                    WHEN 'ACTIVE_BOTH_STRONG_DECLINE' THEN 'OTHER_VALUE_STRONG_DECLINE'
                    WHEN 'ACTIVE_BOTH_SALES_DECLINE' THEN 'OTHER_VALUE_SALES_DECLINE'
                    ELSE 'OTHER_VALUE_ACTIVE'
                END
            END
        )::BIGINT AS customer_state_issues
    FROM mart.customer_state
),

schema_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM information_schema.columns
    WHERE table_schema = 'mart'
      AND table_name = 'customer_state'
      AND column_name IN (
          'future4_valid_basket_count',
          'future4_has_purchase',
          'future4_no_purchase',
          'predicted_probability',
          'no_purchase_probability'
      )
),

overview_issues AS (
    SELECT COUNT(*)::BIGINT AS share_issues
    FROM mart.diag_customer_state_overview
    WHERE state_share IS NULL
       OR state_share NOT BETWEEN 0 AND 1
),

overview_count_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM (
        SELECT dimension_type
        FROM mart.diag_customer_state_overview
        GROUP BY dimension_type
        HAVING SUM(state_row_count) <> (SELECT COUNT(*) FROM mart.customer_state)
    ) AS invalid
),

weekly_count_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM (
        SELECT
            reference_week,
            dimension_type
        FROM mart.diag_customer_state_by_week
        GROUP BY
            reference_week,
            dimension_type
        HAVING SUM(state_row_count) <> MAX(reference_week_total_count)
    ) AS invalid
),

diagnostic_counts AS (
    SELECT
        (SELECT COUNT(*) FROM mart.diag_customer_state_overview) AS overview_count,
        (SELECT COUNT(*) FROM mart.diag_customer_state_by_week) AS by_week_count,
        (SELECT COUNT(*) FROM mart.diag_customer_state_stability) AS stability_count,
        (SELECT COUNT(*) FROM mart.diag_customer_value_state_shift) AS shift_count
),

checks AS (
    SELECT
        'source_nonempty'::TEXT AS check_name,
        'FAIL'::TEXT AS severity,
        CASE WHEN source_count > 0 THEN 0 ELSE 1 END::BIGINT AS issue_count,
        'household_reference_week 행 존재'::TEXT AS detail
    FROM source_counts

    UNION ALL

    SELECT
        'expected_row_count',
        'FAIL',
        ABS(customer_count - source_count),
        'customer_state와 원천 행 수 대사'
    FROM source_counts

    UNION ALL

    SELECT
        'primary_key_integrity',
        'FAIL',
        null_key_count + duplicate_count,
        '가구·기준주차 키 NULL 및 중복'
    FROM customer_summary

    UNION ALL

    SELECT 'fixed_window_integrity', 'FAIL', fixed_window_issues, '4주 활동기간 고정'
    FROM customer_summary

    UNION ALL

    SELECT 'threshold_integrity', 'FAIL', threshold_issues, '저장 임계값 대사'
    FROM customer_summary

    UNION ALL

    SELECT 'current_rfm_reconciliation', 'FAIL', issue_count, '현재 RFM 원천 대사'
    FROM current_reconciliation

    UNION ALL

    SELECT 'four_week_activity_reconciliation', 'FAIL', issue_count, '기존 4주 활동값 대사'
    FROM activity_reconciliation

    UNION ALL

    SELECT 'activity_window_comparison_reconciliation', 'FAIL', issue_count, '05B 4주 결과 대사'
    FROM comparison_reconciliation

    UNION ALL

    SELECT 'pre_window_snapshot_integrity', 'FAIL', issue_count, '기준주차 - 4 스냅샷 대사'
    FROM snapshot_reconciliation

    UNION ALL

    SELECT 'value_state_integrity', 'FAIL', value_state_issues + null_state_issues, '사전 가치상태 조건'
    FROM state_integrity
    CROSS JOIN customer_summary

    UNION ALL

    SELECT 'current_value_state_integrity', 'FAIL', current_value_state_issues, '현재 가치상태 조건'
    FROM state_integrity

    UNION ALL

    SELECT 'activity_state_integrity', 'FAIL', activity_state_issues, '7개 활동상태 조건'
    FROM state_integrity

    UNION ALL

    SELECT 'customer_state_integrity', 'FAIL', customer_state_issues, '가치·활동 결합상태 조건'
    FROM state_integrity

    UNION ALL

    SELECT 'candidate_flag_integrity', 'FAIL', candidate_flag_issues, '활동감소 및 고가치 후보 플래그'
    FROM customer_summary

    UNION ALL

    SELECT 'future_leakage_schema_check', 'FAIL', issue_count, '미래·예측 컬럼 부재'
    FROM schema_issues

    UNION ALL

    SELECT 'overview_share_integrity', 'FAIL', share_issues, '전체 상태 비율 범위'
    FROM overview_issues

    UNION ALL

    SELECT 'overview_count_reconciliation', 'FAIL', issue_count, '차원별 전체 행 수 대사'
    FROM overview_count_issues

    UNION ALL

    SELECT 'weekly_count_reconciliation', 'FAIL', issue_count, '주차·차원별 행 수 대사'
    FROM weekly_count_issues

    UNION ALL

    SELECT
        'diagnostic_nonempty',
        'FAIL',
        CASE
            WHEN overview_count > 0
             AND by_week_count > 0
             AND stability_count > 0
             AND shift_count > 0
            THEN 0
            ELSE 1
        END,
        '신규 진단 테이블 행 존재'
    FROM diagnostic_counts
)
SELECT
    check_name,
    severity,
    issue_count,
    detail,
    CASE
        WHEN issue_count = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM checks

UNION ALL

SELECT
    'validation_fail_summary',
    'FAIL',
    COALESCE(SUM(issue_count) FILTER (
        WHERE issue_count > 0
    ), 0),
    FORMAT(
        'FAIL checks=%s, FAIL issue_count sum=%s',
        COUNT(*) FILTER (WHERE issue_count > 0),
        COALESCE(SUM(issue_count) FILTER (WHERE issue_count > 0), 0)
    ),
    CASE
        WHEN COUNT(*) FILTER (WHERE issue_count > 0) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END
FROM checks;

-- 06-09. 결과 확인
-- 06-09-01. 전체 행과 기간 확인
SELECT
    COUNT(*)::BIGINT AS total_row_count,
    COUNT(DISTINCT household_key)::BIGINT AS distinct_household_count,
    COUNT(DISTINCT reference_week)::BIGINT AS reference_week_count,
    MIN(reference_week) AS min_reference_week,
    MAX(reference_week) AS max_reference_week,
    COUNT(*) FILTER (
        WHERE value_state IN (
            'NO_PRE_WINDOW_SNAPSHOT',
            'NO_RECENT_VALUE_HISTORY'
        )
    )::BIGINT AS insufficient_value_history_count,
    COUNT(*) FILTER (
        WHERE value_state IN (
            'NO_PRE_WINDOW_SNAPSHOT',
            'NO_RECENT_VALUE_HISTORY'
        )
    )::NUMERIC / NULLIF(COUNT(*), 0) AS insufficient_value_history_share
FROM mart.customer_state;

-- 06-09-02. 구매가치 상태 분포
SELECT
    dimension_value,
    state_row_count,
    state_share,
    distinct_household_count
FROM mart.diag_customer_state_overview
WHERE dimension_type = 'VALUE_STATE'
ORDER BY dimension_value;

-- 06-09-03. 활동상태 분포
SELECT
    dimension_value,
    state_row_count,
    state_share,
    distinct_household_count
FROM mart.diag_customer_state_overview
WHERE dimension_type = 'ACTIVITY_STATE'
ORDER BY dimension_value;

-- 06-09-04. 최종 customer_state 분포
SELECT
    dimension_value,
    state_row_count,
    state_share,
    distinct_household_count
FROM mart.diag_customer_state_overview
WHERE dimension_type = 'CUSTOMER_STATE'
ORDER BY state_row_count DESC;

-- 06-09-05. 고가치 활동감소 후보 요약
SELECT
    COUNT(*) FILTER (
        WHERE value_state = 'HIGH_VALUE'
    )::BIGINT AS high_value_count,
    COUNT(*) FILTER (
        WHERE is_high_value_activity_decline_candidate
    )::BIGINT AS high_value_activity_decline_candidate_count,
    COUNT(*) FILTER (
        WHERE is_high_value_activity_decline_candidate
    )::NUMERIC / NULLIF(COUNT(*) FILTER (
        WHERE value_state = 'HIGH_VALUE'
    ), 0) AS high_value_activity_decline_share_of_high_value,
    COUNT(*) FILTER (
        WHERE is_high_value_strong_decline_candidate
    )::BIGINT AS high_value_strong_decline_candidate_count,
    COUNT(*) FILTER (
        WHERE is_high_value_strong_decline_candidate
    )::NUMERIC / NULLIF(COUNT(*) FILTER (
        WHERE value_state = 'HIGH_VALUE'
    ), 0) AS high_value_strong_decline_share_of_high_value,
    COUNT(*) FILTER (
        WHERE is_high_value_became_inactive_candidate
    )::BIGINT AS high_value_became_inactive_candidate_count,
    COUNT(*) FILTER (
        WHERE is_high_value_became_inactive_candidate
    )::NUMERIC / NULLIF(COUNT(*) FILTER (
        WHERE value_state = 'HIGH_VALUE'
    ), 0) AS high_value_became_inactive_share_of_high_value,
    COUNT(*) FILTER (
        WHERE is_high_value_activity_decline_candidate
    )::NUMERIC / NULLIF(COUNT(*), 0) AS high_value_activity_decline_share_of_all
FROM mart.customer_state;

-- 06-09-06. 기준주차별 상태 안정성
SELECT
    dimension_type,
    dimension_value,
    reference_week_count,
    average_state_share,
    minimum_state_share,
    maximum_state_share,
    stddev_state_share
FROM mart.diag_customer_state_stability
WHERE dimension_value IN (
    'BECAME_INACTIVE',
    'ACTIVE_BOTH_VERY_STRONG_DECLINE',
    'ACTIVE_BOTH_STRONG_DECLINE',
    'ACTIVE_BOTH_SALES_DECLINE',
    'HIGH_VALUE_BECAME_INACTIVE',
    'HIGH_VALUE_VERY_STRONG_DECLINE',
    'HIGH_VALUE_STRONG_DECLINE',
    'HIGH_VALUE_SALES_DECLINE'
)
ORDER BY
    dimension_type,
    dimension_value;

-- 06-09-07. 현재 가치와 활동감소 이전 가치 비교
SELECT
    current_value_state,
    value_state,
    row_count,
    share_of_all,
    distinct_household_count,
    high_pre_window_but_not_current_high_count,
    current_high_but_not_pre_window_high_count
FROM mart.diag_customer_value_state_shift
ORDER BY
    value_state,
    current_value_state;

-- 06-09-08. 정합성 검증
SELECT
    check_name,
    severity,
    issue_count,
    detail,
    status
FROM customer_state_validation
ORDER BY check_name;

-- ==================================================
-- 07. 기준주차 × 활동상태 × 경과기간 상태 코호트
-- ==================================================

BEGIN;

DROP TABLE IF EXISTS mart.state_cohort;

-- 07-01. 코호트 추적기간 및 관측가능 기준 설정
-- 07-02. 기준주차 활동상태 코호트 확정
-- 07-03. 이후 4·8·12주 구매 지속성 계산
-- 07-04. Tableau용 상태 코호트 테이블 생성
-- purchase_rate는 기준주차의 activity_state 코호트 중 이후 N주 안에
-- 한 번이라도 유효 구매한 가구 비율이며 신규고객 retention이나 영구 churn 지표가 아니다.
CREATE TABLE mart.state_cohort AS
WITH elapsed_window_catalog(elapsed_weeks) AS (
    VALUES
        (4),
        (8),
        (12)
),

activity_state_catalog(activity_state) AS (
    VALUES
        ('NO_ACTIVITY_BOTH_WINDOWS'),
        ('REACTIVATED'),
        ('BECAME_INACTIVE'),
        ('ACTIVE_BOTH_VERY_STRONG_DECLINE'),
        ('ACTIVE_BOTH_STRONG_DECLINE'),
        ('ACTIVE_BOTH_SALES_DECLINE'),
        ('ACTIVE_BOTH_NO_MAJOR_DECLINE')
),

observed_period AS (
    SELECT MAX(week_no) AS max_observed_week
    FROM mart.fact_household_week
),

cohort_reference_weeks AS (
    SELECT
        customer.reference_week,
        observed_period.max_observed_week
    FROM mart.customer_state AS customer
    CROSS JOIN observed_period
    WHERE customer.reference_week + 12 <= observed_period.max_observed_week
    GROUP BY
        customer.reference_week,
        observed_period.max_observed_week
),

cohort_households AS (
    SELECT
        customer.household_key,
        customer.reference_week,
        customer.activity_state
    FROM mart.customer_state AS customer
    JOIN cohort_reference_weeks
        ON cohort_reference_weeks.reference_week = customer.reference_week
),

cohort_sizes AS (
    SELECT
        reference_week,
        activity_state,
        COUNT(*)::BIGINT AS cohort_household_count
    FROM cohort_households
    GROUP BY
        reference_week,
        activity_state
),

future_purchase_by_household AS (
    SELECT
        cohort.household_key,
        cohort.reference_week,
        cohort.activity_state,
        elapsed.elapsed_weeks,
        BOOL_OR(
            weekly.week_no <= cohort.reference_week + elapsed.elapsed_weeks
            AND weekly.valid_basket_count > 0
        ) AS has_purchase_within_window
    FROM cohort_households AS cohort
    JOIN mart.fact_household_week AS weekly
        ON weekly.household_key = cohort.household_key
       AND weekly.week_no > cohort.reference_week
       AND weekly.week_no <= cohort.reference_week + 12
    CROSS JOIN elapsed_window_catalog AS elapsed
    GROUP BY
        cohort.household_key,
        cohort.reference_week,
        cohort.activity_state,
        elapsed.elapsed_weeks
),

cohort_purchases AS (
    SELECT
        reference_week,
        activity_state,
        elapsed_weeks,
        COUNT(*) FILTER (
            WHERE has_purchase_within_window
        )::BIGINT AS purchased_household_count
    FROM future_purchase_by_household
    GROUP BY
        reference_week,
        activity_state,
        elapsed_weeks
),

full_grid AS (
    SELECT
        cohort_reference_weeks.reference_week,
        activity_state_catalog.activity_state,
        elapsed_window_catalog.elapsed_weeks
    FROM cohort_reference_weeks
    CROSS JOIN activity_state_catalog
    CROSS JOIN elapsed_window_catalog
)
SELECT
    full_grid.reference_week,
    full_grid.activity_state,
    full_grid.elapsed_weeks,
    full_grid.reference_week + full_grid.elapsed_weeks AS followup_end_week,
    COALESCE(cohort_sizes.cohort_household_count, 0)::BIGINT AS cohort_household_count,
    COALESCE(cohort_purchases.purchased_household_count, 0)::BIGINT AS purchased_household_count,
    COALESCE(cohort_purchases.purchased_household_count, 0)::NUMERIC
        / NULLIF(cohort_sizes.cohort_household_count, 0) AS purchase_rate
FROM full_grid
LEFT JOIN cohort_sizes
    ON cohort_sizes.reference_week = full_grid.reference_week
   AND cohort_sizes.activity_state = full_grid.activity_state
LEFT JOIN cohort_purchases
    ON cohort_purchases.reference_week = full_grid.reference_week
   AND cohort_purchases.activity_state = full_grid.activity_state
   AND cohort_purchases.elapsed_weeks = full_grid.elapsed_weeks;

ALTER TABLE mart.state_cohort
    ADD CONSTRAINT pk_state_cohort
    PRIMARY KEY (
        reference_week,
        activity_state,
        elapsed_weeks
    );

ANALYZE mart.state_cohort;

COMMIT;

-- 07-05. 코호트 결과 진단
-- 영구 진단 테이블은 만들지 않으며 검증과 결과 조회에서 직접 확인한다.

-- 07-06. 정합성 검증
DROP TABLE IF EXISTS pg_temp.state_cohort_validation;

CREATE TEMP TABLE state_cohort_validation AS
WITH observed_period AS (
    SELECT MAX(week_no) AS max_observed_week
    FROM mart.fact_household_week
),

source_counts AS (
    SELECT
        (SELECT COUNT(*)::BIGINT FROM mart.customer_state) AS customer_state_count,
        (SELECT COUNT(*)::BIGINT FROM mart.fact_household_week) AS future_week_source_count,
        (SELECT COUNT(*)::BIGINT FROM mart.state_cohort) AS state_cohort_count,
        observed_period.max_observed_week
    FROM observed_period
),

eligible_reference_weeks AS (
    SELECT reference_week
    FROM mart.customer_state
    CROSS JOIN observed_period
    WHERE reference_week + 12 <= observed_period.max_observed_week
    GROUP BY reference_week
),

eligible_counts AS (
    SELECT COUNT(*)::BIGINT AS eligible_reference_week_count
    FROM eligible_reference_weeks
),

cohort_summary AS (
    SELECT
        COUNT(*) FILTER (
            WHERE reference_week IS NULL
               OR activity_state IS NULL
               OR elapsed_weeks IS NULL
        )::BIGINT AS null_key_count,
        (COUNT(*) - COUNT(DISTINCT (
            reference_week,
            activity_state,
            elapsed_weeks
        )))::BIGINT AS duplicate_key_count,
        COUNT(*) FILTER (
            WHERE elapsed_weeks NOT IN (4, 8, 12)
        )::BIGINT AS elapsed_window_issues,
        COUNT(*) FILTER (
            WHERE activity_state NOT IN (
                'NO_ACTIVITY_BOTH_WINDOWS',
                'REACTIVATED',
                'BECAME_INACTIVE',
                'ACTIVE_BOTH_VERY_STRONG_DECLINE',
                'ACTIVE_BOTH_STRONG_DECLINE',
                'ACTIVE_BOTH_SALES_DECLINE',
                'ACTIVE_BOTH_NO_MAJOR_DECLINE'
            )
        )::BIGINT AS activity_state_issues,
        COUNT(*) FILTER (
            WHERE followup_end_week <> reference_week + elapsed_weeks
        )::BIGINT AS followup_end_week_issues,
        COUNT(*) FILTER (
            WHERE purchased_household_count < 0
               OR purchased_household_count > cohort_household_count
        )::BIGINT AS purchased_bound_issues,
        COUNT(*) FILTER (
            WHERE cohort_household_count = 0
              AND (
                    purchased_household_count <> 0
                    OR purchase_rate IS NOT NULL
                )
        )::BIGINT AS zero_cohort_issues,
        COUNT(*) FILTER (
            WHERE cohort_household_count > 0
              AND (
                    purchase_rate IS NULL
                    OR purchase_rate NOT BETWEEN 0 AND 1
                )
        )::BIGINT AS nonzero_rate_issues,
        COUNT(*) FILTER (
            WHERE cohort_household_count > 0
              AND purchase_rate IS DISTINCT FROM
                    purchased_household_count::NUMERIC / cohort_household_count
        )::BIGINT AS rate_recalculation_issues
    FROM mart.state_cohort
),

horizon_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM (
        SELECT
            reference_week,
            activity_state
        FROM mart.state_cohort
        GROUP BY
            reference_week,
            activity_state
        HAVING COUNT(*) <> 3
            OR COUNT(DISTINCT elapsed_weeks) <> 3
            OR MIN(elapsed_weeks) <> 4
            OR MAX(elapsed_weeks) <> 12
    ) AS invalid
),

followup_complete_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.state_cohort
    CROSS JOIN observed_period
    WHERE followup_end_week > observed_period.max_observed_week
),

common_reference_week_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM (
        SELECT elapsed_weeks
        FROM mart.state_cohort
        GROUP BY elapsed_weeks
        HAVING COUNT(DISTINCT reference_week)
            <> (SELECT eligible_reference_week_count FROM eligible_counts)
    ) AS invalid
),

cohort_size_reconciliation AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM (
        SELECT
            cohort.reference_week,
            cohort.elapsed_weeks
        FROM mart.state_cohort AS cohort
        JOIN (
            SELECT
                reference_week,
                COUNT(*)::BIGINT AS expected_count
            FROM mart.customer_state
            JOIN eligible_reference_weeks
                USING (reference_week)
            GROUP BY reference_week
        ) AS expected
            ON expected.reference_week = cohort.reference_week
        GROUP BY
            cohort.reference_week,
            cohort.elapsed_weeks,
            expected.expected_count
        HAVING SUM(cohort.cohort_household_count) <> expected.expected_count
    ) AS invalid
),

cohort_size_horizon_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM (
        SELECT
            reference_week,
            activity_state
        FROM mart.state_cohort
        GROUP BY
            reference_week,
            activity_state
        HAVING MIN(cohort_household_count) <> MAX(cohort_household_count)
    ) AS invalid
),

cumulative_issues AS (
    SELECT
        COUNT(*) FILTER (
            WHERE purchased_4w > purchased_8w
               OR purchased_8w > purchased_12w
        )::BIGINT AS purchase_count_issues,
        COUNT(*) FILTER (
            WHERE cohort_household_count > 0
              AND (
                    purchase_rate_4w > purchase_rate_8w
                    OR purchase_rate_8w > purchase_rate_12w
                )
        )::BIGINT AS purchase_rate_issues
    FROM (
        SELECT
            reference_week,
            activity_state,
            MAX(cohort_household_count) AS cohort_household_count,
            MAX(purchased_household_count) FILTER (
                WHERE elapsed_weeks = 4
            ) AS purchased_4w,
            MAX(purchased_household_count) FILTER (
                WHERE elapsed_weeks = 8
            ) AS purchased_8w,
            MAX(purchased_household_count) FILTER (
                WHERE elapsed_weeks = 12
            ) AS purchased_12w,
            MAX(purchase_rate) FILTER (
                WHERE elapsed_weeks = 4
            ) AS purchase_rate_4w,
            MAX(purchase_rate) FILTER (
                WHERE elapsed_weeks = 8
            ) AS purchase_rate_8w,
            MAX(purchase_rate) FILTER (
                WHERE elapsed_weeks = 12
            ) AS purchase_rate_12w
        FROM mart.state_cohort
        GROUP BY
            reference_week,
            activity_state
    ) AS horizon_values
),

original_state_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM (
        SELECT
            cohort.reference_week,
            cohort.activity_state,
            cohort.cohort_household_count,
            COUNT(customer.household_key)::BIGINT AS expected_count
        FROM mart.state_cohort AS cohort
        LEFT JOIN mart.customer_state AS customer
            ON customer.reference_week = cohort.reference_week
           AND customer.activity_state = cohort.activity_state
        WHERE cohort.elapsed_weeks = 4
        GROUP BY
            cohort.reference_week,
            cohort.activity_state,
            cohort.cohort_household_count
        HAVING cohort.cohort_household_count <> COUNT(customer.household_key)
    ) AS invalid
),

future_boundary_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.state_cohort
    CROSS JOIN observed_period
    WHERE reference_week + 12 > observed_period.max_observed_week
),

prediction_column_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM information_schema.columns
    WHERE table_schema = 'mart'
      AND table_name = 'state_cohort'
      AND column_name IN (
          'predicted_probability',
          'no_purchase_probability',
          'model_split',
          'train_flag',
          'validation_flag',
          'test_flag'
      )
),

checks AS (
    SELECT
        'source_nonempty'::TEXT AS check_name,
        'FAIL'::TEXT AS severity,
        CASE WHEN customer_state_count > 0 THEN 0 ELSE 1 END::BIGINT AS issue_count,
        'customer_state 행 존재'::TEXT AS detail
    FROM source_counts

    UNION ALL

    SELECT
        'future_week_source_nonempty',
        'FAIL',
        CASE WHEN future_week_source_count > 0 THEN 0 ELSE 1 END,
        'fact_household_week 행 존재'
    FROM source_counts

    UNION ALL

    SELECT
        'cohort_reference_week_nonempty',
        'FAIL',
        CASE WHEN eligible_reference_week_count > 0 THEN 0 ELSE 1 END,
        '12주 추적 가능 기준주차 존재'
    FROM eligible_counts

    UNION ALL

    SELECT
        'primary_key_integrity',
        'FAIL',
        null_key_count + duplicate_key_count,
        '기준주차·활동상태·경과기간 키 NULL 및 중복'
    FROM cohort_summary

    UNION ALL

    SELECT
        'elapsed_window_integrity',
        'FAIL',
        elapsed_window_issues,
        '경과기간 4·8·12 허용값'
    FROM cohort_summary

    UNION ALL

    SELECT
        'activity_state_integrity',
        'FAIL',
        activity_state_issues,
        '7개 활동상태 허용값'
    FROM cohort_summary

    UNION ALL

    SELECT
        'full_grid_row_count',
        'FAIL',
        ABS(state_cohort_count - eligible_reference_week_count * 7 * 3),
        '기준주차 × 7개 상태 × 3개 경과기간'
    FROM source_counts
    CROSS JOIN eligible_counts

    UNION ALL

    SELECT
        'horizon_coverage',
        'FAIL',
        issue_count,
        '모든 기준주차·상태의 4·8·12주 행'
    FROM horizon_issues

    UNION ALL

    SELECT
        'followup_end_week_integrity',
        'FAIL',
        followup_end_week_issues,
        '추적 종료주차 산식'
    FROM cohort_summary

    UNION ALL

    SELECT
        'followup_complete_integrity',
        'FAIL',
        issue_count,
        '추적 종료주차 관찰범위 이내'
    FROM followup_complete_issues

    UNION ALL

    SELECT
        'common_reference_week_integrity',
        'FAIL',
        issue_count,
        '세 경과기간의 동일 기준주차 집합'
    FROM common_reference_week_issues

    UNION ALL

    SELECT
        'cohort_size_reconciliation',
        'FAIL',
        issue_count,
        '주차·경과기간별 7개 상태 가구 수 대사'
    FROM cohort_size_reconciliation

    UNION ALL

    SELECT
        'cohort_size_same_across_horizons',
        'FAIL',
        issue_count,
        '경과기간별 코호트 크기 동일성'
    FROM cohort_size_horizon_issues

    UNION ALL

    SELECT
        'purchased_count_bounds',
        'FAIL',
        purchased_bound_issues,
        '구매가구 수 범위'
    FROM cohort_summary

    UNION ALL

    SELECT
        'zero_cohort_integrity',
        'FAIL',
        zero_cohort_issues,
        '0명 코호트 건수와 NULL 구매율'
    FROM cohort_summary

    UNION ALL

    SELECT
        'nonzero_cohort_rate_integrity',
        'FAIL',
        nonzero_rate_issues,
        '비어 있지 않은 코호트 구매율 범위'
    FROM cohort_summary

    UNION ALL

    SELECT
        'purchase_rate_recalculation',
        'FAIL',
        rate_recalculation_issues,
        '구매가구 수 기반 구매율 재계산'
    FROM cohort_summary

    UNION ALL

    SELECT
        'cumulative_purchase_monotonicity',
        'FAIL',
        purchase_count_issues,
        '누적 구매가구 수 4주≤8주≤12주'
    FROM cumulative_issues

    UNION ALL

    SELECT
        'cumulative_rate_monotonicity',
        'FAIL',
        purchase_rate_issues,
        '누적 구매율 4주≤8주≤12주'
    FROM cumulative_issues

    UNION ALL

    SELECT
        'original_state_reconciliation',
        'FAIL',
        issue_count,
        'customer_state 활동상태 분포 대사'
    FROM original_state_issues

    UNION ALL

    SELECT
        'future_boundary_exclusion',
        'FAIL',
        issue_count,
        '12주 추적 불완전 기준주차 제외'
    FROM future_boundary_issues

    UNION ALL

    SELECT
        'no_future_columns_from_prediction',
        'FAIL',
        issue_count,
        '모델·데이터분할 컬럼 부재'
    FROM prediction_column_issues
)
SELECT
    check_name,
    severity,
    issue_count,
    detail,
    CASE
        WHEN issue_count = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM checks

UNION ALL

SELECT
    'validation_fail_summary',
    'FAIL',
    COALESCE(SUM(issue_count) FILTER (
        WHERE issue_count > 0
    ), 0),
    FORMAT(
        'FAIL checks=%s, FAIL issue_count sum=%s',
        COUNT(*) FILTER (WHERE issue_count > 0),
        COALESCE(SUM(issue_count) FILTER (WHERE issue_count > 0), 0)
    ),
    CASE
        WHEN COUNT(*) FILTER (WHERE issue_count > 0) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END
FROM checks;

-- 07-07. 결과 확인
-- 07-07-01. 코호트 전체 구조 확인
WITH observed_period AS (
    SELECT MAX(week_no) AS max_observed_week
    FROM mart.fact_household_week
)
SELECT
    COUNT(*)::BIGINT AS total_row_count,
    COUNT(DISTINCT reference_week)::BIGINT AS reference_week_count,
    MIN(reference_week) AS min_reference_week,
    MAX(reference_week) AS max_reference_week,
    COUNT(DISTINCT activity_state)::BIGINT AS activity_state_count,
    COUNT(DISTINCT elapsed_weeks)::BIGINT AS elapsed_window_count,
    observed_period.max_observed_week,
    COUNT(DISTINCT reference_week)::BIGINT * 7 * 3 AS expected_row_count
FROM mart.state_cohort
CROSS JOIN observed_period
GROUP BY observed_period.max_observed_week;

-- 07-07-02. 기준주차별 cohort 규모 대사
SELECT
    reference_week,
    SUM(cohort_household_count)::BIGINT AS cohort_household_count
FROM mart.state_cohort
WHERE elapsed_weeks = 4
GROUP BY reference_week
ORDER BY reference_week;

-- 07-07-03. 활동상태별 전체 cohort 규모
SELECT
    activity_state,
    COUNT(DISTINCT reference_week)::BIGINT AS reference_week_count,
    SUM(cohort_household_count)::BIGINT AS total_cohort_records,
    AVG(cohort_household_count) AS average_cohort_household_count,
    MIN(cohort_household_count) AS minimum_cohort_household_count,
    MAX(cohort_household_count) AS maximum_cohort_household_count
FROM mart.state_cohort
WHERE elapsed_weeks = 4
GROUP BY activity_state
ORDER BY activity_state;

-- 07-07-04. 활동상태 × 경과기간 구매 지속성
SELECT
    activity_state,
    elapsed_weeks,
    SUM(cohort_household_count)::BIGINT AS total_cohort_household_records,
    SUM(purchased_household_count)::BIGINT AS total_purchased_household_records,
    SUM(purchased_household_count)::NUMERIC
        / NULLIF(SUM(cohort_household_count), 0) AS weighted_purchase_rate
FROM mart.state_cohort
GROUP BY
    activity_state,
    elapsed_weeks
ORDER BY
    activity_state,
    elapsed_weeks;

-- 07-07-05. 기준주차 × 활동상태 × 경과기간 전체 결과
SELECT
    reference_week,
    activity_state,
    elapsed_weeks,
    followup_end_week,
    cohort_household_count,
    purchased_household_count,
    purchase_rate
FROM mart.state_cohort
ORDER BY
    reference_week,
    activity_state,
    elapsed_weeks;

-- 07-07-06. 정합성 검증
SELECT
    check_name,
    severity,
    issue_count,
    detail,
    status
FROM state_cohort_validation
ORDER BY check_name;

-- ==================================================
-- 07B. ACTIVE_BOTH 세부 상태 절대 활동량 진단
-- ==================================================

BEGIN;

DROP TABLE IF EXISTS mart.diag_active_both_recent_basket_control;
DROP TABLE IF EXISTS mart.diag_active_both_state_profile;

-- 07B-01. 분석대상 및 동일 코호트 표본 확정
-- 07B-02. 가구 × 기준주차 진단 데이터 구성
-- 07B-03. ACTIVE_BOTH 상태별 절대 활동량 프로파일
-- 07B-04. 장기 구매기준선 대비 prior/recent 활동 진단
CREATE TABLE mart.diag_active_both_state_profile AS
WITH eligible_reference_weeks AS (
    SELECT DISTINCT reference_week
    FROM mart.state_cohort
),

active_both_base AS (
    SELECT
        customer.household_key,
        customer.reference_week,
        customer.activity_state,
        customer.prior4_valid_basket_count,
        customer.recent4_valid_basket_count,
        customer.prior4_sales,
        customer.recent4_sales,
        customer.basket_count_change,
        customer.basket_count_change_rate,
        customer.sales_change,
        customer.sales_change_rate,
        customer.pre_window_frequency_26w,
        customer.pre_window_monetary_26w,
        customer.pre_window_rfm_value_index_26w,
        comparison_4w.future4_has_purchase,
        comparison_4w.future4_no_purchase,
        customer.pre_window_frequency_26w * 4.0::NUMERIC / 26.0::NUMERIC
            AS expected_4w_basket_from_pre26w,
        customer.pre_window_monetary_26w * 4.0::NUMERIC / 26.0::NUMERIC
            AS expected_4w_sales_from_pre26w
    FROM mart.customer_state AS customer
    JOIN eligible_reference_weeks
        ON eligible_reference_weeks.reference_week = customer.reference_week
    JOIN mart.activity_window_comparison AS comparison_4w
        ON comparison_4w.household_key = customer.household_key
       AND comparison_4w.reference_week = customer.reference_week
       AND comparison_4w.window_weeks = 4
    WHERE customer.activity_state IN (
        'ACTIVE_BOTH_NO_MAJOR_DECLINE',
        'ACTIVE_BOTH_SALES_DECLINE',
        'ACTIVE_BOTH_STRONG_DECLINE',
        'ACTIVE_BOTH_VERY_STRONG_DECLINE'
    )
),

analysis_data AS (
    SELECT
        active_both_base.*,
        prior4_valid_basket_count::NUMERIC
            / NULLIF(expected_4w_basket_from_pre26w, 0)
            AS prior4_basket_vs_baseline_ratio,
        recent4_valid_basket_count::NUMERIC
            / NULLIF(expected_4w_basket_from_pre26w, 0)
            AS recent4_basket_vs_baseline_ratio,
        prior4_sales
            / NULLIF(expected_4w_sales_from_pre26w, 0)
            AS prior4_sales_vs_baseline_ratio,
        recent4_sales
            / NULLIF(expected_4w_sales_from_pre26w, 0)
            AS recent4_sales_vs_baseline_ratio
    FROM active_both_base
)
SELECT
    activity_state,
    COUNT(*)::BIGINT AS row_count,
    COUNT(DISTINCT household_key)::BIGINT AS distinct_household_count,
    COUNT(DISTINCT reference_week)::BIGINT AS reference_week_count,
    AVG(prior4_valid_basket_count) AS prior4_basket_mean,
    PERCENTILE_CONT(0.25) WITHIN GROUP (
        ORDER BY prior4_valid_basket_count
    ) AS prior4_basket_p25,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY prior4_valid_basket_count
    ) AS prior4_basket_median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (
        ORDER BY prior4_valid_basket_count
    ) AS prior4_basket_p75,
    AVG(recent4_valid_basket_count) AS recent4_basket_mean,
    PERCENTILE_CONT(0.25) WITHIN GROUP (
        ORDER BY recent4_valid_basket_count
    ) AS recent4_basket_p25,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY recent4_valid_basket_count
    ) AS recent4_basket_median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (
        ORDER BY recent4_valid_basket_count
    ) AS recent4_basket_p75,
    AVG(prior4_sales) AS prior4_sales_mean,
    PERCENTILE_CONT(0.25) WITHIN GROUP (
        ORDER BY prior4_sales
    ) AS prior4_sales_p25,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY prior4_sales
    ) AS prior4_sales_median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (
        ORDER BY prior4_sales
    ) AS prior4_sales_p75,
    AVG(recent4_sales) AS recent4_sales_mean,
    PERCENTILE_CONT(0.25) WITHIN GROUP (
        ORDER BY recent4_sales
    ) AS recent4_sales_p25,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY recent4_sales
    ) AS recent4_sales_median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (
        ORDER BY recent4_sales
    ) AS recent4_sales_p75,
    AVG(basket_count_change) AS basket_change_mean,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY basket_count_change
    ) AS basket_change_median,
    AVG(sales_change) AS sales_change_mean,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY sales_change
    ) AS sales_change_median,
    AVG(basket_count_change_rate) AS basket_change_rate_mean,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY basket_count_change_rate
    ) AS basket_change_rate_median,
    PERCENTILE_CONT(0.25) WITHIN GROUP (
        ORDER BY basket_count_change_rate
    ) AS basket_change_rate_p25,
    PERCENTILE_CONT(0.75) WITHIN GROUP (
        ORDER BY basket_count_change_rate
    ) AS basket_change_rate_p75,
    AVG(sales_change_rate) AS sales_change_rate_mean,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY sales_change_rate
    ) AS sales_change_rate_median,
    PERCENTILE_CONT(0.25) WITHIN GROUP (
        ORDER BY sales_change_rate
    ) AS sales_change_rate_p25,
    PERCENTILE_CONT(0.75) WITHIN GROUP (
        ORDER BY sales_change_rate
    ) AS sales_change_rate_p75,
    AVG(pre_window_frequency_26w) AS pre_frequency_26w_mean,
    PERCENTILE_CONT(0.25) WITHIN GROUP (
        ORDER BY pre_window_frequency_26w
    ) AS pre_frequency_26w_p25,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY pre_window_frequency_26w
    ) AS pre_frequency_26w_median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (
        ORDER BY pre_window_frequency_26w
    ) AS pre_frequency_26w_p75,
    AVG(pre_window_monetary_26w) AS pre_monetary_26w_mean,
    PERCENTILE_CONT(0.25) WITHIN GROUP (
        ORDER BY pre_window_monetary_26w
    ) AS pre_monetary_26w_p25,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY pre_window_monetary_26w
    ) AS pre_monetary_26w_median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (
        ORDER BY pre_window_monetary_26w
    ) AS pre_monetary_26w_p75,
    AVG(pre_window_rfm_value_index_26w) AS pre_rfm_mean,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY pre_window_rfm_value_index_26w
    ) AS pre_rfm_median,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY prior4_basket_vs_baseline_ratio
    ) AS prior4_basket_vs_baseline_median,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY recent4_basket_vs_baseline_ratio
    ) AS recent4_basket_vs_baseline_median,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY prior4_sales_vs_baseline_ratio
    ) AS prior4_sales_vs_baseline_median,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY recent4_sales_vs_baseline_ratio
    ) AS recent4_sales_vs_baseline_median,
    COUNT(*) FILTER (
        WHERE future4_has_purchase
    )::BIGINT AS future4_purchase_count,
    COUNT(*) FILTER (
        WHERE future4_no_purchase
    )::BIGINT AS future4_no_purchase_count,
    COUNT(*) FILTER (
        WHERE future4_has_purchase
    )::NUMERIC / NULLIF(COUNT(*), 0) AS future4_purchase_rate,
    COUNT(*) FILTER (
        WHERE future4_no_purchase
    )::NUMERIC / NULLIF(COUNT(*), 0) AS future4_no_purchase_rate
FROM analysis_data
GROUP BY activity_state;

ANALYZE mart.diag_active_both_state_profile;

-- 07B-05. 최근 절대 구매횟수 통제 진단
CREATE TABLE mart.diag_active_both_recent_basket_control AS
WITH eligible_reference_weeks AS (
    SELECT DISTINCT reference_week
    FROM mart.state_cohort
),

active_both_base AS (
    SELECT
        customer.household_key,
        customer.reference_week,
        customer.activity_state,
        customer.prior4_valid_basket_count,
        customer.recent4_valid_basket_count,
        customer.recent4_sales,
        customer.pre_window_frequency_26w,
        comparison_4w.future4_has_purchase,
        comparison_4w.future4_no_purchase
    FROM mart.customer_state AS customer
    JOIN eligible_reference_weeks
        ON eligible_reference_weeks.reference_week = customer.reference_week
    JOIN mart.activity_window_comparison AS comparison_4w
        ON comparison_4w.household_key = customer.household_key
       AND comparison_4w.reference_week = customer.reference_week
       AND comparison_4w.window_weeks = 4
    WHERE customer.activity_state IN (
        'ACTIVE_BOTH_NO_MAJOR_DECLINE',
        'ACTIVE_BOTH_SALES_DECLINE',
        'ACTIVE_BOTH_STRONG_DECLINE',
        'ACTIVE_BOTH_VERY_STRONG_DECLINE'
    )
)
SELECT
    recent4_valid_basket_count,
    activity_state,
    COUNT(*)::BIGINT AS row_count,
    COUNT(DISTINCT household_key)::BIGINT AS distinct_household_count,
    COUNT(DISTINCT reference_week)::BIGINT AS reference_week_count,
    AVG(prior4_valid_basket_count) AS prior4_basket_mean,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY prior4_valid_basket_count
    ) AS prior4_basket_median,
    AVG(recent4_sales) AS recent4_sales_mean,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY recent4_sales
    ) AS recent4_sales_median,
    AVG(pre_window_frequency_26w) AS pre_frequency_26w_mean,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY pre_window_frequency_26w
    ) AS pre_frequency_26w_median,
    COUNT(*) FILTER (
        WHERE future4_has_purchase
    )::BIGINT AS future4_purchase_count,
    COUNT(*) FILTER (
        WHERE future4_no_purchase
    )::BIGINT AS future4_no_purchase_count,
    COUNT(*) FILTER (
        WHERE future4_has_purchase
    )::NUMERIC / NULLIF(COUNT(*), 0) AS future4_purchase_rate,
    COUNT(*) FILTER (
        WHERE future4_no_purchase
    )::NUMERIC / NULLIF(COUNT(*), 0) AS future4_no_purchase_rate
FROM active_both_base
GROUP BY
    recent4_valid_basket_count,
    activity_state;

ANALYZE mart.diag_active_both_recent_basket_control;

COMMIT;

-- 07B-06. STRONG vs NO_MAJOR 동일 최근활동 비교
-- 별도 영구 테이블 없이 결과 조회에서 조건부 비교한다.

-- 07B-07. 정합성 검증
DROP TABLE IF EXISTS pg_temp.active_both_diagnostic_validation;

CREATE TEMP TABLE active_both_diagnostic_validation AS
WITH eligible_reference_weeks AS (
    SELECT DISTINCT reference_week
    FROM mart.state_cohort
),

active_both_base AS (
    SELECT
        customer.household_key,
        customer.reference_week,
        customer.activity_state,
        customer.prior4_valid_basket_count,
        customer.recent4_valid_basket_count,
        customer.prior4_sales,
        customer.recent4_sales,
        customer.pre_window_frequency_26w,
        customer.pre_window_monetary_26w,
        comparison_4w.future4_has_purchase,
        comparison_4w.future4_no_purchase,
        customer.pre_window_frequency_26w * 4.0::NUMERIC / 26.0::NUMERIC
            AS expected_4w_basket_from_pre26w,
        customer.pre_window_monetary_26w * 4.0::NUMERIC / 26.0::NUMERIC
            AS expected_4w_sales_from_pre26w
    FROM mart.customer_state AS customer
    JOIN eligible_reference_weeks
        ON eligible_reference_weeks.reference_week = customer.reference_week
    JOIN mart.activity_window_comparison AS comparison_4w
        ON comparison_4w.household_key = customer.household_key
       AND comparison_4w.reference_week = customer.reference_week
       AND comparison_4w.window_weeks = 4
    WHERE customer.activity_state IN (
        'ACTIVE_BOTH_NO_MAJOR_DECLINE',
        'ACTIVE_BOTH_SALES_DECLINE',
        'ACTIVE_BOTH_STRONG_DECLINE',
        'ACTIVE_BOTH_VERY_STRONG_DECLINE'
    )
),

base_summary AS (
    SELECT
        COUNT(*) FILTER (
            WHERE activity_state NOT IN (
                'ACTIVE_BOTH_NO_MAJOR_DECLINE',
                'ACTIVE_BOTH_SALES_DECLINE',
                'ACTIVE_BOTH_STRONG_DECLINE',
                'ACTIVE_BOTH_VERY_STRONG_DECLINE'
            )
        )::BIGINT AS invalid_state_count,
        (COUNT(*) - COUNT(DISTINCT (
            household_key,
            reference_week
        )))::BIGINT AS duplicate_count,
        COUNT(*) FILTER (
            WHERE prior4_valid_basket_count <= 0
               OR recent4_valid_basket_count <= 0
        )::BIGINT AS purchase_integrity_count,
        COUNT(*) FILTER (
            WHERE (
                    expected_4w_basket_from_pre26w IS NULL
                    OR expected_4w_basket_from_pre26w = 0
                )
              AND (
                    prior4_valid_basket_count::NUMERIC
                        / NULLIF(expected_4w_basket_from_pre26w, 0)
                ) IS NOT NULL
        )::BIGINT
        + COUNT(*) FILTER (
            WHERE (
                    expected_4w_sales_from_pre26w IS NULL
                    OR expected_4w_sales_from_pre26w = 0
                )
              AND (
                    prior4_sales
                        / NULLIF(expected_4w_sales_from_pre26w, 0)
                ) IS NOT NULL
        )::BIGINT AS baseline_denominator_issues
    FROM active_both_base
),

reference_sample_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM (
        (SELECT reference_week FROM eligible_reference_weeks
         EXCEPT
         SELECT DISTINCT reference_week FROM active_both_base)
        UNION ALL
        (SELECT DISTINCT reference_week FROM active_both_base
         EXCEPT
         SELECT reference_week FROM eligible_reference_weeks)
    ) AS differences
),

profile_summary AS (
    SELECT
        COUNT(*)::BIGINT AS profile_row_count,
        COUNT(DISTINCT activity_state)::BIGINT AS profile_state_count,
        COUNT(*) FILTER (
            WHERE prior4_basket_p25 > prior4_basket_median
               OR prior4_basket_median > prior4_basket_p75
               OR recent4_basket_p25 > recent4_basket_median
               OR recent4_basket_median > recent4_basket_p75
               OR prior4_sales_p25 > prior4_sales_median
               OR prior4_sales_median > prior4_sales_p75
               OR recent4_sales_p25 > recent4_sales_median
               OR recent4_sales_median > recent4_sales_p75
               OR basket_change_rate_p25 > basket_change_rate_median
               OR basket_change_rate_median > basket_change_rate_p75
               OR sales_change_rate_p25 > sales_change_rate_median
               OR sales_change_rate_median > sales_change_rate_p75
               OR pre_frequency_26w_p25 > pre_frequency_26w_median
               OR pre_frequency_26w_median > pre_frequency_26w_p75
               OR pre_monetary_26w_p25 > pre_monetary_26w_median
               OR pre_monetary_26w_median > pre_monetary_26w_p75
        )::BIGINT AS quantile_issues,
        COUNT(*) FILTER (
            WHERE future4_purchase_rate IS NULL
               OR future4_no_purchase_rate IS NULL
               OR future4_purchase_rate NOT BETWEEN 0 AND 1
               OR future4_no_purchase_rate NOT BETWEEN 0 AND 1
        )::BIGINT AS rate_bound_issues,
        COUNT(*) FILTER (
            WHERE ABS(
                future4_purchase_rate + future4_no_purchase_rate - 1
            ) > 1e-12::NUMERIC
        )::BIGINT AS complement_issues,
        COUNT(*) FILTER (
            WHERE future4_purchase_count + future4_no_purchase_count <> row_count
        )::BIGINT AS count_issues
    FROM mart.diag_active_both_state_profile
),

cohort_4w_reconciliation AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM (
        SELECT
            profile.activity_state
        FROM mart.diag_active_both_state_profile AS profile
        JOIN (
            SELECT
                activity_state,
                SUM(cohort_household_count)::BIGINT AS row_count,
                SUM(purchased_household_count)::BIGINT AS purchased_count,
                SUM(purchased_household_count)::NUMERIC
                    / NULLIF(SUM(cohort_household_count), 0) AS purchase_rate
            FROM mart.state_cohort
            WHERE elapsed_weeks = 4
              AND activity_state IN (
                    'ACTIVE_BOTH_NO_MAJOR_DECLINE',
                    'ACTIVE_BOTH_SALES_DECLINE',
                    'ACTIVE_BOTH_STRONG_DECLINE',
                    'ACTIVE_BOTH_VERY_STRONG_DECLINE'
                )
            GROUP BY activity_state
        ) AS cohort
            ON cohort.activity_state = profile.activity_state
        WHERE profile.row_count IS DISTINCT FROM cohort.row_count
           OR profile.future4_purchase_count IS DISTINCT FROM cohort.purchased_count
           OR profile.future4_purchase_rate IS DISTINCT FROM cohort.purchase_rate
    ) AS invalid
),

control_summary AS (
    SELECT
        COUNT(*) FILTER (
            WHERE recent4_valid_basket_count <= 0
        )::BIGINT AS nonpositive_issues,
        COUNT(*) FILTER (
            WHERE future4_purchase_count + future4_no_purchase_count <> row_count
               OR future4_purchase_rate IS NULL
               OR future4_no_purchase_rate IS NULL
               OR future4_purchase_rate NOT BETWEEN 0 AND 1
               OR future4_no_purchase_rate NOT BETWEEN 0 AND 1
        )::BIGINT AS rate_issues
    FROM mart.diag_active_both_recent_basket_control
),

control_count_reconciliation AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM (
        SELECT profile.activity_state
        FROM mart.diag_active_both_state_profile AS profile
        JOIN (
            SELECT
                activity_state,
                SUM(row_count)::BIGINT AS row_count
            FROM mart.diag_active_both_recent_basket_control
            GROUP BY activity_state
        ) AS control
            ON control.activity_state = profile.activity_state
        WHERE control.row_count IS DISTINCT FROM profile.row_count
    ) AS invalid
),

state_definition_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM (
        SELECT activity_state
        FROM mart.diag_active_both_state_profile
        UNION ALL
        SELECT activity_state
        FROM mart.diag_active_both_recent_basket_control
    ) AS diagnostic_states
    WHERE activity_state NOT IN (
        'ACTIVE_BOTH_NO_MAJOR_DECLINE',
        'ACTIVE_BOTH_SALES_DECLINE',
        'ACTIVE_BOTH_STRONG_DECLINE',
        'ACTIVE_BOTH_VERY_STRONG_DECLINE'
    )
),

checks AS (
    SELECT
        'customer_state_source_nonempty'::TEXT AS check_name,
        'FAIL'::TEXT AS severity,
        CASE
            WHEN (SELECT COUNT(*) FROM mart.customer_state) > 0 THEN 0
            ELSE 1
        END::BIGINT AS issue_count,
        'customer_state 행 존재'::TEXT AS detail

    UNION ALL

    SELECT
        'state_cohort_source_nonempty',
        'FAIL',
        CASE
            WHEN (SELECT COUNT(*) FROM mart.state_cohort) > 0 THEN 0
            ELSE 1
        END,
        'state_cohort 행 존재'

    UNION ALL

    SELECT 'same_reference_week_sample', 'FAIL', issue_count, '07과 동일 기준주차 집합'
    FROM reference_sample_issues

    UNION ALL

    SELECT 'active_both_only', 'FAIL', invalid_state_count, 'ACTIVE_BOTH 네 상태만 포함'
    FROM base_summary

    UNION ALL

    SELECT 'household_reference_unique', 'FAIL', duplicate_count, '가구×기준주차 중복'
    FROM base_summary

    UNION ALL

    SELECT 'active_both_purchase_integrity', 'FAIL', purchase_integrity_count, 'prior4·recent4 구매 양수'
    FROM base_summary

    UNION ALL

    SELECT
        'state_profile_expected_rows',
        'FAIL',
        ABS(profile_row_count - 4),
        '상태 프로파일 4행'
    FROM profile_summary

    UNION ALL

    SELECT
        'state_profile_state_coverage',
        'FAIL',
        CASE WHEN profile_state_count = 4 THEN 0 ELSE 1 END,
        'ACTIVE_BOTH 네 상태 각각 한 행'
    FROM profile_summary

    UNION ALL

    SELECT 'quantile_order_integrity', 'FAIL', quantile_issues, '주요 지표 분위수 순서'
    FROM profile_summary

    UNION ALL

    SELECT 'future4_rate_bounds', 'FAIL', rate_bound_issues, '상태별 future4 비율 범위'
    FROM profile_summary

    UNION ALL

    SELECT 'future4_complement_integrity', 'FAIL', complement_issues, 'future4 구매·미구매율 합계'
    FROM profile_summary

    UNION ALL

    SELECT 'future4_count_integrity', 'FAIL', count_issues, 'future4 구매·미구매 건수 합계'
    FROM profile_summary

    UNION ALL

    SELECT 'state_cohort_4w_reconciliation', 'FAIL', issue_count, '07 +4주 가중 결과 대사'
    FROM cohort_4w_reconciliation

    UNION ALL

    SELECT 'recent_basket_control_positive', 'FAIL', nonpositive_issues, 'recent4 basket 양수'
    FROM control_summary

    UNION ALL

    SELECT 'recent_basket_control_count_reconciliation', 'FAIL', issue_count, '통제표와 상태 프로파일 건수 대사'
    FROM control_count_reconciliation

    UNION ALL

    SELECT 'recent_basket_control_rate_integrity', 'FAIL', rate_issues, '통제 셀 future4 건수·비율'
    FROM control_summary

    UNION ALL

    SELECT 'baseline_ratio_denominator_integrity', 'FAIL', baseline_denominator_issues, '0·NULL 장기 기준선 비율'
    FROM base_summary

    UNION ALL

    SELECT 'no_state_definition_change', 'FAIL', issue_count, '06의 ACTIVE_BOTH 상태값 재사용'
    FROM state_definition_issues
)
SELECT
    check_name,
    severity,
    issue_count,
    detail,
    CASE
        WHEN issue_count = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM checks

UNION ALL

SELECT
    'validation_fail_summary',
    'FAIL',
    COALESCE(SUM(issue_count) FILTER (
        WHERE issue_count > 0
    ), 0),
    FORMAT(
        'FAIL checks=%s, FAIL issue_count sum=%s',
        COUNT(*) FILTER (WHERE issue_count > 0),
        COALESCE(SUM(issue_count) FILTER (WHERE issue_count > 0), 0)
    ),
    CASE
        WHEN COUNT(*) FILTER (WHERE issue_count > 0) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END
FROM checks;

-- 07B-08. 결과 확인
-- 07B-08-01. 분석 표본 확인
WITH eligible_reference_weeks AS (
    SELECT DISTINCT reference_week
    FROM mart.state_cohort
)
SELECT
    COUNT(*)::BIGINT AS total_row_count,
    COUNT(DISTINCT customer.household_key)::BIGINT AS distinct_household_count,
    COUNT(DISTINCT customer.reference_week)::BIGINT AS reference_week_count,
    MIN(customer.reference_week) AS min_reference_week,
    MAX(customer.reference_week) AS max_reference_week
FROM mart.customer_state AS customer
JOIN eligible_reference_weeks
    ON eligible_reference_weeks.reference_week = customer.reference_week
WHERE customer.activity_state IN (
    'ACTIVE_BOTH_NO_MAJOR_DECLINE',
    'ACTIVE_BOTH_SALES_DECLINE',
    'ACTIVE_BOTH_STRONG_DECLINE',
    'ACTIVE_BOTH_VERY_STRONG_DECLINE'
);

-- 07B-08-02. ACTIVE_BOTH 상태별 절대 활동 프로파일
SELECT
    activity_state,
    row_count,
    distinct_household_count,
    reference_week_count,
    prior4_basket_mean,
    prior4_basket_p25,
    prior4_basket_median,
    prior4_basket_p75,
    recent4_basket_mean,
    recent4_basket_p25,
    recent4_basket_median,
    recent4_basket_p75,
    prior4_sales_mean,
    prior4_sales_p25,
    prior4_sales_median,
    prior4_sales_p75,
    recent4_sales_mean,
    recent4_sales_p25,
    recent4_sales_median,
    recent4_sales_p75,
    basket_change_mean,
    basket_change_median,
    sales_change_mean,
    sales_change_median,
    basket_change_rate_mean,
    basket_change_rate_median,
    basket_change_rate_p25,
    basket_change_rate_p75,
    sales_change_rate_mean,
    sales_change_rate_median,
    sales_change_rate_p25,
    sales_change_rate_p75,
    pre_frequency_26w_mean,
    pre_frequency_26w_p25,
    pre_frequency_26w_median,
    pre_frequency_26w_p75,
    pre_monetary_26w_mean,
    pre_monetary_26w_p25,
    pre_monetary_26w_median,
    pre_monetary_26w_p75,
    pre_rfm_mean,
    pre_rfm_median,
    prior4_basket_vs_baseline_median,
    recent4_basket_vs_baseline_median,
    prior4_sales_vs_baseline_median,
    recent4_sales_vs_baseline_median,
    future4_purchase_count,
    future4_no_purchase_count,
    future4_purchase_rate,
    future4_no_purchase_rate
FROM mart.diag_active_both_state_profile
ORDER BY
    CASE activity_state
        WHEN 'ACTIVE_BOTH_NO_MAJOR_DECLINE' THEN 1
        WHEN 'ACTIVE_BOTH_SALES_DECLINE' THEN 2
        WHEN 'ACTIVE_BOTH_STRONG_DECLINE' THEN 3
        WHEN 'ACTIVE_BOTH_VERY_STRONG_DECLINE' THEN 4
        ELSE 99
    END;

-- 07B-08-03. 최근 구매횟수 통제 상태별 결과
SELECT
    recent4_valid_basket_count,
    activity_state,
    row_count,
    prior4_basket_median,
    recent4_sales_median,
    pre_frequency_26w_median,
    future4_purchase_count,
    future4_no_purchase_count,
    future4_purchase_rate,
    future4_no_purchase_rate
FROM mart.diag_active_both_recent_basket_control
ORDER BY
    recent4_valid_basket_count,
    activity_state;

-- 07B-08-04. STRONG vs NO_MAJOR 동일 recent basket 비교
WITH compared AS (
    SELECT
        recent4_valid_basket_count,
        MAX(row_count) FILTER (
            WHERE activity_state = 'ACTIVE_BOTH_NO_MAJOR_DECLINE'
        ) AS no_major_row_count,
        MAX(row_count) FILTER (
            WHERE activity_state = 'ACTIVE_BOTH_STRONG_DECLINE'
        ) AS strong_row_count,
        MAX(future4_no_purchase_rate) FILTER (
            WHERE activity_state = 'ACTIVE_BOTH_NO_MAJOR_DECLINE'
        ) AS no_major_future4_no_purchase_rate,
        MAX(future4_no_purchase_rate) FILTER (
            WHERE activity_state = 'ACTIVE_BOTH_STRONG_DECLINE'
        ) AS strong_future4_no_purchase_rate
    FROM mart.diag_active_both_recent_basket_control
    GROUP BY recent4_valid_basket_count
)
SELECT
    recent4_valid_basket_count,
    no_major_row_count,
    strong_row_count,
    no_major_future4_no_purchase_rate,
    strong_future4_no_purchase_rate,
    CASE
        WHEN no_major_row_count IS NULL
          OR strong_row_count IS NULL
        THEN NULL
        ELSE strong_future4_no_purchase_rate - no_major_future4_no_purchase_rate
    END AS strong_minus_no_major_no_purchase_rate_gap
FROM compared
ORDER BY recent4_valid_basket_count;

-- 07B-08-05. baseline reversion 진단 요약
SELECT
    activity_state,
    prior4_basket_vs_baseline_median,
    recent4_basket_vs_baseline_median,
    prior4_sales_vs_baseline_median,
    recent4_sales_vs_baseline_median
FROM mart.diag_active_both_state_profile
ORDER BY
    CASE activity_state
        WHEN 'ACTIVE_BOTH_NO_MAJOR_DECLINE' THEN 1
        WHEN 'ACTIVE_BOTH_SALES_DECLINE' THEN 2
        WHEN 'ACTIVE_BOTH_STRONG_DECLINE' THEN 3
        WHEN 'ACTIVE_BOTH_VERY_STRONG_DECLINE' THEN 4
        ELSE 99
    END;

-- 07B-08-06. 정합성 검증
SELECT
    check_name,
    severity,
    issue_count,
    detail,
    status
FROM active_both_diagnostic_validation
ORDER BY check_name;

-- ==================================================
-- 08. 가구 × 기준주차 다음 4주 미구매 모델 데이터셋
-- ==================================================

BEGIN;

DROP TABLE IF EXISTS mart.model_dataset;

-- 08-01. 모델링 원천 및 4주 Target 확정
-- 08-02. 과거 Feature 결합
-- 08-03. mart.model_dataset 생성
CREATE TABLE mart.model_dataset AS
SELECT
    reference_data.household_key,
    reference_data.reference_week,
    reference_data.reference_end_day,
    reference_data.observation_start_week,
    reference_data.observation_end_week,
    reference_data.prior4_start_week,
    reference_data.prior4_end_week,
    reference_data.recent4_start_week,
    reference_data.recent4_end_week,
    reference_data.reference_week + 1 AS target_start_week,
    reference_data.reference_week + 4 AS target_end_week,
    reference_data.has_purchase_26w,
    reference_data.recency_weeks_26w,
    reference_data.recency_days_26w,
    reference_data.frequency_26w,
    reference_data.monetary_26w,
    reference_data.purchase_week_count_26w,
    reference_data.purchase_day_count_26w,
    reference_data.active_week_rate_26w,
    reference_data.average_basket_value_26w,
    reference_data.average_weekly_sales_26w,
    reference_data.average_sales_per_active_week_26w,
    reference_data.discount_amount_26w,
    reference_data.discount_rate_proxy_26w,
    reference_data.paid_product_count_26w,
    reference_data.paid_department_count_26w,
    reference_data.paid_commodity_count_26w,
    reference_data.recency_percentile_26w,
    reference_data.frequency_percentile_26w,
    reference_data.monetary_percentile_26w,
    reference_data.fm_value_index_26w,
    reference_data.rfm_value_index_26w,
    reference_data.prior4_has_purchase,
    reference_data.prior4_valid_basket_count,
    reference_data.prior4_purchase_week_count,
    reference_data.prior4_purchase_day_count,
    reference_data.prior4_sales,
    reference_data.prior4_average_basket_value,
    reference_data.prior4_discount_amount,
    reference_data.prior4_paid_product_count,
    reference_data.prior4_paid_department_count,
    reference_data.prior4_paid_commodity_count,
    reference_data.recent4_has_purchase,
    reference_data.recent4_valid_basket_count,
    reference_data.recent4_purchase_week_count,
    reference_data.recent4_purchase_day_count,
    reference_data.recent4_sales,
    reference_data.recent4_average_basket_value,
    reference_data.recent4_discount_amount,
    reference_data.recent4_paid_product_count,
    reference_data.recent4_paid_department_count,
    reference_data.recent4_paid_commodity_count,
    reference_data.basket_count_change,
    reference_data.purchase_week_count_change,
    reference_data.purchase_day_count_change,
    reference_data.sales_change,
    reference_data.average_basket_value_change,
    reference_data.paid_product_count_change,
    reference_data.paid_department_count_change,
    reference_data.paid_commodity_count_change,
    reference_data.discount_amount_change,
    reference_data.basket_count_change_rate,
    reference_data.sales_change_rate,
    reference_data.average_basket_value_change_rate,
    reference_data.paid_product_count_change_rate,
    reference_data.paid_department_count_change_rate,
    reference_data.paid_commodity_count_change_rate,
    reference_data.discount_amount_change_rate,
    reference_data.basket_change_denominator_status,
    reference_data.sales_change_denominator_status,
    reference_data.average_basket_change_denominator_status,
    reference_data.product_change_denominator_status,
    reference_data.department_change_denominator_status,
    reference_data.commodity_change_denominator_status,
    reference_data.discount_change_denominator_status,
    customer.pre_window_has_snapshot,
    customer.pre_window_has_purchase_26w,
    customer.pre_window_recency_weeks_26w,
    customer.pre_window_recency_days_26w,
    customer.pre_window_frequency_26w,
    customer.pre_window_monetary_26w,
    customer.pre_window_fm_value_index_26w,
    customer.pre_window_rfm_value_index_26w,
    customer.activity_transition,
    customer.activity_state,
    customer.value_state,
    customer.current_value_state,
    customer.customer_state,
    customer.is_became_inactive,
    customer.is_sales_decline_30,
    customer.is_both_decline_30,
    customer.is_both_decline_50,
    CASE
        WHEN comparison_4w.future4_no_purchase THEN 1
        ELSE 0
    END::SMALLINT AS target_no_purchase_4w
FROM mart.household_reference_week AS reference_data
JOIN mart.customer_state AS customer
    ON customer.household_key = reference_data.household_key
   AND customer.reference_week = reference_data.reference_week
JOIN mart.activity_window_comparison AS comparison_4w
    ON comparison_4w.household_key = reference_data.household_key
   AND comparison_4w.reference_week = reference_data.reference_week
   AND comparison_4w.window_weeks = 4
WHERE reference_data.has_complete_future_4w_window;

-- 08-04. 키·제약조건·인덱스
ALTER TABLE mart.model_dataset
    ADD CONSTRAINT pk_model_dataset
    PRIMARY KEY (
        household_key,
        reference_week
    ),
    ADD CONSTRAINT chk_model_dataset_target
    CHECK (target_no_purchase_4w IN (0, 1)),
    ADD CONSTRAINT chk_model_dataset_target_start
    CHECK (target_start_week = reference_week + 1),
    ADD CONSTRAINT chk_model_dataset_target_end
    CHECK (target_end_week = reference_week + 4),
    ADD CONSTRAINT chk_model_dataset_recent_end
    CHECK (recent4_end_week = reference_week),
    ADD CONSTRAINT chk_model_dataset_observation_end
    CHECK (observation_end_week = reference_week);

CREATE INDEX idx_model_dataset_reference_week
    ON mart.model_dataset (reference_week);

ANALYZE mart.model_dataset;

COMMIT;

-- 08-05. 모델 데이터 진단
-- Target 불균형은 진단만 하며 행 삭제·복제·SQL 전처리를 수행하지 않는다.

-- 08-06. 정합성 및 Leakage 검증
DROP TABLE IF EXISTS pg_temp.model_dataset_validation;

CREATE TEMP TABLE model_dataset_validation AS
WITH source_counts AS (
    SELECT
        (SELECT COUNT(*)::BIGINT FROM mart.household_reference_week) AS reference_source_count,
        (SELECT COUNT(*)::BIGINT FROM mart.customer_state) AS customer_state_count,
        (SELECT COUNT(*)::BIGINT
         FROM mart.activity_window_comparison
         WHERE window_weeks = 4) AS target_source_count,
        (SELECT COUNT(*)::BIGINT FROM mart.model_dataset) AS model_count,
        (SELECT COUNT(*)::BIGINT
         FROM mart.household_reference_week
         WHERE has_complete_future_4w_window) AS eligible_source_count
),

model_summary AS (
    SELECT
        COUNT(*) FILTER (
            WHERE household_key IS NULL
               OR reference_week IS NULL
        )::BIGINT AS null_key_count,
        (COUNT(*) - COUNT(DISTINCT (
            household_key,
            reference_week
        )))::BIGINT AS duplicate_key_count,
        COUNT(*) FILTER (
            WHERE target_no_purchase_4w NOT IN (0, 1)
        )::BIGINT AS invalid_target_count,
        COUNT(*) FILTER (
            WHERE target_no_purchase_4w IS NULL
        )::BIGINT AS null_target_count,
        COUNT(*) FILTER (
            WHERE target_start_week <> reference_week + 1
               OR target_end_week <> reference_week + 4
        )::BIGINT AS target_boundary_count,
        COUNT(*) FILTER (
            WHERE observation_end_week > reference_week
               OR recent4_end_week > reference_week
               OR prior4_end_week > reference_week
        )::BIGINT AS observation_boundary_count,
        COUNT(*) FILTER (
            WHERE observation_end_week >= target_start_week
               OR recent4_end_week >= target_start_week
               OR prior4_end_week >= target_start_week
        )::BIGINT AS time_separation_count
    FROM mart.model_dataset
),

customer_join_counts AS (
    SELECT COUNT(*)::BIGINT AS joined_count
    FROM mart.household_reference_week AS reference_data
    JOIN mart.customer_state AS customer
        ON customer.household_key = reference_data.household_key
       AND customer.reference_week = reference_data.reference_week
    WHERE reference_data.has_complete_future_4w_window
),

target_join_counts AS (
    SELECT COUNT(*)::BIGINT AS joined_count
    FROM mart.household_reference_week AS reference_data
    JOIN mart.activity_window_comparison AS comparison_4w
        ON comparison_4w.household_key = reference_data.household_key
       AND comparison_4w.reference_week = reference_data.reference_week
       AND comparison_4w.window_weeks = 4
    WHERE reference_data.has_complete_future_4w_window
),

reference_week_set_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM (
        (SELECT DISTINCT reference_week
         FROM mart.household_reference_week
         WHERE has_complete_future_4w_window
         EXCEPT
         SELECT DISTINCT reference_week FROM mart.model_dataset)
        UNION ALL
        (SELECT DISTINCT reference_week FROM mart.model_dataset
         EXCEPT
         SELECT DISTINCT reference_week
         FROM mart.household_reference_week
         WHERE has_complete_future_4w_window)
    ) AS differences
),

complete_window_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.model_dataset AS model
    JOIN mart.household_reference_week AS source
        ON source.household_key = model.household_key
       AND source.reference_week = model.reference_week
    WHERE NOT source.has_complete_future_4w_window
),

target_source_issues AS (
    SELECT
        COUNT(*) FILTER (
            WHERE model.target_no_purchase_4w IS DISTINCT FROM CASE
                WHEN comparison_4w.future4_no_purchase THEN 1
                ELSE 0
            END::SMALLINT
        )::BIGINT AS target_issues,
        COUNT(*) FILTER (
            WHERE model.target_no_purchase_4w = 1
              AND comparison_4w.future4_valid_basket_count <> 0
               OR model.target_no_purchase_4w = 0
              AND comparison_4w.future4_valid_basket_count <= 0
        )::BIGINT AS complement_issues
    FROM mart.model_dataset AS model
    JOIN mart.activity_window_comparison AS comparison_4w
        ON comparison_4w.household_key = model.household_key
       AND comparison_4w.reference_week = model.reference_week
       AND comparison_4w.window_weeks = 4
),

reference_feature_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.model_dataset AS model
    JOIN mart.household_reference_week AS source
        ON source.household_key = model.household_key
       AND source.reference_week = model.reference_week
    WHERE model.recency_weeks_26w IS DISTINCT FROM source.recency_weeks_26w
       OR model.frequency_26w IS DISTINCT FROM source.frequency_26w
       OR model.monetary_26w IS DISTINCT FROM source.monetary_26w
       OR model.prior4_valid_basket_count IS DISTINCT FROM source.prior4_valid_basket_count
       OR model.recent4_valid_basket_count IS DISTINCT FROM source.recent4_valid_basket_count
       OR model.prior4_sales IS DISTINCT FROM source.prior4_sales
       OR model.recent4_sales IS DISTINCT FROM source.recent4_sales
       OR model.basket_count_change IS DISTINCT FROM source.basket_count_change
       OR model.sales_change IS DISTINCT FROM source.sales_change
       OR model.basket_count_change_rate IS DISTINCT FROM source.basket_count_change_rate
       OR model.sales_change_rate IS DISTINCT FROM source.sales_change_rate
       OR model.rfm_value_index_26w IS DISTINCT FROM source.rfm_value_index_26w
),

customer_feature_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.model_dataset AS model
    JOIN mart.customer_state AS source
        ON source.household_key = model.household_key
       AND source.reference_week = model.reference_week
    WHERE model.pre_window_frequency_26w IS DISTINCT FROM source.pre_window_frequency_26w
       OR model.pre_window_monetary_26w IS DISTINCT FROM source.pre_window_monetary_26w
       OR model.pre_window_rfm_value_index_26w IS DISTINCT FROM source.pre_window_rfm_value_index_26w
       OR model.activity_state IS DISTINCT FROM source.activity_state
       OR model.value_state IS DISTINCT FROM source.value_state
       OR model.customer_state IS DISTINCT FROM source.customer_state
),

denominator_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM mart.model_dataset AS model
    JOIN mart.household_reference_week AS source
        ON source.household_key = model.household_key
       AND source.reference_week = model.reference_week
    WHERE model.basket_change_denominator_status IS DISTINCT FROM source.basket_change_denominator_status
       OR model.basket_count_change_rate IS DISTINCT FROM source.basket_count_change_rate
       OR model.sales_change_denominator_status IS DISTINCT FROM source.sales_change_denominator_status
       OR model.sales_change_rate IS DISTINCT FROM source.sales_change_rate
       OR model.average_basket_change_denominator_status IS DISTINCT FROM source.average_basket_change_denominator_status
       OR model.average_basket_value_change_rate IS DISTINCT FROM source.average_basket_value_change_rate
       OR model.product_change_denominator_status IS DISTINCT FROM source.product_change_denominator_status
       OR model.paid_product_count_change_rate IS DISTINCT FROM source.paid_product_count_change_rate
       OR model.department_change_denominator_status IS DISTINCT FROM source.department_change_denominator_status
       OR model.paid_department_count_change_rate IS DISTINCT FROM source.paid_department_count_change_rate
       OR model.commodity_change_denominator_status IS DISTINCT FROM source.commodity_change_denominator_status
       OR model.paid_commodity_count_change_rate IS DISTINCT FROM source.paid_commodity_count_change_rate
       OR model.discount_change_denominator_status IS DISTINCT FROM source.discount_change_denominator_status
       OR model.discount_amount_change_rate IS DISTINCT FROM source.discount_amount_change_rate
),

future_feature_column_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM information_schema.columns
    WHERE table_schema = 'mart'
      AND table_name = 'model_dataset'
      AND (
            column_name IN (
                'future4_valid_basket_count',
                'future4_sales',
                'future4_has_purchase',
                'future4_no_purchase',
                'purchase_rate',
                'weighted_purchase_rate',
                'predicted_probability',
                'no_purchase_probability'
            )
            OR column_name LIKE 'future8\_%' ESCAPE '\'
            OR column_name LIKE 'future12\_%' ESCAPE '\'
        )
),

model_split_column_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM information_schema.columns
    WHERE table_schema = 'mart'
      AND table_name = 'model_dataset'
      AND column_name IN (
          'model_split',
          'train_flag',
          'validation_flag',
          'test_flag'
      )
),

post_outcome_column_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM information_schema.columns
    WHERE table_schema = 'mart'
      AND table_name = 'model_dataset'
      AND (
            column_name LIKE '%purchase_rate%'
            OR column_name LIKE '%baseline_ratio%'
            OR column_name LIKE '%weighted%'
        )
),

required_feature_issues AS (
    SELECT 13 - COUNT(*)::BIGINT AS issue_count
    FROM information_schema.columns
    WHERE table_schema = 'mart'
      AND table_name = 'model_dataset'
      AND column_name IN (
          'recent4_valid_basket_count',
          'prior4_valid_basket_count',
          'recent4_sales',
          'prior4_sales',
          'basket_count_change',
          'basket_count_change_rate',
          'sales_change',
          'sales_change_rate',
          'frequency_26w',
          'monetary_26w',
          'pre_window_frequency_26w',
          'pre_window_monetary_26w',
          'activity_state'
      )
),

state_cohort_overlap_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM (
        SELECT
            cohort.activity_state
        FROM (
            SELECT
                activity_state,
                SUM(cohort_household_count)::BIGINT AS cohort_count,
                SUM(purchased_household_count)::BIGINT AS purchase_count,
                SUM(purchased_household_count)::NUMERIC
                    / NULLIF(SUM(cohort_household_count), 0) AS purchase_rate
            FROM mart.state_cohort
            WHERE elapsed_weeks = 4
            GROUP BY activity_state
        ) AS cohort
        JOIN (
            SELECT
                model.activity_state,
                COUNT(*)::BIGINT AS cohort_count,
                COUNT(*) FILTER (
                    WHERE model.target_no_purchase_4w = 0
                )::BIGINT AS purchase_count,
                COUNT(*) FILTER (
                    WHERE model.target_no_purchase_4w = 0
                )::NUMERIC / NULLIF(COUNT(*), 0) AS purchase_rate
            FROM mart.model_dataset AS model
            JOIN (
                SELECT DISTINCT reference_week
                FROM mart.state_cohort
            ) AS overlap_weeks
                ON overlap_weeks.reference_week = model.reference_week
            GROUP BY model.activity_state
        ) AS model
            ON model.activity_state = cohort.activity_state
        WHERE model.cohort_count IS DISTINCT FROM cohort.cohort_count
           OR model.purchase_count IS DISTINCT FROM cohort.purchase_count
           OR model.purchase_rate IS DISTINCT FROM cohort.purchase_rate
    ) AS invalid
),

diagnostic_07b_overlap_issues AS (
    SELECT COUNT(*)::BIGINT AS issue_count
    FROM (
        SELECT profile.activity_state
        FROM mart.diag_active_both_state_profile AS profile
        JOIN (
            SELECT
                model.activity_state,
                COUNT(*) FILTER (
                    WHERE model.target_no_purchase_4w = 1
                )::BIGINT AS no_purchase_count
            FROM mart.model_dataset AS model
            JOIN (
                SELECT DISTINCT reference_week
                FROM mart.state_cohort
            ) AS overlap_weeks
                ON overlap_weeks.reference_week = model.reference_week
            WHERE model.activity_state IN (
                'ACTIVE_BOTH_NO_MAJOR_DECLINE',
                'ACTIVE_BOTH_SALES_DECLINE',
                'ACTIVE_BOTH_STRONG_DECLINE',
                'ACTIVE_BOTH_VERY_STRONG_DECLINE'
            )
            GROUP BY model.activity_state
        ) AS model
            ON model.activity_state = profile.activity_state
        WHERE model.no_purchase_count IS DISTINCT FROM profile.future4_no_purchase_count
    ) AS invalid
),

week_class_issues AS (
    SELECT
        COUNT(*) FILTER (
            WHERE row_count = 0
        )::BIGINT AS empty_week_count,
        COUNT(*) FILTER (
            WHERE class_count < 2
        )::BIGINT AS single_class_week_count
    FROM (
        SELECT
            reference_week,
            COUNT(*)::BIGINT AS row_count,
            COUNT(DISTINCT target_no_purchase_4w)::BIGINT AS class_count
        FROM mart.model_dataset
        GROUP BY reference_week
    ) AS weekly
),

checks AS (
    SELECT
        'household_reference_week_source_nonempty'::TEXT AS check_name,
        'FAIL'::TEXT AS severity,
        CASE WHEN reference_source_count > 0 THEN 0 ELSE 1 END::BIGINT AS issue_count,
        'household_reference_week 행 존재'::TEXT AS detail
    FROM source_counts

    UNION ALL

    SELECT 'customer_state_source_nonempty', 'FAIL', CASE WHEN customer_state_count > 0 THEN 0 ELSE 1 END, 'customer_state 행 존재'
    FROM source_counts

    UNION ALL

    SELECT 'target_source_nonempty', 'FAIL', CASE WHEN target_source_count > 0 THEN 0 ELSE 1 END, 'window=4 Target 원천 행 존재'
    FROM source_counts

    UNION ALL

    SELECT 'model_dataset_nonempty', 'FAIL', CASE WHEN model_count > 0 THEN 0 ELSE 1 END, 'model_dataset 행 존재'
    FROM source_counts

    UNION ALL

    SELECT 'primary_key_integrity', 'FAIL', null_key_count + duplicate_key_count, '가구×기준주차 키 NULL 및 중복'
    FROM model_summary

    UNION ALL

    SELECT 'source_row_count_reconciliation', 'FAIL', ABS(model_count - eligible_source_count), '미래4주 완전 관찰 원천 행 수 대사'
    FROM source_counts

    UNION ALL

    SELECT 'customer_state_one_to_one_reconciliation', 'FAIL', ABS(joined_count - eligible_source_count), 'customer_state 1:1 JOIN'
    FROM customer_join_counts
    CROSS JOIN source_counts

    UNION ALL

    SELECT 'target_one_to_one_reconciliation', 'FAIL', ABS(joined_count - eligible_source_count), 'window=4 Target 1:1 JOIN'
    FROM target_join_counts
    CROSS JOIN source_counts

    UNION ALL

    SELECT 'reference_week_range_reconciliation', 'FAIL', issue_count, '미래4주 완전 관찰 기준주차 집합'
    FROM reference_week_set_issues

    UNION ALL

    SELECT 'complete_future4_window_integrity', 'FAIL', issue_count, '미래4주 완전 관찰행만 포함'
    FROM complete_window_issues

    UNION ALL

    SELECT 'target_value_integrity', 'FAIL', invalid_target_count, 'Target 0·1 허용값'
    FROM model_summary

    UNION ALL

    SELECT 'target_null_integrity', 'FAIL', null_target_count, 'Target NULL 부재'
    FROM model_summary

    UNION ALL

    SELECT 'target_source_reconciliation', 'FAIL', target_issues, 'future4_no_purchase Target 대사'
    FROM target_source_issues

    UNION ALL

    SELECT 'target_complement_reconciliation', 'FAIL', complement_issues, '유효 장바구니 수와 Target 보수 관계'
    FROM target_source_issues

    UNION ALL

    SELECT 'target_boundary_integrity', 'FAIL', target_boundary_count, 'Target +1주~+4주 경계'
    FROM model_summary

    UNION ALL

    SELECT 'observation_boundary_integrity', 'FAIL', observation_boundary_count, 'Feature 관찰창 기준주차 이내'
    FROM model_summary

    UNION ALL

    SELECT 'strict_time_separation', 'FAIL', time_separation_count, 'Feature 창과 Target 창 엄격 분리'
    FROM model_summary

    UNION ALL

    SELECT 'household_reference_feature_reconciliation', 'FAIL', issue_count, '핵심 과거 Feature 원천 대사'
    FROM reference_feature_issues

    UNION ALL

    SELECT 'customer_state_feature_reconciliation', 'FAIL', issue_count, 'PRE_WINDOW 및 상태 Feature 대사'
    FROM customer_feature_issues

    UNION ALL

    SELECT 'denominator_null_integrity', 'FAIL', issue_count, '변화율과 분모 상태 원천 대사'
    FROM denominator_issues

    UNION ALL

    SELECT 'no_future_feature_columns', 'FAIL', issue_count, '미래 결과·확률 컬럼 부재'
    FROM future_feature_column_issues

    UNION ALL

    SELECT 'no_model_split_columns', 'FAIL', issue_count, 'SQL Model Split 컬럼 부재'
    FROM model_split_column_issues

    UNION ALL

    SELECT 'no_post_outcome_diagnostic_join', 'FAIL', issue_count, '07·07B 사후 집계 Feature 부재'
    FROM post_outcome_column_issues

    UNION ALL

    SELECT 'required_07b_feature_columns', 'FAIL', issue_count, '07B 핵심 원변수 13개 보존'
    FROM required_feature_issues

    UNION ALL

    SELECT 'state_cohort_4w_overlap_reconciliation', 'FAIL', issue_count, '07 +4주 구매 결과 대사'
    FROM state_cohort_overlap_issues

    UNION ALL

    SELECT 'diagnostic_07b_overlap_reconciliation', 'FAIL', issue_count, '07B ACTIVE_BOTH 미구매 건수 대사'
    FROM diagnostic_07b_overlap_issues

    UNION ALL

    SELECT 'target_by_week_nonempty', 'FAIL', empty_week_count, '모든 기준주차 관측행 존재'
    FROM week_class_issues

    UNION ALL

    SELECT 'class_presence_by_week', 'WARN', single_class_week_count, '주차별 Target 두 클래스 존재 여부'
    FROM week_class_issues
)
SELECT
    check_name,
    severity,
    issue_count,
    detail,
    CASE
        WHEN issue_count = 0 THEN 'PASS'
        WHEN severity = 'WARN' THEN 'WARN'
        ELSE 'FAIL'
    END AS status
FROM checks

UNION ALL

SELECT
    'validation_fail_summary',
    'FAIL',
    COALESCE(SUM(issue_count) FILTER (
        WHERE issue_count > 0
          AND severity = 'FAIL'
    ), 0),
    FORMAT(
        'FAIL checks=%s, FAIL issue_count sum=%s',
        COUNT(*) FILTER (
            WHERE issue_count > 0
              AND severity = 'FAIL'
        ),
        COALESCE(SUM(issue_count) FILTER (
            WHERE issue_count > 0
              AND severity = 'FAIL'
        ), 0)
    ),
    CASE
        WHEN COUNT(*) FILTER (
            WHERE issue_count > 0
              AND severity = 'FAIL'
        ) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END
FROM checks;

-- 08-07. 결과 확인
-- 08-07-01. 모델 데이터 전체 구조
SELECT
    COUNT(*)::BIGINT AS total_row_count,
    COUNT(DISTINCT household_key)::BIGINT AS distinct_household_count,
    COUNT(DISTINCT reference_week)::BIGINT AS reference_week_count,
    MIN(reference_week) AS min_reference_week,
    MAX(reference_week) AS max_reference_week,
    MIN(target_start_week) AS min_target_start_week,
    MAX(target_end_week) AS max_target_end_week,
    (
        SELECT COUNT(*)::BIGINT
        FROM information_schema.columns
        WHERE table_schema = 'mart'
          AND table_name = 'model_dataset'
    ) AS column_count
FROM mart.model_dataset;

-- 08-07-02. Target 전체 분포
SELECT
    COUNT(*)::BIGINT AS total_row_count,
    COUNT(*) FILTER (
        WHERE target_no_purchase_4w = 1
    )::BIGINT AS target_no_purchase_count,
    COUNT(*) FILTER (
        WHERE target_no_purchase_4w = 0
    )::BIGINT AS target_purchase_count,
    COUNT(*) FILTER (
        WHERE target_no_purchase_4w = 1
    )::NUMERIC / NULLIF(COUNT(*), 0) AS target_no_purchase_rate,
    COUNT(*) FILTER (
        WHERE target_no_purchase_4w = 0
    )::NUMERIC / NULLIF(COUNT(*), 0) AS target_purchase_rate
FROM mart.model_dataset;

-- 08-07-03. 개발구간 Target 안정성 확인
SELECT
    reference_week,
    COUNT(*)::BIGINT AS row_count,
    COUNT(*) FILTER (
        WHERE target_no_purchase_4w = 1
    )::BIGINT AS target_no_purchase_count,
    COUNT(*) FILTER (
        WHERE target_no_purchase_4w = 1
    )::NUMERIC / NULLIF(COUNT(*), 0) AS target_no_purchase_rate
FROM mart.model_dataset
WHERE reference_week <= (
    SELECT MAX(reference_week)
    FROM mart.state_cohort
)
GROUP BY reference_week
ORDER BY reference_week;

-- 08-07-04. 핵심 Feature NULL 현황
WITH long_features AS (
    SELECT
        feature.feature_name,
        feature.feature_value
    FROM mart.model_dataset AS model
    CROSS JOIN LATERAL (
        VALUES
            ('recency_weeks_26w', model.recency_weeks_26w::NUMERIC),
            ('rfm_value_index_26w', model.rfm_value_index_26w::NUMERIC),
            ('basket_count_change_rate', model.basket_count_change_rate::NUMERIC),
            ('sales_change_rate', model.sales_change_rate::NUMERIC),
            ('pre_window_frequency_26w', model.pre_window_frequency_26w::NUMERIC),
            ('pre_window_monetary_26w', model.pre_window_monetary_26w::NUMERIC),
            ('pre_window_rfm_value_index_26w', model.pre_window_rfm_value_index_26w::NUMERIC)
    ) AS feature(
        feature_name,
        feature_value
    )
)
SELECT
    feature_name,
    COUNT(*) FILTER (
        WHERE feature_value IS NULL
    )::BIGINT AS null_count,
    COUNT(*) FILTER (
        WHERE feature_value IS NULL
    )::NUMERIC / NULLIF(COUNT(*), 0) AS null_share
FROM long_features
GROUP BY feature_name
ORDER BY feature_name;

-- 08-07-05. 07B 핵심 Feature 존재 및 범위
WITH long_features AS (
    SELECT
        feature.feature_name,
        feature.feature_value
    FROM mart.model_dataset AS model
    CROSS JOIN LATERAL (
        VALUES
            ('recent4_valid_basket_count', model.recent4_valid_basket_count::NUMERIC),
            ('prior4_valid_basket_count', model.prior4_valid_basket_count::NUMERIC),
            ('recent4_sales', model.recent4_sales::NUMERIC),
            ('prior4_sales', model.prior4_sales::NUMERIC),
            ('basket_count_change_rate', model.basket_count_change_rate::NUMERIC),
            ('sales_change_rate', model.sales_change_rate::NUMERIC),
            ('frequency_26w', model.frequency_26w::NUMERIC),
            ('monetary_26w', model.monetary_26w::NUMERIC)
    ) AS feature(
        feature_name,
        feature_value
    )
)
SELECT
    feature_name,
    COUNT(feature_value)::BIGINT AS nonnull_count,
    MIN(feature_value) AS minimum,
    MAX(feature_value) AS maximum,
    AVG(feature_value) AS average
FROM long_features
GROUP BY feature_name
ORDER BY feature_name;

-- 08-07-06. 정합성 검증
SELECT
    check_name,
    severity,
    issue_count,
    detail,
    status
FROM model_dataset_validation
ORDER BY check_name;