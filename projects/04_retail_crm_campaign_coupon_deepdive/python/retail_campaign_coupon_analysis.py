from __future__ import annotations

# ============================================================
# 01. 설정 및 입출력 경로
# ============================================================

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager
import numpy as np
import pandas as pd


PROJECT_DIR = Path(__file__).resolve().parent
INPUT_DIR = PROJECT_DIR
FIGURE_DIR = PROJECT_DIR / "outputs" / "campaign_coupon" / "figures"

CSV_FILES = {
    "campaign_type": "01_campaign_type_response.csv",
    "historical_response": "02_historical_response_rate.csv",
    "period_sales": "03_pre_during_post_sales.csv",
    "actionability_summary": "04_crm_actionability_summary.csv",
    "sensitivity": "05_crm_sensitivity_summary.csv",
    "actionability_customers": "06_crm_actionability_customers.csv",
}

HISTORICAL_ORDER = [
    "NO_HISTORY",
    "EXPOSED_NO_REDEMPTION",
    "ONE_TIME_REDEEMER",
    "REPEAT_REDEEMER",
]
HISTORICAL_LABELS = {
    "NO_HISTORY": "과거 캠페인 경험 없음",
    "EXPOSED_NO_REDEMPTION": "노출 후 쿠폰 사용 없음",
    "ONE_TIME_REDEEMER": "1회 캠페인 반응",
    "REPEAT_REDEEMER": "반복 캠페인 반응",
}
HISTORICAL_COLORS = {
    "NO_HISTORY": "#B8C4CE",
    "EXPOSED_NO_REDEMPTION": "#6F8FAF",
    "ONE_TIME_REDEEMER": "#F2B56B",
    "REPEAT_REDEEMER": "#D2675A",
}

ACTION_ORDER = [
    "COUPON_PRIORITY",
    "COUPON_TEST",
    "TEST_AND_LEARN",
    "ALTERNATIVE_INTERVENTION",
]
ACTION_LABELS = {
    "COUPON_PRIORITY": "쿠폰·프로모션 우선 검토",
    "COUPON_TEST": "쿠폰 테스트 검토",
    "TEST_AND_LEARN": "반응정보 탐색 필요",
    "ALTERNATIVE_INTERVENTION": "대체 CRM 접근 검토",
}
ACTION_COLORS = {
    "COUPON_PRIORITY": "#C44E52",
    "COUPON_TEST": "#E6A15A",
    "TEST_AND_LEARN": "#7A9E9F",
    "ALTERNATIVE_INTERVENTION": "#4C72B0",
}

CUMULATIVE_ORDER = ["TOP_10", "TOP_20", "TOP_30", "TOP_40", "TOP_50"]
CUMULATIVE_LABELS = {
    "TOP_10": "위험 상위 10%",
    "TOP_20": "위험 상위 20%",
    "TOP_30": "위험 상위 30%",
    "TOP_40": "위험 상위 40%",
    "TOP_50": "위험 상위 50%",
}
BAND_ORDER = [
    "BAND_00_10",
    "BAND_10_20",
    "BAND_20_30",
    "BAND_30_40",
    "BAND_40_50",
]
BAND_LABELS = {
    "BAND_00_10": "위험 0~10%",
    "BAND_10_20": "위험 10~20%",
    "BAND_20_30": "위험 20~30%",
    "BAND_30_40": "위험 30~40%",
    "BAND_40_50": "위험 40~50%",
}

