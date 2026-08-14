# ============================================================
# 01_profile
# 원본 데이터 구조 및 품질 프로파일링
# ============================================================

from __future__ import annotations

import logging
import sqlite3
import sys
import tempfile
import time
from collections import Counter
from pathlib import Path
from typing import Any, Iterable

import pandas as pd


BASE_DIR = Path(__file__).resolve().parent


RAW_DIR = BASE_DIR


OUTPUT_DIR = BASE_DIR / "outputs" / "profiling"

TRANSACTION_FILE = BASE_DIR / "transaction_data.csv"
PRODUCT_FILE = BASE_DIR / "product.csv"
CHUNK_SIZE = 200_000

TRANSACTION_REQUIRED = [
    "HOUSEHOLD_KEY", "BASKET_ID", "DAY", "PRODUCT_ID", "QUANTITY",
    "SALES_VALUE", "STORE_ID", "RETAIL_DISC", "TRANS_TIME", "WEEK_NO",
    "COUPON_DISC", "COUPON_MATCH_DISC",
]
PRODUCT_REQUIRED = [
    "PRODUCT_ID", "MANUFACTURER", "DEPARTMENT", "BRAND", "COMMODITY_DESC",
    "SUB_COMMODITY_DESC", "CURR_SIZE_OF_PRODUCT",
]
ID_COLUMNS = ["HOUSEHOLD_KEY", "BASKET_ID", "PRODUCT_ID", "STORE_ID"]
BASKET_ATTRIBUTES = ["HOUSEHOLD_KEY", "STORE_ID", "DAY", "WEEK_NO", "TRANS_TIME"]
VALUE_COLUMNS = ["QUANTITY", "SALES_VALUE", "RETAIL_DISC", "COUPON_DISC", "COUPON_MATCH_DISC"]
CATEGORY_COLUMNS = ["DEPARTMENT", "BRAND", "COMMODITY_DESC", "SUB_COMMODITY_DESC", "CURR_SIZE_OF_PRODUCT"]
FILE_COLUMNS = ["file_name", "file_size_mb", "row_count", "column_count", "duplicate_row_count"]
PROFILE_COLUMNS = ["file_name", "column_name", "inferred_dtype", "row_count", "null_count", "null_rate", "unique_count", "min_value", "max_value"]
CHECK_COLUMNS = ["check_group", "check_name", "result_value", "status", "description"]
TIME_COLUMNS = ["min_day", "max_day", "min_week", "max_week", "observed_week_count", "missing_week_count", "missing_week_list", "valid_reference_week_count", "first_valid_reference_week", "last_valid_reference_week", "valid_reference_week_list"]


def column_lookup(columns: Iterable[str]) -> dict[str, str]:
    """원본 이름을 보존하면서 대소문자를 무시하는 컬럼 조회표를 만든다."""
    return {str(column).casefold(): str(column) for column in columns}


def validate_file(path: Path, required: list[str]) -> tuple[list[str], dict[str, str]]:
    """파일 존재와 필수 컬럼을 검사하고 실제 컬럼명 매핑을 반환한다."""
    if not path.is_file():
        logging.error("입력 검증 실패 | 파일명=%s | 누락 컬럼=확인 불가 | 실제 컬럼=확인 불가", path.name)
        raise FileNotFoundError(f"입력 파일이 없습니다: {path}")
    columns = list(pd.read_csv(path, nrows=0).columns)
    lookup = column_lookup(columns)
    missing = [name for name in required if name.casefold() not in lookup]
    if missing:
        logging.error("입력 검증 실패 | 파일명=%s | 누락 컬럼=%s | 실제 컬럼=%s", path.name, missing, columns)
        raise ValueError(f"{path.name} 필수 컬럼 누락: {missing}")
    return columns, {name: lookup[name.casefold()] for name in required}


def create_database(path: str) -> sqlite3.Connection:
    """디스크 기반 임시 SQLite 데이터베이스와 집계 테이블을 준비한다."""
    connection = sqlite3.connect(path)
    connection.execute("PRAGMA journal_mode=OFF")
    connection.execute("PRAGMA synchronous=OFF")
    connection.executescript("""
        CREATE TABLE row_patterns (hash1 INTEGER NOT NULL, hash2 INTEGER NOT NULL, row_count INTEGER NOT NULL, PRIMARY KEY (hash1, hash2));
        CREATE TABLE combo_patterns (basket_id TEXT NOT NULL, product_id TEXT NOT NULL, hash1 INTEGER NOT NULL, hash2 INTEGER NOT NULL, row_count INTEGER NOT NULL, PRIMARY KEY (basket_id, product_id, hash1, hash2));
        CREATE TABLE basket_attributes (basket_id TEXT NOT NULL, attribute_name TEXT NOT NULL, attribute_value TEXT NOT NULL, PRIMARY KEY (basket_id, attribute_name, attribute_value));
        CREATE TABLE household_baskets (household_key TEXT NOT NULL, basket_id TEXT NOT NULL, PRIMARY KEY (household_key, basket_id));
        CREATE TABLE household_weeks (household_key TEXT NOT NULL, week_no INTEGER NOT NULL, PRIMARY KEY (household_key, week_no));
        CREATE TABLE household_totals (household_key TEXT PRIMARY KEY, total_quantity REAL NOT NULL, total_sales REAL NOT NULL, first_week INTEGER, last_week INTEGER);
        CREATE TABLE column_uniques (column_name TEXT NOT NULL, value_key TEXT NOT NULL, PRIMARY KEY (column_name, value_key));
    """)
    return connection


def sql_text(value: Any, numeric: bool = False) -> str:
    """SQLite 키 비교에 사용할 안정적인 텍스트 표현을 반환한다."""
    if numeric:
        return float(value).hex()
    return str(value)


def hash_frame(frame: pd.DataFrame) -> tuple[pd.Series, pd.Series]:
    """동일 행을 식별할 결정적인 이중 64비트 해시를 계산한다."""
    # 서로 다른 컬럼 순서와 키를 사용한 이중 해시는 충돌 가능성을 매우 낮추지만,
    # 이론적으로 충돌 가능성이 0은 아닌 확률적 행 식별 방식이다.
    first = pd.util.hash_pandas_object(frame, index=False, hash_key="profile-key-0001")
    second = pd.util.hash_pandas_object(frame.iloc[:, ::-1], index=False, hash_key="profile-key-0002")
    # SQLite INTEGER는 signed 64비트이므로 최상위 비트를 뒤집어 범위만 변환한다.
    first_signed = (first.astype("uint64") ^ (1 << 63)).astype("int64")
    second_signed = (second.astype("uint64") ^ (1 << 63)).astype("int64")
    return first_signed, second_signed


def upsert_counts(connection: sqlite3.Connection, table: str, columns: list[str], rows: Iterable[tuple[Any, ...]]) -> None:
    """청크에서 축소된 출현 횟수를 명시적 트랜잭션으로 일괄 UPSERT한다."""
    keys = ",".join(columns)
    placeholders = ",".join("?" for _ in columns)
    conflict = ",".join(columns[:-1])
    sql = f"INSERT INTO {table} ({keys}) VALUES ({placeholders}) ON CONFLICT ({conflict}) DO UPDATE SET row_count=row_count+excluded.row_count"
    with connection:
        connection.executemany(sql, rows)


def insert_ignore(connection: sqlite3.Connection, table: str, columns: list[str], rows: Iterable[tuple[Any, ...]]) -> None:
    """청크 내부에서 중복 제거된 키를 SQLite에 일괄 저장한다."""
    sql = f"INSERT OR IGNORE INTO {table} ({','.join(columns)}) VALUES ({','.join('?' for _ in columns)})"
    with connection:
        connection.executemany(sql, rows)


def initialise_stats(columns: list[str]) -> dict[str, dict[str, Any]]:
    """컬럼별 청크 누적 통계를 초기화한다."""
    return {column: {"dtypes": set(), "nulls": 0, "numeric": True, "min": None, "max": None} for column in columns}


def update_column_stats(connection: sqlite3.Connection, stats: dict[str, dict[str, Any]], frame: pd.DataFrame) -> None:
    """컬럼 통계와 청크 내부 고유값을 누적한다."""
    for column in frame.columns:
        series = frame[column]
        item = stats[column]
        item["dtypes"].add(str(series.dtype))
        item["nulls"] += int(series.isna().sum())
        numeric = pd.api.types.is_numeric_dtype(series.dtype)
        item["numeric"] = item["numeric"] and numeric
        if numeric and series.notna().any():
            low, high = series.min(), series.max()
            item["min"] = low if item["min"] is None else min(item["min"], low)
            item["max"] = high if item["max"] is None else max(item["max"], high)
        unique_values = series.dropna().drop_duplicates()
        # 전체 행 대신 청크 내 고유값만 디스크에 저장하여 정확성과 메모리 사용량을 함께 관리한다.
        insert_ignore(connection, "column_uniques", ["column_name", "value_key"],
                      ((column, sql_text(value, numeric)) for value in unique_values.array))


def inferred_dtype(item: dict[str, Any]) -> str:
    """청크별 pandas 추론 자료형을 결정적인 문자열로 합친다."""
    values = sorted(item["dtypes"])
    return values[0] if len(values) == 1 else f"mixed({','.join(values)})"


def transaction_dtypes(names: dict[str, str]) -> dict[str, str]:
    """청크마다 ID의 표현이 달라지는 것을 막는 문자열 자료형 설정을 만든다."""
    return {names[column]: "string" for column in ID_COLUMNS}


