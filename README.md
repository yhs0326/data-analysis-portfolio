# Data Analysis Portfolio

**고객·구매 데이터를 분석 가능한 단위로 만들고, 통계·모델 검증을 거쳐 CRM·커머스 의사결정 기준으로 연결하는 데이터 분석가를 지향합니다.**

분석기법의 개수보다 **문제 정의 → 데이터 구조·품질 확인 → 검증 → 의사결정**의 흐름을 보여주는 데 집중했습니다.

---

## About Me

- **Major**: Mathematics / Applied Statistics (Double Major)
- **Target Role**: Data Analyst
- **Domain Focus**: E-commerce, CRM, Consumer Behavior
- **Tools**: SQL, PostgreSQL, Python, R, Tableau
- **Certificates**: ADsP (2025.09), SQLD (2026.03)

### Analysis Focus

- 비즈니스 질문을 분석 가능한 KPI와 분석 단위로 구체화
- SQL 기반 Data Mart 설계와 데이터 품질 검증
- Python/R 기반 고객분석·통계검정·예측모델링
- 시간 순서와 실제 운영 흐름을 고려한 Validation / Test
- 분석 결과를 고객 우선순위·모니터링·CRM 접근 검토 등 **실제 의사결정 기준**으로 연결

---

## Start Here

프로젝트 진행 시점을 기준으로 최신 프로젝트부터 정리했습니다. **03과 04는 하나의 Retail CRM Decision Track**으로 이어집니다.

| No. | Project | Period | Business Question | Key Decision / Result | Portfolio |
|---|---|---|---|---|---|
| 04 | [Campaign & Coupon Deep Dive](projects/04_retail_crm_campaign_coupon_deepdive/) **— 03 Extension** | 2026.08 | 먼저 확인할 고객은 찾았다. 그렇다면 그 고객에게 어떤 CRM 접근을 검토할 근거가 있는가? | 과거 프로모션 반응을 별도 판단 축으로 추가. 최종 50가구를 **쿠폰·프로모션 우선 검토 5가구 / 쿠폰 테스트 10가구 / 반응정보 탐색 3가구 / 대체 CRM 접근 32가구**로 구분 | [README](projects/04_retail_crm_campaign_coupon_deepdive/) · [PDF](projects/04_retail_crm_campaign_coupon_deepdive/outputs/retail_crm_campaign_coupon_deepdive.pdf) |
| 03 | [Retail CRM Priority Design](projects/03_retail_crm_priority/) **— Main CRM Project** | 2026.07 ~ 2026.08 | 구매기여가 큰 고객 중 누구부터 확인할 것인가? | 최근 26주 구매금액 상위 20% 안에서 미구매 위험 상위 10%를 선별. 91~98주 합산 **86건 중 65건(75.6%)** 포착, 가치고객 대비 **Lift 7.56배** | [README](projects/03_retail_crm_priority/) · [PDF](projects/03_retail_crm_priority/outputs/retail_crm_priority.pdf) |
| 02 | [Youth Quality of Work Analysis](projects/02_youth_quality_of_work/) | 2026.05 ~ 2026.06 | 청년 고용 문제를 취업 여부가 아니라 취업 이후 노동의 질로 보면 무엇이 달라지는가? | 청년 노동의 질 **3.23 → 3.13**, 청년 취업자의 **33.17%**를 취약 노동유형으로 식별. 고용안정·재취업 가능성 중심의 정책 모니터링 방향 제안 | [README](projects/02_youth_quality_of_work/) · [PDF](projects/02_youth_quality_of_work/outputs/youth_quality_of_work_portfolio.pdf) |
| 01 | [Consumer Pattern Transition](projects/01_consumer_pattern_transition/) | 2026.01 ~ 2026.02 | 소비 시간대 구조 변화가 다음 분기 변화를 미리 구분하는 신호가 될 수 있는가? | 소비패턴 전이 집단의 **다음 분기 피크시간 변화율 47.9%**, 유지집단 **26.8%** — 약 1.8배. 전이 발생 상권·업종을 조기경보 Watchlist로 활용하는 시나리오 제안 | [README](projects/01_consumer_pattern_transition/) · [PDF](projects/01_consumer_pattern_transition/outputs/consumer_pattern_transition_portfolio.pdf) |

---

## Portfolio Map

```text
01. Consumer Pattern Transition
    시간 흐름을 고려한 위험 신호 탐지 · Walk-forward 검증
                ↓
02. Youth Quality of Work
    통계검정 · 회귀 · 군집을 활용한 설명 분석
                ↓
03. Retail CRM Priority Design
    고객 행동을 "누구부터 확인할 것인가"라는 CRM 운영 기준으로 연결
                ↓
04. Campaign & Coupon Deep Dive
    03의 고객 선별을 "그 고객에게 어떻게 접근할 것인가"로 확장
```

---

## How I Approach Analysis

### 1. Problem / Decision
분석기법을 먼저 정하기보다 **누가 어떤 결정을 내려야 하는지**를 먼저 정의합니다.

### 2. Data / Metric Design
원천 데이터의 범위와 한계를 확인하고, 질문에 맞는 **분석 단위·KPI·라벨**을 설계합니다.

### 3. Analysis / Validation
SQL Data Mart, 통계 분석, 고객 세분화, 예측모형을 필요에 따라 사용하고 **중복·JOIN 증폭·기간 Coverage·시간 누출**을 점검합니다.

