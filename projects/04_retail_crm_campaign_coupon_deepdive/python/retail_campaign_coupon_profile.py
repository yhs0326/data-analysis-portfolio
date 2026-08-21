from pathlib import Path
from typing import Any

import pandas as pd


PROJECT_DIR = Path(__file__).resolve().parent
RAW_DIR = PROJECT_DIR
OUTPUT_DIR = PROJECT_DIR / "outputs" / "profiling_campaign_coupon"
CHUNK_SIZE = 200_000

FILES = {
    "campaign_desc.csv": ["CAMPAIGN", "DESCRIPTION", "START_DAY", "END_DAY"],
    "campaign_table.csv": ["HOUSEHOLD_KEY", "CAMPAIGN"],
    "coupon.csv": ["COUPON_UPC", "PRODUCT_ID", "CAMPAIGN"],
    "coupon_redempt.csv": ["HOUSEHOLD_KEY", "COUPON_UPC", "CAMPAIGN", "DAY"],
}
ID_COLUMNS = {"HOUSEHOLD_KEY", "COUPON_UPC", "PRODUCT_ID", "CAMPAIGN"}
RANGE_COLUMNS = {"START_DAY", "END_DAY", "DAY"}
FILE_COLUMNS = ["file_name", "file_size_mb", "row_count", "column_count", "duplicate_row_count"]
PROFILE_COLUMNS = [
    "file_name", "column_name", "dtype", "row_count", "null_count",
    "null_rate", "unique_count", "min_value", "max_value",
]
CHECK_COLUMNS = ["check_group", "check_name", "result_value", "status", "description"]


def validate_headers() -> tuple[dict[str, Path], dict[str, dict[str, str]]]:
    """Validate required files/headers and retain their actual spelling."""
    paths: dict[str, Path] = {}
    names: dict[str, dict[str, str]] = {}
    for file_name, required in FILES.items():
        path = RAW_DIR / file_name
        if not path.is_file():
            raise FileNotFoundError(f"필수 CSV 파일 없음 | 파일={file_name} | 경로={path}")
        try:
            actual = list(pd.read_csv(path, nrows=0).columns)
        except Exception as exc:
            raise RuntimeError(f"CSV Header 읽기 실패 | 파일={file_name} | 오류={exc}") from exc
        lookup = {str(column).casefold(): str(column) for column in actual}
        missing = [column for column in required if column.casefold() not in lookup]
        if missing:
            raise ValueError(
                f"필수 컬럼 없음 | 파일={file_name} | 예상 필수 컬럼={required} | "
                f"실제 컬럼={actual} | 누락 컬럼={missing}"
            )
        paths[file_name] = path
        names[file_name] = {column: lookup[column.casefold()] for column in required}
    return paths, names


def add_check(
    rows: list[dict[str, Any]], group: str, name: str, value: Any,
    status: str, description: str,
) -> None:
    rows.append(dict(zip(CHECK_COLUMNS, [group, name, value, status, description])))


def add_null_unique_checks(
    rows: list[dict[str, Any]], group: str, frame: pd.DataFrame, columns: list[str],
) -> None:
    for column in columns:
        nulls = int(frame[column].isna().sum())
        add_check(rows, group, f"{column}_null_count", nulls, "PASS" if nulls == 0 else "WARN", "NULL 행 수")
        add_check(rows, group, f"{column}_unique_count", int(frame[column].nunique()), "INFO", "NULL 제외 고유값 수")


def add_distribution(rows: list[dict[str, Any]], group: str, prefix: str, values: pd.Series) -> None:
    for metric, value in (
        ("min", values.min()), ("median", values.median()),
        ("mean", values.mean()), ("max", values.max()),
    ):
        add_check(rows, group, f"{prefix}_{metric}", value, "INFO", f"{prefix} {metric} 요약")