def process_transaction(path: Path, columns: list[str], names: dict[str, str], connection: sqlite3.Connection) -> dict[str, Any]:
    """거래 파일을 한 번 순차적으로 읽으며 벡터·그룹 집계를 수행한다."""
    started = time.perf_counter()
    stats = initialise_stats(columns)
    row_count = 0
    id_nulls = Counter()
    id_values = {column: set() for column in ID_COLUMNS}
    attribute_nulls = Counter()
    signs = {column: Counter() for column in VALUE_COLUMNS}
    product_rows = Counter()
    weeks: set[int] = set()
    days: set[Any] = set()
    day_weeks: dict[Any, set[int]] = {}

    reader = pd.read_csv(path, chunksize=CHUNK_SIZE, dtype=transaction_dtypes(names))
    for number, chunk in enumerate(reader, 1):
        logging.info("transaction_data.csv 청크 %d 처리: %s행", number, f"{len(chunk):,}")
        row_count += len(chunk)
        update_column_stats(connection, stats, chunk)

        hash1, hash2 = hash_frame(chunk)
        hashes = pd.DataFrame({"hash1": hash1, "hash2": hash2})
        grouped_hashes = hashes.value_counts(sort=False).rename("row_count").reset_index()
        upsert_counts(connection, "row_patterns", ["hash1", "hash2", "row_count"], grouped_hashes.itertuples(index=False, name=None))

        basket = names["BASKET_ID"]
        product = names["PRODUCT_ID"]
        valid_combo = chunk[basket].notna() & chunk[product].notna()
        combo = pd.DataFrame({"basket_id": chunk.loc[valid_combo, basket], "product_id": chunk.loc[valid_combo, product],
                              "hash1": hash1.loc[valid_combo], "hash2": hash2.loc[valid_combo]})
        combo_grouped = combo.value_counts(sort=False).rename("row_count").reset_index()
        upsert_counts(connection, "combo_patterns", ["basket_id", "product_id", "hash1", "hash2", "row_count"], combo_grouped.itertuples(index=False, name=None))

        for attribute in BASKET_ATTRIBUTES:
            actual = names[attribute]
            attribute_nulls[attribute] += int(chunk[actual].isna().sum())
            valid = chunk[basket].notna() & chunk[actual].notna()
            pairs = chunk.loc[valid, [basket, actual]].drop_duplicates()
            insert_ignore(connection, "basket_attributes", ["basket_id", "attribute_name", "attribute_value"],
                          ((str(a), attribute, sql_text(v)) for a, v in pairs.itertuples(index=False, name=None)))

        for identifier in ID_COLUMNS:
            series = chunk[names[identifier]]
            id_nulls[identifier] += int(series.isna().sum())
            id_values[identifier].update(series.dropna().unique())
        product_rows.update(chunk[product].dropna().value_counts(sort=False).to_dict())

        numeric_cache = {column: pd.to_numeric(chunk[names[column]], errors="coerce")
                         for column in VALUE_COLUMNS + ["DAY", "WEEK_NO"]}
        for column in VALUE_COLUMNS:
            numeric = numeric_cache[column]
            signs[column]["missing"] += int(numeric.isna().sum())
            signs[column]["negative"] += int(numeric.lt(0).sum())
            signs[column]["zero"] += int(numeric.eq(0).sum())
            signs[column]["positive"] += int(numeric.gt(0).sum())

        week_numeric = numeric_cache["WEEK_NO"].dropna().astype("int64")
        day_numeric = numeric_cache["DAY"]
        weeks.update(week_numeric.unique())
        days.update(day_numeric.dropna().unique())
        day_week_pairs = pd.DataFrame({"day": day_numeric, "week": numeric_cache["WEEK_NO"]}).dropna().drop_duplicates()
        for day, week_values in day_week_pairs.groupby("day", sort=False)["week"]:
            day_weeks.setdefault(day, set()).update(week_values.astype("int64").unique())

        household = names["HOUSEHOLD_KEY"]
        valid_hb = chunk[household].notna() & chunk[basket].notna()
        hb = chunk.loc[valid_hb, [household, basket]].drop_duplicates()
        insert_ignore(connection, "household_baskets", ["household_key", "basket_id"], hb.itertuples(index=False, name=None))
        valid_hw = chunk[household].notna() & numeric_cache["WEEK_NO"].notna()
        hw = pd.DataFrame({"household_key": chunk.loc[valid_hw, household],
                           "week_no": numeric_cache["WEEK_NO"].loc[valid_hw].astype("int64")}).drop_duplicates()
        insert_ignore(connection, "household_weeks", ["household_key", "week_no"], hw.itertuples(index=False, name=None))

        household_frame = pd.DataFrame({"household_key": chunk[household], "quantity": numeric_cache["QUANTITY"],
                                        "sales": numeric_cache["SALES_VALUE"], "week": numeric_cache["WEEK_NO"]}).dropna(subset=["household_key"])
        aggregate = household_frame.groupby("household_key", sort=False).agg(total_quantity=("quantity", "sum"), total_sales=("sales", "sum"), first_week=("week", "min"), last_week=("week", "max")).reset_index()
        sql = """INSERT INTO household_totals VALUES (?, ?, ?, ?, ?)
                 ON CONFLICT(household_key) DO UPDATE SET
                 total_quantity=total_quantity+excluded.total_quantity,
                 total_sales=total_sales+excluded.total_sales,
                 first_week=CASE WHEN first_week IS NULL THEN excluded.first_week WHEN excluded.first_week IS NULL THEN first_week ELSE MIN(first_week, excluded.first_week) END,
                 last_week=CASE WHEN last_week IS NULL THEN excluded.last_week WHEN excluded.last_week IS NULL THEN last_week ELSE MAX(last_week, excluded.last_week) END"""
        with connection:
            connection.executemany(sql, aggregate.itertuples(index=False, name=None))
        del chunk, hashes, grouped_hashes, combo, combo_grouped, numeric_cache, household_frame, aggregate

    logging.info("transaction_data.csv 처리시간: %.3f초", time.perf_counter() - started)
    return {"stats": stats, "row_count": row_count, "columns": columns, "id_nulls": id_nulls,
            "id_values": id_values, "attribute_nulls": attribute_nulls, "signs": signs,
            "product_rows": product_rows, "weeks": weeks, "days": days, "day_weeks": day_weeks}


def process_product(path: Path, columns: list[str], names: dict[str, str]) -> dict[str, Any]:
    """상대적으로 작은 상품 파일의 전체 품질 통계를 계산한다."""
    started = time.perf_counter()
    frame = pd.read_csv(path, dtype={names["PRODUCT_ID"]: "string"})
    stats = initialise_stats(columns)
    unique_counts: dict[str, int] = {}
    for column in columns:
        series = frame[column]
        item = stats[column]
        item["dtypes"].add(str(series.dtype))
        item["nulls"] = int(series.isna().sum())
        item["numeric"] = pd.api.types.is_numeric_dtype(series.dtype)
        if item["numeric"] and series.notna().any():
            item["min"], item["max"] = series.min(), series.max()
        unique_counts[column] = int(series.nunique(dropna=True))
    product_id = names["PRODUCT_ID"]
    counts = frame[product_id].value_counts(dropna=True)
    duplicate_ids = int((counts - 1).clip(lower=0).sum())
    information = [column for column in columns if column != product_id]
    conflicting = int(frame.dropna(subset=[product_id]).groupby(product_id, sort=False)[information].nunique(dropna=False).gt(1).any(axis=1).sum())
    result = {"frame": frame, "stats": stats, "unique_counts": unique_counts,
              "row_count": len(frame), "duplicate_rows": int(frame.duplicated().sum()),
              "product_ids": set(frame[product_id].dropna().unique()), "product_nulls": int(frame[product_id].isna().sum()),
              "duplicate_ids": duplicate_ids, "conflicting_ids": conflicting}
    logging.info("product.csv 처리시간: %.3f초", time.perf_counter() - started)
    return result


def query_scalar(connection: sqlite3.Connection, sql: str) -> int:
    """단일 정수 SQLite 집계 결과를 반환한다."""
    value = connection.execute(sql).fetchone()[0]
    return int(value or 0)


def finalise_sqlite(connection: sqlite3.Connection) -> dict[str, Any]:
    """SQLite에 누적된 전체 파일 기준 중복·일관성·가구 통계를 확정한다."""
    connection.executescript("""
        CREATE INDEX idx_combo_ids ON combo_patterns (basket_id, product_id);
        CREATE INDEX idx_basket_attribute ON basket_attributes (basket_id, attribute_name);
    """)
    duplicate_rows = query_scalar(connection, "SELECT SUM(row_count - 1) FROM row_patterns WHERE row_count > 1")
    combo_sql = "SELECT basket_id, product_id, SUM(row_count) total_rows, COUNT(*) patterns FROM combo_patterns GROUP BY basket_id, product_id"
    combo_duplicates = query_scalar(connection, f"SELECT SUM(total_rows - 1) FROM ({combo_sql}) WHERE total_rows >= 2")
    combo_exact = query_scalar(connection, f"SELECT SUM(total_rows - patterns) FROM ({combo_sql})")
    combo_different = query_scalar(connection, f"SELECT SUM(patterns - 1) FROM ({combo_sql}) WHERE patterns >= 2")
    if combo_duplicates != combo_exact + combo_different:
        raise RuntimeError("BASKET_ID+PRODUCT_ID 중복 분해 관계가 성립하지 않습니다.")
    inconsistencies = pd.read_sql_query("""SELECT basket_id AS BASKET_ID, attribute_name AS inconsistent_column,
                                             COUNT(*) AS unique_value_count
                                      FROM basket_attributes GROUP BY basket_id, attribute_name
                                      HAVING COUNT(*) >= 2""", connection)
    households = pd.read_sql_query("""SELECT t.household_key,
        COALESCE(b.basket_count, 0) basket_count, COALESCE(w.week_count, 0) active_week_count,
        t.total_quantity, t.total_sales AS total_sales_value, t.first_week, t.last_week
        FROM household_totals t
        LEFT JOIN (SELECT household_key, COUNT(*) basket_count FROM household_baskets GROUP BY household_key) b USING (household_key)
        LEFT JOIN (SELECT household_key, COUNT(*) week_count FROM household_weeks GROUP BY household_key) w USING (household_key)""", connection)
    unique_counts = dict(connection.execute("SELECT column_name, COUNT(*) FROM column_uniques GROUP BY column_name"))
    return {"duplicate_rows": duplicate_rows, "combo_duplicates": combo_duplicates, "combo_exact": combo_exact,
            "combo_different": combo_different, "inconsistencies": inconsistencies,
            "households": households, "unique_counts": unique_counts}


def add_check(rows: list[dict[str, Any]], group: str, name: str, value: Any, status: str, description: str) -> None:
    """품질 점검 결과를 고정 스키마의 긴 형식으로 추가한다."""
    rows.append(dict(zip(CHECK_COLUMNS, [group, name, value, status, description])))