REQUIRED_COLUMNS = {
    "campaign_type": {
        "campaign_type",
        "recipient_observation_count",
        "redeemer_observation_count",
        "redemption_rate",
    },
    "historical_response": {
        "promotion_response_state",
        "observation_count",
        "current_redeemer_count",
        "current_redemption_rate",
    },
    "period_sales": {
        "response_group",
        "pre_sales_per_day_mean",
        "during_sales_per_day_mean",
        "post_sales_per_day_mean",
        "pre_sales_per_day_median",
        "during_sales_per_day_median",
        "post_sales_per_day_median",
    },
    "actionability_summary": {
        "promotion_actionability",
        "promotion_evidence_level",
        "household_count",
        "share_of_priority_households",
    },
    "sensitivity": {
        "analysis_type",
        "cohort_label",
        "cutoff_lower",
        "cutoff_upper",
        "cohort_household_count",
        "promotion_response_state",
        "state_household_count",
        "state_share",
        "share_difference_vs_top10_pp",
    },
    "actionability_customers": {
        "priority_rank",
        "household_key",
        "predicted_no_purchase_probability",
        "pre_window_monetary_26w",
        "risk_rank_within_high_economic_value",
        "historical_campaign_count",
        "historical_redeemed_campaign_count",
        "historical_campaign_redemption_rate",
        "days_since_last_historical_redemption",
        "promotion_response_state",
        "promotion_evidence_level",
        "promotion_actionability",
    },
}

NUMERIC_COLUMNS = {
    "campaign_type": [
        "recipient_observation_count",
        "redeemer_observation_count",
        "redemption_rate",
    ],
    "historical_response": [
        "observation_count",
        "current_redeemer_count",
        "current_redemption_rate",
    ],
    "period_sales": [
        "pre_sales_per_day_mean",
        "during_sales_per_day_mean",
        "post_sales_per_day_mean",
        "pre_sales_per_day_median",
        "during_sales_per_day_median",
        "post_sales_per_day_median",
    ],
    "actionability_summary": ["household_count", "share_of_priority_households"],
    "sensitivity": [
        "cutoff_lower",
        "cutoff_upper",
        "cohort_household_count",
        "state_household_count",
        "state_share",
        "share_difference_vs_top10_pp",
    ],
    "actionability_customers": [
        "priority_rank",
        "household_key",
        "predicted_no_purchase_probability",
        "pre_window_monetary_26w",
        "risk_rank_within_high_economic_value",
        "historical_campaign_count",
        "historical_redeemed_campaign_count",
        "historical_campaign_redemption_rate",
        "days_since_last_historical_redemption",
    ],
}


# ============================================================
# 02. 한국어 글꼴 설정
# ============================================================

def configure_korean_font() -> str:
    installed = {font.name for font in font_manager.fontManager.ttflist}
    candidates = [
        "Malgun Gothic",
        "Noto Sans CJK KR",
        "Noto Sans KR",
        "NanumGothic",
        "AppleGothic",
    ]
    selected = next((name for name in candidates if name in installed), "DejaVu Sans")
    plt.rcParams.update(
        {
            "font.family": selected,
            "axes.unicode_minus": False,
            "figure.facecolor": "white",
            "axes.facecolor": "white",
            "axes.titlesize": 15,
            "axes.labelsize": 11,
            "xtick.labelsize": 10,
            "ytick.labelsize": 10,
            "legend.fontsize": 9,
        }
    )
    if selected == "DejaVu Sans":
        print("[주의] 설치된 한국어 글꼴을 찾지 못했습니다. 실행 환경의 글꼴을 확인하세요.")
    return selected


# ============================================================
# 03. SQL Export CSV 로드 및 품질 검증
# ============================================================