### 4. Decision / Limitation
결과가 처음 가설과 다르면 원인을 확인하고 기준을 다시 설계합니다. 실험하지 않은 결과는 캠페인 효과나 인과효과로 과대해석하지 않습니다.

---

## Main Business Track — Retail CRM Decision Track

### 03. Retail CRM Priority Design — 누구를 먼저 확인할 것인가?

초기에는 `RFM 고가치 × 전체 미구매 위험 상위 10%`를 CRM 최우선 고객으로 보려 했지만 **교집합이 0가구**였습니다. 원하는 결과를 만들기 위해 cutoff를 바꾸지 않고, 예측위험과 경제적 구매기여의 역할이 다르다는 점을 확인해 Business Layer를 다시 설계했습니다.

```text
전체 2,500가구
→ 최근 26주 구매금액 상위 20% = 500가구
→ 그 안에서 다음 4주 미구매 위험 상위 10%
→ CRM Priority 50가구
```

91~98주에 같은 기준을 반복 적용했을 때 가치고객 미구매 **86건 중 65건(75.6%)**을 Priority에서 포착했고, Priority 미구매율은 **16.25%**로 가치고객 전체 **2.15%** 대비 **7.56배**였습니다.

![03 CRM Priority 운영 규칙과 반복 검증](projects/03_retail_crm_priority/outputs/03_crm_priority_summary.jpg)

→ [03 Project README](projects/03_retail_crm_priority/) · [Portfolio PDF](projects/03_retail_crm_priority/outputs/retail_crm_priority.pdf)

### 04. Campaign & Coupon Deep Dive — 그 고객에게 어떻게 접근할 것인가?

03에서 `누구부터 확인할지`를 정한 뒤, 04에서는 **현재 Campaign 시작 전에 알 수 있었던 과거 프로모션 반응**을 별도 판단 축으로 추가했습니다.

과거 반복 반응 관측의 현재 쿠폰 사용률은 **40.8%**, 1회 반응은 **23.8%**, 노출 후 미상환은 **7.4%**였습니다. 이를 CRM Priority 50가구에 연결해 **쿠폰·프로모션 우선 검토 5가구 / 쿠폰 테스트 10가구 / 반응정보 탐색 3가구 / 대체 CRM 접근 32가구**로 구분했습니다.

또한 Coupon Redemption **2,318건**을 Coupon-Product Bridge와 직접 JOIN하면 약 **947.65배**로 행이 증폭되는 구조를 확인해, 반응률과 상환 횟수는 JOIN 이후 `COUNT(*)`로 계산하지 않도록 분석 단위를 분리했습니다.

![04 고객 선별에서 CRM 실행 설계로 확장](projects/04_retail_crm_campaign_coupon_deepdive/outputs/04_campaign_coupon_extension.jpg)

**다음 검증:** 현재 결과는 관찰자료 기반의 CRM 검토 근거입니다. 실제 운영에서는 상태별로 Treatment / Holdout을 무작위 배정하고 **4주 구매율의 순증(Incremental Purchase Rate)**과 **고객당 순증 매출(Incremental Revenue per Household)**을 비교하는 A/B Test로 효과를 검증해야 합니다.

→ [04 Project README](projects/04_retail_crm_campaign_coupon_deepdive/) · [Portfolio PDF](projects/04_retail_crm_campaign_coupon_deepdive/outputs/retail_crm_campaign_coupon_deepdive.pdf)

---

## Supporting Projects

| Project | What it demonstrates | Key Result / Use Case |
|---|---|---|
| [01. Consumer Pattern Transition](projects/01_consumer_pattern_transition/) | 시간대 소비구조 유형화, 전이 탐지, 코호트, Walk-forward 검증 | 전이 집단 다음 분기 피크시간 변화율 **47.9%** vs 유지집단 **26.8%**. 전이 발생 상권·업종을 우선 모니터링하는 조기경보 신호로 활용 |
| [02. Youth Quality of Work](projects/02_youth_quality_of_work/) | 지표 설계, KMeans, OLS(HC3), Logistic, 비모수 검정 | 청년 노동의 질 **3.23 → 3.13**, 취약 노동유형 **33.17%**. 고용안정성·재취업 가능성을 중심으로 취약집단 모니터링 및 지원 방향 검토 |

---

## Repository Structure

현재 `portfolio-revision` 브랜치의 최상위 구조입니다.

```text
data-analysis-portfolio/
├── .gitignore
├── README.md
├── requirements.txt
└── projects/
    ├── 01_consumer_pattern_transition/
    ├── 02_youth_quality_of_work/
    ├── 03_retail_crm_priority/
    └── 04_retail_crm_campaign_coupon_deepdive/
```

각 프로젝트 폴더의 실제 세부 구조와 파일 역할은 해당 프로젝트 README에 정리했습니다.

---

## Data Notice

원본 데이터는 각 제공처의 이용 조건과 저장 용량을 고려해 저장소에 포함하지 않습니다. 대신 분석 흐름, 주요 코드·SQL, 검증 결과, 시각화 및 포트폴리오 PDF를 확인할 수 있도록 구성했습니다.

---

## Note

이 저장소는 분석기법의 개수를 보여주는 것보다 **문제 정의 → 데이터 검증 → 분석 → 해석 → 의사결정 → 다음 검증 계획**의 흐름을 보여주는 것을 목표로 합니다.