def household_summary(households: pd.DataFrame) -> pd.DataFrame:
    """가구별 상세값에서 반복구매 요약 지표만 생성한다."""
    metrics: list[tuple[str, Any]] = [("household_count", len(households))]
    for column in ["basket_count", "active_week_count", "total_sales_value"]:
        for label, quantile in [("min", 0), ("p25", .25), ("median", .5), ("p75", .75), ("max", 1)]:
            metrics.append((f"{column}_{label}", households[column].quantile(quantile) if len(households) else ""))
    count = len(households)
    conditions = [("one_basket_households", households["basket_count"].eq(1)),
                  ("two_or_more_basket_households", households["basket_count"].ge(2)),
                  ("two_or_more_active_week_households", households["active_week_count"].ge(2))]
    for name, condition in conditions:
        value = int(condition.sum())
        metrics.extend([(f"{name}_count", value), (f"{name}_rate", value / count if count else 0.0)])
    return pd.DataFrame(metrics, columns=["metric", "value"]).sort_values("metric", kind="stable")


def build_outputs(tx: dict[str, Any], product: dict[str, Any], sql_result: dict[str, Any], tx_names: dict[str, str], product_names: dict[str, str]) -> tuple[pd.DataFrame, dict[str, Any], pd.DataFrame, set[str]]:
    """모든 핵심 검증, 시간 요약, 가구 요약 및 미연결 ID를 계산한다."""
    checks: list[dict[str, Any]] = []
    for identifier in ID_COLUMNS:
        add_check(checks, "transaction_core_id", f"{identifier}_unique_count", len(tx["id_values"][identifier]), "PASS", f"결측을 제외한 {identifier} 고유값 수")
        nulls = tx["id_nulls"][identifier]
        add_check(checks, "transaction_core_id", f"{identifier}_null_count", nulls, "WARN" if nulls else "PASS", f"{identifier} 결측 행 수")
    duplicate_items = [
        ("basket_product_duplicate_extra_rows", sql_result["combo_duplicates"], "동일 BASKET_ID+PRODUCT_ID 조합에서 첫 행을 제외한 추가 행 수"),
        ("basket_product_exact_duplicate_extra_rows", sql_result["combo_exact"], "각 조합 안에서 같은 전체 행 패턴이 반복된 추가 행 수"),
        ("basket_product_different_extra_patterns", sql_result["combo_different"], "각 조합 안에서 첫 패턴을 제외한 서로 다른 전체 행 패턴 수"),
    ]
    for name, value, description in duplicate_items:
        add_check(checks, "transaction_unit", name, value, "WARN" if value else "PASS", description)
    for attribute in BASKET_ATTRIBUTES:
        nulls = tx["attribute_nulls"][attribute]
        add_check(checks, "basket_consistency", f"{attribute}_null_count", nulls, "WARN" if nulls else "PASS", f"BASKET_ID 일관성 대상 {attribute}의 결측 행 수")
        count = int((sql_result["inconsistencies"]["inconsistent_column"] == attribute).sum()) if len(sql_result["inconsistencies"]) else 0
        add_check(checks, "basket_consistency", f"{attribute}_inconsistent_basket_count", count, "WARN" if count else "PASS", f"둘 이상의 {attribute} 비결측값에 연결된 BASKET_ID 수")
    for column in VALUE_COLUMNS:
        discount = column not in {"QUANTITY", "SALES_VALUE"}
        description = "할인값의 부호별 현황이며 업무 정의 확인 전 오류로 판정하지 않음" if discount else f"{column} 부호별 현황이며 값은 수정하지 않음"
        for sign in ["missing", "negative", "zero", "positive"]:
            value = tx["signs"][column][sign]
            warn = value > 0 and (sign == "missing" or (not discount and sign in {"negative", "zero"}))
            add_check(checks, "value_distribution", f"{column}_{sign}_count", value, "WARN" if warn else "PASS", description)

    weeks = sorted(tx["weeks"])
    missing = sorted(set(range(weeks[0], weeks[-1] + 1)) - set(weeks)) if weeks else []
    valid = [week for week in weeks if set(range(week - 25, week + 5)).issubset(tx["weeks"])]
    inconsistent_days = sum(len(values) > 1 for values in tx["day_weeks"].values())
    add_check(checks, "time", "day_multiple_week_count", inconsistent_days, "WARN" if inconsistent_days else "PASS", "둘 이상의 WEEK_NO에 연결된 DAY 수")
    time_summary = {"min_day": min(tx["days"]) if tx["days"] else "", "max_day": max(tx["days"]) if tx["days"] else "",
                    "min_week": weeks[0] if weeks else "", "max_week": weeks[-1] if weeks else "", "observed_week_count": len(weeks),
                    "missing_week_count": len(missing), "missing_week_list": ",".join(map(str, missing)), "valid_reference_week_count": len(valid),
                    "first_valid_reference_week": valid[0] if valid else "", "last_valid_reference_week": valid[-1] if valid else "",
                    "valid_reference_week_list": ",".join(map(str, valid))}

    tx_products = set(tx["id_values"]["PRODUCT_ID"])
    product_ids = product["product_ids"]
    unmatched = tx_products - product_ids
    unmatched_rows = sum(tx["product_rows"][item] for item in unmatched)
    relationship = [
        ("transaction_unique_product_id_count", len(tx_products), "PASS"),
        ("product_unique_product_id_count", len(product_ids), "PASS"),
        ("matched_transaction_product_id_count", len(tx_products & product_ids), "PASS"),
        ("unmatched_transaction_product_id_count", len(unmatched), "WARN" if unmatched else "PASS"),
        ("unmatched_transaction_product_id_rate", len(unmatched) / len(tx_products) if tx_products else 0.0, "WARN" if unmatched else "PASS"),
        ("unmatched_product_transaction_row_count", unmatched_rows, "WARN" if unmatched_rows else "PASS"),
        ("unmatched_product_transaction_row_rate", unmatched_rows / tx["row_count"] if tx["row_count"] else 0.0, "WARN" if unmatched_rows else "PASS"),
        ("unused_product_id_count", len(product_ids - tx_products), "PASS"),
    ]
    for name, value, status in relationship:
        add_check(checks, "transaction_product_relationship", name, value, status, "transaction과 product의 PRODUCT_ID 연결 결과")
    product_items = [("product_id_unique_count", len(product_ids)), ("product_id_null_count", product["product_nulls"]),
                     ("product_id_duplicate_extra_rows", product["duplicate_ids"]), ("product_id_conflicting_information_count", product["conflicting_ids"])]
    for name, value in product_items:
        add_check(checks, "product_core_id", name, value, "WARN" if name != "product_id_unique_count" and value else "PASS", "product.csv PRODUCT_ID 품질 결과")
    for logical in CATEGORY_COLUMNS:
        actual = product_names[logical]
        nulls = product["stats"][actual]["nulls"]
        for suffix, value in [("null_count", nulls), ("null_rate", nulls / product["row_count"] if product["row_count"] else 0.0), ("unique_count", product["unique_counts"][actual])]:
            add_check(checks, "product_category", f"{logical}_{suffix}", value, "WARN" if suffix.startswith("null") and nulls else "PASS", f"{logical}의 {suffix} 결과")
    quality = pd.DataFrame(checks, columns=CHECK_COLUMNS).sort_values(["check_group", "check_name"], kind="stable")
    return quality, time_summary, household_summary(sql_result["households"]), unmatched


def column_profile(path: Path, columns: list[str], stats: dict[str, dict[str, Any]], row_count: int, unique_counts: dict[str, int]) -> list[dict[str, Any]]:
    """누적 통계를 고정 컬럼의 프로파일 행으로 변환한다."""
    rows = []
    for column in columns:
        item = stats[column]
        rows.append(dict(zip(PROFILE_COLUMNS, [path.name, column, inferred_dtype(item), row_count, item["nulls"], item["nulls"] / row_count if row_count else 0.0,
                                                       unique_counts.get(column, 0), item["min"] if item["numeric"] and item["min"] is not None else "",
                                                       item["max"] if item["numeric"] and item["max"] is not None else ""])))
    return rows


def write_report(file_summary: pd.DataFrame, quality: pd.DataFrame, time_summary: dict[str, Any], households: pd.DataFrame) -> None:
    """지정된 열 개 절로 Markdown 프로파일링 보고서를 저장한다."""
    def lines(group: str) -> str:
        subset = quality[quality["check_group"] == group]
        return "\n".join(f"- {row.check_name}: {row.result_value} ({row.status})" for row in subset.itertuples()) or "- 해당 없음"
    files = "\n".join(f"- {row.file_name}: {row.file_size_mb:.6f} MB, {row.row_count:,}행, {row.column_count}열" for row in file_summary.itertuples())
    household_lines = "\n".join(f"- {row.metric}: {row.value}" for row in households.itertuples())
    warnings = quality[quality["status"] == "WARN"]
    warning_lines = "\n".join(f"- {row.check_name}: {row.description} (결과: {row.result_value})" for row in warnings.itertuples()) or "- WARN 항목 없음"
    report = f"""# 원본 데이터 프로파일링 보고서

## 1. 프로파일링 목적
원본 구조와 품질을 전체 행 기준으로 확인하며 값을 정제하거나 원인을 추측하지 않는다.

## 2. 분석 파일
- transaction_data.csv
- product.csv

## 3. 파일 크기와 행·열 수
{files}

## 4. 핵심 ID와 거래 단위 확인
{lines('transaction_core_id')}
{lines('transaction_unit')}
{lines('basket_consistency')}
{lines('product_core_id')}

## 5. 금액·수량의 부호별 현황
{lines('value_distribution')}
음수 수량이 확인된 경우 업무상 의미는 추가 확인이 필요하다.

## 6. 시간 범위와 유효 기준주차
- DAY: {time_summary['min_day']} ~ {time_summary['max_day']}
- WEEK_NO: {time_summary['min_week']} ~ {time_summary['max_week']}
- 유효 기준주차 수: {time_summary['valid_reference_week_count']}
- 유효 기준주차: {time_summary['valid_reference_week_list']}
{lines('time')}

## 7. transaction-product 연결 결과
{lines('transaction_product_relationship')}

## 8. 가구 반복구매 현황
{household_lines}

## 9. 상품 카테고리 변수 결측 현황
{lines('product_category')}

## 10. 분석 전에 확인해야 할 WARN 항목
{warning_lines}

음수·0·중복·미연결 값은 프로파일링 단계에서 수정하거나 제거하지 않았으며, 업무 정의와 분포를 확인한 뒤 전처리 규칙을 확정해야 한다.
"""
    (OUTPUT_DIR / "profiling_report.md").write_text(report, encoding="utf-8-sig")