def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def load_and_validate_csvs(input_dir: Path) -> dict[str, pd.DataFrame]:
    paths = {key: input_dir / name for key, name in CSV_FILES.items()}
    missing = [f"{path.name} (예상 경로: {path})" for path in paths.values() if not path.is_file()]
    if missing:
        raise FileNotFoundError("SQL Export CSV가 누락되었습니다:\n- " + "\n- ".join(missing))
    print("[01] 입력 CSV 6개 확인 PASS")

    frames: dict[str, pd.DataFrame] = {}
    for key, path in paths.items():
        frame = pd.read_csv(path)
        missing_columns = sorted(REQUIRED_COLUMNS[key] - set(frame.columns))
        if missing_columns:
            raise ValueError(
                f"{path.name} 필수 컬럼 누락: {missing_columns}; 실제 컬럼: {list(frame.columns)}"
            )
        for column in NUMERIC_COLUMNS[key]:
            frame[column] = pd.to_numeric(frame[column], errors="raise")
        frames[key] = frame

    campaign = frames["campaign_type"]
    require(not campaign["campaign_type"].duplicated().any(), "Campaign Type 중복 행이 있습니다.")
    require((campaign["recipient_observation_count"] > 0).all(), "Campaign 수신 관측 수는 양수여야 합니다.")
    require((campaign["redeemer_observation_count"] >= 0).all(), "Campaign 반응 수가 음수입니다.")
    require(
        (campaign["redeemer_observation_count"] <= campaign["recipient_observation_count"]).all(),
        "Campaign 반응 수가 수신 관측 수를 초과합니다.",
    )
    require(campaign["redemption_rate"].between(0, 1).all(), "Campaign 반응률이 0~1 범위를 벗어났습니다.")

    historical = frames["historical_response"]
    require(set(historical["promotion_response_state"]) == set(HISTORICAL_ORDER), "Historical Response 네 상태가 모두 필요합니다.")
    require(not historical["promotion_response_state"].duplicated().any(), "Historical Response 중복 행이 있습니다.")
    require((historical["observation_count"] > 0).all(), "Historical 관측 수는 양수여야 합니다.")
    require((historical["current_redeemer_count"] >= 0).all(), "현재 반응 수가 음수입니다.")
    require(
        (historical["current_redeemer_count"] <= historical["observation_count"]).all(),
        "현재 반응 수가 Historical 관측 수를 초과합니다.",
    )
    require(historical["current_redemption_rate"].between(0, 1).all(), "현재 반응률이 0~1 범위를 벗어났습니다.")

    period = frames["period_sales"]
    require(not period["response_group"].duplicated().any(), "response_group 중복 행이 있습니다.")
    require(
        set(period["response_group"]) == {"REDEEMER", "NON_REDEEMER"},
        "PRE·DURING·POST CSV에는 REDEEMER와 NON_REDEEMER가 모두 필요합니다.",
    )
    require(
        not period[NUMERIC_COLUMNS["period_sales"]].isna().any().any(),
        "PRE·DURING·POST 구매금액에 NULL이 있습니다.",
    )

    action_summary = frames["actionability_summary"]
    require(set(action_summary["promotion_actionability"]) == set(ACTION_ORDER), "Actionability 네 상태가 모두 필요합니다.")
    require(
        not action_summary["promotion_actionability"].duplicated().any(),
        "Actionability Summary에 중복 행이 있습니다.",
    )
    require((action_summary["household_count"] > 0).all(), "Actionability 고객 수는 양수여야 합니다.")
    require(np.isclose(action_summary["share_of_priority_households"].sum(), 1.0), "Actionability 비중 합이 1이 아닙니다.")

    sensitivity = frames["sensitivity"]
    require(set(sensitivity["analysis_type"]) == {"CUMULATIVE", "BAND"}, "민감도 CSV에는 CUMULATIVE와 BAND가 모두 필요합니다.")
    require(set(sensitivity["promotion_response_state"]).issubset(HISTORICAL_ORDER), "허용되지 않은 Historical Response가 있습니다.")
    validate_sensitivity_group(sensitivity, "CUMULATIVE", CUMULATIVE_ORDER)
    validate_sensitivity_group(sensitivity, "BAND", BAND_ORDER)

    customers = frames["actionability_customers"]
    require(not customers["household_key"].duplicated().any(), "최종 고객 household_key가 중복되었습니다.")
    require(not customers["priority_rank"].duplicated().any(), "최종 고객 priority_rank가 중복되었습니다.")
    require(customers["predicted_no_purchase_probability"].between(0, 1).all(), "예측확률이 0~1 범위를 벗어났습니다.")
    require(customers["pre_window_monetary_26w"].notna().all(), "최근 26주 구매금액에 NULL이 있습니다.")
    require(set(customers["promotion_actionability"]) == set(ACTION_ORDER), "최종 고객 Actionability 네 상태가 모두 필요합니다.")
    require(set(customers["promotion_response_state"]).issubset(HISTORICAL_ORDER), "최종 고객에 허용되지 않은 Historical Response가 있습니다.")

    summary_count = int(action_summary["household_count"].sum())
    require(summary_count == len(customers) == customers["household_key"].nunique(), "Actionability Summary와 최종 고객 수가 일치하지 않습니다.")
    require(
        action_summary.set_index("promotion_actionability")["household_count"].sort_index().equals(
            customers.groupby("promotion_actionability").size().sort_index().astype(action_summary["household_count"].dtype)
        ),
        "Actionability별 고객 수가 04와 06 CSV에서 일치하지 않습니다.",
    )
    print("[02] CSV Schema 및 품질검증 PASS")
    return frames


