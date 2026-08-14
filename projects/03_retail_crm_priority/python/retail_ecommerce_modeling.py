from __future__ import annotations

import json
import math
import platform
from datetime import datetime, timezone
from importlib.metadata import version
from pathlib import Path
from typing import Any, Iterable

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import sklearn
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

# ============================================================
# CONFIG
# ============================================================
PROJECT_DIR = Path(__file__).resolve().parent
INPUT_CSV = PROJECT_DIR / "model_dataset.csv"

OUTPUT_DIR = PROJECT_DIR / "outputs" / "modeling"
FIGURE_DIR = OUTPUT_DIR / "figures"

RANDOM_STATE = 42
RUN_FINAL_TEST = False
RUN_CRM_WEEK98_SIMULATION = False
RUN_REVISED_CRM_WEEK98_SIMULATION = False
RUN_REVISED_CRM_WEEKLY_STABILITY = True
TOP_K_VALUES = (0.05, 0.10, 0.20)
TARGET = "target_no_purchase_4w"
KEY_COLUMNS = ["household_key", "reference_week"]
EXPECTED_ROWS = 182_500
EXPECTED_HOUSEHOLDS = 2_500
EXPECTED_WEEK_MIN = 26
EXPECTED_WEEK_MAX = 98
EXPECTED_WEEK_COUNT = 73

FINAL_MODEL_SPEC = {
    "model_family": "logistic_regression",
    "feature_set": "full_behavior_plus_customer_state",
    "C": 1.0,
    "class_weight": None,
    "random_state": RANDOM_STATE,
}
FINAL_TEST_COMPLETION_MARKER = OUTPUT_DIR / "final_test_completed.json"

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
        # Split construction never inspects TEST outcomes; the one-time evaluator does.
        protected_test = name == "TEST"
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
    from xgboost import XGBClassifier

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
                "precision_at_10pct": top_10pct_metrics["precision_at_k"],
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
    dict[str, dict[str, Any]],
]:
    """Run fixed validation ablations and the small Logistic/XGBoost grids."""
    print_pipeline_step("4/8", "Training and comparing validation candidates")
    feature_set_rows: list[dict[str, Any]] = []
    comparison_rows: list[dict[str, Any]] = []
    topk_rows: list[dict[str, Any]] = []
    weekly_rows: list[pd.DataFrame] = []

    validation_pr_auc_leader_specification: dict[str, Any] = {}
    validation_pr_auc_leader_probability: np.ndarray | None = None
    validation_finalists: dict[str, dict[str, Any]] = {}
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
        nonlocal validation_pr_auc_leader_specification
        nonlocal validation_pr_auc_leader_probability
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
        candidate_weekly_metrics = evaluate_weekly_model_stability(
            validation_data,
            validation_no_purchase_probability,
            candidate_id,
        )
        weekly_rows.append(candidate_weekly_metrics)
        if metrics["pr_auc"] > best_pr_auc:
            best_pr_auc = metrics["pr_auc"]
            validation_pr_auc_leader_probability = validation_no_purchase_probability
            validation_pr_auc_leader_specification = {
                "model_name": model_name,
                "candidate_id": candidate_id,
                "feature_set": feature_set,
                "features": feature_sets[feature_set],
                "parameters": parameters,
            }

        model_family: str | None = None
        if "logistic" in model_name and parameters.get("class_weight") is None:
            model_family = "logistic_regression"
        elif (
            model_name.startswith("xgboost")
            and float(parameters.get("scale_pos_weight", 1.0)) == 1.0
        ):
            model_family = "xgboost"

        if model_family is not None:
            candidate_artifact = {
                "candidate_id": candidate_id,
                "model_family": model_family,
                "model_name": model_name,
                "feature_set": feature_set,
                "features": feature_sets[feature_set],
                "parameters": parameters,
                "pipeline": pipeline,
                "validation_probability": validation_no_purchase_probability,
                "metrics": metrics,
                "top_k_metrics": top_k_metrics.copy(),
                "weekly_metrics": candidate_weekly_metrics,
            }
            current_finalist = validation_finalists.get(model_family)
            candidate_rank = (metrics["pr_auc"], -metrics["brier_score"])
            current_rank = (
                (
                    current_finalist["metrics"]["pr_auc"],
                    -current_finalist["metrics"]["brier_score"],
                )
                if current_finalist is not None
                else (-np.inf, -np.inf)
            )
            if candidate_rank > current_rank:
                validation_finalists[model_family] = candidate_artifact
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
        validation_pr_auc_leader_probability is None
        or best_logistic is None
        or best_xgboost is None
        or set(validation_finalists) != {"logistic_regression", "xgboost"}
    ):
        raise RuntimeError("No validation model was successfully fitted")

    comparison = pd.DataFrame(comparison_rows).sort_values(
        ["pr_auc", "brier_score"], ascending=[False, True]
    )
    feature_comparison = pd.DataFrame(feature_set_rows).sort_values(
        "pr_auc", ascending=False
    )
    topk_comparison = pd.DataFrame(topk_rows)

    best_name = validation_pr_auc_leader_specification["candidate_id"]
    weekly = pd.concat(weekly_rows, ignore_index=True)
    calibration = create_calibration_bin_table(
        validation_data[TARGET].astype(int).to_numpy(),
        validation_pr_auc_leader_probability,
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
        validation_pr_auc_leader_specification,
        validation_pr_auc_leader_probability,
        weekly,
        calibration,
        logistic_coefficients,
        xgb_importance,
        validation_finalists,
    )