def main() -> int:
    """입력 검증부터 임시 DB 정리까지 전체 프로파일링 실행을 관리한다."""
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    total_started = time.perf_counter()
    connection: sqlite3.Connection | None = None
    try:
        started = time.perf_counter()
        tx_columns, tx_names = validate_file(TRANSACTION_FILE, TRANSACTION_REQUIRED)
        product_columns, product_names = validate_file(PRODUCT_FILE, PRODUCT_REQUIRED)
        logging.info("입력 검증 처리시간: %.3f초", time.perf_counter() - started)
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        for name in ["basket_inconsistencies.csv", "unmatched_product_ids.csv"]:
            (OUTPUT_DIR / name).unlink(missing_ok=True)

        with tempfile.NamedTemporaryFile(prefix="raw_profile_", suffix=".sqlite3", delete=False) as temporary:
            database_path = temporary.name
        try:
            connection = create_database(database_path)
            tx = process_transaction(TRANSACTION_FILE, tx_columns, tx_names, connection)
            product = process_product(PRODUCT_FILE, product_columns, product_names)
            final_started = time.perf_counter()
            sql_result = finalise_sqlite(connection)
            quality, time_summary, households, unmatched = build_outputs(tx, product, sql_result, tx_names, product_names)
            file_summary = pd.DataFrame([
                [TRANSACTION_FILE.name, TRANSACTION_FILE.stat().st_size / 1024 ** 2, tx["row_count"], len(tx_columns), sql_result["duplicate_rows"]],
                [PRODUCT_FILE.name, PRODUCT_FILE.stat().st_size / 1024 ** 2, product["row_count"], len(product_columns), product["duplicate_rows"]],
            ], columns=FILE_COLUMNS).sort_values("file_name", kind="stable")
            profiles = column_profile(TRANSACTION_FILE, tx_columns, tx["stats"], tx["row_count"], sql_result["unique_counts"])
            profiles += column_profile(PRODUCT_FILE, product_columns, product["stats"], product["row_count"], product["unique_counts"])
            profile_frame = pd.DataFrame(profiles, columns=PROFILE_COLUMNS).sort_values(["file_name", "column_name"], kind="stable")
            file_summary.to_csv(OUTPUT_DIR / "file_summary.csv", index=False, columns=FILE_COLUMNS, encoding="utf-8-sig")
            profile_frame.to_csv(OUTPUT_DIR / "column_profile.csv", index=False, columns=PROFILE_COLUMNS, encoding="utf-8-sig")
            quality.to_csv(OUTPUT_DIR / "quality_checks.csv", index=False, columns=CHECK_COLUMNS, encoding="utf-8-sig")
            pd.DataFrame([time_summary], columns=TIME_COLUMNS).to_csv(OUTPUT_DIR / "time_window_summary.csv", index=False, encoding="utf-8-sig")
            households.to_csv(OUTPUT_DIR / "household_activity_summary.csv", index=False, columns=["metric", "value"], encoding="utf-8-sig")
            if not sql_result["inconsistencies"].empty:
                sql_result["inconsistencies"].sort_values(["BASKET_ID", "inconsistent_column"], kind="stable").to_csv(OUTPUT_DIR / "basket_inconsistencies.csv", index=False, columns=["BASKET_ID", "inconsistent_column", "unique_value_count"], encoding="utf-8-sig")
            if unmatched:
                pd.DataFrame({"PRODUCT_ID": sorted(unmatched)}).to_csv(OUTPUT_DIR / "unmatched_product_ids.csv", index=False, encoding="utf-8-sig")
            write_report(file_summary, quality, time_summary, households)
            logging.info("최종 집계 및 저장 처리시간: %.3f초", time.perf_counter() - final_started)
        finally:
            if connection is not None:
                connection.close()
                connection = None
            Path(database_path).unlink(missing_ok=True)
        logging.info("전체 실행시간: %.3f초", time.perf_counter() - total_started)
        return 0
    except Exception:
        logging.exception("프로파일링 실패 | transaction=%s | product=%s", TRANSACTION_FILE.name, PRODUCT_FILE.name)
        logging.info("전체 실행시간(실패): %.3f초", time.perf_counter() - total_started)
        return 1


if __name__ == "__main__":
    sys.exit(main())


from __future__ import annotations

import json
import math
import platform
from pathlib import Path
from typing import Any, Iterable

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import sklearn
import xgboost
from sklearn.calibration import calibration_curve
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    average_precision_score,
    brier_score_loss,
    precision_recall_curve,
    roc_auc_score,
)
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from xgboost import XGBClassifier

# ============================================================
# CONFIG
# ============================================================
PROJECT_DIR = Path(__file__).resolve().parents[1]
INPUT_CSV = PROJECT_DIR / "data" / "processed" / "model_dataset.csv"
OUTPUT_DIR = PROJECT_DIR / "outputs" / "modeling"
FIGURE_DIR = OUTPUT_DIR / "figures"

RANDOM_STATE = 42
RUN_FINAL_TEST = False
TOP_K_VALUES = (0.05, 0.10, 0.20)
TARGET = "target_no_purchase_4w"
KEY_COLUMNS = ["household_key", "reference_week"]
EXPECTED_ROWS = 182_500
EXPECTED_HOUSEHOLDS = 2_500
EXPECTED_WEEK_MIN = 26
EXPECTED_WEEK_MAX = 98
EXPECTED_WEEK_COUNT = 73

SPLIT_RANGES = {
    "TRAIN": (26, 74),
    "GAP_TRAIN_VALIDATION": (75, 78),
    "VALIDATION": (79, 86),
    "GAP_VALIDATION_TEST": (87, 90),
    "TEST": (91, 98),
}
EXPECTED_SPLIT_ROWS = {
    "TRAIN": 122_500,
    "GAP_TRAIN_VALIDATION": 10_000,
    "VALIDATION": 20_000,
    "GAP_VALIDATION_TEST": 10_000,
    "TEST": 20_000,
}

METADATA_COLUMNS = [
    "household_key",
    "reference_week",
    "reference_end_day",
    "observation_start_week",
    "observation_end_week",
    "prior4_start_week",
    "prior4_end_week",
    "recent4_start_week",
    "recent4_end_week",
    "target_start_week",
    "target_end_week",
]

CATEGORICAL_FEATURES = [
    "activity_transition",
    "activity_state",
    "value_state",
    "current_value_state",
    "customer_state",
    "basket_change_denominator_status",
    "sales_change_denominator_status",
    "average_basket_change_denominator_status",
    "product_change_denominator_status",
    "department_change_denominator_status",
    "commodity_change_denominator_status",
    "discount_change_denominator_status",
]

BOOLEAN_FEATURES = [
    "has_purchase_26w",
    "prior4_has_purchase",
    "recent4_has_purchase",
    "pre_window_has_snapshot",
    "pre_window_has_purchase_26w",
    "is_became_inactive",
    "is_sales_decline_30",
    "is_both_decline_30",
    "is_both_decline_50",
]

NUMERIC_FEATURES = [
    "recency_weeks_26w",
    "recency_days_26w",
    "frequency_26w",
    "monetary_26w",
    "purchase_week_count_26w",
    "purchase_day_count_26w",
    "active_week_rate_26w",
    "average_basket_value_26w",
    "average_weekly_sales_26w",
    "average_sales_per_active_week_26w",
    "discount_amount_26w",
    "discount_rate_proxy_26w",
    "paid_product_count_26w",
    "paid_department_count_26w",
    "paid_commodity_count_26w",
    "recency_percentile_26w",
    "frequency_percentile_26w",
    "monetary_percentile_26w",
    "fm_value_index_26w",
    "rfm_value_index_26w",
    "prior4_valid_basket_count",
    "prior4_purchase_week_count",
    "prior4_purchase_day_count",
    "prior4_sales",
    "prior4_average_basket_value",
    "prior4_discount_amount",
    "prior4_paid_product_count",
    "prior4_paid_department_count",
    "prior4_paid_commodity_count",
    "recent4_valid_basket_count",
    "recent4_purchase_week_count",
    "recent4_purchase_day_count",
    "recent4_sales",
    "recent4_average_basket_value",
    "recent4_discount_amount",
    "recent4_paid_product_count",
    "recent4_paid_department_count",
    "recent4_paid_commodity_count",
    "basket_count_change",
    "purchase_week_count_change",
    "purchase_day_count_change",
    "sales_change",
    "average_basket_value_change",
    "paid_product_count_change",
    "paid_department_count_change",
    "paid_commodity_count_change",
    "discount_amount_change",
    "basket_count_change_rate",
    "sales_change_rate",
    "average_basket_value_change_rate",
    "paid_product_count_change_rate",
    "paid_department_count_change_rate",
    "paid_commodity_count_change_rate",
    "discount_amount_change_rate",
    "pre_window_recency_weeks_26w",
    "pre_window_recency_days_26w",
    "pre_window_frequency_26w",
    "pre_window_monetary_26w",
    "pre_window_fm_value_index_26w",
    "pre_window_rfm_value_index_26w",
]

ALL_EXPLICIT_FEATURES = NUMERIC_FEATURES + BOOLEAN_FEATURES + CATEGORICAL_FEATURES

FORBIDDEN_EXACT_COLUMNS = {
    "future4_valid_basket_count",
    "future4_sales",
    "future4_has_purchase",
    "future4_no_purchase",
    "purchase_rate",
    "weighted_purchase_rate",
    "predicted_probability",
    "no_purchase_probability",
}


# ============================================================
# Data loading and validation
# ============================================================
def print_pipeline_step(step: str, title: str) -> None:
    """Print one concise marker for a major pipeline stage."""
    print(f"\n[{step}] {title}")


def parse_boolean_series(series: pd.Series, column: str) -> pd.Series:
    """Convert PostgreSQL/CSV boolean representations to nullable 0/1."""
    if pd.api.types.is_bool_dtype(series):
        return series.astype("Int8")
    if pd.api.types.is_numeric_dtype(series):
        numeric = pd.to_numeric(series, errors="coerce")
        invalid = numeric.notna() & ~numeric.isin([0, 1])
        if invalid.any():
            raise ValueError(
                f"{column}: invalid boolean numeric values={sorted(numeric[invalid].unique())}"
            )
        return numeric.astype("Int8")

    normalized = series.astype("string").str.strip().str.lower()
    mapping = {
        "true": 1,
        "t": 1,
        "1": 1,
        "yes": 1,
        "false": 0,
        "f": 0,
        "0": 0,
        "no": 0,
    }
    converted = normalized.map(mapping)
    invalid = series.notna() & converted.isna()
    if invalid.any():
        examples = series.loc[invalid].astype(str).drop_duplicates().head(10).tolist()
        raise ValueError(f"{column}: unrecognized boolean values={examples}")
    return converted.astype("Int8")