def validate_sensitivity_group(frame: pd.DataFrame, analysis_type: str, labels: list[str]) -> None:
    subset = frame.loc[frame["analysis_type"] == analysis_type]
    require(set(subset["cohort_label"]) == set(labels), f"{analysis_type} Cohort 5개가 정확하지 않습니다.")
    require(
        not subset.duplicated(["cohort_label", "promotion_response_state"]).any(),
        f"{analysis_type} Cohort × Segment 중복 행이 있습니다.",
    )
    require(
        subset.groupby("cohort_label")["promotion_response_state"].nunique().eq(len(HISTORICAL_ORDER)).all(),
        f"{analysis_type} 각 Cohort에 Historical Segment 4개가 필요합니다.",
    )
    require(
        np.allclose(subset.groupby("cohort_label")["state_share"].sum().to_numpy(), 1.0),
        f"{analysis_type} Cohort의 state_share 합이 1이 아닙니다.",
    )
    require(subset["state_share"].between(0, 1).all(), f"{analysis_type} state_share가 0~1 범위를 벗어났습니다.")


def style_axis(ax: plt.Axes, grid_axis: str = "y") -> None:
    ax.grid(axis=grid_axis, color="#D9DEE3", linewidth=0.7, alpha=0.7)
    ax.set_axisbelow(True)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.spines["left"].set_color("#AAB2BA")
    ax.spines["bottom"].set_color("#AAB2BA")


def save_figure(fig: plt.Figure, stem: str, output_dir: Path) -> str:
    output_dir.mkdir(parents=True, exist_ok=True)
    png_name = f"{stem}.png"
    fig.savefig(output_dir / png_name, dpi=300, bbox_inches="tight", facecolor="white")
    fig.savefig(output_dir / f"{stem}.svg", bbox_inches="tight", facecolor="white")
    plt.close(fig)
    return png_name


# ============================================================
# 04. Campaign Type별 Coupon 반응률 시각화
# ============================================================

def plot_campaign_type(frame: pd.DataFrame, output_dir: Path) -> str:
    data = frame.sort_values("campaign_type").copy()
    values = data["redemption_rate"] * 100
    fig, ax = plt.subplots(figsize=(9, 6))
    bars = ax.bar(data["campaign_type"], values, color="#4C72B0", width=0.62)
    for bar, rate, redeemed, recipients in zip(
        bars,
        values,
        data["redeemer_observation_count"],
        data["recipient_observation_count"],
    ):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height(),
            f"{rate:.1f}%\n사용 {int(redeemed):,} / 수신 {int(recipients):,}",
            ha="center",
            va="bottom",
            fontsize=10,
        )
    ax.set_title("캠페인 유형별 쿠폰 사용률", pad=18, weight="bold")
    ax.set_xlabel("캠페인 유형")
    ax.set_ylabel("쿠폰 사용률 (%)")
    ax.set_ylim(0, max(values.max() * 1.28, 1))
    style_axis(ax)
    fig.tight_layout()
    return save_figure(fig, "01_캠페인유형별_쿠폰반응률", output_dir)


# ============================================================
# 05. Historical Response별 현재 Campaign 반응률 시각화
# ============================================================