# ============================================================
# Validation finalist checkpoint
# ============================================================
def build_finalist_validation_comparisons(
    validation_data: pd.DataFrame,
    validation_finalists: dict[str, dict[str, Any]],
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Build equal-basis performance, Top-K, calibration, and weekly finalist tables."""
    actual_no_purchase = validation_data[TARGET].astype(int).to_numpy()
    model_comparison_rows: list[dict[str, Any]] = []
    top_k_tables: list[pd.DataFrame] = []
    calibration_tables: list[pd.DataFrame] = []
    weekly_tables: list[pd.DataFrame] = []

    for model_family in ("logistic_regression", "xgboost"):
        finalist = validation_finalists[model_family]
        validation_probability = finalist["validation_probability"]
        if len(validation_probability) != len(validation_data):
            raise ValueError(
                f"{model_family} finalist probabilities={len(validation_probability):,}; "
                f"validation rows={len(validation_data):,}"
            )

        model_comparison_rows.append(
            {
                "model_family": model_family,
                "candidate_id": finalist["candidate_id"],
                "model_name": finalist["model_name"],
                "feature_set": finalist["feature_set"],
                "hyperparameters": json.dumps(finalist["parameters"], sort_keys=True),
                **finalist["metrics"],
            }
        )

        finalist_top_k = finalist["top_k_metrics"].copy()
        finalist_top_k.insert(0, "candidate_id", finalist["candidate_id"])
        finalist_top_k.insert(0, "model_family", model_family)
        top_k_tables.append(finalist_top_k)

        finalist_calibration = create_calibration_bin_table(
            actual_no_purchase,
            validation_probability,
            finalist["candidate_id"],
        ).drop(columns="model_name")
        finalist_calibration.insert(0, "candidate_id", finalist["candidate_id"])
        finalist_calibration.insert(0, "model_family", model_family)
        calibration_tables.append(finalist_calibration)

        finalist_weekly = finalist["weekly_metrics"].copy()
        finalist_weekly.insert(0, "candidate_id", finalist["candidate_id"])
        finalist_weekly.insert(0, "model_family", model_family)
        weekly_tables.append(finalist_weekly)

    finalist_model_comparison = pd.DataFrame(model_comparison_rows)
    finalist_top_k_comparison = pd.concat(top_k_tables, ignore_index=True)
    finalist_calibration_by_bin = pd.concat(calibration_tables, ignore_index=True)
    finalist_weekly_stability = pd.concat(weekly_tables, ignore_index=True)

    validation_start_week, validation_end_week = SPLIT_RANGES["VALIDATION"]
    expected_validation_weeks = set(
        range(validation_start_week, validation_end_week + 1)
    )
    for model_family, weekly_data in finalist_weekly_stability.groupby("model_family"):
        actual_weeks = set(weekly_data["reference_week"])
        if actual_weeks != expected_validation_weeks:
            raise ValueError(
                f"{model_family} weekly validation coverage mismatch: "
                f"actual={sorted(actual_weeks)}"
            )

    finalist_weekly_summary = finalist_weekly_stability.groupby(
        "model_family", as_index=False
    ).agg(
        mean_pr_auc=("pr_auc", "mean"),
        min_pr_auc=("pr_auc", "min"),
        max_pr_auc=("pr_auc", "max"),
        std_pr_auc=("pr_auc", "std"),
        mean_lift_at_10pct=("lift_at_10pct", "mean"),
        min_lift_at_10pct=("lift_at_10pct", "min"),
        max_lift_at_10pct=("lift_at_10pct", "max"),
        std_lift_at_10pct=("lift_at_10pct", "std"),
        mean_brier_score=("brier_score", "mean"),
    )
    return (
        finalist_model_comparison,
        finalist_top_k_comparison,
        finalist_calibration_by_bin,
        finalist_weekly_stability,
        finalist_weekly_summary,
    )


def save_finalist_validation_outputs(
    finalist_model_comparison: pd.DataFrame,
    finalist_top_k_comparison: pd.DataFrame,
    finalist_calibration_by_bin: pd.DataFrame,
    finalist_weekly_stability: pd.DataFrame,
    finalist_weekly_summary: pd.DataFrame,
) -> None:
    """Save the five human-review tables for the finalist checkpoint."""
    finalist_model_comparison.to_csv(
        OUTPUT_DIR / "validation_finalist_model_comparison.csv", index=False
    )
    finalist_top_k_comparison.to_csv(
        OUTPUT_DIR / "validation_finalist_top_k_comparison.csv", index=False
    )
    finalist_calibration_by_bin.to_csv(
        OUTPUT_DIR / "validation_finalist_calibration_by_bin.csv", index=False
    )
    finalist_weekly_stability.to_csv(
        OUTPUT_DIR / "validation_finalist_weekly_stability.csv", index=False
    )
    finalist_weekly_summary.to_csv(
        OUTPUT_DIR / "validation_finalist_weekly_stability_summary.csv", index=False
    )


def save_finalist_validation_figures(
    finalist_calibration_by_bin: pd.DataFrame,
    finalist_weekly_stability: pd.DataFrame,
) -> None:
    """Plot calibration and weekly stability for both finalists on equal axes."""
    display_names = {
        "logistic_regression": "Logistic Regression",
        "xgboost": "XGBoost",
    }

    plt.figure(figsize=(7, 6))
    for model_family, calibration_data in finalist_calibration_by_bin.groupby(
        "model_family", sort=False
    ):
        plt.plot(
            calibration_data["mean_predicted_no_purchase_probability"],
            calibration_data["observed_no_purchase_rate"],
            marker="o",
            label=display_names[model_family],
        )
    plt.plot([0, 1], [0, 1], color="gray", linestyle="--", label="Ideal calibration")
    plt.xlabel("Mean predicted no-purchase probability")
    plt.ylabel("Observed no-purchase rate")
    plt.title("Validation finalist calibration comparison")
    plt.legend()
    plt.tight_layout()
    plt.savefig(FIGURE_DIR / "validation_finalist_calibration_comparison.png", dpi=160)
    plt.close()

    figure, axes = plt.subplots(2, 1, figsize=(9, 9), sharex=True)
    for model_family, weekly_data in finalist_weekly_stability.groupby(
        "model_family", sort=False
    ):
        label = display_names[model_family]
        axes[0].plot(
            weekly_data["reference_week"],
            weekly_data["pr_auc"],
            marker="o",
            label=label,
        )
        axes[1].plot(
            weekly_data["reference_week"],
            weekly_data["lift_at_10pct"],
            marker="o",
            label=label,
        )
    axes[0].set_ylabel("PR-AUC")
    axes[0].set_title("PR-AUC by validation reference week")
    axes[1].set_xlabel("Reference week")
    axes[1].set_ylabel("Lift@10%")
    axes[1].set_title("Lift@10% by validation reference week")
    for axis in axes:
        axis.legend()
    figure.tight_layout()
    figure.savefig(
        FIGURE_DIR / "validation_finalist_weekly_stability_comparison.png",
        dpi=160,
    )
    plt.close(figure)


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


def validate_frozen_final_model_spec(
    data_splits: dict[str, pd.DataFrame],
    feature_sets: dict[str, list[str]],
) -> tuple[pd.DataFrame, pd.DataFrame, list[str]]:
    """Validate the frozen recipe and protected TEST boundary before any scoring."""
    expected_spec = {
        "model_family": "logistic_regression",
        "feature_set": "full_behavior_plus_customer_state",
        "C": 1.0,
        "class_weight": None,
        "random_state": 42,
    }
    if FINAL_MODEL_SPEC != expected_spec or TARGET != "target_no_purchase_4w":
        raise RuntimeError("Frozen final model specification has been modified")

    final_feature_names = feature_sets[FINAL_MODEL_SPEC["feature_set"]]
    final_development_data = pd.concat(
        [data_splits["TRAIN"], data_splits["VALIDATION"]], ignore_index=True
    )
    final_test_data = data_splits["TEST"]
    expected_test_weeks = set(range(91, 99))
    actual_test_weeks = set(final_test_data["reference_week"].unique())
    expected_development_weeks = set(range(26, 75)) | set(range(79, 87))

    if len(final_test_data) != 20_000:
        raise RuntimeError(
            f"Final TEST row count must be 20,000; actual={len(final_test_data):,}"
        )
    if actual_test_weeks != expected_test_weeks:
        raise RuntimeError(
            f"Final TEST weeks must be 91-98; actual={sorted(actual_test_weeks)}"
        )
    development_weeks = set(final_development_data["reference_week"].unique())
    excluded_gap_weeks = set(range(75, 79)) | set(range(87, 91))
    if len(final_development_data) != 142_500:
        raise RuntimeError(
            "Final development row count must be 142,500; "
            f"actual={len(final_development_data):,}"
        )
    if development_weeks != expected_development_weeks:
        raise RuntimeError(
            "Final development weeks must contain TRAIN 26-74 and VALIDATION 79-86 "
            f"only; actual={sorted(development_weeks)}"
        )
    if (
        development_weeks & excluded_gap_weeks
        or development_weeks & expected_test_weeks
    ):
        raise RuntimeError(
            "Final development data contains a GAP or TEST reference week"
        )

    print(
        "\nFINAL MODEL LOCK CHECK\n"
        "Model: Logistic Regression\n"
        f"Feature set: {FINAL_MODEL_SPEC['feature_set']}\n"
        f"C: {FINAL_MODEL_SPEC['C']}\n"
        f"class_weight: {FINAL_MODEL_SPEC['class_weight']}\n"
        "Train weeks: 26-74\n"
        "Validation weeks: 79-86\n"
        f"Final development rows: {len(final_development_data):,}\n"
        "Excluded gaps: 75-78, 87-90\n"
        f"Test weeks: {min(actual_test_weeks)}-{max(actual_test_weeks)}\n"
        f"Test rows: {len(final_test_data):,}\n"
        "Test has not yet been scored.\n"
        "Frozen specification validation: PASS"
    )
    return final_development_data, final_test_data, final_feature_names


def final_test_output_paths() -> list[Path]:
    """Return every protected artifact written by the one-time TEST evaluation."""
    return [
        OUTPUT_DIR / "final_model_lock.json",
        OUTPUT_DIR / "12_final_test_model_performance.csv",
        OUTPUT_DIR / "13_final_test_top_k_metrics.csv",
        OUTPUT_DIR / "14_final_test_weekly_stability.csv",
        OUTPUT_DIR / "15_final_test_calibration_by_bin.csv",
        OUTPUT_DIR / "validation_vs_test_final_logistic_comparison.csv",
        OUTPUT_DIR / "final_test_scored_rows.csv",
        FIGURE_DIR / "final_test_calibration_curve.png",
        FIGURE_DIR / "final_test_weekly_stability.png",
        FINAL_TEST_COMPLETION_MARKER,
    ]


def assert_final_test_not_previously_run() -> None:
    """Refuse to rerun or overwrite any protected final TEST artifact."""
    existing_outputs = [path for path in final_test_output_paths() if path.exists()]
    if existing_outputs:
        existing_list = "\n".join(str(path) for path in existing_outputs)
        raise RuntimeError(
            "Final Test has already been completed or has existing protected output. "
            "Do not rerun or overwrite the protected Test evaluation.\n"
            f"Existing artifacts:\n{existing_list}"
        )


def load_frozen_logistic_validation_metrics() -> dict[str, float]:
    """Load the already-reviewed C=1 unweighted Logistic validation metrics."""
    comparison_path = OUTPUT_DIR / "validation_finalist_model_comparison.csv"
    if not comparison_path.exists():
        raise RuntimeError(
            "Validation finalist comparison is required before opening Final Test: "
            f"{comparison_path}"
        )
    comparison = pd.read_csv(comparison_path)
    parameter_values = comparison["hyperparameters"].map(json.loads)
    frozen_rows = comparison.loc[
        (comparison["model_family"] == "logistic_regression")
        & (comparison["feature_set"] == FINAL_MODEL_SPEC["feature_set"])
        & parameter_values.map(
            lambda parameters: float(parameters.get("C")) == FINAL_MODEL_SPEC["C"]
            and parameters.get("class_weight") is None
        )
    ]
    if len(frozen_rows) != 1:
        raise RuntimeError(
            "Expected exactly one frozen Logistic validation finalist row; "
            f"actual={len(frozen_rows)}"
        )
    return frozen_rows.iloc[0].to_dict()


def evaluate_frozen_final_test_once(
    final_development_data: pd.DataFrame,
    final_test_data: pd.DataFrame,
    final_feature_names: list[str],
    validation_metrics: dict[str, float],
) -> dict[str, Any]:
    """Fit one frozen Logistic pipeline and score protected TEST exactly once."""
    assert_final_test_not_previously_run()
    final_logistic_pipeline = build_logistic_pipeline(
        final_feature_names,
        c_value=FINAL_MODEL_SPEC["C"],
        class_weight=FINAL_MODEL_SPEC["class_weight"],
    )
    final_logistic_pipeline.fit(
        final_development_data[final_feature_names],
        final_development_data[TARGET].astype(int),
    )

    # This is the only TEST predict_proba call. Every downstream result reuses it.
    final_test_no_purchase_probability = final_logistic_pipeline.predict_proba(
        final_test_data[final_feature_names]
    )[:, 1]
    actual_test_no_purchase = final_test_data[TARGET].astype(int).to_numpy()
    final_test_metrics, final_test_top_k_metrics = calculate_probability_model_metrics(
        actual_test_no_purchase,
        final_test_no_purchase_probability,
    )
    final_test_weekly_stability = evaluate_weekly_model_stability(
        final_test_data,
        final_test_no_purchase_probability,
        "frozen_final_logistic_regression",
    )
    final_test_calibration = create_calibration_bin_table(
        actual_test_no_purchase,
        final_test_no_purchase_probability,
        "frozen_final_logistic_regression",
    )
    final_test_calibration.insert(0, "bin", range(1, len(final_test_calibration) + 1))

    model_performance = pd.DataFrame(
        [
            {
                **FINAL_MODEL_SPEC,
                "development_row_count": len(final_development_data),
                "test_row_count": len(final_test_data),
                "test_reference_week_min": int(final_test_data["reference_week"].min()),
                "test_reference_week_max": int(final_test_data["reference_week"].max()),
                "test_no_purchase_rate": float(actual_test_no_purchase.mean()),
                **final_test_metrics,
            }
        ]
    )
    final_test_top_k_metrics.insert(0, "model_family", "logistic_regression")
    scored_rows = final_test_data[
        ["household_key", "reference_week", "reference_end_day", TARGET]
    ].copy()
    scored_rows["predicted_no_purchase_probability"] = (
        final_test_no_purchase_probability
    )

    comparison_metrics = (
        "pr_auc",
        "roc_auc",
        "brier_score",
        "precision_at_10pct",
        "recall_at_10pct",
        "lift_at_10pct",
    )
    validation_vs_test = {
        "model_family": "logistic_regression",
        "feature_set": FINAL_MODEL_SPEC["feature_set"],
    }
    for metric in comparison_metrics:
        validation_value = float(validation_metrics[metric])
        test_value = float(final_test_metrics[metric])
        validation_vs_test[f"validation_{metric}"] = validation_value
        validation_vs_test[f"test_{metric}"] = test_value
        validation_vs_test[f"delta_{metric}"] = test_value - validation_value

    return {
        "model_performance": model_performance,
        "top_k_metrics": final_test_top_k_metrics,
        "weekly_stability": final_test_weekly_stability,
        "calibration": final_test_calibration,
        "validation_vs_test": pd.DataFrame([validation_vs_test]),
        "scored_rows": scored_rows,
        "metrics": final_test_metrics,
    }


def save_final_test_outputs(
    final_test_results: dict[str, Any],
    final_development_data: pd.DataFrame,
    final_test_data: pd.DataFrame,
    final_feature_names: list[str],
) -> None:
    """Persist protected TEST artifacts and write the completion marker last."""
    final_test_results["model_performance"].to_csv(
        OUTPUT_DIR / "12_final_test_model_performance.csv", index=False
    )
    final_test_results["top_k_metrics"].to_csv(
        OUTPUT_DIR / "13_final_test_top_k_metrics.csv", index=False
    )
    final_test_results["weekly_stability"].to_csv(
        OUTPUT_DIR / "14_final_test_weekly_stability.csv", index=False
    )
    final_test_results["calibration"].to_csv(
        OUTPUT_DIR / "15_final_test_calibration_by_bin.csv", index=False
    )
    final_test_results["validation_vs_test"].to_csv(
        OUTPUT_DIR / "validation_vs_test_final_logistic_comparison.csv", index=False
    )
    final_test_results["scored_rows"].to_csv(
        OUTPUT_DIR / "final_test_scored_rows.csv", index=False
    )

    calibration = final_test_results["calibration"]
    plt.figure(figsize=(7, 6))
    plt.plot(
        calibration["mean_predicted_no_purchase_probability"],
        calibration["observed_no_purchase_rate"],
        marker="o",
        label="Final Logistic Regression",
    )
    plt.plot([0, 1], [0, 1], color="gray", linestyle="--", label="Ideal calibration")
    plt.xlabel("Mean predicted no-purchase probability")
    plt.ylabel("Observed no-purchase rate")
    plt.title("Final TEST calibration")
    plt.legend()
    plt.tight_layout()
    plt.savefig(FIGURE_DIR / "final_test_calibration_curve.png", dpi=160)
    plt.close()

    weekly = final_test_results["weekly_stability"]
    figure, axes = plt.subplots(2, 1, figsize=(9, 9), sharex=True)
    axes[0].plot(weekly["reference_week"], weekly["pr_auc"], marker="o")
    axes[0].set_ylabel("PR-AUC")
    axes[0].set_title("Final TEST PR-AUC by reference week")
    axes[1].plot(weekly["reference_week"], weekly["lift_at_10pct"], marker="o")
    axes[1].set_xlabel("Reference week")
    axes[1].set_ylabel("Lift@10%")
    axes[1].set_title("Final TEST Lift@10% by reference week")
    figure.tight_layout()
    figure.savefig(FIGURE_DIR / "final_test_weekly_stability.png", dpi=160)
    plt.close(figure)

    numeric_features, categorical_features = split_feature_types(final_feature_names)
    boolean_features = [
        feature for feature in final_feature_names if feature in BOOLEAN_FEATURES
    ]
    numeric_features = [
        feature for feature in numeric_features if feature not in BOOLEAN_FEATURES
    ]
    final_model_lock = {
        **FINAL_MODEL_SPEC,
        "target": TARGET,
        "train_weeks": list(range(26, 75)),
        "validation_weeks": list(range(79, 87)),
        "excluded_gap_weeks": list(range(75, 79)) + list(range(87, 91)),
        "test_weeks": list(range(91, 99)),
        "top_k_values": list(TOP_K_VALUES),
        "numeric_features": numeric_features,
        "boolean_features": boolean_features,
        "categorical_features": categorical_features,
        "feature_count": len(final_feature_names),
        "final_development_row_count": len(final_development_data),
        "test_row_count": len(final_test_data),
        "python_version": platform.python_version(),
        "pandas_version": pd.__version__,
        "scikit_learn_version": sklearn.__version__,
    }
    (OUTPUT_DIR / "final_model_lock.json").write_text(
        json.dumps(final_model_lock, indent=2), encoding="utf-8"
    )

    completion_record = {
        "completed_at_utc": datetime.now(timezone.utc).isoformat(),
        "model_family": FINAL_MODEL_SPEC["model_family"],
        "feature_set": FINAL_MODEL_SPEC["feature_set"],
        "test_weeks": "91-98",
        "test_row_count": len(final_test_data),
        "test_predict_proba_call_count": 1,
        "warning": "Do not tune or replace the frozen model using Final TEST results.",
    }
    FINAL_TEST_COMPLETION_MARKER.write_text(
        json.dumps(completion_record, indent=2), encoding="utf-8"
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
        "xgboost": version("xgboost"),
        "random_state": RANDOM_STATE,
        "run_final_test": RUN_FINAL_TEST,
    }
    (OUTPUT_DIR / "run_environment.json").write_text(
        json.dumps(versions, indent=2), encoding="utf-8"
    )


# ============================================================
# Week 98 CRM priority simulation from saved Final TEST scores
# ============================================================
def load_final_crm_artifacts() -> tuple[dict[str, Any], pd.DataFrame, pd.DataFrame]:
    """Load and validate immutable Final TEST artifacts without running a model."""
    required_paths = {
        "model_lock": OUTPUT_DIR / "final_model_lock.json",
        "completion_marker": FINAL_TEST_COMPLETION_MARKER,
        "scored_rows": OUTPUT_DIR / "final_test_scored_rows.csv",
        "weekly_stability": OUTPUT_DIR / "14_final_test_weekly_stability.csv",
    }
    missing_paths = [str(path) for path in required_paths.values() if not path.exists()]
    if missing_paths:
        raise RuntimeError(
            "CRM simulation requires completed Final TEST artifacts. Missing:\n"
            + "\n".join(missing_paths)
        )

    model_lock = json.loads(required_paths["model_lock"].read_text(encoding="utf-8"))
    expected_lock = {
        "model_family": "logistic_regression",
        "feature_set": "full_behavior_plus_customer_state",
        "C": 1.0,
        "class_weight": None,
    }
    lock_mismatches = {
        key: (model_lock.get(key), expected_value)
        for key, expected_value in expected_lock.items()
        if model_lock.get(key) != expected_value
    }
    if lock_mismatches or 98 not in model_lock.get("test_weeks", []):
        raise RuntimeError(
            f"Final model lock does not match the frozen Logistic model: {lock_mismatches}"
        )

    scored_rows = pd.read_csv(required_paths["scored_rows"])
    weekly_stability = pd.read_csv(required_paths["weekly_stability"])
    required_score_columns = {
        "household_key",
        "reference_week",
        TARGET,
        "predicted_no_purchase_probability",
    }
    missing_score_columns = required_score_columns - set(scored_rows.columns)
    if missing_score_columns:
        raise RuntimeError(
            f"Final TEST scored rows are missing columns: {sorted(missing_score_columns)}"
        )
    return model_lock, scored_rows, weekly_stability


def select_top_k_households(
    operational_snapshot: pd.DataFrame,
    top_k_share: float,
) -> pd.DataFrame:
    """Rank saved risk probabilities with a deterministic household-key tie break."""
    selected_count = max(1, int(math.ceil(len(operational_snapshot) * top_k_share)))
    ranked_snapshot = operational_snapshot.sort_values(
        ["predicted_no_purchase_probability", "household_key"],
        ascending=[False, True],
        kind="mergesort",
    ).reset_index(drop=True)
    ranked_snapshot["risk_rank"] = np.arange(1, len(ranked_snapshot) + 1)
    ranked_snapshot["risk_share_rank"] = ranked_snapshot["risk_rank"] / len(
        ranked_snapshot
    )
    ranked_snapshot["is_high_risk_top10"] = (
        ranked_snapshot["risk_rank"] <= selected_count
    )
    return ranked_snapshot


def build_week98_operational_priority_snapshot(
    model_dataset: pd.DataFrame,
    final_test_scored_rows: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.Series]:
    """Build the week-98 operational list before exposing future actual outcomes."""
    week98_features = model_dataset.loc[model_dataset["reference_week"] == 98].copy()
    week98_scores = final_test_scored_rows.loc[
        final_test_scored_rows["reference_week"] == 98
    ].copy()
    for name, frame in (
        ("model_dataset", week98_features),
        ("scored_rows", week98_scores),
    ):
        duplicate_count = int(
            frame.duplicated(["household_key", "reference_week"], keep=False).sum()
        )
        if len(frame) != 2_500 or frame["household_key"].nunique() != 2_500:
            raise RuntimeError(
                f"Week 98 {name} must contain 2,500 unique households; "
                f"rows={len(frame):,}, households={frame['household_key'].nunique():,}"
            )
        if duplicate_count:
            raise RuntimeError(f"Week 98 {name} duplicate key rows={duplicate_count}")

    actual_outcomes = week98_scores.set_index("household_key")[TARGET].rename(
        "actual_no_purchase_99_102"
    )
    prediction_columns = [
        "household_key",
        "reference_week",
        "predicted_no_purchase_probability",
    ]
    feature_columns = [column for column in week98_features.columns if column != TARGET]
    operational_snapshot = week98_features[feature_columns].merge(
        week98_scores[prediction_columns],
        on=["household_key", "reference_week"],
        how="inner",
        validate="one_to_one",
    )
    if len(operational_snapshot) != 2_500:
        raise RuntimeError(
            f"Week 98 merged snapshot rows={len(operational_snapshot):,}"
        )
    if operational_snapshot["predicted_no_purchase_probability"].isna().any():
        raise RuntimeError("Week 98 snapshot contains missing predictions")

    expected_value_state = np.select(
        [
            ~operational_snapshot["pre_window_has_snapshot"].astype(bool),
            (~operational_snapshot["pre_window_has_purchase_26w"].astype(bool))
            | operational_snapshot["pre_window_rfm_value_index_26w"].isna(),
            operational_snapshot["pre_window_rfm_value_index_26w"] >= 0.80,
        ],
        [
            "NO_PRE_WINDOW_SNAPSHOT",
            "NO_RECENT_VALUE_HISTORY",
            "HIGH_VALUE",
        ],
        default="OTHER_VALUE",
    )
    value_state_mismatches = int(
        (operational_snapshot["value_state"].astype(str) != expected_value_state).sum()
    )
    if value_state_mismatches:
        raise RuntimeError(f"Week 98 value_state mismatches={value_state_mismatches}")

    if {"target_start_week", "target_end_week"}.issubset(operational_snapshot.columns):
        invalid_target_window = ~(
            (operational_snapshot["target_start_week"] == 99)
            & (operational_snapshot["target_end_week"] == 102)
        )
        if invalid_target_window.any():
            raise RuntimeError(
                f"Week 98 target window mismatches={int(invalid_target_window.sum())}"
            )

    operational_snapshot = select_top_k_households(operational_snapshot, 0.10)
    if int(operational_snapshot["is_high_risk_top10"].sum()) != 250:
        raise RuntimeError(
            "Week 98 high-risk Top 10% must contain exactly 250 households"
        )
    operational_snapshot["is_high_value"] = (
        operational_snapshot["value_state"] == "HIGH_VALUE"
    )
    operational_snapshot["is_crm_priority"] = (
        operational_snapshot["is_high_value"]
        & operational_snapshot["is_high_risk_top10"]
    )
    operational_snapshot["crm_value_risk_segment"] = np.select(
        [
            operational_snapshot["is_high_value"]
            & operational_snapshot["is_high_risk_top10"],
            operational_snapshot["is_high_value"],
            operational_snapshot["is_high_risk_top10"],
        ],
        [
            "HIGH_VALUE_HIGH_RISK",
            "HIGH_VALUE_NOT_HIGH_RISK",
            "NON_HIGH_VALUE_HIGH_RISK",
        ],
        default="NON_HIGH_VALUE_NOT_HIGH_RISK",
    )

    priority_list = operational_snapshot.loc[
        operational_snapshot["is_crm_priority"]
    ].sort_values(
        [
            "predicted_no_purchase_probability",
            "pre_window_rfm_value_index_26w",
            "household_key",
        ],
        ascending=[False, False, True],
        kind="mergesort",
    )
    priority_list = priority_list.copy()
    priority_list.insert(0, "priority_rank", np.arange(1, len(priority_list) + 1))
    return operational_snapshot, priority_list, actual_outcomes


def evaluate_week98_priority_backtest(
    operational_snapshot: pd.DataFrame,
    priority_list: pd.DataFrame,
    actual_outcomes: pd.Series,
    final_test_weekly_stability: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, dict[str, Any]]:
    """Attach week 99-102 actuals only after the operational lists are complete."""
    backtest_snapshot = operational_snapshot.merge(
        actual_outcomes,
        left_on="household_key",
        right_index=True,
        how="left",
        validate="one_to_one",
    )
    if backtest_snapshot["actual_no_purchase_99_102"].isna().any():
        raise RuntimeError("Week 98 backtest contains missing actual outcomes")
    priority_backtest = priority_list.merge(
        actual_outcomes,
        left_on="household_key",
        right_index=True,
        how="left",
        validate="one_to_one",
    )

    segment_summary = (
        backtest_snapshot.groupby("crm_value_risk_segment", as_index=False)
        .agg(
            household_count=("household_key", "size"),
            average_predicted_no_purchase_probability=(
                "predicted_no_purchase_probability",
                "mean",
            ),
            actual_no_purchase_count=("actual_no_purchase_99_102", "sum"),
            actual_no_purchase_rate=("actual_no_purchase_99_102", "mean"),
            average_pre_window_rfm_value_index=(
                "pre_window_rfm_value_index_26w",
                "mean",
            ),
            average_pre_window_frequency_26w=("pre_window_frequency_26w", "mean"),
            average_pre_window_monetary_26w=("pre_window_monetary_26w", "mean"),
        )
        .rename(columns={"crm_value_risk_segment": "segment"})
    )
    segment_order = [
        "HIGH_VALUE_HIGH_RISK",
        "HIGH_VALUE_NOT_HIGH_RISK",
        "NON_HIGH_VALUE_HIGH_RISK",
        "NON_HIGH_VALUE_NOT_HIGH_RISK",
    ]
    segment_summary = pd.DataFrame({"segment": segment_order}).merge(
        segment_summary, on="segment", how="left", validate="one_to_one"
    )
    segment_summary[["household_count", "actual_no_purchase_count"]] = segment_summary[
        ["household_count", "actual_no_purchase_count"]
    ].fillna(0)
    segment_summary["household_share"] = segment_summary["household_count"] / len(
        backtest_snapshot
    )

    group_masks = {
        "ALL_WEEK98": pd.Series(True, index=backtest_snapshot.index),
        "HIGH_RISK_TOP10": backtest_snapshot["is_high_risk_top10"],
        "HIGH_VALUE_ALL": backtest_snapshot["is_high_value"],
        "HIGH_VALUE_HIGH_RISK": backtest_snapshot["is_crm_priority"],
        "NON_HIGH_VALUE_HIGH_RISK": (
            ~backtest_snapshot["is_high_value"]
            & backtest_snapshot["is_high_risk_top10"]
        ),
    }
    group_rows: list[dict[str, Any]] = []
    for group_name, group_mask in group_masks.items():
        group = backtest_snapshot.loc[group_mask]
        group_rows.append(
            {
                "group": group_name,
                "household_count": len(group),
                "household_share": len(group) / len(backtest_snapshot),
                "actual_no_purchase_count": int(
                    group["actual_no_purchase_99_102"].sum()
                ),
                "actual_no_purchase_rate": group["actual_no_purchase_99_102"].mean(),
                "average_predicted_no_purchase_probability": group[
                    "predicted_no_purchase_probability"
                ].mean(),
                "average_pre_window_rfm_value_index": group[
                    "pre_window_rfm_value_index_26w"
                ].mean(),
                "average_pre_window_monetary_26w": group[
                    "pre_window_monetary_26w"
                ].mean(),
            }
        )
    backtest_summary = pd.DataFrame(group_rows)
    summary_by_group = backtest_summary.set_index("group")

    def safe_ratio(numerator: float, denominator: float) -> float | None:
        if pd.isna(numerator) or pd.isna(denominator) or denominator == 0:
            return None
        return float(numerator / denominator)

    def optional_float(value: float) -> float | None:
        return None if pd.isna(value) else float(value)

    all_group = summary_by_group.loc["ALL_WEEK98"]
    high_risk_group = summary_by_group.loc["HIGH_RISK_TOP10"]
    high_value_group = summary_by_group.loc["HIGH_VALUE_ALL"]
    priority_group = summary_by_group.loc["HIGH_VALUE_HIGH_RISK"]
    all_monetary = backtest_snapshot["pre_window_monetary_26w"].sum()
    high_value_monetary = backtest_snapshot.loc[
        backtest_snapshot["is_high_value"], "pre_window_monetary_26w"
    ].sum()
    priority_monetary = backtest_snapshot.loc[
        backtest_snapshot["is_crm_priority"], "pre_window_monetary_26w"
    ].sum()
    summary = {
        "reference_week": 98,
        "forecast_weeks": "99-102",
        "total_households": len(backtest_snapshot),
        "high_risk_top10_count": int(high_risk_group["household_count"]),
        "high_value_count": int(high_value_group["household_count"]),
        "priority_count": int(priority_group["household_count"]),
        "week98_baseline_no_purchase_rate": float(all_group["actual_no_purchase_rate"]),
        "high_risk_top10_no_purchase_rate": float(
            high_risk_group["actual_no_purchase_rate"]
        ),
        "high_risk_top10_lift_vs_all": safe_ratio(
            high_risk_group["actual_no_purchase_rate"],
            all_group["actual_no_purchase_rate"],
        ),
        "priority_no_purchase_rate": optional_float(
            priority_group["actual_no_purchase_rate"]
        ),
        "priority_lift_vs_all": safe_ratio(
            priority_group["actual_no_purchase_rate"],
            all_group["actual_no_purchase_rate"],
        ),
        "priority_lift_vs_high_value": safe_ratio(
            priority_group["actual_no_purchase_rate"],
            high_value_group["actual_no_purchase_rate"],
        ),
        "priority_capture_of_all_no_purchase": safe_ratio(
            priority_group["actual_no_purchase_count"],
            all_group["actual_no_purchase_count"],
        ),
        "high_value_priority_capture": safe_ratio(
            priority_group["actual_no_purchase_count"],
            high_value_group["actual_no_purchase_count"],
        ),
        "priority_pre_window_monetary_share_of_all": safe_ratio(
            priority_monetary, all_monetary
        ),
        "priority_pre_window_monetary_share_of_high_value": safe_ratio(
            priority_monetary, high_value_monetary
        ),
        "value_basis": "PRE_WINDOW_RFM",
        "value_cutoff": 0.80,
        "risk_basis": "TOP_10_PERCENT_WITHIN_REFERENCE_WEEK",
    }

    week98_weekly = final_test_weekly_stability.loc[
        final_test_weekly_stability["reference_week"] == 98
    ]
    if len(week98_weekly) != 1:
        raise RuntimeError(
            f"Final TEST weekly stability must contain one week-98 row; actual={len(week98_weekly)}"
        )
    expected_precision = float(week98_weekly.iloc[0]["precision_at_10pct"])
    expected_lift = float(week98_weekly.iloc[0]["lift_at_10pct"])
    if not np.isclose(summary["high_risk_top10_no_purchase_rate"], expected_precision):
        raise RuntimeError("Week 98 CRM Top 10% precision differs from Final TEST")
    if not np.isclose(summary["high_risk_top10_lift_vs_all"], expected_lift):
        raise RuntimeError("Week 98 CRM Top 10% lift differs from Final TEST")

    return priority_backtest, segment_summary, backtest_summary, summary


def save_crm_week98_outputs(
    operational_snapshot: pd.DataFrame,
    priority_list: pd.DataFrame,
    priority_backtest: pd.DataFrame,
    segment_summary: pd.DataFrame,
    backtest_summary: pd.DataFrame,
    summary: dict[str, Any],
) -> None:
    """Save operational lists separately from future-outcome backtest artifacts."""
    operational_columns = [
        "household_key",
        "reference_week",
        "predicted_no_purchase_probability",
        "risk_rank",
        "risk_share_rank",
        "is_high_risk_top10",
        "value_state",
        "is_high_value",
        "is_crm_priority",
        "crm_value_risk_segment",
        "pre_window_rfm_value_index_26w",
        "pre_window_frequency_26w",
        "pre_window_monetary_26w",
        "activity_state",
        "customer_state",
    ]
    priority_columns = [
        "priority_rank",
        "household_key",
        "reference_week",
        "predicted_no_purchase_probability",
        "risk_rank",
        "value_state",
        "pre_window_rfm_value_index_26w",
        "pre_window_frequency_26w",
        "pre_window_monetary_26w",
        "pre_window_recency_weeks_26w",
        "activity_state",
        "prior4_valid_basket_count",
        "recent4_valid_basket_count",
        "prior4_sales",
        "recent4_sales",
        "customer_state",
    ]
    operational_snapshot[operational_columns].to_csv(
        OUTPUT_DIR / "crm_week98_all_households.csv", index=False
    )
    priority_list[priority_columns].to_csv(
        OUTPUT_DIR / "crm_week98_priority_list.csv", index=False
    )
    priority_backtest[priority_columns + ["actual_no_purchase_99_102"]].to_csv(
        OUTPUT_DIR / "crm_week98_priority_backtest.csv", index=False
    )
    segment_summary.to_csv(OUTPUT_DIR / "crm_week98_segment_summary.csv", index=False)
    backtest_summary.to_csv(OUTPUT_DIR / "crm_week98_backtest_summary.csv", index=False)
    (OUTPUT_DIR / "crm_week98_summary.json").write_text(
        json.dumps(summary, indent=2, allow_nan=False), encoding="utf-8"
    )

    high_risk_cutoff = operational_snapshot.loc[
        operational_snapshot["is_high_risk_top10"],
        "predicted_no_purchase_probability",
    ].min()
    plt.figure(figsize=(8, 6))
    is_priority = operational_snapshot["is_crm_priority"]
    plt.scatter(
        operational_snapshot.loc[~is_priority, "pre_window_rfm_value_index_26w"],
        operational_snapshot.loc[~is_priority, "predicted_no_purchase_probability"],
        s=12,
        alpha=0.35,
        label="Other households",
    )
    plt.scatter(
        operational_snapshot.loc[is_priority, "pre_window_rfm_value_index_26w"],
        operational_snapshot.loc[is_priority, "predicted_no_purchase_probability"],
        s=22,
        alpha=0.8,
        label="High-value + high-risk priority",
    )
    plt.axvline(0.80, color="gray", linestyle="--", label="High-value cutoff")
    plt.axhline(
        high_risk_cutoff, color="tab:red", linestyle="--", label="Top 10% risk boundary"
    )
    plt.xlabel("PRE_WINDOW RFM value index")
    plt.ylabel("Predicted next-4-week no-purchase probability")
    plt.title("Week 98 CRM value × no-purchase risk")
    plt.legend()
    plt.tight_layout()
    plt.savefig(FIGURE_DIR / "crm_week98_value_risk_matrix.png", dpi=160)
    plt.close()

    plt.figure(figsize=(10, 6))
    plt.bar(segment_summary["segment"], segment_summary["actual_no_purchase_rate"])
    plt.axhline(
        summary["week98_baseline_no_purchase_rate"],
        color="tab:red",
        linestyle="--",
        label="All week-98 households",
    )
    plt.ylabel("Actual no-purchase rate, weeks 99-102")
    plt.title("Week 98 CRM segment backtest")
    plt.xticks(rotation=20, ha="right")
    plt.legend()
    plt.tight_layout()
    plt.savefig(FIGURE_DIR / "crm_week98_segment_no_purchase_rate.png", dpi=160)
    plt.close()


# ============================================================
# Revised week-98 CRM policy: monetary value first, then risk
# ============================================================
def build_revised_week98_operational_priority(
    operational_snapshot: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Build a target-free monetary-value-first operational priority list."""
    revised_snapshot = operational_snapshot.copy()
    forbidden_columns = {TARGET, "actual_no_purchase_99_102"}
    if forbidden_columns & set(revised_snapshot.columns):
        raise RuntimeError("Future outcomes cannot enter revised priority selection")

    monetary = revised_snapshot["pre_window_monetary_26w"]
    negative_count = int((monetary.dropna() < 0).sum())
    if negative_count:
        raise RuntimeError(
            f"Week 98 PRE_WINDOW monetary contains {negative_count} negative values"
        )
    revised_snapshot["economic_value_26w"] = monetary

    valid_value_mask = monetary.notna()
    valid_value_count = int(valid_value_mask.sum())
    if not valid_value_count:
        raise RuntimeError("Week 98 has no valid PRE_WINDOW monetary values")
    value_ranked = revised_snapshot.loc[valid_value_mask].sort_values(
        ["economic_value_26w", "household_key"],
        ascending=[False, True],
        kind="mergesort",
    )
    revised_snapshot["economic_value_rank"] = np.nan
    revised_snapshot.loc[value_ranked.index, "economic_value_rank"] = np.arange(
        1, valid_value_count + 1
    )
    revised_snapshot["economic_value_share_rank"] = (
        revised_snapshot["economic_value_rank"] / valid_value_count
    )
    revised_snapshot["economic_value_percentile"] = (
        valid_value_count - revised_snapshot["economic_value_rank"] + 1
    ) / valid_value_count

    high_value_count = max(1, int(math.ceil(valid_value_count * 0.20)))
    revised_snapshot["is_high_economic_value_top20"] = (
        revised_snapshot["economic_value_rank"] <= high_value_count
    )
    revised_snapshot["economic_value_segment"] = np.where(
        revised_snapshot["is_high_economic_value_top20"],
        "HIGH_ECONOMIC_VALUE",
        "OTHER_ECONOMIC_VALUE",
    )
    revised_snapshot["is_global_high_risk_top10"] = revised_snapshot[
        "is_high_risk_top10"
    ]

    high_value_ranked = revised_snapshot.loc[
        revised_snapshot["is_high_economic_value_top20"]
    ].sort_values(
        [
            "predicted_no_purchase_probability",
            "economic_value_26w",
            "household_key",
        ],
        ascending=[False, False, True],
        kind="mergesort",
    )
    revised_snapshot["risk_rank_within_high_economic_value"] = np.nan
    revised_snapshot.loc[
        high_value_ranked.index, "risk_rank_within_high_economic_value"
    ] = np.arange(1, len(high_value_ranked) + 1)
    priority_count = max(1, int(math.ceil(len(high_value_ranked) * 0.10)))
    revised_snapshot["is_revised_crm_priority"] = (
        revised_snapshot["risk_rank_within_high_economic_value"] <= priority_count
    )

    priority_list = revised_snapshot.loc[
        revised_snapshot["is_revised_crm_priority"]
    ].sort_values(
        [
            "risk_rank_within_high_economic_value",
            "economic_value_26w",
            "household_key",
        ],
        ascending=[True, False, True],
        kind="mergesort",
    )
    priority_list = priority_list.copy()
    priority_list.insert(0, "priority_rank", np.arange(1, len(priority_list) + 1))

    old_high_value = revised_snapshot["value_state"] == "HIGH_VALUE"
    new_high_value = revised_snapshot["is_high_economic_value_top20"]
    global_high_risk = revised_snapshot["is_global_high_risk_top10"]
    overlap_count = int((old_high_value & new_high_value).sum())

    def correlation(left: pd.Series, right: pd.Series, rank: bool = False) -> float:
        paired = pd.concat([left, right], axis=1).dropna()
        if len(paired) < 2:
            return float("nan")
        if rank:
            paired = paired.rank(method="average")
        return float(paired.iloc[:, 0].corr(paired.iloc[:, 1]))

    diagnostic_values = {
        "monetary_row_count": len(revised_snapshot),
        "monetary_valid_count": valid_value_count,
        "monetary_null_count": int(monetary.isna().sum()),
        "monetary_zero_count": int((monetary == 0).sum()),
        "monetary_negative_count": negative_count,
        "monetary_min": monetary.min(),
        "monetary_median": monetary.median(),
        "monetary_mean": monetary.mean(),
        "monetary_max": monetary.max(),
        "old_rfm_high_value_count": int(old_high_value.sum()),
        "new_high_economic_value_count": int(new_high_value.sum()),
        "old_new_value_overlap_count": overlap_count,
        "old_new_overlap_share_of_old": overlap_count / max(1, old_high_value.sum()),
        "old_new_overlap_share_of_new": overlap_count / max(1, new_high_value.sum()),
        "old_rfm_vs_risk_pearson": correlation(
            revised_snapshot["pre_window_rfm_value_index_26w"],
            revised_snapshot["predicted_no_purchase_probability"],
        ),
        "old_rfm_vs_risk_rank_correlation": correlation(
            revised_snapshot["pre_window_rfm_value_index_26w"],
            revised_snapshot["predicted_no_purchase_probability"],
            rank=True,
        ),
        "monetary_vs_risk_pearson": correlation(
            monetary, revised_snapshot["predicted_no_purchase_probability"]
        ),
        "monetary_vs_risk_rank_correlation": correlation(
            monetary,
            revised_snapshot["predicted_no_purchase_probability"],
            rank=True,
        ),
        "old_rfm_high_value_global_top10_overlap": int(
            (old_high_value & global_high_risk).sum()
        ),
        "new_economic_value_global_top10_overlap": int(
            (new_high_value & global_high_risk).sum()
        ),
    }
    diagnostic = pd.DataFrame(
        {"metric": diagnostic_values.keys(), "value": diagnostic_values.values()}
    )
    return revised_snapshot, priority_list, diagnostic


def evaluate_revised_week98_backtest(
    revised_snapshot: pd.DataFrame,
    priority_list: pd.DataFrame,
    actual_outcomes: pd.Series,
    final_test_weekly_stability: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, dict[str, Any]]:
    """Evaluate the frozen operational policy only after attaching future outcomes."""
    backtest = revised_snapshot.merge(
        actual_outcomes,
        left_on="household_key",
        right_index=True,
        how="left",
        validate="one_to_one",
    )
    if backtest["actual_no_purchase_99_102"].isna().any():
        raise RuntimeError("Revised week-98 backtest contains missing outcomes")
    priority_backtest = priority_list.merge(
        actual_outcomes,
        left_on="household_key",
        right_index=True,
        how="left",
        validate="one_to_one",
    )

    group_masks = {
        "ALL_WEEK98": pd.Series(True, index=backtest.index),
        "GLOBAL_HIGH_RISK_TOP10": backtest["is_global_high_risk_top10"],
        "OLD_RFM_HIGH_VALUE": backtest["value_state"] == "HIGH_VALUE",
        "NEW_HIGH_ECONOMIC_VALUE_TOP20": backtest["is_high_economic_value_top20"],
        "REVISED_CRM_PRIORITY": backtest["is_revised_crm_priority"],
    }

    def summarize(name: str, mask: pd.Series) -> dict[str, Any]:
        group = backtest.loc[mask]
        return {
            "group": name,
            "household_count": len(group),
            "household_share": len(group) / len(backtest),
            "average_predicted_no_purchase_probability": group[
                "predicted_no_purchase_probability"
            ].mean(),
            "actual_no_purchase_count": int(group["actual_no_purchase_99_102"].sum()),
            "actual_no_purchase_rate": group["actual_no_purchase_99_102"].mean(),
            "average_pre_window_monetary_26w": group["pre_window_monetary_26w"].mean(),
            "median_pre_window_monetary_26w": group["pre_window_monetary_26w"].median(),
            "average_pre_window_rfm_value_index_26w": group[
                "pre_window_rfm_value_index_26w"
            ].mean(),
        }

    backtest_summary = pd.DataFrame(
        [summarize(name, mask) for name, mask in group_masks.items()]
    )
    by_group = backtest_summary.set_index("group")

    def safe_ratio(numerator: float, denominator: float) -> float | None:
        if pd.isna(numerator) or pd.isna(denominator) or denominator == 0:
            return None
        return float(numerator / denominator)

    all_group = by_group.loc["ALL_WEEK98"]
    global_risk = by_group.loc["GLOBAL_HIGH_RISK_TOP10"]
    high_value = by_group.loc["NEW_HIGH_ECONOMIC_VALUE_TOP20"]
    priority = by_group.loc["REVISED_CRM_PRIORITY"]
    all_monetary = backtest["pre_window_monetary_26w"].sum()
    high_value_monetary = backtest.loc[
        backtest["is_high_economic_value_top20"], "pre_window_monetary_26w"
    ].sum()
    priority_monetary = backtest.loc[
        backtest["is_revised_crm_priority"], "pre_window_monetary_26w"
    ].sum()
    summary = {
        "reference_week": 98,
        "forecast_weeks": "99-102",
        "total_households": len(backtest),
        "valid_economic_value_households": int(
            backtest["economic_value_26w"].notna().sum()
        ),
        "high_economic_value_count": int(high_value["household_count"]),
        "global_high_risk_top10_count": int(global_risk["household_count"]),
        "revised_priority_count": int(priority["household_count"]),
        "economic_value_basis": "PRE_WINDOW_MONETARY_26W",
        "economic_value_policy": "TOP_20_PERCENT_WITHIN_WEEK98",
        "priority_policy": "TOP_10_PERCENT_RISK_WITHIN_HIGH_ECONOMIC_VALUE",
        "baseline_no_purchase_rate": float(all_group["actual_no_purchase_rate"]),
        "global_high_risk_no_purchase_rate": float(
            global_risk["actual_no_purchase_rate"]
        ),
        "global_high_risk_lift": safe_ratio(
            global_risk["actual_no_purchase_rate"],
            all_group["actual_no_purchase_rate"],
        ),
        "high_economic_value_no_purchase_rate": float(
            high_value["actual_no_purchase_rate"]
        ),
        "revised_priority_no_purchase_rate": float(priority["actual_no_purchase_rate"]),
        "revised_priority_lift_vs_all": safe_ratio(
            priority["actual_no_purchase_rate"], all_group["actual_no_purchase_rate"]
        ),
        "revised_priority_lift_vs_high_economic_value": safe_ratio(
            priority["actual_no_purchase_rate"], high_value["actual_no_purchase_rate"]
        ),
        "revised_priority_capture_of_all_no_purchase": safe_ratio(
            priority["actual_no_purchase_count"], all_group["actual_no_purchase_count"]
        ),
        "revised_priority_capture_of_high_economic_value_no_purchase": safe_ratio(
            priority["actual_no_purchase_count"], high_value["actual_no_purchase_count"]
        ),
        "revised_priority_monetary_share_of_all": safe_ratio(
            priority_monetary, all_monetary
        ),
        "revised_priority_monetary_share_of_high_economic_value": safe_ratio(
            priority_monetary, high_value_monetary
        ),
    }

    week98 = final_test_weekly_stability.loc[
        final_test_weekly_stability["reference_week"] == 98
    ]
    if len(week98) != 1:
        raise RuntimeError("Final TEST weekly stability must contain one week-98 row")
    if not np.isclose(
        summary["global_high_risk_no_purchase_rate"],
        float(week98.iloc[0]["precision_at_10pct"]),
    ) or not np.isclose(
        summary["global_high_risk_lift"],
        float(week98.iloc[0]["lift_at_10pct"]),
    ):
        raise RuntimeError("Week 98 global Top 10% differs from Final TEST")

    old_intersection = (backtest["value_state"] == "HIGH_VALUE") & backtest[
        "is_global_high_risk_top10"
    ]
    strategy_masks = {
        "OLD_RFM_GLOBAL_TOP10_INTERSECTION": old_intersection,
        "GLOBAL_RISK_TOP10_ONLY": backtest["is_global_high_risk_top10"],
        "REVISED_VALUE_FIRST_RISK_RANKING": backtest["is_revised_crm_priority"],
    }
    strategy_rows = []
    for strategy, mask in strategy_masks.items():
        row = summarize(strategy, mask)
        group_monetary = backtest.loc[mask, "pre_window_monetary_26w"].sum()
        strategy_rows.append(
            {
                "strategy": strategy,
                "priority_household_count": row["household_count"],
                "priority_share": row["household_share"],
                "actual_no_purchase_count": row["actual_no_purchase_count"],
                "actual_no_purchase_rate": row["actual_no_purchase_rate"],
                "lift_vs_all": safe_ratio(
                    row["actual_no_purchase_rate"],
                    all_group["actual_no_purchase_rate"],
                ),
                "average_predicted_no_purchase_probability": row[
                    "average_predicted_no_purchase_probability"
                ],
                "average_pre_window_monetary_26w": row[
                    "average_pre_window_monetary_26w"
                ],
                "median_pre_window_monetary_26w": row["median_pre_window_monetary_26w"],
                "monetary_share_of_all": safe_ratio(group_monetary, all_monetary),
            }
        )
    return (
        priority_backtest,
        backtest_summary,
        pd.DataFrame(strategy_rows),
        summary,
    )


def save_revised_crm_outputs(
    revised_snapshot: pd.DataFrame,
    priority_list: pd.DataFrame,
    priority_backtest: pd.DataFrame,
    backtest_summary: pd.DataFrame,
    strategy_comparison: pd.DataFrame,
    value_diagnostic: pd.DataFrame,
    summary: dict[str, Any],
) -> None:
    """Save only revised CRM artifacts, keeping every prior artifact immutable."""
    operational_columns = [
        "household_key",
        "reference_week",
        "predicted_no_purchase_probability",
        "risk_rank",
        "risk_share_rank",
        "is_global_high_risk_top10",
        "pre_window_monetary_26w",
        "economic_value_rank",
        "economic_value_percentile",
        "is_high_economic_value_top20",
        "risk_rank_within_high_economic_value",
        "is_revised_crm_priority",
        "pre_window_rfm_value_index_26w",
        "value_state",
        "activity_state",
        "customer_state",
    ]
    priority_columns = [
        "priority_rank",
        "household_key",
        "reference_week",
        "predicted_no_purchase_probability",
        "risk_rank",
        "risk_rank_within_high_economic_value",
        "pre_window_monetary_26w",
        "economic_value_rank",
        "economic_value_percentile",
        "is_high_economic_value_top20",
        "pre_window_frequency_26w",
        "pre_window_recency_weeks_26w",
        "pre_window_rfm_value_index_26w",
        "value_state",
        "activity_state",
        "customer_state",
        "prior4_valid_basket_count",
        "recent4_valid_basket_count",
        "prior4_sales",
        "recent4_sales",
    ]
    revised_snapshot[operational_columns].to_csv(
        OUTPUT_DIR / "crm_week98_revised_all_households.csv", index=False
    )
    priority_list[priority_columns].to_csv(
        OUTPUT_DIR / "crm_week98_revised_priority_list.csv", index=False
    )
    priority_backtest[priority_columns + ["actual_no_purchase_99_102"]].to_csv(
        OUTPUT_DIR / "crm_week98_revised_priority_backtest.csv", index=False
    )
    backtest_summary.to_csv(
        OUTPUT_DIR / "crm_week98_revised_backtest_summary.csv", index=False
    )
    strategy_comparison.to_csv(
        OUTPUT_DIR / "crm_week98_priority_strategy_comparison.csv", index=False
    )
    value_diagnostic.to_csv(
        OUTPUT_DIR / "crm_week98_value_definition_diagnostic.csv", index=False
    )
    (OUTPUT_DIR / "crm_week98_revised_summary.json").write_text(
        json.dumps(summary, indent=2, allow_nan=False), encoding="utf-8"
    )

    high_value_boundary = revised_snapshot.loc[
        revised_snapshot["is_high_economic_value_top20"],
        "economic_value_percentile",
    ].min()
    global_risk_boundary = revised_snapshot.loc[
        revised_snapshot["is_global_high_risk_top10"],
        "predicted_no_purchase_probability",
    ].min()
    priority = revised_snapshot["is_revised_crm_priority"]
    plt.figure(figsize=(8, 6))
    plt.scatter(
        revised_snapshot.loc[~priority, "economic_value_percentile"],
        revised_snapshot.loc[~priority, "predicted_no_purchase_probability"],
        s=12,
        alpha=0.3,
        label="Other households",
    )
    plt.scatter(
        revised_snapshot.loc[priority, "economic_value_percentile"],
        revised_snapshot.loc[priority, "predicted_no_purchase_probability"],
        s=28,
        alpha=0.85,
        label="Priority within high economic value",
    )
    plt.axvline(
        high_value_boundary,
        color="gray",
        linestyle="--",
        label="Top 20% value boundary",
    )
    plt.axhline(
        global_risk_boundary,
        color="tab:red",
        linestyle="--",
        label="Global top 10% risk boundary",
    )
    plt.xlabel("Economic value percentile (higher is more valuable)")
    plt.ylabel("Predicted next-4-week no-purchase probability")
    plt.title("Week 98 revised CRM value-first risk ranking")
    plt.legend()
    plt.tight_layout()
    plt.savefig(FIGURE_DIR / "crm_week98_revised_value_risk_scatter.png", dpi=160)
    plt.close()

    figure_groups = [
        "ALL_WEEK98",
        "GLOBAL_HIGH_RISK_TOP10",
        "NEW_HIGH_ECONOMIC_VALUE_TOP20",
        "REVISED_CRM_PRIORITY",
    ]
    figure_data = backtest_summary.set_index("group").loc[figure_groups]
    plt.figure(figsize=(10, 6))
    plt.bar(figure_data.index, figure_data["actual_no_purchase_rate"])
    plt.axhline(
        summary["baseline_no_purchase_rate"],
        color="tab:red",
        linestyle="--",
        label="Week 98 baseline",
    )
    plt.ylabel("Actual no-purchase rate, weeks 99-102")
    plt.title("Week 98 revised CRM strategy backtest")
    plt.xticks(rotation=18, ha="right")
    plt.legend()
    plt.tight_layout()
    plt.savefig(FIGURE_DIR / "crm_week98_revised_strategy_backtest.png", dpi=160)
    plt.close()

    profile_metrics = {
        "Predicted no-purchase probability": "predicted_no_purchase_probability",
        "PRE_WINDOW monetary 26w": "pre_window_monetary_26w",
        "PRE_WINDOW frequency 26w": "pre_window_frequency_26w",
        "Recent 4-week basket count": "recent4_valid_basket_count",
    }
    high_value = revised_snapshot["is_high_economic_value_top20"]
    profile = pd.DataFrame(
        {
            "High economic value": [
                revised_snapshot.loc[high_value, column].mean()
                for column in profile_metrics.values()
            ],
            "Revised priority": [
                revised_snapshot.loc[priority, column].mean()
                for column in profile_metrics.values()
            ],
        },
        index=profile_metrics.keys(),
    )
    profile.plot(
        kind="bar",
        subplots=True,
        layout=(2, 2),
        legend=False,
        figsize=(11, 7),
        title=list(profile.columns),
    )
    plt.suptitle("Week 98 revised priority profile")
    plt.tight_layout()
    plt.savefig(FIGURE_DIR / "crm_week98_revised_priority_profile.png", dpi=160)
    plt.close("all")


# ============================================================
# Revised CRM weekly stability using immutable Final TEST scores
# ============================================================
def build_revised_crm_priority_for_week(
    week_features: pd.DataFrame,
    week_scores: pd.DataFrame,
    reference_week: int,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.Series, dict[str, Any]]:
    """Apply the frozen Monetary Top20 -> within-value Risk Top10 rule for one week."""
    for name, frame in (("model_dataset", week_features), ("scored_rows", week_scores)):
        duplicates = int(frame.duplicated(KEY_COLUMNS, keep=False).sum())
        if (
            len(frame) != EXPECTED_HOUSEHOLDS
            or frame["household_key"].nunique() != EXPECTED_HOUSEHOLDS
        ):
            raise RuntimeError(
                f"Week {reference_week} {name} must contain 2,500 unique households; "
                f"rows={len(frame):,}, households={frame['household_key'].nunique():,}"
            )
        if duplicates:
            raise RuntimeError(
                f"Week {reference_week} {name} duplicate key rows={duplicates}"
            )

    actual_outcomes = week_scores.set_index(KEY_COLUMNS)[TARGET].rename(
        "actual_no_purchase_next4w"
    )
    feature_columns = [column for column in week_features.columns if column != TARGET]
    operational = week_features[feature_columns].merge(
        week_scores[KEY_COLUMNS + ["predicted_no_purchase_probability"]],
        on=KEY_COLUMNS,
        how="inner",
        validate="one_to_one",
    )
    if (
        len(operational) != EXPECTED_HOUSEHOLDS
        or operational["predicted_no_purchase_probability"].isna().any()
    ):
        raise RuntimeError(f"Week {reference_week} prediction merge failed")

    monetary = operational["pre_window_monetary_26w"]
    negative_count = int((monetary.dropna() < 0).sum())
    if negative_count:
        raise RuntimeError(
            f"Week {reference_week} PRE_WINDOW monetary has {negative_count} negative values"
        )
    quality = {
        "reference_week": reference_week,
        "row_count": len(operational),
        "valid_monetary_count": int(monetary.notna().sum()),
        "null_count": int(monetary.isna().sum()),
        "zero_count": int((monetary == 0).sum()),
        "negative_count": negative_count,
        "minimum": monetary.min(),
        "median": monetary.median(),
        "mean": monetary.mean(),
        "maximum": monetary.max(),
    }

    # Reuse the exact Week-98 ranking implementation after creating the same global rank.
    operational = select_top_k_households(operational, 0.10)
    revised, priority, _ = build_revised_week98_operational_priority(operational)
    revised = revised.rename(columns={"risk_rank": "global_risk_rank"})
    priority = priority.rename(
        columns={
            "risk_rank": "global_risk_rank",
            "priority_rank": "priority_rank_within_week",
        }
    )
    forecast_start = reference_week + 1
    forecast_end = reference_week + 4
    revised["forecast_start_week"] = forecast_start
    revised["forecast_end_week"] = forecast_end
    priority["forecast_start_week"] = forecast_start
    priority["forecast_end_week"] = forecast_end
    return revised, priority, actual_outcomes, quality


def evaluate_revised_crm_week_backtest(
    operational: pd.DataFrame,
    priority: pd.DataFrame,
    actual_outcomes: pd.Series,
) -> tuple[pd.DataFrame, dict[str, Any]]:
    """Attach next-four-week outcomes only after the weekly selection is frozen."""
    backtest = operational.merge(
        actual_outcomes,
        left_on=KEY_COLUMNS,
        right_index=True,
        how="left",
        validate="one_to_one",
    )
    priority_backtest = priority.merge(
        actual_outcomes,
        left_on=KEY_COLUMNS,
        right_index=True,
        how="left",
        validate="one_to_one",
    )
    if backtest["actual_no_purchase_next4w"].isna().any():
        raise RuntimeError("Weekly revised CRM backtest has missing outcomes")

    high_value = backtest["is_high_economic_value_top20"]
    is_priority = backtest["is_revised_crm_priority"]
    global_risk = backtest["is_global_high_risk_top10"]
    all_group = backtest
    high_group = backtest.loc[high_value]
    priority_group = backtest.loc[is_priority]
    global_group = backtest.loc[global_risk]

    def ratio(numerator: float, denominator: float) -> float | None:
        if pd.isna(numerator) or pd.isna(denominator) or denominator == 0:
            return None
        return float(numerator / denominator)

    all_rate = float(all_group["actual_no_purchase_next4w"].mean())
    high_rate = float(high_group["actual_no_purchase_next4w"].mean())
    priority_rate = float(priority_group["actual_no_purchase_next4w"].mean())
    global_rate = float(global_group["actual_no_purchase_next4w"].mean())
    high_events = int(high_group["actual_no_purchase_next4w"].sum())
    priority_events = int(priority_group["actual_no_purchase_next4w"].sum())
    all_events = int(all_group["actual_no_purchase_next4w"].sum())
    row = {
        "reference_week": int(all_group["reference_week"].iloc[0]),
        "forecast_start_week": int(all_group["forecast_start_week"].iloc[0]),
        "forecast_end_week": int(all_group["forecast_end_week"].iloc[0]),
        "total_household_count": len(all_group),
        "total_actual_no_purchase_count": all_events,
        "total_actual_no_purchase_rate": all_rate,
        "global_high_risk_count": len(global_group),
        "global_high_risk_actual_no_purchase_count": int(
            global_group["actual_no_purchase_next4w"].sum()
        ),
        "global_high_risk_actual_no_purchase_rate": global_rate,
        "global_high_risk_lift_vs_all": ratio(global_rate, all_rate),
        "high_economic_value_count": len(high_group),
        "high_economic_value_actual_no_purchase_count": high_events,
        "high_economic_value_actual_no_purchase_rate": high_rate,
        "high_economic_value_average_monetary": high_group[
            "pre_window_monetary_26w"
        ].mean(),
        "high_economic_value_median_monetary": high_group[
            "pre_window_monetary_26w"
        ].median(),
        "revised_priority_count": len(priority_group),
        "revised_priority_actual_no_purchase_count": priority_events,
        "revised_priority_actual_no_purchase_rate": priority_rate,
        "revised_priority_lift_vs_all": ratio(priority_rate, all_rate),
        "revised_priority_lift_vs_high_economic_value": ratio(priority_rate, high_rate),
        "revised_priority_capture_within_high_economic_value": ratio(
            priority_events, high_events
        ),
        "revised_priority_capture_of_all_no_purchase": ratio(
            priority_events, all_events
        ),
        "revised_priority_average_predicted_probability": priority_group[
            "predicted_no_purchase_probability"
        ].mean(),
        "revised_priority_average_monetary": priority_group[
            "pre_window_monetary_26w"
        ].mean(),
        "revised_priority_median_monetary": priority_group[
            "pre_window_monetary_26w"
        ].median(),
        "revised_priority_monetary_share_of_all": ratio(
            priority_group["pre_window_monetary_26w"].sum(),
            all_group["pre_window_monetary_26w"].sum(),
        ),
        "revised_priority_monetary_share_of_high_economic_value": ratio(
            priority_group["pre_window_monetary_26w"].sum(),
            high_group["pre_window_monetary_26w"].sum(),
        ),
    }
    return priority_backtest, row


def run_revised_crm_weekly_stability(
    model_dataset: pd.DataFrame,
    final_test_scored_rows: pd.DataFrame,
    final_test_weekly_stability: pd.DataFrame,
) -> dict[str, pd.DataFrame]:
    """Build one 20,000-row merge source and evaluate the fixed rule by week."""
    test_weeks = list(range(91, 99))
    features = model_dataset.loc[model_dataset["reference_week"].isin(test_weeks)]
    scores = final_test_scored_rows.loc[
        final_test_scored_rows["reference_week"].isin(test_weeks)
    ]
    if len(features) != 20_000 or len(scores) != 20_000:
        raise RuntimeError(
            f"Weekly CRM requires 20,000 feature and score rows; features={len(features):,}, scores={len(scores):,}"
        )

    priorities: list[pd.DataFrame] = []
    priority_backtests: list[pd.DataFrame] = []
    backtest_rows: list[dict[str, Any]] = []
    quality_rows: list[dict[str, Any]] = []
    all_backtests: list[pd.DataFrame] = []
    for reference_week in test_weeks:
        week_features = features.loc[features["reference_week"] == reference_week]
        week_scores = scores.loc[scores["reference_week"] == reference_week]
        operational, priority, outcomes, quality = build_revised_crm_priority_for_week(
            week_features, week_scores, reference_week
        )
        priority_backtest, metrics = evaluate_revised_crm_week_backtest(
            operational, priority, outcomes
        )
        full_backtest = operational.merge(
            outcomes, left_on=KEY_COLUMNS, right_index=True, validate="one_to_one"
        )
        priorities.append(priority)
        priority_backtests.append(priority_backtest)
        all_backtests.append(full_backtest)
        backtest_rows.append(metrics)
        quality_rows.append(quality)

    weekly = pd.DataFrame(backtest_rows).sort_values("reference_week")
    expected = final_test_weekly_stability.set_index("reference_week")
    for row in weekly.itertuples(index=False):
        if (
            row.reference_week not in expected.index
            or not np.isclose(
                row.global_high_risk_actual_no_purchase_rate,
                expected.loc[row.reference_week, "precision_at_10pct"],
            )
            or not np.isclose(
                row.global_high_risk_lift_vs_all,
                expected.loc[row.reference_week, "lift_at_10pct"],
            )
        ):
            raise RuntimeError(
                f"Week {row.reference_week} global Top 10% differs from Final TEST"
            )

    week98_path = OUTPUT_DIR / "crm_week98_revised_summary.json"
    if not week98_path.exists():
        raise RuntimeError(
            f"Weekly stability requires existing Week-98 summary: {week98_path}"
        )
    week98_summary = json.loads(week98_path.read_text(encoding="utf-8"))
    week98 = weekly.loc[weekly["reference_week"] == 98].iloc[0]
    week98_checks = {
        "high_economic_value_count": week98.high_economic_value_count,
        "revised_priority_count": week98.revised_priority_count,
        "baseline_no_purchase_rate": week98.total_actual_no_purchase_rate,
        "high_economic_value_no_purchase_rate": week98.high_economic_value_actual_no_purchase_rate,
        "revised_priority_no_purchase_rate": week98.revised_priority_actual_no_purchase_rate,
        "revised_priority_lift_vs_high_economic_value": week98.revised_priority_lift_vs_high_economic_value,
        "revised_priority_capture_of_high_economic_value_no_purchase": week98.revised_priority_capture_within_high_economic_value,
        "revised_priority_monetary_share_of_all": week98.revised_priority_monetary_share_of_all,
    }
    for key, actual in week98_checks.items():
        expected_value = week98_summary.get(key)
        if expected_value is None or not np.isclose(actual, expected_value):
            raise RuntimeError(
                f"Week 98 weekly result differs from saved revised summary for {key}"
            )

    priority_list = pd.concat(priorities, ignore_index=True)
    priority_backtest = pd.concat(priority_backtests, ignore_index=True)
    combined_backtest = pd.concat(all_backtests, ignore_index=True)
    lift = weekly["revised_priority_lift_vs_high_economic_value"]
    capture = weekly["revised_priority_capture_within_high_economic_value"]
    stability_summary = pd.DataFrame(
        [
            {
                "weeks_evaluated": len(weekly),
                "mean_high_economic_value_no_purchase_rate": weekly[
                    "high_economic_value_actual_no_purchase_rate"
                ].mean(),
                "min_high_economic_value_no_purchase_rate": weekly[
                    "high_economic_value_actual_no_purchase_rate"
                ].min(),
                "max_high_economic_value_no_purchase_rate": weekly[
                    "high_economic_value_actual_no_purchase_rate"
                ].max(),
                "total_high_economic_value_no_purchase_events": weekly[
                    "high_economic_value_actual_no_purchase_count"
                ].sum(),
                "mean_priority_no_purchase_rate": weekly[
                    "revised_priority_actual_no_purchase_rate"
                ].mean(),
                "min_priority_no_purchase_rate": weekly[
                    "revised_priority_actual_no_purchase_rate"
                ].min(),
                "max_priority_no_purchase_rate": weekly[
                    "revised_priority_actual_no_purchase_rate"
                ].max(),
                "total_priority_no_purchase_events": weekly[
                    "revised_priority_actual_no_purchase_count"
                ].sum(),
                "mean_priority_lift_vs_high_economic_value": lift.mean(),
                "median_priority_lift_vs_high_economic_value": lift.median(),
                "min_priority_lift_vs_high_economic_value": lift.min(),
                "max_priority_lift_vs_high_economic_value": lift.max(),
                "std_priority_lift_vs_high_economic_value": lift.std(),
                "weeks_with_defined_lift": int(lift.notna().sum()),
                "weeks_priority_rate_above_high_value_rate": int(
                    (
                        weekly["revised_priority_actual_no_purchase_rate"]
                        > weekly["high_economic_value_actual_no_purchase_rate"]
                    ).sum()
                ),
                "mean_priority_capture_within_high_economic_value": capture.mean(),
                "median_priority_capture_within_high_economic_value": capture.median(),
                "min_priority_capture_within_high_economic_value": capture.min(),
                "max_priority_capture_within_high_economic_value": capture.max(),
                "total_high_value_no_purchase_events": weekly[
                    "high_economic_value_actual_no_purchase_count"
                ].sum(),
                "total_priority_captured_high_value_no_purchase_events": weekly[
                    "revised_priority_actual_no_purchase_count"
                ].sum(),
                "mean_priority_monetary_share_of_all": weekly[
                    "revised_priority_monetary_share_of_all"
                ].mean(),
                "mean_priority_monetary_share_of_high_economic_value": weekly[
                    "revised_priority_monetary_share_of_high_economic_value"
                ].mean(),
            }
        ]
    )

    pooled_masks = {
        "ALL_TEST_WEEK_SNAPSHOTS": pd.Series(True, index=combined_backtest.index),
        "HIGH_ECONOMIC_VALUE_WEEK_SNAPSHOTS": combined_backtest[
            "is_high_economic_value_top20"
        ],
        "REVISED_PRIORITY_WEEK_SNAPSHOTS": combined_backtest["is_revised_crm_priority"],
    }
    pooled_rows = []
    for group_name, mask in pooled_masks.items():
        group = combined_backtest.loc[mask]
        pooled_rows.append(
            {
                "group": group_name,
                "record_count": len(group),
                "actual_no_purchase_count": int(
                    group["actual_no_purchase_next4w"].sum()
                ),
                "actual_no_purchase_rate": group["actual_no_purchase_next4w"].mean(),
                "average_predicted_probability": group[
                    "predicted_no_purchase_probability"
                ].mean(),
                "average_pre_window_monetary": group["pre_window_monetary_26w"].mean(),
            }
        )
    pooled = pd.DataFrame(pooled_rows)
    pooled_by_group = pooled.set_index("group")
    high_pooled = pooled_by_group.loc["HIGH_ECONOMIC_VALUE_WEEK_SNAPSHOTS"]
    priority_pooled = pooled_by_group.loc["REVISED_PRIORITY_WEEK_SNAPSHOTS"]
    pooled["pooled_lift_vs_high_economic_value"] = np.nan
    pooled["pooled_capture_within_high_economic_value"] = np.nan
    priority_row = pooled["group"] == "REVISED_PRIORITY_WEEK_SNAPSHOTS"
    pooled.loc[priority_row, "pooled_lift_vs_high_economic_value"] = (
        priority_pooled.actual_no_purchase_rate / high_pooled.actual_no_purchase_rate
        if high_pooled.actual_no_purchase_rate
        else np.nan
    )
    pooled.loc[priority_row, "pooled_capture_within_high_economic_value"] = (
        priority_pooled.actual_no_purchase_count / high_pooled.actual_no_purchase_count
        if high_pooled.actual_no_purchase_count
        else np.nan
    )

    recurrence = (
        priority_list.groupby("household_key", as_index=False)
        .agg(
            priority_week_count=("reference_week", "size"),
            first_priority_week=("reference_week", "min"),
            last_priority_week=("reference_week", "max"),
        )
        .sort_values(["priority_week_count", "household_key"], ascending=[False, True])
    )
    recurrence_summary = pd.DataFrame(
        [
            {
                "total_priority_household_week_records": len(priority_list),
                "unique_priority_households": len(recurrence),
                "households_selected_once": int(
                    (recurrence["priority_week_count"] == 1).sum()
                ),
                "households_selected_multiple_weeks": int(
                    (recurrence["priority_week_count"] >= 2).sum()
                ),
                "max_weeks_selected_for_one_household": int(
                    recurrence["priority_week_count"].max()
                ),
            }
        ]
    )
    return {
        "weekly": weekly,
        "quality": pd.DataFrame(quality_rows),
        "priority_list": priority_list,
        "priority_backtest": priority_backtest,
        "stability_summary": stability_summary,
        "pooled": pooled,
        "recurrence_summary": recurrence_summary,
        "recurrence": recurrence,
    }


def save_revised_crm_weekly_outputs(results: dict[str, pd.DataFrame]) -> None:
    """Save new weekly artifacts without modifying Final TEST or Week-98 outputs."""
    priority_columns = [
        "reference_week",
        "forecast_start_week",
        "forecast_end_week",
        "priority_rank_within_week",
        "household_key",
        "predicted_no_purchase_probability",
        "risk_rank_within_high_economic_value",
        "pre_window_monetary_26w",
        "economic_value_rank",
        "economic_value_percentile",
        "pre_window_frequency_26w",
        "pre_window_recency_weeks_26w",
        "pre_window_rfm_value_index_26w",
        "activity_state",
        "customer_state",
        "prior4_valid_basket_count",
        "recent4_valid_basket_count",
        "prior4_sales",
        "recent4_sales",
    ]
    results["weekly"].to_csv(
        OUTPUT_DIR / "crm_revised_weekly_stability.csv", index=False
    )
    results["quality"].to_csv(
        OUTPUT_DIR / "crm_revised_weekly_value_quality.csv", index=False
    )
    results["priority_list"][priority_columns].to_csv(
        OUTPUT_DIR / "crm_revised_weekly_priority_list.csv", index=False
    )
    results["priority_backtest"][
        priority_columns + ["actual_no_purchase_next4w"]
    ].to_csv(OUTPUT_DIR / "crm_revised_weekly_priority_backtest.csv", index=False)
    results["stability_summary"].to_csv(
        OUTPUT_DIR / "crm_revised_weekly_stability_summary.csv", index=False
    )
    results["pooled"].to_csv(
        OUTPUT_DIR / "crm_revised_weekly_pooled_backtest.csv", index=False
    )
    results["recurrence_summary"].to_csv(
        OUTPUT_DIR / "crm_revised_weekly_priority_recurrence_summary.csv", index=False
    )
    results["recurrence"].to_csv(
        OUTPUT_DIR / "crm_revised_weekly_priority_recurrence_by_household.csv",
        index=False,
    )

    weekly = results["weekly"]
    plt.figure(figsize=(9, 5))
    plt.plot(
        weekly["reference_week"],
        weekly["high_economic_value_actual_no_purchase_rate"],
        marker="o",
        label="High economic value",
    )
    plt.plot(
        weekly["reference_week"],
        weekly["revised_priority_actual_no_purchase_rate"],
        marker="o",
        label="Revised priority",
    )
    plt.xlabel("Reference week")
    plt.ylabel("Actual next-4-week no-purchase rate")
    plt.title("Revised CRM weekly priority effect")
    plt.legend()
    plt.tight_layout()
    plt.savefig(FIGURE_DIR / "crm_revised_weekly_priority_effect.png", dpi=160)
    plt.close()

    plt.figure(figsize=(9, 5))
    plt.plot(
        weekly["reference_week"],
        weekly["revised_priority_lift_vs_high_economic_value"],
        marker="o",
    )
    plt.axhline(1.0, color="gray", linestyle="--")
    plt.xlabel("Reference week")
    plt.ylabel("Lift vs high economic value")
    plt.title("Revised CRM weekly priority lift")
    plt.tight_layout()
    plt.savefig(FIGURE_DIR / "crm_revised_weekly_priority_lift.png", dpi=160)
    plt.close()

    plt.figure(figsize=(9, 5))
    plt.plot(
        weekly["reference_week"],
        weekly["revised_priority_capture_within_high_economic_value"],
        marker="o",
    )
    plt.xlabel("Reference week")
    plt.ylabel("Capture within high economic value")
    plt.title("Revised CRM weekly priority capture")
    plt.tight_layout()
    plt.savefig(FIGURE_DIR / "crm_revised_weekly_priority_capture.png", dpi=160)
    plt.close()


# ============================================================
# Main
# ============================================================
def main() -> None:
    """Run exactly one explicit pipeline mode without crossing artifact boundaries."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    FIGURE_DIR.mkdir(parents=True, exist_ok=True)

    active_modes = sum(
        bool(mode)
        for mode in (
            RUN_FINAL_TEST,
            RUN_CRM_WEEK98_SIMULATION,
            RUN_REVISED_CRM_WEEK98_SIMULATION,
            RUN_REVISED_CRM_WEEKLY_STABILITY,
        )
    )
    if active_modes > 1:
        raise RuntimeError("Final TEST and CRM simulation modes cannot run together")

    if RUN_REVISED_CRM_WEEKLY_STABILITY:
        model_lock, final_test_scored_rows, final_test_weekly_stability = (
            load_final_crm_artifacts()
        )
        if model_lock.get("test_weeks") != list(range(91, 99)):
            raise RuntimeError("Frozen model lock must contain TEST weeks 91-98")
        model_dataset, _ = load_and_validate_model_dataset(INPUT_CSV)
        weekly_results = run_revised_crm_weekly_stability(
            model_dataset,
            final_test_scored_rows,
            final_test_weekly_stability,
        )
        save_revised_crm_weekly_outputs(weekly_results)

        def weekly_metric(value: float) -> str:
            return "NULL" if pd.isna(value) else f"{value:.6f}"

        print(
            "\nREVISED CRM WEEKLY STABILITY COMPLETE\n"
            "Weeks: 91-98\n"
            "Policy: PRE_WINDOW Monetary Top20 -> Risk Top10 within high-economic-value\n"
            "Model refit: NO\n"
            "Prediction regenerated: NO"
        )
        for row in weekly_results["weekly"].itertuples(index=False):
            print(
                f"\nWeek {row.reference_week}:\n"
                "High-value no-purchase events = "
                f"{row.high_economic_value_actual_no_purchase_count}\n"
                "High-value no-purchase rate = "
                f"{row.high_economic_value_actual_no_purchase_rate:.6f}\n"
                "Priority no-purchase events = "
                f"{row.revised_priority_actual_no_purchase_count}\n"
                "Priority no-purchase rate = "
                f"{row.revised_priority_actual_no_purchase_rate:.6f}\n"
                "Lift vs high-value = "
                f"{weekly_metric(row.revised_priority_lift_vs_high_economic_value)}\n"
                "Capture within high-value = "
                f"{weekly_metric(row.revised_priority_capture_within_high_economic_value)}"
            )
        summary = weekly_results["stability_summary"].iloc[0]
        pooled = weekly_results["pooled"].set_index("group")
        pooled_priority = pooled.loc["REVISED_PRIORITY_WEEK_SNAPSHOTS"]
        pooled_high_value = pooled.loc["HIGH_ECONOMIC_VALUE_WEEK_SNAPSHOTS"]
        print(
            "\nOverall:\n"
            "Mean priority Lift vs high-value = "
            f"{weekly_metric(summary.mean_priority_lift_vs_high_economic_value)}\n"
            "Median = "
            f"{weekly_metric(summary.median_priority_lift_vs_high_economic_value)}\n"
            "Weeks with Priority rate > High-value rate = "
            f"{int(summary.weeks_priority_rate_above_high_value_rate)} / 8\n"
            "Pooled high-value no-purchase events = "
            f"{int(pooled_high_value.actual_no_purchase_count)}\n"
            "Pooled Priority captured events = "
            f"{int(pooled_priority.actual_no_purchase_count)}\n"
            "Pooled capture = "
            f"{weekly_metric(pooled_priority.pooled_capture_within_high_economic_value)}"
        )
        return

    if RUN_REVISED_CRM_WEEK98_SIMULATION:
        _, final_test_scored_rows, final_test_weekly_stability = (
            load_final_crm_artifacts()
        )
        model_dataset, _ = load_and_validate_model_dataset(INPUT_CSV)
        operational_snapshot, _, actual_outcomes = (
            build_week98_operational_priority_snapshot(
                model_dataset, final_test_scored_rows
            )
        )
        revised_snapshot, priority_list, value_diagnostic = (
            build_revised_week98_operational_priority(operational_snapshot)
        )
        (
            priority_backtest,
            backtest_summary,
            strategy_comparison,
            revised_summary,
        ) = evaluate_revised_week98_backtest(
            revised_snapshot,
            priority_list,
            actual_outcomes,
            final_test_weekly_stability,
        )
        save_revised_crm_outputs(
            revised_snapshot,
            priority_list,
            priority_backtest,
            backtest_summary,
            strategy_comparison,
            value_diagnostic,
            revised_summary,
        )

        def format_revised_metric(value: float | None) -> str:
            return "NULL" if value is None else f"{value:.6f}"

        print(
            "\nREVISED WEEK 98 CRM PRIORITY COMPLETE\n"
            "Reference week: 98\n"
            "Forecast: 99-102\n"
            f"Total households: {revised_summary['total_households']:,}\n"
            "Economic value basis: PRE_WINDOW monetary 26w\n"
            "High economic value policy: Top 20%\n"
            "High economic value households: "
            f"{revised_summary['high_economic_value_count']:,}\n"
            "Global risk top10: "
            f"{revised_summary['global_high_risk_top10_count']:,}\n"
            "Revised priority policy: Top 10% risk within high-economic-value customers\n"
            "Revised priority households: "
            f"{revised_summary['revised_priority_count']:,}\n"
            "Baseline actual no-purchase rate: "
            f"{revised_summary['baseline_no_purchase_rate']:.6f}\n"
            "Global risk top10 actual no-purchase rate: "
            f"{revised_summary['global_high_risk_no_purchase_rate']:.6f}\n"
            "High-economic-value actual no-purchase rate: "
            f"{revised_summary['high_economic_value_no_purchase_rate']:.6f}\n"
            "Revised priority actual no-purchase rate: "
            f"{revised_summary['revised_priority_no_purchase_rate']:.6f}\n"
            "Revised priority Lift vs all: "
            f"{format_revised_metric(revised_summary['revised_priority_lift_vs_all'])}\n"
            "Revised priority Lift vs high-economic-value: "
            f"{format_revised_metric(revised_summary['revised_priority_lift_vs_high_economic_value'])}\n"
            "Revised priority capture: "
            f"{format_revised_metric(revised_summary['revised_priority_capture_of_all_no_purchase'])}\n"
            "Revised priority monetary share: "
            f"{format_revised_metric(revised_summary['revised_priority_monetary_share_of_all'])}\n"
            "Model refit: NO\n"
            "Prediction regenerated: NO\n"
            "Operational household list: crm_week98_revised_priority_list.csv"
        )
        return

    if RUN_CRM_WEEK98_SIMULATION:
        _, final_test_scored_rows, final_test_weekly_stability = (
            load_final_crm_artifacts()
        )
        model_dataset, _ = load_and_validate_model_dataset(INPUT_CSV)
        (
            operational_snapshot,
            priority_list,
            actual_outcomes,
        ) = build_week98_operational_priority_snapshot(
            model_dataset, final_test_scored_rows
        )
        (
            priority_backtest,
            segment_summary,
            backtest_summary,
            crm_summary,
        ) = evaluate_week98_priority_backtest(
            operational_snapshot,
            priority_list,
            actual_outcomes,
            final_test_weekly_stability,
        )
        save_crm_week98_outputs(
            operational_snapshot,
            priority_list,
            priority_backtest,
            segment_summary,
            backtest_summary,
            crm_summary,
        )

        def format_metric(value: float | None) -> str:
            return "NULL" if value is None else f"{value:.6f}"

        print(
            "\nWEEK 98 CRM PRIORITY SIMULATION COMPLETE\n"
            "Reference week: 98\n"
            "Forecast window: 99-102\n"
            f"Total households: {crm_summary['total_households']:,}\n"
            f"High-risk top 10%: {crm_summary['high_risk_top10_count']:,}\n"
            f"High-value households: {crm_summary['high_value_count']:,}\n"
            f"High-value + high-risk priority households: {crm_summary['priority_count']:,}\n"
            "Week 98 baseline no-purchase rate: "
            f"{format_metric(crm_summary['week98_baseline_no_purchase_rate'])}\n"
            "High-risk top10 actual no-purchase rate: "
            f"{format_metric(crm_summary['high_risk_top10_no_purchase_rate'])}\n"
            "High-risk top10 Lift vs all: "
            f"{format_metric(crm_summary['high_risk_top10_lift_vs_all'])}\n"
            "Priority actual no-purchase rate: "
            f"{format_metric(crm_summary['priority_no_purchase_rate'])}\n"
            "Priority Lift vs all: "
            f"{format_metric(crm_summary['priority_lift_vs_all'])}\n"
            "Priority Lift vs high-value: "
            f"{format_metric(crm_summary['priority_lift_vs_high_value'])}\n"
            "Priority capture of all no-purchase: "
            f"{format_metric(crm_summary['priority_capture_of_all_no_purchase'])}\n"
            "High-value priority capture: "
            f"{format_metric(crm_summary['high_value_priority_capture'])}\n\n"
            "Final Test model was NOT refit.\n"
            "Final Test predictions were NOT regenerated.\n"
            "Operational priority list: crm_week98_priority_list.csv\n"
            "Backtest: crm_week98_priority_backtest.csv"
        )
        return

    model_dataset, data_quality_summary = load_and_validate_model_dataset(INPUT_CSV)
    data_splits, time_split_summary = create_time_based_splits(model_dataset)
    feature_sets = build_feature_sets()
    all_feature_names = feature_sets["full_behavior_plus_customer_state"]

    if RUN_FINAL_TEST:
        (
            final_development_data,
            final_test_data,
            final_feature_names,
        ) = validate_frozen_final_model_spec(data_splits, feature_sets)
        validation_metrics = load_frozen_logistic_validation_metrics()
        final_test_results = evaluate_frozen_final_test_once(
            final_development_data,
            final_test_data,
            final_feature_names,
            validation_metrics,
        )
        save_final_test_outputs(
            final_test_results,
            final_development_data,
            final_test_data,
            final_feature_names,
        )

        metrics = final_test_results["metrics"]
        print(
            "\nFINAL TEST COMPLETE\n"
            "Frozen model: Logistic Regression\n"
            f"Feature set: {FINAL_MODEL_SPEC['feature_set']}\n"
            f"C: {FINAL_MODEL_SPEC['C']}\n"
            f"class_weight: {FINAL_MODEL_SPEC['class_weight']}\n"
            "Test weeks: 91-98\n"
            f"Test rows: {len(final_test_data):,}\n"
            f"Test PR-AUC: {metrics['pr_auc']:.6f}\n"
            f"Test ROC-AUC: {metrics['roc_auc']:.6f}\n"
            f"Test Brier: {metrics['brier_score']:.6f}\n"
            f"Precision@10%: {metrics['precision_at_10pct']:.6f}\n"
            f"Recall@10%: {metrics['recall_at_10pct']:.6f}\n"
            f"Lift@10%: {metrics['lift_at_10pct']:.6f}\n\n"
            "Final Test has been evaluated once.\n"
            "The frozen model has NOT been modified.\n"
            "Do NOT tune the model using these Test results.\n"
            "Next checkpoint: Review Test generalization before CRM prioritization."
        )
        return

    (
        train_feature_missingness,
        train_numeric_feature_profile,
        train_categorical_feature_profile,
    ) = profile_training_features(data_splits["TRAIN"], all_feature_names)

    (
        validation_feature_set_comparison,
        validation_model_performance,
        validation_top_k_metrics,
        validation_pr_auc_leader_specification,
        validation_pr_auc_leader_probability,
        validation_weekly_stability,
        validation_calibration_by_bin,
        logistic_regression_coefficients,
        xgboost_feature_importance,
        validation_finalists,
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
        validation_pr_auc_leader_probability,
        validation_model_performance,
        validation_calibration_by_bin,
        validation_weekly_stability,
    )

    (
        finalist_model_comparison,
        finalist_top_k_comparison,
        finalist_calibration_by_bin,
        finalist_weekly_stability,
        finalist_weekly_summary,
    ) = build_finalist_validation_comparisons(
        data_splits["VALIDATION"], validation_finalists
    )
    save_finalist_validation_outputs(
        finalist_model_comparison,
        finalist_top_k_comparison,
        finalist_calibration_by_bin,
        finalist_weekly_stability,
        finalist_weekly_summary,
    )
    save_finalist_validation_figures(
        finalist_calibration_by_bin,
        finalist_weekly_stability,
    )

    print_pipeline_step("7/8", "Validation finalist checkpoint complete")
    for model_family in ("logistic_regression", "xgboost"):
        finalist = validation_finalists[model_family]
        print(
            f"\n{model_family} finalist:\n"
            f"candidate_id = {finalist['candidate_id']}\n"
            f"feature_set = {finalist['feature_set']}\n"
            f"hyperparameters = {json.dumps(finalist['parameters'], sort_keys=True)}\n"
            f"PR-AUC = {finalist['metrics']['pr_auc']:.6f}\n"
            f"Lift@10% = {finalist['metrics']['lift_at_10pct']:.6f}\n"
            f"Brier = {finalist['metrics']['brier_score']:.6f}"
        )

    print("\nValidation PR-AUC leader (not a final model):")
    print(json.dumps(validation_pr_auc_leader_specification, indent=2, default=str))
    print_pipeline_step("8/8", "Stopping before final model selection and TEST")
    print(
        "Validation finalist comparison completed.\n"
        "Review performance, Top-K, calibration, weekly stability, and model "
        "simplicity before locking the final model.\n\n"
        "Final model has NOT been selected.\n"
        "Final Test has NOT been run."
    )

    final_test_outputs = [
        *OUTPUT_DIR.glob("1[2-4]_final_test_*.csv"),
        *FIGURE_DIR.glob("final_test_*.png"),
    ]
    if final_test_outputs:
        print("Existing final-test output found; this run did not create or update it.")


if __name__ == "__main__":
    main()


# ============================================================
# 06~07페이지 Tableau 시각화용 CSV 생성
# ============================================================



# ============================================================
# 0. 경로 설정
# ============================================================

PROJECT_DIR_TABLEAU = Path.cwd()

MODEL_OUTPUT_DIR_TABLEAU = PROJECT_DIR_TABLEAU / "outputs" / "modeling"
TABLEAU_OUTPUT_DIR = MODEL_OUTPUT_DIR_TABLEAU / "tableau_06_07"

TABLEAU_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

ENCODING = "utf-8-sig"

print("현재 작업 폴더:", PROJECT_DIR_TABLEAU)
print("모델 결과 폴더:", MODEL_OUTPUT_DIR_TABLEAU)

# ============================================================
# 1. 필요한 기존 결과파일 경로
# ============================================================

PATH_VALIDATION_COMPARE = (
    MODEL_OUTPUT_DIR_TABLEAU
    / "validation_finalist_model_comparison.csv"
)

PATH_FINAL_TEST_PERFORMANCE = (
    MODEL_OUTPUT_DIR_TABLEAU
    / "12_final_test_model_performance.csv"
)

PATH_FINAL_TEST_TOPK = (
    MODEL_OUTPUT_DIR_TABLEAU
    / "13_final_test_top_k_metrics.csv"
)

PATH_FINAL_TEST_CALIBRATION = (
    MODEL_OUTPUT_DIR_TABLEAU
    / "15_final_test_calibration_by_bin.csv"
)


# ============================================================
# 2. 파일 존재 여부 확인
# ============================================================

required_files = [
    PATH_VALIDATION_COMPARE,
    PATH_FINAL_TEST_PERFORMANCE,
    PATH_FINAL_TEST_TOPK,
    PATH_FINAL_TEST_CALIBRATION,
]

missing_files = [
    path for path in required_files
    if not path.exists()
]

if missing_files:
    print("\n[오류] 필요한 기존 결과파일이 없습니다.")

    for path in missing_files:
        print(path)

    raise FileNotFoundError(
        "위 파일이 outputs/modeling 폴더에 존재하는지 확인하세요."
    )


# ============================================================
# 3. 기존 모델링 결과 불러오기
# ============================================================

validation_compare = pd.read_csv(
    PATH_VALIDATION_COMPARE
)

final_test_performance = pd.read_csv(
    PATH_FINAL_TEST_PERFORMANCE
)

final_test_topk = pd.read_csv(
    PATH_FINAL_TEST_TOPK
)

final_test_calibration = pd.read_csv(
    PATH_FINAL_TEST_CALIBRATION
)


# ============================================================
# 4. 06페이지
#    로지스틱 회귀 vs XGBoost
#
#    PDF 핵심 메시지:
#    - XGBoost는 전체 PR-AUC가 조금 높음
#    - 위험 상위 10% 선별에서는 로지스틱 회귀도 경쟁력 있음
#    - 설명 가능성까지 고려해 로지스틱 회귀 최종 선택
# ============================================================

model_name_map = {
    "logistic_regression": "로지스틱 회귀",
    "xgboost": "XGBoost",
}

model_order_map = {
    "logistic_regression": 1,
    "xgboost": 2,
}


# 필요한 두 모델만 추출
page06_source = validation_compare[
    validation_compare["model_family"].isin(
        ["logistic_regression", "xgboost"]
    )
].copy()


# 혹시 중복이 있는지 확인
if len(page06_source) != 2:
    raise ValueError(
        "validation_finalist_model_comparison.csv에서 "
        "로지스틱 회귀와 XGBoost가 각각 1행씩 있어야 합니다."
    )


page06_source["모델"] = (
    page06_source["model_family"]
    .map(model_name_map)
)

page06_source["모델순서"] = (
    page06_source["model_family"]
    .map(model_order_map)
)

page06_source["최종선택"] = np.where(
    page06_source["model_family"]
    == "logistic_regression",
    "최종 선택",
    "비교 모델",
)


# ------------------------------------------------------------
# 06페이지 그래프에서는 지표 2개만 사용
#
# 1. PR-AUC
# 2. 위험 상위 10% 실제 미구매율
#
# Brier, Lift 등을 한 그래프에 섞으면 단위가 달라져
# PDF 가독성이 떨어지므로 제외
# ------------------------------------------------------------

page06_pr_auc = page06_source[
    [
        "모델",
        "모델순서",
        "최종선택",
        "pr_auc",
    ]
].copy()

page06_pr_auc["지표"] = "PR-AUC"
page06_pr_auc["지표순서"] = 1

page06_pr_auc = page06_pr_auc.rename(
    columns={
        "pr_auc": "지표값"
    }
)


page06_top10 = page06_source[
    [
        "모델",
        "모델순서",
        "최종선택",
        "precision_at_10pct",
    ]
].copy()

page06_top10["지표"] = "위험 상위 10% 실제 미구매율"
page06_top10["지표순서"] = 2

page06_top10 = page06_top10.rename(
    columns={
        "precision_at_10pct": "지표값"
    }
)


# 세로형(Long Format)으로 결합
page06_tableau = pd.concat(
    [
        page06_pr_auc,
        page06_top10,
    ],
    ignore_index=True,
)


page06_tableau = page06_tableau[
    [
        "지표",
        "지표순서",
        "모델",
        "모델순서",
        "최종선택",
        "지표값",
    ]
].sort_values(
    [
        "지표순서",
        "모델순서",
    ]
)


# 저장
PAGE06_OUTPUT = (
    TABLEAU_OUTPUT_DIR
    / "06_로지스틱회귀_XGBoost_비교.csv"
)

page06_tableau.to_csv(
    PAGE06_OUTPUT,
    index=False,
    encoding=ENCODING,
)


# ============================================================
# 5. 07페이지 메인 그래프
#    전체 고객 vs 위험 상위 10% 실제 미구매율
# ============================================================

# Final Test 전체 성능은 한 행
if len(final_test_performance) != 1:
    raise ValueError(
        "12_final_test_model_performance.csv는 "
        "최종 모델 1행이어야 합니다."
    )

test_performance = final_test_performance.iloc[0]


# 전체 Test 고객×주차 수
전체고객수 = int(
    test_performance["test_row_count"]
)


# 전체 실제 미구매율
# 기존 코드에는 test_no_purchase_rate와
# no_purchase_rate가 함께 존재할 수 있으므로
# 명시적인 test_no_purchase_rate를 우선 사용
if "test_no_purchase_rate" in final_test_performance.columns:
    전체미구매율 = float(
        test_performance["test_no_purchase_rate"]
    )
else:
    전체미구매율 = float(
        test_performance["no_purchase_rate"]
    )


전체미구매수 = int(
    round(
        전체고객수
        * 전체미구매율
    )
)


# ------------------------------------------------------------
# Top 10% 행 찾기
# ------------------------------------------------------------

final_test_topk["top_k_share"] = pd.to_numeric(
    final_test_topk["top_k_share"],
    errors="raise",
)

top10_rows = final_test_topk[
    np.isclose(
        final_test_topk["top_k_share"],
        0.10,
    )
]


if len(top10_rows) != 1:
    raise ValueError(
        "13_final_test_top_k_metrics.csv에서 "
        "Top 10% 행이 정확히 1개여야 합니다."
    )


top10 = top10_rows.iloc[0]


위험상위10고객수 = int(
    top10["selected_row_count"]
)

위험상위10미구매수 = int(
    round(
        float(
            top10["selected_no_purchase_count"]
        )
    )
)

위험상위10미구매율 = float(
    top10["precision_at_k"]
)

위험상위10집중도 = float(
    top10["lift_at_k"]
)


# ------------------------------------------------------------
# Tableau용 데이터
# ------------------------------------------------------------

page07_rate = pd.DataFrame(
    [
        {
            "고객집단": "전체 고객",
            "집단순서": 1,
            "고객기록수": 전체고객수,
            "실제미구매수": 전체미구매수,
            "실제미구매율": 전체미구매율,
            "실제구매율": 1 - 전체미구매율,
            "전체대비미구매집중도": 1.0,
            "평가기간": "91~98주",
        },
        {
            "고객집단": "위험 상위 10%",
            "집단순서": 2,
            "고객기록수": 위험상위10고객수,
            "실제미구매수": 위험상위10미구매수,
            "실제미구매율": 위험상위10미구매율,
            "실제구매율": 1 - 위험상위10미구매율,
            "전체대비미구매집중도": 위험상위10집중도,
            "평가기간": "91~98주",
        },
    ]
)


PAGE07_RATE_OUTPUT = (
    TABLEAU_OUTPUT_DIR
    / "07_전체고객_위험상위10_실제미구매율.csv"
)

page07_rate.to_csv(
    PAGE07_RATE_OUTPUT,
    index=False,
    encoding=ENCODING,
)


# ============================================================
# 6. 07페이지 보조 그래프
#    Calibration
#
#    X축 = 평균 예측 미구매 확률
#    Y축 = 실제 미구매율
#
#    실제 모델 선과 이상적 일치선을 같이 그릴 수 있도록
#    Long Format으로 변환
# ============================================================

calibration = final_test_calibration.copy()


# bin이 없는 경우만 생성
if "bin" not in calibration.columns:
    calibration.insert(
        0,
        "bin",
        range(
            1,
            len(calibration) + 1
        ),
    )


calibration[
    "평균예측미구매확률"
] = pd.to_numeric(
    calibration[
        "mean_predicted_no_purchase_probability"
    ],
    errors="raise",
)


calibration[
    "실제미구매율"
] = pd.to_numeric(
    calibration[
        "observed_no_purchase_rate"
    ],
    errors="raise",
)


calibration[
    "예측실제차이"
] = (
    calibration["실제미구매율"]
    - calibration["평균예측미구매확률"]
)


calibration[
    "절대오차"
] = calibration[
    "예측실제차이"
].abs()


# ------------------------------------------------------------
# 실제 모델 Calibration 선
# ------------------------------------------------------------

calibration_actual = pd.DataFrame(
    {
        "확률구간": calibration["bin"],
        "평균예측미구매확률": (
            calibration[
                "평균예측미구매확률"
            ]
        ),
        "선구분": "실제 미구매율",
        "그래프미구매율": (
            calibration[
                "실제미구매율"
            ]
        ),
        "예측실제차이": (
            calibration[
                "예측실제차이"
            ]
        ),
        "절대오차": (
            calibration[
                "절대오차"
            ]
        ),
    }
)


# ------------------------------------------------------------
# 이상적인 Calibration 기준선
# 예측확률 = 실제미구매율
# ------------------------------------------------------------

calibration_ideal = pd.DataFrame(
    {
        "확률구간": calibration["bin"],
        "평균예측미구매확률": (
            calibration[
                "평균예측미구매확률"
            ]
        ),
        "선구분": "이상적 일치선",
        "그래프미구매율": (
            calibration[
                "평균예측미구매확률"
            ]
        ),
        "예측실제차이": 0.0,
        "절대오차": 0.0,
    }
)


page07_calibration = pd.concat(
    [
        calibration_actual,
        calibration_ideal,
    ],
    ignore_index=True,
)


page07_calibration = (
    page07_calibration
    .sort_values(
        [
            "선구분",
            "평균예측미구매확률",
        ]
    )
    .reset_index(drop=True)
)


PAGE07_CALIBRATION_OUTPUT = (
    TABLEAU_OUTPUT_DIR
    / "07_예측확률_실제미구매율_Calibration.csv"
)

page07_calibration.to_csv(
    PAGE07_CALIBRATION_OUTPUT,
    index=False,
    encoding=ENCODING,
)


# ============================================================
# 7. 저장 결과 검증
# ============================================================

print("\n")
print("=" * 70)
print("06~07페이지 Tableau용 CSV 생성 완료")
print("=" * 70)

print("\n저장 폴더")
print(TABLEAU_OUTPUT_DIR)


print("\n[06페이지]")
print(PAGE06_OUTPUT.name)

print(
    page06_tableau.to_string(
        index=False
    )
)


print("\n[07페이지 - 전체 고객 vs 위험 상위 10%]")
print(PAGE07_RATE_OUTPUT.name)

print(
    page07_rate.to_string(
        index=False
    )
)


print("\n[07페이지 - Calibration]")
print(PAGE07_CALIBRATION_OUTPUT.name)

print(
    page07_calibration.head(
        20
    ).to_string(
        index=False
    )
)


# ============================================================
# 8. 핵심 수치 자동 확인
# ============================================================

print("\n")
print("=" * 70)
print("PDF에 들어갈 핵심 수치")
print("=" * 70)

print(
    f"전체 실제 미구매율: "
    f"{전체미구매율 * 100:.2f}%"
)

print(
    f"위험 상위 10% 실제 미구매율: "
    f"{위험상위10미구매율 * 100:.2f}%"
)

print(
    f"전체 대비 미구매 집중도: "
    f"{위험상위10집중도:.2f}배"
)


평균절대오차 = (
    calibration[
        "절대오차"
    ].mean()
)

최대절대오차 = (
    calibration[
        "절대오차"
    ].max()
)


print(
    f"Calibration 평균 절대오차: "
    f"{평균절대오차 * 100:.2f}%p"
)

print(
    f"Calibration 최대 절대오차: "
    f"{최대절대오차 * 100:.2f}%p"
)


print("\n생성된 CSV 3개")

print(
    "1.",
    PAGE06_OUTPUT.name,
)

print(
    "2.",
    PAGE07_RATE_OUTPUT.name,
)

print(
    "3.",
    PAGE07_CALIBRATION_OUTPUT.name,
)