def validate_forbidden_columns(columns: Iterable[str]) -> None:
    lowered = {column.lower() for column in columns}
    forbidden = sorted(FORBIDDEN_EXACT_COLUMNS & lowered)
    forbidden += sorted(
        column
        for column in lowered
        if column.startswith("future8_") or column.startswith("future12_")
    )
    if forbidden:
        raise ValueError(f"Forbidden future/post-outcome columns detected: {forbidden}")


def load_and_validate_model_dataset(path: Path) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Load the model CSV and enforce its schema, grain, target, and size contract."""
    print_pipeline_step("1/8", "Loading and validating the model dataset")
    if not path.exists():
        raise FileNotFoundError(
            f"Model dataset CSV not found: {path}\n"
            "Export mart.model_dataset to this path before running the script."
        )

    data = pd.read_csv(path, low_memory=False)
    data.columns = [column.strip().lower() for column in data.columns]

    required = set(KEY_COLUMNS + METADATA_COLUMNS + [TARGET] + ALL_EXPLICIT_FEATURES)
    missing = sorted(required - set(data.columns))
    if missing:
        raise ValueError(f"Required model_dataset columns are missing: {missing}")
    validate_forbidden_columns(data.columns)

    for column in KEY_COLUMNS + [TARGET]:
        data[column] = pd.to_numeric(data[column], errors="raise")
    data["household_key"] = data["household_key"].astype("int64")
    data["reference_week"] = data["reference_week"].astype("int64")
    data[TARGET] = data[TARGET].astype("Int8")

    for column in BOOLEAN_FEATURES:
        data[column] = parse_boolean_series(data[column], column).astype("float64")

    conversion_rows: list[dict[str, Any]] = []
    for column in NUMERIC_FEATURES:
        original_nonnull = data[column].notna()
        converted = pd.to_numeric(data[column], errors="coerce")
        failed = int((original_nonnull & converted.isna()).sum())
        conversion_rows.append(
            {"column": column, "numeric_conversion_failure_count": failed}
        )
        if failed:
            raise ValueError(f"{column}: numeric conversion failures={failed}")
        data[column] = converted

    for column in CATEGORICAL_FEATURES:
        data[column] = data[column].astype("object").where(data[column].notna(), np.nan)

    duplicate_count = int(data.duplicated(KEY_COLUMNS, keep=False).sum())
    target_null_count = int(data[TARGET].isna().sum())
    target_values = set(data[TARGET].dropna().astype(int).unique())
    actual = {
        "row_count": len(data),
        "column_count": data.shape[1],
        "unique_household_count": data["household_key"].nunique(),
        "reference_week_count": data["reference_week"].nunique(),
        "min_reference_week": int(data["reference_week"].min()),
        "max_reference_week": int(data["reference_week"].max()),
        "duplicate_key_row_count": duplicate_count,
        "target_null_count": target_null_count,
        "target_no_purchase_rate": float(data[TARGET].mean()),
    }
    print(pd.Series(actual).to_string())
    print(
        "\nTarget counts:\n",
        data[TARGET].value_counts(dropna=False).sort_index().to_string(),
    )

    if duplicate_count:
        raise ValueError(
            f"Duplicate household_key × reference_week rows={duplicate_count}"
        )
    if target_null_count:
        raise ValueError(f"Target NULL rows={target_null_count}")
    if target_values != {0, 1}:
        raise ValueError(
            f"Target must contain exactly 0 and 1; actual={sorted(target_values)}"
        )

    expected_mismatches = {
        "row_count": (actual["row_count"], EXPECTED_ROWS),
        "unique_household_count": (
            actual["unique_household_count"],
            EXPECTED_HOUSEHOLDS,
        ),
        "reference_week_count": (actual["reference_week_count"], EXPECTED_WEEK_COUNT),
        "min_reference_week": (actual["min_reference_week"], EXPECTED_WEEK_MIN),
        "max_reference_week": (actual["max_reference_week"], EXPECTED_WEEK_MAX),
    }
    mismatches = {
        name: values
        for name, values in expected_mismatches.items()
        if values[0] != values[1]
    }
    if mismatches:
        details = "; ".join(
            f"{name}: actual={actual_value}, expected={expected_value}"
            for name, (actual_value, expected_value) in mismatches.items()
        )
        raise ValueError(
            f"Model dataset dimensions differ from the confirmed SQL result: {details}"
        )

    quality = pd.DataFrame(
        [
            {
                "metric": name,
                "actual_value": value,
                "expected_value": expected_mismatches.get(name, (None, None))[1],
            }
            for name, value in actual.items()
        ]
    )
    conversion = pd.DataFrame(conversion_rows)
    quality = pd.concat(
        [
            quality,
            conversion.rename(
                columns={
                    "column": "metric",
                    "numeric_conversion_failure_count": "actual_value",
                }
            ),
        ],
        ignore_index=True,
    )
    return data, quality


# ============================================================
# Time split and train-only EDA
# ============================================================
def create_time_based_splits(
    model_dataset: pd.DataFrame,
) -> tuple[dict[str, pd.DataFrame], pd.DataFrame]:
    """Partition reference weeks into fixed train, gap, validation, gap, and test sets."""
    print_pipeline_step("2/8", "Creating time-based splits with four-week gaps")
    splits: dict[str, pd.DataFrame] = {}
    summary_rows: list[dict[str, Any]] = []

    for name, (start_week, end_week) in SPLIT_RANGES.items():
        subset = model_dataset.loc[
            model_dataset["reference_week"].between(start_week, end_week)
        ].copy()
        actual_weeks = set(subset["reference_week"].unique())
        expected_weeks = set(range(start_week, end_week + 1))
        if actual_weeks != expected_weeks:
            raise ValueError(
                f"{name}: week coverage mismatch; missing={sorted(expected_weeks - actual_weeks)}, "
                f"unexpected={sorted(actual_weeks - expected_weeks)}"
            )
        if len(subset) != EXPECTED_SPLIT_ROWS[name]:
            raise ValueError(
                f"{name}: row_count actual={len(subset)}, expected={EXPECTED_SPLIT_ROWS[name]}"
            )
        splits[name] = subset
        protected_test = name == "TEST" and not RUN_FINAL_TEST
        row = {
            "split": name,
            "start_week": start_week,
            "end_week": end_week,
            "week_count": len(actual_weeks),
            "row_count": len(subset),
            "no_purchase_count": pd.NA if protected_test else int(subset[TARGET].sum()),
            "purchase_count": (
                pd.NA if protected_test else int((subset[TARGET] == 0).sum())
            ),
            "no_purchase_rate": (
                np.nan if protected_test else float(subset[TARGET].mean())
            ),
            "target_details_protected": protected_test,
        }
        summary_rows.append(row)
        if protected_test:
            print(
                f"{name}: weeks={start_week}-{end_week}, rows={len(subset):,}, target metrics PROTECTED"
            )
        else:
            print(
                f"{name}: weeks={start_week}-{end_week}, rows={len(subset):,}, "
                f"no_purchase_rate={row['no_purchase_rate']:.4f}"
            )

    assigned_rows = sum(len(frame) for frame in splits.values())
    if assigned_rows != len(model_dataset):
        raise ValueError(
            f"Split rows={assigned_rows:,} do not reconcile to "
            f"data rows={len(model_dataset):,}"
        )
    return splits, pd.DataFrame(summary_rows)


def build_feature_sets() -> dict[str, list[str]]:
    """Build the six nested feature sets used for validation ablation."""
    recency_only_features = ["recency_weeks_26w", "has_purchase_26w"]
    rfm_behavior_features = recency_only_features + ["frequency_26w", "monetary_26w"]
    rfm_plus_absolute_activity_features = rfm_behavior_features + [
        "prior4_valid_basket_count",
        "recent4_valid_basket_count",
        "prior4_purchase_week_count",
        "recent4_purchase_week_count",
        "prior4_purchase_day_count",
        "recent4_purchase_day_count",
        "prior4_sales",
        "recent4_sales",
    ]
    absolute_activity_plus_change_features = rfm_plus_absolute_activity_features + [
        "basket_count_change",
        "sales_change",
        "basket_count_change_rate",
        "sales_change_rate",
        "basket_change_denominator_status",
        "sales_change_denominator_status",
    ]
    full_behavior_features = list(
        dict.fromkeys(
            NUMERIC_FEATURES
            + BOOLEAN_FEATURES
            + [
                "basket_change_denominator_status",
                "sales_change_denominator_status",
                "average_basket_change_denominator_status",
                "product_change_denominator_status",
                "department_change_denominator_status",
                "commodity_change_denominator_status",
                "discount_change_denominator_status",
            ]
        )
    )
    full_behavior_plus_customer_state_features = list(
        dict.fromkeys(full_behavior_features + CATEGORICAL_FEATURES)
    )
    feature_sets = {
        "recency_only": recency_only_features,
        "rfm_behavior": rfm_behavior_features,
        "rfm_plus_absolute_activity": rfm_plus_absolute_activity_features,
        "rfm_absolute_activity_plus_change": absolute_activity_plus_change_features,
        "full_behavior_features": full_behavior_features,
        "full_behavior_plus_customer_state": full_behavior_plus_customer_state_features,
    }
    duplicate_feature_sets = [
        feature_set_name
        for feature_set_name, feature_names in feature_sets.items()
        if len(feature_names) != len(set(feature_names))
    ]
    if duplicate_feature_sets:
        raise ValueError(f"Duplicate features detected in: {duplicate_feature_sets}")
    return feature_sets


def profile_training_features(
    train_data: pd.DataFrame,
    all_feature_names: list[str],
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Create missingness, numeric, and categorical profiles from TRAIN only."""
    print_pipeline_step("3/8", "Profiling training features")
    missingness_rows = [
        {
            "feature_name": column,
            "dtype": str(train_data[column].dtype),
            "null_count": int(train_data[column].isna().sum()),
            "null_rate": float(train_data[column].isna().mean()),
        }
        for column in all_feature_names
    ]

    numeric_profile_columns = [
        column
        for column in NUMERIC_FEATURES + BOOLEAN_FEATURES
        if column in all_feature_names
    ]
    numeric_profile_rows: list[dict[str, Any]] = []
    for column in numeric_profile_columns:
        values = pd.to_numeric(train_data[column], errors="coerce")
        numeric_profile_rows.append(
            {
                "feature_name": column,
                "count": int(values.notna().sum()),
                "missing": int(values.isna().sum()),
                "missing_rate": float(values.isna().mean()),
                "mean": values.mean(),
                "std": values.std(),
                "minimum": values.min(),
                "p01": values.quantile(0.01),
                "p05": values.quantile(0.05),
                "p25": values.quantile(0.25),
                "median": values.quantile(0.50),
                "p75": values.quantile(0.75),
                "p95": values.quantile(0.95),
                "p99": values.quantile(0.99),
                "maximum": values.max(),
            }
        )

    categorical_profile_rows: list[dict[str, Any]] = []
    for column in [
        feature for feature in CATEGORICAL_FEATURES if feature in all_feature_names
    ]:
        grouped = (
            train_data.assign(_category=train_data[column].fillna("__MISSING__"))
            .groupby("_category", dropna=False)[TARGET]
            .agg(row_count="size", target_rate="mean")
            .reset_index()
        )
        grouped["category_share"] = grouped["row_count"] / len(train_data)
        grouped.insert(0, "feature_name", column)
        grouped = grouped.rename(columns={"_category": "category_value"})
        categorical_profile_rows.extend(grouped.to_dict("records"))

    return (
        pd.DataFrame(missingness_rows),
        pd.DataFrame(numeric_profile_rows),
        pd.DataFrame(categorical_profile_rows),
    )