def plot_historical_response(frame: pd.DataFrame, output_dir: Path) -> str:
    data = frame.set_index("promotion_response_state").loc[HISTORICAL_ORDER].reset_index()
    values = data["current_redemption_rate"] * 100
    labels = [HISTORICAL_LABELS[state] for state in data["promotion_response_state"]]
    colors = [HISTORICAL_COLORS[state] for state in data["promotion_response_state"]]
    fig, ax = plt.subplots(figsize=(11, 6))
    bars = ax.bar(labels, values, color=colors, width=0.66)
    for bar, rate, redeemed, observations in zip(
        bars, values, data["current_redeemer_count"], data["observation_count"]
    ):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height(),
            f"{rate:.1f}%\n사용 {int(redeemed):,} / 관측 {int(observations):,}",
            ha="center",
            va="bottom",
            fontsize=9.5,
        )
    ax.set_title("과거 프로모션 반응 수준별 현재 쿠폰 사용률", pad=18, weight="bold")
    ax.set_xlabel("과거 프로모션 반응 수준")
    ax.set_ylabel("현재 캠페인 쿠폰 사용률 (%)")
    ax.set_ylim(0, max(values.max() * 1.25, 1))
    ax.tick_params(axis="x", rotation=8)
    style_axis(ax)
    fig.tight_layout()
    return save_figure(fig, "02_과거프로모션반응별_현재캠페인반응률", output_dir)


# ============================================================
# 06. Redeemer·Non-Redeemer PRE·DURING·POST 시각화
# ============================================================

def plot_period_sales(frame: pd.DataFrame, output_dir: Path) -> str:
    value_columns = [
        "pre_sales_per_day_mean",
        "during_sales_per_day_mean",
        "post_sales_per_day_mean",
    ]
    period_labels = ["캠페인 전 8주", "캠페인 진행기간", "캠페인 후 4주"]
    group_labels = {"REDEEMER": "쿠폰 반응 고객", "NON_REDEEMER": "쿠폰 비반응 고객"}
    group_colors = {"REDEEMER": "#C44E52", "NON_REDEEMER": "#4C72B0"}
    require(set(frame["response_group"]).issubset(group_labels), "예상하지 못한 response_group이 있습니다.")
    fig, ax = plt.subplots(figsize=(10, 6))
    x = np.arange(len(period_labels))
    for group in ["REDEEMER", "NON_REDEEMER"]:
        if group not in set(frame["response_group"]):
            continue
        values = frame.loc[frame["response_group"] == group, value_columns].iloc[0].to_numpy(dtype=float)
        ax.plot(x, values, marker="o", linewidth=2.5, markersize=7, label=group_labels[group], color=group_colors[group])
        for x_value, value in zip(x, values):
            ax.annotate(f"{value:,.2f}", (x_value, value), xytext=(0, 9), textcoords="offset points", ha="center", color=group_colors[group])
    ax.set_title("쿠폰 반응 여부에 따른 캠페인 전·중·후 하루 평균 구매금액", pad=18, weight="bold")
    ax.set_xlabel("관찰 기간")
    ax.set_ylabel("하루 평균 구매금액")
    ax.set_xticks(x, period_labels)
    ax.legend(frameon=False)
    style_axis(ax)
    fig.tight_layout()
    return save_figure(fig, "03_캠페인전중후_일평균구매금액", output_dir)


# ============================================================
# 07. 최종 CRM Actionability 분포 시각화
# ============================================================

def plot_actionability(frame: pd.DataFrame, total_households: int, output_dir: Path) -> str:
    data = frame.set_index("promotion_actionability").loc[ACTION_ORDER].reset_index()
    labels = [ACTION_LABELS[action] for action in data["promotion_actionability"]]
    colors = [ACTION_COLORS[action] for action in data["promotion_actionability"]]
    fig, ax = plt.subplots(figsize=(11, 6))
    bars = ax.bar(labels, data["household_count"], color=colors, width=0.66)
    for bar, count, share in zip(bars, data["household_count"], data["share_of_priority_households"]):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height(), f"{int(count):,}가구\n{share * 100:.1f}%", ha="center", va="bottom")
    ax.set_title(f"최종 CRM 우선관리 {total_households:,}가구의 접근 검토 방향", pad=18, weight="bold")
    ax.set_xlabel("CRM 접근 검토 방향")
    ax.set_ylabel("고객 수")
    ax.set_ylim(0, max(data["household_count"].max() * 1.25, 1))
    ax.tick_params(axis="x", rotation=8)
    style_axis(ax)
    fig.tight_layout()
    return save_figure(fig, "04_최종CRM_Actionability분포", output_dir)