def add_reference_check(
    rows: list[dict[str, Any]], group: str, child: pd.Series, parent: pd.Series,
    key_name: str,
) -> int:
    child_values = pd.Index(child.dropna().unique())
    parent_values = pd.Index(parent.dropna().unique())
    mapped = child_values.isin(parent_values)
    missing = child_values[~mapped]
    total, mapped_count = len(child_values), int(mapped.sum())
    add_check(rows, group, f"total_unique_{key_name}", total, "INFO", f"참조 대상 고유 {key_name} 수")
    add_check(rows, group, f"mapped_unique_{key_name}", mapped_count, "INFO", f"매핑된 고유 {key_name} 수")
    add_check(rows, group, f"unmapped_unique_{key_name}", len(missing), "PASS" if len(missing) == 0 else "WARN", f"미매핑 고유 {key_name} 수")
    add_check(rows, group, f"{key_name}_mapping_rate", mapped_count / total if total else 1.0, "INFO", "고유키 기준 매핑률")
    add_check(rows, group, f"unmapped_{key_name}_sample", ", ".join(map(str, missing[:20])), "INFO", "미매핑 값 최대 20개")
    return len(missing)


def main() -> None:
    paths, names = validate_headers()
    frames: dict[str, pd.DataFrame] = {}
    try:
        for file_name, path in paths.items():
            dtype = {actual: "string" for semantic, actual in names[file_name].items() if semantic in ID_COLUMNS}
            frames[file_name] = pd.read_csv(path, dtype=dtype)
    except Exception as exc:
        raise RuntimeError(f"CSV 읽기 실패 | 파일={file_name} | 오류={exc}") from exc
    print("[01] 파일 로드 완료")

    file_rows: list[dict[str, Any]] = []
    profile_rows: list[dict[str, Any]] = []
    duplicate_counts: dict[str, int] = {}
    for file_name, frame in frames.items():
        duplicate_counts[file_name] = int(frame.duplicated().sum())
        file_rows.append(dict(zip(FILE_COLUMNS, [
            file_name, paths[file_name].stat().st_size / (1024 ** 2), len(frame),
            len(frame.columns), duplicate_counts[file_name],
        ])))
        semantic_ranges = {names[file_name][column] for column in RANGE_COLUMNS if column in names[file_name]}
        for column in frame.columns:
            series = frame[column]
            calculate_range = pd.api.types.is_numeric_dtype(series) or column in semantic_ranges
            numeric = pd.to_numeric(series, errors="coerce") if column in semantic_ranges else series
            profile_rows.append(dict(zip(PROFILE_COLUMNS, [
                file_name, column, str(series.dtype), len(frame), int(series.isna().sum()),
                float(series.isna().mean()), int(series.nunique()),
                numeric.min() if calculate_range and numeric.notna().any() else None,
                numeric.max() if calculate_range and numeric.notna().any() else None,
            ])))
    print("[02] 공통 프로파일 완료")

    checks: list[dict[str, Any]] = []
    for file_name, duplicate_count in duplicate_counts.items():
        add_check(
            checks, "common", f"{file_name}_duplicate_row_count", duplicate_count,
            "PASS" if duplicate_count == 0 else "WARN", "완전히 동일한 첫 행 이후 중복 행 수",
        )
    desc, table = frames["campaign_desc.csv"], frames["campaign_table.csv"]
    dn, tn = names["campaign_desc.csv"], names["campaign_table.csv"]
    campaign, start, end, description = dn["CAMPAIGN"], dn["START_DAY"], dn["END_DAY"], dn["DESCRIPTION"]
    start_values, end_values = pd.to_numeric(desc[start], errors="coerce"), pd.to_numeric(desc[end], errors="coerce")
    add_null_unique_checks(checks, "campaign_desc", desc, [campaign, start, end])
    campaign_duplicates = int(desc.duplicated([campaign]).sum())
    add_check(checks, "campaign_desc", "campaign_duplicate_count", campaign_duplicates, "PASS" if campaign_duplicates == 0 else "WARN", "CAMPAIGN 첫 행 이후 중복 행 수")
    for column, values in ((start, start_values), (end, end_values)):
        add_check(checks, "campaign_desc", f"{column}_min", values.min(), "INFO", "기간 컬럼 최소값")
        add_check(checks, "campaign_desc", f"{column}_max", values.max(), "INFO", "기간 컬럼 최대값")
    invalid_period = int(start_values.gt(end_values).sum())
    add_check(checks, "campaign_desc", "start_after_end_count", invalid_period, "PASS" if invalid_period == 0 else "WARN", "START_DAY가 END_DAY보다 큰 행 수")
    duration = end_values - start_values + 1
    for metric, value in (("min", duration.min()), ("median", duration.median()), ("max", duration.max())):
        add_check(checks, "campaign_desc", f"campaign_duration_{metric}", value, "INFO", "캠페인 기간(양 끝 포함) 요약")
    description_counts = desc.groupby(description, dropna=False)[campaign].nunique()
    add_check(checks, "campaign_desc", "description_unique_count", int(desc[description].nunique()), "INFO", "DESCRIPTION 고유값 수")
    for value, count in description_counts.items():
        add_check(checks, "campaign_desc", f"description_campaign_count[{value}]", int(count), "INFO", "DESCRIPTION별 고유 캠페인 수")

    household, table_campaign = tn["HOUSEHOLD_KEY"], tn["CAMPAIGN"]
    add_null_unique_checks(checks, "campaign_table", table, [household, table_campaign])
    table_pair_duplicates = int(table.duplicated([household, table_campaign]).sum())
    add_check(checks, "campaign_table", "household_campaign_duplicate_count", table_pair_duplicates, "PASS" if table_pair_duplicates == 0 else "WARN", "HOUSEHOLD_KEY+CAMPAIGN 첫 행 이후 중복 행 수")
    add_check(checks, "campaign_table", "unique_household_campaign_count", int(table.drop_duplicates([household, table_campaign]).shape[0]), "INFO", "고유 가구-캠페인 조합 수")
    campaign_households = table.groupby(table_campaign)[household].nunique()
    add_distribution(checks, "campaign_table", "households_per_campaign", campaign_households)
    print("[03] Campaign 구조 검증 완료")

    coupon = frames["coupon.csv"]
    cn = names["coupon.csv"]
    coupon_upc, product, coupon_campaign = cn["COUPON_UPC"], cn["PRODUCT_ID"], cn["CAMPAIGN"]
    add_null_unique_checks(checks, "coupon", coupon, [coupon_upc, product, coupon_campaign])
    coupon_product_duplicates = int(coupon.duplicated([coupon_upc, product]).sum())
    add_check(checks, "coupon", "coupon_product_duplicate_count", coupon_product_duplicates, "PASS" if coupon_product_duplicates == 0 else "WARN", "COUPON_UPC+PRODUCT_ID 첫 행 이후 중복 행 수")
    products_per_coupon = coupon.groupby(coupon_upc)[product].nunique()
    single_product = int(products_per_coupon.eq(1).sum())
    multi_product = int(products_per_coupon.ge(2).sum())
    add_check(checks, "coupon", "single_product_coupon_count", single_product, "INFO", "한 PRODUCT_ID에만 연결된 쿠폰 수")
    add_check(checks, "coupon", "multi_product_coupon_count", multi_product, "INFO", "둘 이상 PRODUCT_ID에 연결된 쿠폰 수")
    add_distribution(checks, "coupon", "products_per_coupon", products_per_coupon)
    coupons_per_campaign = coupon.groupby(coupon_campaign)[coupon_upc].nunique()
    add_distribution(checks, "coupon", "coupons_per_campaign", coupons_per_campaign)
    print("[04] Coupon 구조 검증 완료")

    redempt = frames["coupon_redempt.csv"]
    rn = names["coupon_redempt.csv"]
    rh, rc, rcam, redemption_day = (
    rn["HOUSEHOLD_KEY"],
    rn["COUPON_UPC"],
    rn["CAMPAIGN"],
    rn["DAY"],
)
    add_null_unique_checks(checks, "coupon_redempt", redempt, [rh, rc, rcam, redemption_day])
    redemption_duplicates = int(redempt.duplicated([rh, rc, rcam, redemption_day]).sum())
    add_check(checks, "coupon_redempt", "redemption_candidate_duplicate_count", redemption_duplicates, "PASS" if redemption_duplicates == 0 else "WARN", "가구+쿠폰+캠페인+상환일 첫 행 이후 중복 행 수")
    for key, prefix in ((rh, "redemptions_per_household"), (rcam, "redemptions_per_campaign"), (rc, "redemptions_per_coupon")):
        add_distribution(checks, "coupon_redempt", prefix, redempt.groupby(key).size())
    print("[05] Redemption 구조 검증 완료")

    unmapped_campaign = 0
    for group, child in (("campaign_table_to_desc", table[table_campaign]), ("coupon_to_desc", coupon[coupon_campaign]), ("redempt_to_desc", redempt[rcam])):
        unmapped_campaign += add_reference_check(checks, group, child, desc[campaign], "campaign")
    unmapped_coupon = add_reference_check(checks, "redempt_to_coupon", redempt[rc], coupon[coupon_upc], "coupon")

    valid_coupon_pairs = pd.MultiIndex.from_frame(coupon[[coupon_upc, coupon_campaign]].dropna().drop_duplicates())
    redemption_pairs = pd.MultiIndex.from_frame(redempt[[rc, rcam]])
    valid_pair = redemption_pairs.isin(valid_coupon_pairs) & redempt[rc].notna().to_numpy() & redempt[rcam].notna().to_numpy()
    invalid_pair_count = int((~valid_pair).sum())
    add_check(checks, "redemption_campaign_coupon", "total_redemption_rows", len(redempt), "INFO", "전체 상환 행 수")
    add_check(checks, "redemption_campaign_coupon", "valid_mapping_rows", int(valid_pair.sum()), "INFO", "coupon.csv에 조합이 존재하는 상환 행 수")
    add_check(checks, "redemption_campaign_coupon", "invalid_mapping_rows", invalid_pair_count, "PASS" if invalid_pair_count == 0 else "WARN", "coupon.csv에 조합이 없는 상환 행 수")
    add_check(checks, "redemption_campaign_coupon", "invalid_mapping_rate", invalid_pair_count / len(redempt) if len(redempt) else 0.0, "INFO", "비정상 조합 비율")

    unmapped_product: int | str = "reference_file_not_found"
    product_path = RAW_DIR / "product.csv"
    if product_path.is_file():
        try:
            product_header = list(pd.read_csv(product_path, nrows=0).columns)
            product_lookup = {str(column).casefold(): str(column) for column in product_header}
            if "product_id" not in product_lookup:
                raise ValueError(f"필수 컬럼 없음 | 파일=product.csv | 실제 컬럼={product_header} | 누락 컬럼=['PRODUCT_ID']")
            product_actual = product_lookup["product_id"]
            product_ids = pd.read_csv(product_path, usecols=[product_actual], dtype={product_actual: "string"})[product_actual]
        except Exception as exc:
            raise RuntimeError(f"참조 CSV 읽기 실패 | 파일=product.csv | 오류={exc}") from exc
        unmapped_product = add_reference_check(checks, "coupon_to_product", coupon[product], product_ids, "product")
    else:
        add_check(checks, "coupon_to_product", "reference_file_status", "not_found", "INFO", "product.csv가 없어 선택 검증을 건너뜀")

    transaction_path = RAW_DIR / "transaction_data.csv"
    if transaction_path.is_file():
        try:
            transaction_header = list(pd.read_csv(transaction_path, nrows=0).columns)
            transaction_lookup = {str(column).casefold(): str(column) for column in transaction_header}
            if "household_key" not in transaction_lookup:
                raise ValueError(f"필수 컬럼 없음 | 파일=transaction_data.csv | 실제 컬럼={transaction_header} | 누락 컬럼=['HOUSEHOLD_KEY']")
            transaction_household = transaction_lookup["household_key"]
            transaction_households: set[str] = set()
            for chunk in pd.read_csv(transaction_path, usecols=[transaction_household], dtype={transaction_household: "string"}, chunksize=CHUNK_SIZE):
                transaction_households.update(chunk[transaction_household].dropna().unique())
            reference_households = pd.Series(list(transaction_households), dtype="string")
        except Exception as exc:
            raise RuntimeError(f"참조 CSV 읽기 실패 | 파일=transaction_data.csv | 오류={exc}") from exc
        add_reference_check(checks, "campaign_table_to_transaction", table[household], reference_households, "household")
        add_reference_check(checks, "redempt_to_transaction", redempt[rh], reference_households, "household")
    else:
        add_check(checks, "household_to_transaction", "reference_file_status", "not_found", "INFO", "transaction_data.csv가 없어 선택 검증을 건너뜀")
    print("[06] 파일 간 Key 검증 완료")

    period_keys = pd.DataFrame({
        rcam: desc[campaign], "_start": start_values, "_end": end_values,
    }).drop_duplicates()
    unambiguous = period_keys.groupby(rcam, dropna=False).size().eq(1)
    period_keys = period_keys[period_keys[rcam].isin(unambiguous[unambiguous].index)]
    period_check = redempt[[rcam, redemption_day]].merge(period_keys, on=rcam, how="left", validate="many_to_one")
    redemption_values = pd.to_numeric(period_check[redemption_day], errors="coerce")
    known = redemption_values.notna() & period_check["_start"].notna() & period_check["_end"].notna()
    before = known & redemption_values.lt(period_check["_start"])
    after = known & redemption_values.gt(period_check["_end"])
    inside = known & ~before & ~after
    unknown = ~known
    outside_count = int(before.sum() + after.sum())
    for check_name, value, status, description_text in (
        ("total_redemptions", len(redempt), "INFO", "전체 상환 행 수"),
        ("inside_campaign_period", int(inside.sum()), "INFO", "캠페인 기간 내부 상환 수"),
        ("before_campaign_start", int(before.sum()), "PASS" if not before.any() else "WARN", "캠페인 시작 전 상환 수"),
        ("after_campaign_end", int(after.sum()), "PASS" if not after.any() else "WARN", "캠페인 종료 후 상환 수"),
        ("period_unavailable", int(unknown.sum()), "PASS" if not unknown.any() else "WARN", "NULL·미매핑·기간 중복으로 확인 불가한 상환 수"),
    ):
        add_check(checks, "redemption_campaign_period", check_name, value, status, description_text)
    print("[07] Campaign 기간 검증 완료")

    try:
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise RuntimeError(f"결과 디렉터리 생성 실패 | 경로={OUTPUT_DIR} | 오류={exc}") from exc
    pd.DataFrame(file_rows, columns=FILE_COLUMNS).to_csv(OUTPUT_DIR / "campaign_coupon_file_summary.csv", index=False, encoding="utf-8-sig")
    pd.DataFrame(profile_rows, columns=PROFILE_COLUMNS).to_csv(OUTPUT_DIR / "campaign_coupon_column_profile.csv", index=False, encoding="utf-8-sig")
    pd.DataFrame(checks, columns=CHECK_COLUMNS).to_csv(OUTPUT_DIR / "campaign_coupon_quality_checks.csv", index=False, encoding="utf-8-sig")
    print("[08] 결과 저장 완료")
    print("\n프로파일링 완료\n")
    for row in file_rows:
        print(f"{row['file_name']:<25}: {row['row_count']:,} rows")
    print(f"\n미매핑 Campaign          : {unmapped_campaign:,}")
    print(f"미매핑 Coupon            : {unmapped_coupon:,}")
    print(f"미매핑 Product           : {unmapped_product}")
    print(f"기간 밖 Redemption       : {outside_count:,}")
    print(f"다중 Product 연결 Coupon : {multi_product:,}")
    print(f"\n결과 저장 위치:\n{OUTPUT_DIR}")


if __name__ == "__main__":
    main()