# ============================================================
# Preprocessing, models, and metrics
# ============================================================
def split_feature_types(feature_names: list[str]) -> tuple[list[str], list[str]]:
    """Separate an explicit feature set into numeric and categorical columns."""
    categorical_feature_names = [
        column for column in feature_names if column in CATEGORICAL_FEATURES
    ]
    numeric_feature_names = [
        column for column in feature_names if column not in categorical_feature_names
    ]
    return numeric_feature_names, categorical_feature_names


def build_model_preprocessor(
    feature_names: list[str], scale_numeric: bool
) -> ColumnTransformer:
    """Create an unfitted train-only imputation, encoding, and scaling transformer."""
    numeric_feature_names, categorical_feature_names = split_feature_types(
        feature_names
    )
    numeric_steps: list[tuple[str, Any]] = [
        ("imputer", SimpleImputer(strategy="median", add_indicator=True)),
    ]
    if scale_numeric:
        numeric_steps.append(("scaler", StandardScaler(with_mean=False)))

    transformers: list[tuple[str, Any, list[str]]] = []
    if numeric_feature_names:
        transformers.append(("numeric", Pipeline(numeric_steps), numeric_feature_names))
    if categorical_feature_names:
        transformers.append(
            (
                "categorical",
                Pipeline(
                    [
                        (
                            "imputer",
                            SimpleImputer(
                                strategy="constant", fill_value="__MISSING__"
                            ),
                        ),
                        ("onehot", OneHotEncoder(handle_unknown="ignore")),
                    ]
                ),
                categorical_feature_names,
            )
        )
    return ColumnTransformer(transformers=transformers, remainder="drop")


def build_logistic_pipeline(
    features: list[str],
    c_value: float = 1.0,
    class_weight: str | None = None,
) -> Pipeline:
    return Pipeline(
        [
            ("preprocess", build_model_preprocessor(features, scale_numeric=True)),
            (
                "model",
                LogisticRegression(
                    C=c_value,
                    penalty="l2",
                    class_weight=class_weight,
                    max_iter=3_000,
                    random_state=RANDOM_STATE,
                ),
            ),
        ]
    )


def build_xgboost_pipeline(features: list[str], params: dict[str, Any]) -> Pipeline:
    # Median imputation remains inside the train-fitted pipeline for both model
    # families. This favors a common, auditable leakage boundary over separate
    # preprocessing conventions; XGBoost still captures nonlinear interactions.
    return Pipeline(
        [
            ("preprocess", build_model_preprocessor(features, scale_numeric=False)),
            (
                "model",
                XGBClassifier(
                    objective="binary:logistic",
                    eval_metric="aucpr",
                    importance_type="gain",
                    random_state=RANDOM_STATE,
                    n_jobs=-1,
                    tree_method="hist",
                    **params,
                ),
            ),
        ]
    )


def calculate_top_k_metrics(
    actual_no_purchase: np.ndarray,
    predicted_no_purchase_probability: np.ndarray,
    top_k_values: Iterable[float] = TOP_K_VALUES,
) -> pd.DataFrame:
    """Calculate no-purchase recall, precision, and lift after one risk sort."""
    descending_risk_order = np.argsort(
        -predicted_no_purchase_probability, kind="mergesort"
    )
    total_no_purchase_count = float(np.sum(actual_no_purchase))
    no_purchase_rate = float(np.mean(actual_no_purchase))
    rows: list[dict[str, float]] = []
    for top_k_share in top_k_values:
        selected_row_count = max(
            1, int(math.ceil(len(actual_no_purchase) * top_k_share))
        )
        selected_rows = descending_risk_order[:selected_row_count]
        selected_no_purchase_count = float(np.sum(actual_no_purchase[selected_rows]))
        precision_at_k = selected_no_purchase_count / selected_row_count
        recall_at_k = (
            selected_no_purchase_count / total_no_purchase_count
            if total_no_purchase_count
            else np.nan
        )
        lift_at_k = precision_at_k / no_purchase_rate if no_purchase_rate else np.nan
        rows.append(
            {
                "top_k_share": top_k_share,
                "selected_row_count": selected_row_count,
                "selected_no_purchase_count": selected_no_purchase_count,
                "precision_at_k": precision_at_k,
                "recall_at_k": recall_at_k,
                "lift_at_k": lift_at_k,
            }
        )
    return pd.DataFrame(rows)


def safe_roc_auc(
    actual_no_purchase: np.ndarray,
    predicted_no_purchase_probability: np.ndarray,
) -> float:
    """Return ROC-AUC, or NULL when a weekly slice contains only one class."""
    if np.unique(actual_no_purchase).size != 2:
        return np.nan
    return float(roc_auc_score(actual_no_purchase, predicted_no_purchase_probability))


def calculate_probability_model_metrics(
    actual_no_purchase: np.ndarray,
    predicted_no_purchase_probability: np.ndarray,
) -> tuple[dict[str, float], pd.DataFrame]:
    """Calculate common probability and ranking metrics for one scored dataset."""
    top_k_metrics = calculate_top_k_metrics(
        actual_no_purchase, predicted_no_purchase_probability
    )
    model_metrics: dict[str, float] = {
        "pr_auc": float(
            average_precision_score(
                actual_no_purchase, predicted_no_purchase_probability
            )
        ),
        "roc_auc": safe_roc_auc(actual_no_purchase, predicted_no_purchase_probability),
        "brier_score": float(
            brier_score_loss(actual_no_purchase, predicted_no_purchase_probability)
        ),
        "accuracy_at_50pct_threshold": float(
            np.mean(
                (predicted_no_purchase_probability >= 0.5).astype(int)
                == actual_no_purchase
            )
        ),
        "no_purchase_rate": float(np.mean(actual_no_purchase)),
        "no_skill_accuracy": float(np.mean(actual_no_purchase == 0)),
    }
    for row in top_k_metrics.itertuples(index=False):
        percentage = int(round(row.top_k_share * 100))
        model_metrics[f"recall_at_{percentage}pct"] = float(row.recall_at_k)
        model_metrics[f"precision_at_{percentage}pct"] = float(row.precision_at_k)
        model_metrics[f"lift_at_{percentage}pct"] = float(row.lift_at_k)
    return model_metrics, top_k_metrics


def fit_and_evaluate_on_validation(
    model_pipeline: Pipeline,
    feature_names: list[str],
    train_data: pd.DataFrame,
    validation_data: pd.DataFrame,
) -> tuple[Pipeline, dict[str, float], pd.DataFrame, np.ndarray]:
    """Fit one candidate on TRAIN and calculate its VALIDATION metrics once."""
    model_pipeline.fit(train_data[feature_names], train_data[TARGET].astype(int))
    validation_no_purchase_probability = model_pipeline.predict_proba(
        validation_data[feature_names]
    )[:, 1]
    validation_model_metrics, validation_top_k_metrics = (
        calculate_probability_model_metrics(
            validation_data[TARGET].astype(int).to_numpy(),
            validation_no_purchase_probability,
        )
    )
    return (
        model_pipeline,
        validation_model_metrics,
        validation_top_k_metrics,
        validation_no_purchase_probability,
    )


def evaluate_weekly_model_stability(
    validation_data: pd.DataFrame,
    predicted_no_purchase_probability: np.ndarray,
    model_name: str,
) -> pd.DataFrame:
    """Calculate model metrics independently for each validation reference week."""
    weekly_predictions = validation_data[["reference_week", TARGET]].copy()
    weekly_predictions["predicted_no_purchase_probability"] = (
        predicted_no_purchase_probability
    )
    rows: list[dict[str, Any]] = []
    for reference_week, weekly_data in weekly_predictions.groupby(
        "reference_week", sort=True
    ):
        actual_no_purchase = weekly_data[TARGET].astype(int).to_numpy()
        weekly_no_purchase_probability = weekly_data[
            "predicted_no_purchase_probability"
        ].to_numpy()
        weekly_model_metrics, weekly_top_k_metrics = (
            calculate_probability_model_metrics(
                actual_no_purchase, weekly_no_purchase_probability
            )
        )
        top_10pct_metrics = weekly_top_k_metrics.loc[
            np.isclose(weekly_top_k_metrics["top_k_share"], 0.10)
        ].iloc[0]
        rows.append(
            {
                "model_name": model_name,
                "reference_week": int(reference_week),
                "row_count": len(weekly_data),
                "no_purchase_rate": float(np.mean(actual_no_purchase)),
                "pr_auc": weekly_model_metrics["pr_auc"],
                "roc_auc": weekly_model_metrics["roc_auc"],
                "recall_at_10pct": top_10pct_metrics["recall_at_k"],
                "lift_at_10pct": top_10pct_metrics["lift_at_k"],
                "brier_score": weekly_model_metrics["brier_score"],
            }
        )
    return pd.DataFrame(rows)


def create_calibration_bin_table(
    actual_no_purchase: np.ndarray,
    predicted_no_purchase_probability: np.ndarray,
    model_name: str,
) -> pd.DataFrame:
    """Summarize predicted and observed no-purchase rates in ten quantile bins."""
    observed_no_purchase_rate, mean_predicted_no_purchase_probability = (
        calibration_curve(
            actual_no_purchase,
            predicted_no_purchase_probability,
            n_bins=10,
            strategy="quantile",
        )
    )
    return pd.DataFrame(
        {
            "model_name": model_name,
            "mean_predicted_no_purchase_probability": (
                mean_predicted_no_purchase_probability
            ),
            "observed_no_purchase_rate": observed_no_purchase_rate,
        }
    )