# ============================================================
# 08. Risk Cutoff 누적 민감도 시각화
# ============================================================

def plot_stacked_sensitivity(
    frame: pd.DataFrame,
    analysis_type: str,
    order: list[str],
    label_map: dict[str, str],
    title: str,
    stem: str,
    output_dir: Path,
) -> str:
    data = frame.loc[frame["analysis_type"] == analysis_type].copy()
    shares = (
        data.pivot(index="cohort_label", columns="promotion_response_state", values="state_share")
        .reindex(index=order, columns=HISTORICAL_ORDER)
        * 100
    )
    counts = data.groupby("cohort_label")["cohort_household_count"].first().reindex(order)
    fig, ax = plt.subplots(figsize=(11, 6.5))
    bottom = np.zeros(len(order))
    x = np.arange(len(order))
    for state in HISTORICAL_ORDER:
        values = shares[state].to_numpy(dtype=float)
        ax.bar(x, values, bottom=bottom, width=0.7, label=HISTORICAL_LABELS[state], color=HISTORICAL_COLORS[state])
        for position, value, base in zip(x, values, bottom):
            if value >= 7:
                ax.text(position, base + value / 2, f"{value:.1f}%", ha="center", va="center", fontsize=8.5, color="white" if state in {"EXPOSED_NO_REDEMPTION", "REPEAT_REDEEMER"} else "#25313A")
        bottom += values
    for position, count in zip(x, counts):
        ax.text(position, 101.2, f"n = {int(count):,}", ha="center", va="bottom", fontsize=9)
    subtitle = (
        "경제적 가치 상위 20% 고객 안에서 위험 상위 10% → 50%로 누적 확대"
        if analysis_type == "CUMULATIVE"
        else "각 구간은 서로 겹치지 않는 50가구"
    )
    ax.set_title(title, pad=34, weight="bold")
    ax.text(0.5, 1.025, subtitle, transform=ax.transAxes, ha="center", va="bottom", fontsize=10, color="#55616C")
    ax.set_xlabel("미구매 위험 상위 고객 범위" if analysis_type == "CUMULATIVE" else "미구매 위험 구간")
    ax.set_ylabel("과거 프로모션 반응 구성비 (%)")
    ax.set_xticks(x, [label_map[label] for label in order])
    ax.set_ylim(0, 108)
    ax.legend(title="과거 프로모션 반응", frameon=False, bbox_to_anchor=(1.02, 1), loc="upper left")
    style_axis(ax)
    fig.tight_layout()
    return save_figure(fig, stem, output_dir)


# ============================================================
# 09. Risk Band별 Promotion Response 시각화
# ============================================================

def sensitivity_key_message(frame: pd.DataFrame) -> str:
    cumulative = frame.loc[frame["analysis_type"] == "CUMULATIVE"]
    lookup = cumulative.set_index(["cohort_label", "promotion_response_state"])["state_share"]
    repeat_difference = (lookup[("TOP_50", "REPEAT_REDEEMER")] - lookup[("TOP_10", "REPEAT_REDEEMER")]) * 100
    exposed_difference = (lookup[("TOP_50", "EXPOSED_NO_REDEMPTION")] - lookup[("TOP_10", "EXPOSED_NO_REDEMPTION")]) * 100
    return f"위험 상위 10% 대비 상위 50%의 반복 반응 비중 차이는 {repeat_difference:+.1f}%p, 노출 후 미사용 비중 차이는 {exposed_difference:+.1f}%p로 관찰됨"


# ============================================================
# 10. CRM Priority × Promotion Response Matrix 시각화
# ============================================================