def get_transformed_feature_names(pipeline: Pipeline) -> np.ndarray:
    return pipeline.named_steps["preprocess"].get_feature_names_out()


# ============================================================
# Validation experiments
# ============================================================
def run_validation_experiments(
    train_data: pd.DataFrame,
    validation_data: pd.DataFrame,
    feature_sets: dict[str, list[str]],
) -> tuple[
    pd.DataFrame,
    pd.DataFrame,
    pd.DataFrame,
    dict[str, Any],
    np.ndarray,
    pd.DataFrame,
    pd.DataFrame,
    pd.DataFrame,
    pd.DataFrame,
]:
    """Run fixed validation ablations and the small Logistic/XGBoost grids."""
    print_pipeline_step("4/8", "Training and comparing validation candidates")
    feature_set_rows: list[dict[str, Any]] = []
    comparison_rows: list[dict[str, Any]] = []
    topk_rows: list[dict[str, Any]] = []
    weekly_rows: list[pd.DataFrame] = []

    selected_model_specification: dict[str, Any] = {}
    selected_validation_probability: np.ndarray | None = None
    best_pr_auc = -np.inf
    best_logistic: tuple[Pipeline, str, dict[str, float]] | None = None
    best_xgboost: tuple[Pipeline, str, dict[str, float]] | None = None

    def record(
        model_name: str,
        feature_set: str,
        parameters: dict[str, Any],
        pipeline: Pipeline,
        metrics: dict[str, float],
        top_k_metrics: pd.DataFrame,
        validation_no_purchase_probability: np.ndarray,
        feature_set_table: bool,
    ) -> None:
        nonlocal selected_model_specification
        nonlocal selected_validation_probability
        nonlocal best_pr_auc, best_logistic, best_xgboost
        candidate_id = f"{model_name}__{feature_set}__{len(comparison_rows) + 1:02d}"
        row = {
            "candidate_id": candidate_id,
            "model_name": model_name,
            "feature_set": feature_set,
            "class_weight_or_scale_pos_weight": parameters.get(
                "class_weight", parameters.get("scale_pos_weight", 1)
            ),
            "hyperparameters": json.dumps(parameters, sort_keys=True),
            **metrics,
        }
        comparison_rows.append(row)
        if feature_set_table:
            feature_set_rows.append(row.copy())
        for top_k_row in top_k_metrics.to_dict("records"):
            topk_rows.append(
                {
                    "candidate_id": candidate_id,
                    "model_name": model_name,
                    "feature_set": feature_set,
                    **top_k_row,
                }
            )
        weekly_rows.append(
            evaluate_weekly_model_stability(
                validation_data,
                validation_no_purchase_probability,
                candidate_id,
            )
        )
        if metrics["pr_auc"] > best_pr_auc:
            best_pr_auc = metrics["pr_auc"]
            selected_validation_probability = validation_no_purchase_probability
            selected_model_specification = {
                "model_name": model_name,
                "candidate_id": candidate_id,
                "feature_set": feature_set,
                "features": feature_sets[feature_set],
                "parameters": parameters,
            }
        if "logistic" in model_name and (
            best_logistic is None or metrics["pr_auc"] > best_logistic[2]["pr_auc"]
        ):
            best_logistic = (pipeline, feature_set, metrics)
        if model_name.startswith("xgboost") and (
            best_xgboost is None or metrics["pr_auc"] > best_xgboost[2]["pr_auc"]
        ):
            best_xgboost = (pipeline, feature_set, metrics)

    # One fixed, unweighted logistic model per nested feature set.
    ablation_model_names = {
        "recency_only": "recency_logistic_baseline",
        "rfm_behavior": "rfm_logistic_baseline",
    }
    for feature_set_name, feature_names in feature_sets.items():
        model_pipeline = build_logistic_pipeline(
            feature_names, c_value=1.0, class_weight=None
        )
        (
            fitted_pipeline,
            validation_model_metrics,
            validation_top_k_metrics,
            validation_no_purchase_probability,
        ) = fit_and_evaluate_on_validation(
            model_pipeline,
            feature_names,
            train_data,
            validation_data,
        )
        record(
            ablation_model_names.get(feature_set_name, "logistic_feature_set_ablation"),
            feature_set_name,
            {"C": 1.0, "class_weight": None},
            fitted_pipeline,
            validation_model_metrics,
            validation_top_k_metrics,
            validation_no_purchase_probability,
            feature_set_table=True,
        )
        print(
            f"  {feature_set_name}: " f"PR-AUC={validation_model_metrics['pr_auc']:.4f}"
        )

    full_set = "full_behavior_plus_customer_state"
    full_features = feature_sets[full_set]

    # Small, explicit logistic candidate grid.
    for c_value in (0.1, 1.0, 10.0):
        for class_weight in (None, "balanced"):
            # The unweighted C=1 candidate was already fitted in the ablation.
            if c_value == 1.0 and class_weight is None:
                continue
            pipeline = build_logistic_pipeline(
                full_features,
                c_value=c_value,
                class_weight=class_weight,
            )
            (
                fitted_pipeline,
                validation_model_metrics,
                validation_top_k_metrics,
                validation_no_purchase_probability,
            ) = fit_and_evaluate_on_validation(
                pipeline, full_features, train_data, validation_data
            )
            record(
                (
                    "full_logistic_regression_balanced"
                    if class_weight == "balanced"
                    else "full_logistic_regression"
                ),
                full_set,
                {"C": c_value, "class_weight": class_weight},
                fitted_pipeline,
                validation_model_metrics,
                validation_top_k_metrics,
                validation_no_purchase_probability,
                feature_set_table=False,
            )

    purchase_to_no_purchase_ratio = float(
        (train_data[TARGET] == 0).sum() / (train_data[TARGET] == 1).sum()
    )
    xgb_candidates = [
        {
            "n_estimators": 200,
            "max_depth": 3,
            "learning_rate": 0.05,
            "subsample": 0.8,
            "colsample_bytree": 0.8,
            "scale_pos_weight": 1.0,
        },
        {
            "n_estimators": 400,
            "max_depth": 3,
            "learning_rate": 0.03,
            "subsample": 0.8,
            "colsample_bytree": 1.0,
            "scale_pos_weight": 1.0,
        },
        {
            "n_estimators": 300,
            "max_depth": 5,
            "learning_rate": 0.05,
            "subsample": 1.0,
            "colsample_bytree": 0.8,
            "scale_pos_weight": 1.0,
        },
        {
            "n_estimators": 300,
            "max_depth": 3,
            "learning_rate": 0.05,
            "subsample": 0.8,
            "colsample_bytree": 0.8,
            "scale_pos_weight": purchase_to_no_purchase_ratio,
        },
    ]
    for params in xgb_candidates:
        pipeline = build_xgboost_pipeline(full_features, params)
        (
            fitted_pipeline,
            validation_model_metrics,
            validation_top_k_metrics,
            validation_no_purchase_probability,
        ) = fit_and_evaluate_on_validation(
            pipeline, full_features, train_data, validation_data
        )
        record(
            ("xgboost_weighted" if params["scale_pos_weight"] != 1.0 else "xgboost"),
            full_set,
            params,
            fitted_pipeline,
            validation_model_metrics,
            validation_top_k_metrics,
            validation_no_purchase_probability,
            feature_set_table=False,
        )

    if (
        selected_validation_probability is None
        or best_logistic is None
        or best_xgboost is None
    ):
        raise RuntimeError("No validation model was successfully fitted")

    comparison = pd.DataFrame(comparison_rows).sort_values(
        ["pr_auc", "brier_score"], ascending=[False, True]
    )
    feature_comparison = pd.DataFrame(feature_set_rows).sort_values(
        "pr_auc", ascending=False
    )
    topk_comparison = pd.DataFrame(topk_rows)

    best_name = selected_model_specification["candidate_id"]
    weekly = pd.concat(weekly_rows, ignore_index=True)
    calibration = create_calibration_bin_table(
        validation_data[TARGET].astype(int).to_numpy(),
        selected_validation_probability,
        best_name,
    )

    logistic_pipeline, logistic_set, _ = best_logistic
    logistic_names = get_transformed_feature_names(logistic_pipeline)
    logistic_values = logistic_pipeline.named_steps["model"].coef_[0]
    logistic_coefficients = pd.DataFrame(
        {"feature_name": logistic_names, "coefficient": logistic_values}
    )
    logistic_coefficients["absolute_coefficient"] = logistic_coefficients[
        "coefficient"
    ].abs()
    logistic_coefficients.insert(0, "feature_set", logistic_set)
    logistic_coefficients = logistic_coefficients.sort_values(
        "absolute_coefficient", ascending=False
    )

    xgb_pipeline, xgb_set, _ = best_xgboost
    xgb_importance = pd.DataFrame(
        {
            "feature_set": xgb_set,
            "feature_name": get_transformed_feature_names(xgb_pipeline),
            "gain_importance": xgb_pipeline.named_steps["model"].feature_importances_,
        }
    ).sort_values("gain_importance", ascending=False)

    return (
        feature_comparison,
        comparison,
        topk_comparison,
        selected_model_specification,
        selected_validation_probability,
        weekly,
        calibration,
        logistic_coefficients,
        xgb_importance,
    )


# ============================================================
# Output and plots
# ============================================================
def save_validation_figures(
    validation_data: pd.DataFrame,
    selected_validation_probability: np.ndarray,
    validation_model_performance: pd.DataFrame,
    validation_calibration_by_bin: pd.DataFrame,
    validation_weekly_stability: pd.DataFrame,
) -> None:
    """Save the four validation figures produced by the existing analysis."""
    print_pipeline_step("6/8", "Saving validation figures")
    actual_no_purchase = validation_data[TARGET].astype(int).to_numpy()
    precision, recall, _ = precision_recall_curve(
        actual_no_purchase, selected_validation_probability
    )

    plt.figure(figsize=(7, 5))
    plt.plot(recall, precision, label="Best validation model")
    plt.axhline(
        actual_no_purchase.mean(),
        color="gray",
        linestyle="--",
        label="No-skill prevalence",
    )
    plt.xlabel("Recall")
    plt.ylabel("Precision")
    plt.title("Validation precision-recall curve")
    plt.legend()
    plt.tight_layout()
    plt.savefig(FIGURE_DIR / "validation_precision_recall_curve.png", dpi=160)
    plt.close()

    plt.figure(figsize=(6, 6))
    plt.plot(
        validation_calibration_by_bin["mean_predicted_no_purchase_probability"],
        validation_calibration_by_bin["observed_no_purchase_rate"],
        marker="o",
    )
    plt.plot([0, 1], [0, 1], color="gray", linestyle="--")
    plt.xlabel("Mean predicted no-purchase probability")
    plt.ylabel("Observed no-purchase rate")
    plt.title("Validation calibration")
    plt.tight_layout()
    plt.savefig(FIGURE_DIR / "validation_calibration_curve.png", dpi=160)
    plt.close()

    plot_data = validation_model_performance.head(12)
    labels = plot_data["model_name"] + "\n" + plot_data["feature_set"]
    plt.figure(figsize=(11, 6))
    plt.barh(np.arange(len(plot_data)), plot_data["pr_auc"])
    plt.yticks(np.arange(len(plot_data)), labels)
    plt.gca().invert_yaxis()
    plt.xlabel("Validation PR-AUC")
    plt.title("Top validation model candidates")
    plt.tight_layout()
    plt.savefig(FIGURE_DIR / "validation_model_performance_comparison.png", dpi=160)
    plt.close()

    selected_model_name = str(validation_calibration_by_bin["model_name"].iloc[0])
    selected_model_weekly_metrics = validation_weekly_stability.loc[
        validation_weekly_stability["model_name"] == selected_model_name
    ]
    fig, left = plt.subplots(figsize=(9, 5))
    left.plot(
        selected_model_weekly_metrics["reference_week"],
        selected_model_weekly_metrics["pr_auc"],
        marker="o",
        label="PR-AUC",
    )
    left.set_xlabel("Reference week")
    left.set_ylabel("PR-AUC")
    right = left.twinx()
    right.plot(
        selected_model_weekly_metrics["reference_week"],
        selected_model_weekly_metrics["lift_at_10pct"],
        marker="s",
        color="tab:orange",
        label="Lift@10%",
    )
    right.set_ylabel("Lift@10%")
    fig.suptitle("Validation weekly stability")
    fig.tight_layout()
    fig.savefig(FIGURE_DIR / "validation_weekly_model_stability.png", dpi=160)
    plt.close(fig)


def rebuild_selected_model_pipeline(spec: dict[str, Any]) -> Pipeline:
    """Recreate the validation-selected, unfitted pipeline for the final test."""
    if "logistic" in spec["model_name"]:
        return build_logistic_pipeline(
            spec["features"],
            c_value=float(spec["parameters"]["C"]),
            class_weight=spec["parameters"].get("class_weight"),
        )
    return build_xgboost_pipeline(spec["features"], spec["parameters"])


def run_final_test_once(
    data_splits: dict[str, pd.DataFrame],
    selected_model_specification: dict[str, Any],
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Fit the locked model on TRAIN+VALIDATION and evaluate TEST exactly once."""
    print_pipeline_step("8/8", "Running the explicitly enabled final test")
    development_data = pd.concat(
        [data_splits["TRAIN"], data_splits["VALIDATION"]], ignore_index=True
    )
    test_data = data_splits["TEST"]
    selected_feature_names = selected_model_specification["features"]
    selected_model_pipeline = rebuild_selected_model_pipeline(
        selected_model_specification
    )
    selected_model_pipeline.fit(
        development_data[selected_feature_names],
        development_data[TARGET].astype(int),
    )
    test_no_purchase_probability = selected_model_pipeline.predict_proba(
        test_data[selected_feature_names]
    )[:, 1]
    final_test_metrics, final_test_top_k_metrics = calculate_probability_model_metrics(
        test_data[TARGET].astype(int).to_numpy(),
        test_no_purchase_probability,
    )
    final_test_model_performance = pd.DataFrame(
        [{**selected_model_specification, **final_test_metrics}]
    )
    final_test_top_k_metrics.insert(
        0, "model_name", selected_model_specification["model_name"]
    )
    final_test_weekly_stability = evaluate_weekly_model_stability(
        test_data,
        test_no_purchase_probability,
        selected_model_specification["model_name"],
    )

    precision, recall, _ = precision_recall_curve(
        test_data[TARGET].astype(int), test_no_purchase_probability
    )
    plt.figure(figsize=(7, 5))
    plt.plot(recall, precision)
    plt.xlabel("Recall")
    plt.ylabel("Precision")
    plt.title("Final test precision-recall curve")
    plt.tight_layout()
    plt.savefig(FIGURE_DIR / "final_test_precision_recall_curve.png", dpi=160)
    plt.close()
    return (
        final_test_model_performance,
        final_test_top_k_metrics,
        final_test_weekly_stability,
    )


def save_validation_outputs(
    data_quality_summary: pd.DataFrame,
    time_split_summary: pd.DataFrame,
    train_feature_missingness: pd.DataFrame,
    train_numeric_feature_profile: pd.DataFrame,
    train_categorical_feature_profile: pd.DataFrame,
    validation_feature_set_comparison: pd.DataFrame,
    validation_model_performance: pd.DataFrame,
    validation_top_k_metrics: pd.DataFrame,
    validation_weekly_stability: pd.DataFrame,
    validation_calibration_by_bin: pd.DataFrame,
    logistic_regression_coefficients: pd.DataFrame,
    xgboost_feature_importance: pd.DataFrame,
) -> None:
    """Write the official validation tables and environment manifest."""
    print_pipeline_step("5/8", "Saving validation tables")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    FIGURE_DIR.mkdir(parents=True, exist_ok=True)
    data_quality_summary.to_csv(OUTPUT_DIR / "01_data_quality_summary.csv", index=False)
    time_split_summary.to_csv(OUTPUT_DIR / "02_time_split_summary.csv", index=False)
    train_feature_missingness.to_csv(
        OUTPUT_DIR / "03_train_feature_missingness.csv", index=False
    )
    train_numeric_feature_profile.to_csv(
        OUTPUT_DIR / "04_train_numeric_feature_profile.csv", index=False
    )
    train_categorical_feature_profile.to_csv(
        OUTPUT_DIR / "04b_train_categorical_feature_profile.csv", index=False
    )
    validation_feature_set_comparison.to_csv(
        OUTPUT_DIR / "05_validation_feature_set_comparison.csv", index=False
    )
    validation_model_performance.to_csv(
        OUTPUT_DIR / "06_validation_model_performance.csv", index=False
    )
    validation_top_k_metrics.to_csv(
        OUTPUT_DIR / "07_validation_top_k_metrics.csv", index=False
    )
    validation_weekly_stability.to_csv(
        OUTPUT_DIR / "08_validation_weekly_stability.csv", index=False
    )
    validation_calibration_by_bin.to_csv(
        OUTPUT_DIR / "09_validation_calibration_by_bin.csv", index=False
    )
    logistic_regression_coefficients.to_csv(
        OUTPUT_DIR / "10_logistic_regression_coefficients.csv", index=False
    )
    xgboost_feature_importance.to_csv(
        OUTPUT_DIR / "11_xgboost_feature_importance.csv", index=False
    )

    versions = {
        "python": platform.python_version(),
        "pandas": pd.__version__,
        "numpy": np.__version__,
        "scikit_learn": sklearn.__version__,
        "xgboost": xgboost.__version__,
        "random_state": RANDOM_STATE,
        "run_final_test": RUN_FINAL_TEST,
    }
    (OUTPUT_DIR / "run_environment.json").write_text(
        json.dumps(versions, indent=2), encoding="utf-8"
    )


# ============================================================
# Main
# ============================================================
def main() -> None:
    """Run validation selection and keep TEST protected unless explicitly enabled."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    FIGURE_DIR.mkdir(parents=True, exist_ok=True)

    model_dataset, data_quality_summary = load_and_validate_model_dataset(INPUT_CSV)
    data_splits, time_split_summary = create_time_based_splits(model_dataset)
    feature_sets = build_feature_sets()
    all_feature_names = feature_sets["full_behavior_plus_customer_state"]

    (
        train_feature_missingness,
        train_numeric_feature_profile,
        train_categorical_feature_profile,
    ) = profile_training_features(data_splits["TRAIN"], all_feature_names)

    (
        validation_feature_set_comparison,
        validation_model_performance,
        validation_top_k_metrics,
        selected_model_specification,
        selected_validation_probability,
        validation_weekly_stability,
        validation_calibration_by_bin,
        logistic_regression_coefficients,
        xgboost_feature_importance,
    ) = run_validation_experiments(
        data_splits["TRAIN"], data_splits["VALIDATION"], feature_sets
    )

    save_validation_outputs(
        data_quality_summary,
        time_split_summary,
        train_feature_missingness,
        train_numeric_feature_profile,
        train_categorical_feature_profile,
        validation_feature_set_comparison,
        validation_model_performance,
        validation_top_k_metrics,
        validation_weekly_stability,
        validation_calibration_by_bin,
        logistic_regression_coefficients,
        xgboost_feature_importance,
    )
    save_validation_figures(
        data_splits["VALIDATION"],
        selected_validation_probability,
        validation_model_performance,
        validation_calibration_by_bin,
        validation_weekly_stability,
    )

    print_pipeline_step("7/8", "Saving validation results and selected model")
    print(json.dumps(selected_model_specification, indent=2, default=str))
    print(f"RUN_FINAL_TEST={RUN_FINAL_TEST}")

    if RUN_FINAL_TEST:
        (
            final_test_model_performance,
            final_test_top_k_metrics,
            final_test_weekly_stability,
        ) = run_final_test_once(data_splits, selected_model_specification)
        final_test_model_performance.to_csv(
            OUTPUT_DIR / "12_final_test_model_performance.csv", index=False
        )
        final_test_top_k_metrics.to_csv(
            OUTPUT_DIR / "13_final_test_top_k_metrics.csv", index=False
        )
        final_test_weekly_stability.to_csv(
            OUTPUT_DIR / "14_final_test_weekly_stability.csv", index=False
        )
    else:
        print_pipeline_step("8/8", "Final test remains protected")
        test_data = data_splits["TEST"]
        print(
            f"Test rows={len(test_data):,}, weeks="
            f"{test_data['reference_week'].min()}-"
            f"{test_data['reference_week'].max()}. "
            "No test target metrics or predictions were computed."
        )


if __name__ == "__main__":
    main()