def plot_priority_matrix(frame: pd.DataFrame, output_dir: Path) -> str:
    fig, ax = plt.subplots(figsize=(10.5, 7))
    for action in ACTION_ORDER:
        group = frame.loc[frame["promotion_actionability"] == action]
        ax.scatter(
            group["pre_window_monetary_26w"],
            group["predicted_no_purchase_probability"] * 100,
            s=72,
            alpha=0.78,
            color=ACTION_COLORS[action],
            edgecolor="white",
            linewidth=0.7,
            label=ACTION_LABELS[action],
        )
    for row in frame.nsmallest(min(4, len(frame)), "priority_rank").itertuples():
        ax.annotate(
            f"우선순위 {int(row.priority_rank)}",
            (row.pre_window_monetary_26w, row.predicted_no_purchase_probability * 100),
            xytext=(5, 5),
            textcoords="offset points",
            fontsize=8,
            color="#3B4650",
        )
    ax.set_title("CRM 우선관리 고객의 구매가치·미구매 위험·프로모션 반응", pad=18, weight="bold")
    ax.set_xlabel("최근 26주 구매금액 (구매가치)")
    ax.set_ylabel("다음 4주 미구매 예측확률 (%) (미구매 위험)")
    ax.legend(title="CRM 접근 검토 방향", frameon=False, bbox_to_anchor=(1.02, 1), loc="upper left")
    style_axis(ax)
    fig.tight_layout()
    return save_figure(fig, "07_CRM우선순위_프로모션반응_Matrix", output_dir)


# ============================================================
# 11. Figure Manifest 및 실행 요약 저장
# ============================================================

def build_manifest(frames: dict[str, pd.DataFrame], files: list[str]) -> pd.DataFrame:
    campaign = frames["campaign_type"].loc[frames["campaign_type"]["redemption_rate"].idxmax()]
    historical = frames["historical_response"].loc[frames["historical_response"]["current_redemption_rate"].idxmax()]
    period = frames["period_sales"]
    action = frames["actionability_summary"].loc[frames["actionability_summary"]["household_count"].idxmax()]
    redeemer_row = period.loc[period["response_group"] == "REDEEMER"]
    period_message = "CSV에 저장된 그룹별 PRE·DURING·POST 일평균 구매금액 패턴을 비교"
    if not redeemer_row.empty:
        row = redeemer_row.iloc[0]
        period_message = f"반응 고객의 일평균 구매금액은 캠페인 전 {row.pre_sales_per_day_mean:.2f}, 진행기간 {row.during_sales_per_day_mean:.2f}, 캠페인 후 {row.post_sales_per_day_mean:.2f}로 관찰됨"
    rows = [
        ("Figure 1", files[0], "캠페인 유형별 쿠폰 사용률", "캠페인 유형에 따라 관찰된 쿠폰 사용률은 어떻게 다른가?", CSV_FILES["campaign_type"], f"{campaign.campaign_type}의 관찰된 쿠폰 사용률이 {campaign.redemption_rate * 100:.1f}%로 가장 높음", "캠페인 유형과 쿠폰 사용률의 연관이며 인과관계가 아님"),
        ("Figure 2", files[1], "과거 프로모션 반응 수준별 현재 쿠폰 사용률", "과거 프로모션 반응 수준에 따라 현재 쿠폰 사용률은 어떻게 다른가?", CSV_FILES["historical_response"], f"{HISTORICAL_LABELS[historical.promotion_response_state]} 그룹의 현재 쿠폰 사용률이 {historical.current_redemption_rate * 100:.1f}%로 가장 높게 관찰됨", "과거와 현재 반응의 관찰된 연관이며 미래 반응을 보장하지 않음"),
        ("Figure 3", files[2], "쿠폰 반응 여부에 따른 캠페인 전·중·후 하루 평균 구매금액", "쿠폰 반응 고객과 비반응 고객의 캠페인 전·중·후 구매활동은 어떻게 달랐는가?", CSV_FILES["period_sales"], period_message, "관찰자료의 사전·사후 패턴이며 캠페인 인과관계가 아님; 중앙값은 원본 CSV에 보존"),
        ("Figure 4", files[3], "최종 CRM 우선관리 고객의 접근 검토 방향", "최종 CRM 우선관리 고객에게 어떤 접근을 검토할 근거가 있는가?", CSV_FILES["actionability_summary"], f"가장 큰 검토군은 {ACTION_LABELS[action.promotion_actionability]} {int(action.household_count):,}가구", "접근 검토 방향은 자동 발송 규칙이 아니라 담당자 판단을 돕는 근거"),
        ("Figure 5", files[4], "위험고객 범위를 넓혔을 때 과거 프로모션 반응 구성 변화", "미구매 위험 상위 고객 범위를 넓혀도 과거 프로모션 반응 구성은 유지되는가?", CSV_FILES["sensitivity"], sensitivity_key_message(frames["sensitivity"]), "위험 상위 20~50%는 운영정책 변경이 아니라 기존 상위 10% 결과의 민감도 분석"),
        ("Figure 6", files[5], "미구매 위험구간별 과거 프로모션 반응 구성", "위험 상위 10% 이후 추가되는 가치고객의 과거 프로모션 반응은 어떻게 다른가?", CSV_FILES["sensitivity"], "서로 겹치지 않는 미구매 위험구간별 과거 프로모션 반응 구성 차이를 제시", "위험수준과 과거 프로모션 반응의 관찰된 구성 차이이며 인과관계가 아님"),
        ("Figure 7", files[6], "CRM 우선관리 고객의 구매가치·미구매 위험·프로모션 반응", "같은 CRM 우선관리 고객도 과거 프로모션 반응에 따라 검토 방향이 어떻게 달라지는가?", CSV_FILES["actionability_customers"], "구매가치·미구매 위험·과거 프로모션 반응을 서로 다른 판단 축으로 표시", "미구매 위험과 과거 프로모션 반응은 서로 다른 의사결정 축"),
    ]
    return pd.DataFrame(rows, columns=["figure_no", "file_name", "title", "analysis_question", "source_csv", "key_message", "caution"])


def main(input_dir: Path = INPUT_DIR, output_dir: Path = FIGURE_DIR) -> None:
    configure_korean_font()
    frames = load_and_validate_csvs(input_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    figure_files = [plot_campaign_type(frames["campaign_type"], output_dir)]
    print("[03] Figure 1 저장 완료")
    figure_files.append(plot_historical_response(frames["historical_response"], output_dir))
    print("[04] Figure 2 저장 완료")
    figure_files.append(plot_period_sales(frames["period_sales"], output_dir))
    print("[05] Figure 3 저장 완료")
    total_households = len(frames["actionability_customers"])
    figure_files.append(plot_actionability(frames["actionability_summary"], total_households, output_dir))
    print("[06] Figure 4 저장 완료")
    figure_files.append(
        plot_stacked_sensitivity(
            frames["sensitivity"], "CUMULATIVE", CUMULATIVE_ORDER, CUMULATIVE_LABELS,
            "위험고객 범위를 넓혔을 때 과거 프로모션 반응 구성 변화",
            "05_RiskCutoff_HistoricalResponse민감도", output_dir,
        )
    )
    print("[07] Figure 5 저장 완료")
    figure_files.append(
        plot_stacked_sensitivity(
            frames["sensitivity"], "BAND", BAND_ORDER, BAND_LABELS,
            "미구매 위험구간별 과거 프로모션 반응 구성",
            "06_RiskBand_프로모션반응구성", output_dir,
        )
    )
    print("[08] Figure 6 저장 완료")
    figure_files.append(plot_priority_matrix(frames["actionability_customers"], output_dir))
    print("[09] Figure 7 저장 완료")

    manifest = build_manifest(frames, figure_files)
    manifest.to_csv(output_dir / "figure_manifest.csv", index=False, encoding="utf-8-sig")
    print("[10] Figure Manifest 저장 완료")
    print(f"총 Figure 수: {len(figure_files)}")
    print(f"출력 경로: {output_dir}")


if __name__ == "__main__":
    main()
