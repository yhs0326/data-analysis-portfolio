# Data Analysis Portfolio

이커머스·고객 행동 데이터를 중심으로 **무엇을 분석할지 정의하고, SQL로 분석 단위를 만들고, 통계·모델 검증을 거쳐 실제 의사결정 기준으로 연결하는 데이터 분석 포트폴리오**입니다.

모델이나 분석기법 자체보다 **왜 이 문제를 분석했는지 → 무엇을 확인했는지 → 결과로 어떤 판단을 지원할 수 있는지**가 빠르게 보이도록 정리했습니다.

---

## About Me

- **Major**: Mathematics / Applied Statistics (Double Major)
- **Target Role**: Data Analyst
- **Domain Focus**: E-commerce, CRM, Consumer Behavior
- **Tools**: SQL, PostgreSQL, Python, R, Tableau
- **Certificates**: ADsP, SQLD

### Analysis Focus

- 비즈니스 질문을 분석 가능한 KPI와 분석 단위로 구체화
- SQL 기반 분석용 Data Mart 설계와 데이터 품질 검증
- Python/R 기반 고객분석·통계검정·예측모델링
- 시간 순서와 실제 운영 흐름을 고려한 Validation / Test
- 분석 결과를 고객 우선순위, 모니터링 기준 등 **실제 의사결정 규칙**으로 연결

---

## Start Here

지원 직무와의 연관성과 최근 프로젝트를 고려해 아래 순서로 보는 것을 권장합니다.

| Priority | Project | Business Question | Key Decision / Result | Portfolio |
|---|---|---|---|---|
| 1 | [Retail CRM Priority Design](projects/03_retail_crm_priority/) | 모든 고객을 동일하게 관리하기 어렵다면, 구매기여가 큰 고객 중 누구부터 확인할 것인가? | 구매기여 상위 20% 안에서 위험 상위 10%를 주간 우선점검 대상으로 설계. Test 91~98주 합산 기준 가치고객 미구매 65/86건(75.6%)을 Priority에서 포착 | [Project README](projects/03_retail_crm_priority/) |
| 2 | [Consumer Pattern Transition](projects/01_consumer_pattern_transition/) | 소비 시간대 구조의 변화가 다음 분기 위험 상권·업종을 미리 구분하는 신호가 될 수 있는가? | 전이 집단 위험률 47.9%, 유지 집단 26.8%로 약 1.8배 높게 관찰 | [README](projects/01_consumer_pattern_transition/) · [PDF](projects/01_consumer_pattern_transition/outputs/consumer_pattern_transition_portfolio.pdf) |
| 3 | [Youth Quality of Work Analysis](projects/02_youth_quality_of_work/) | 청년 고용 문제를 취업 여부가 아니라 취업 이후 노동의 질로 보면 무엇이 달라지는가? | 청년 노동의 질 3.23 → 3.13, 청년 취업자의 33.17%를 취약 노동유형으로 식별 | [README](projects/02_youth_quality_of_work/) · [PDF](projects/02_youth_quality_of_work/outputs/youth_quality_of_work_portfolio.pdf) |

> Retail CRM 프로젝트의 `65/86`은 91~98주 **가구×기준주차 기록을 합산한 Backtest 결과**이며, 서로 겹치는 미래 4주 구간을 8개의 독립 실험으로 해석하지 않습니다.

---

## How I Approach Analysis

### 1. Problem / Decision
분석기법을 먼저 정하기보다 **누가 어떤 결정을 내려야 하는지**를 먼저 정의합니다.

### 2. Data / Metric Design
원천 데이터의 범위와 한계를 확인하고, 질문에 맞는 분석 단위·KPI·라벨을 설계합니다.

### 3. Analysis / Validation
SQL Data Mart, 통계 분석, 고객 세분화, 예측모형을 필요에 따라 사용하고 시간 누출·과대해석을 점검합니다.

### 4. Decision / Limitation
분석 결과가 처음 가설과 다르면 원인을 확인하고 기준을 다시 설계합니다. 실제 실험을 하지 않은 결과는 캠페인 효과나 인과효과로 표현하지 않습니다.

---

## Representative Projects

### 03. Retail CRM Priority Design

**문제**  
전체 고객의 미구매 위험만 높게 정렬하면 실제로 회사가 먼저 관리해야 할 고객과 일치하지 않을 수 있습니다. 이 프로젝트는 **구매기여가 큰 고객 중 다음 4주 미구매 가능성이 상대적으로 높은 고객을 HOUSEHOLD_KEY 단위로 좁히는 CRM 우선점검 기준**을 설계했습니다.

**분석 흐름**

```text
거래·상품 데이터
→ 고객×주차 Data Mart
→ 구매활동 상태 진단
→ 다음 4주 미구매 위험 예측
→ 시간순 Validation / Final Test
→ RFM 가치×위험 방식의 한계 발견
→ 경제적 구매기여와 위험을 분리
→ 주간 CRM Priority 50가구 산출
```

**핵심 결과**
- Final Test 전체 미구매율: **19.45%**
- 전체 위험 상위 10% 실제 미구매율: **70.85%** / 전체 대비 **3.64배 집중**
- 초기 RFM 고가치 418가구와 전체 위험 상위 250가구의 교집합: **0가구**
- 가치 정의를 최근 26주 구매금액으로 분리한 뒤 매주 500가구 → 50가구로 우선점검 대상 축소
- 91~98주 합산: 가치고객 미구매 **86건 중 65건(75.6%)**을 Priority에서 포착
- Priority 미구매율 **16.25%** vs 가치고객 전체 **2.15%** → 약 **7.56배**

**해석**  
예측 정확도와 CRM 우선순위는 같은 문제가 아니었습니다. 모델은 전체 고위험 고객을 잘 찾았지만, 실제 CRM 의사결정에서는 **경제적 구매기여를 먼저 정의한 뒤 그 고객군 안에서 상대 위험순위를 적용하는 방식**이 목적에 더 적합했습니다.

**범위**  
이 결과는 CRM 캠페인의 매출 효과를 증명한 것이 아니라 **우선 확인할 고객을 선별한 Backtest**입니다.

→ [Project README](projects/03_retail_crm_priority/)

---

### 01. Consumer Pattern Transition

서울 카드매출 분기 데이터를 활용해 **시간대별 소비 구조의 변화가 다음 분기 위험과 함께 나타나는지** 분석했습니다.

**핵심 결과**
- 패턴 유지 집단 위험률: **26.8%**
- 패턴 전이 집단 위험률: **47.9%**
- 전이 집단의 다음 분기 위험률이 유지 집단보다 약 **1.8배** 높게 관찰
- Walk-forward 검증을 통해 전이 신호를 완전한 예측모형이 아니라 **위험 집단 우선 모니터링 신호**로 해석

→ [Project README](projects/01_consumer_pattern_transition/) · [Portfolio PDF](projects/01_consumer_pattern_transition/outputs/consumer_pattern_transition_portfolio.pdf)

---

### 02. Youth Quality of Work Analysis

KWCS 2017·2023을 활용해 취업률만으로 포착하기 어려운 **청년 취업 이후 노동 경험의 질**을 측정하고 취약 노동유형을 분석했습니다.

**핵심 결과**
- 청년 노동의 질: **3.23 → 3.13**
- 중장년 노동의 질: 큰 변화 없음
- 청년 취업자의 **33.17%**를 취약 노동유형으로 식별
- 회귀분석과 비모수 검정을 통해 취약 노동유형과 관련된 조건을 확인하되 인과효과로 해석하지 않음

→ [Project README](projects/02_youth_quality_of_work/) · [Portfolio PDF](projects/02_youth_quality_of_work/outputs/youth_quality_of_work_portfolio.pdf)

---

## Repository Structure

기존 프로젝트의 파일 위치와 코드는 유지하고, 프로젝트별 README에서 문제·결과·파일 역할을 설명합니다.

```text
data-analysis-portfolio/
├── README.md
├── assets/
│   └── images/
│
├── projects/
│   ├── 01_consumer_pattern_transition/
│   │   ├── README.md
│   │   ├── python/
│   │   ├── r/
│   │   ├── sql/
│   │   ├── outputs/
│   │   └── data/
│   │
│   ├── 02_youth_quality_of_work/
│   │   ├── README.md
│   │   ├── data/
│   │   ├── outputs/
│   │   ├── python/
│   │   ├── r/
│   │   └── sql/
│   │
│   └── 03_retail_crm_priority/
│       ├── README.md
│       ├── python/
│       ├── sql/
│       └── outputs/
│
├── requirements.txt
└── .gitignore
```

---

## Project README Principle

각 프로젝트 README는 아래 순서로 빠르게 읽을 수 있도록 정리합니다.

1. **왜 시작했는가** — 문제와 사용자/의사결정
2. **무엇을 분석했는가** — 데이터, 분석 단위, 핵심 지표
3. **무엇을 확인했는가** — 핵심 결과와 검증
4. **무엇이 달라졌는가** — 초기 가설과 다른 결과, 설계 변경
5. **그래서 무엇을 할 수 있는가** — 활용 가능한 판단과 실제 한계
6. **어떻게 재현하는가** — 코드·SQL·결과물 위치

---

## Data Notice

원본 데이터는 각 제공처의 이용 조건과 저장 용량을 고려해 저장소에 포함하지 않습니다.  
대신 분석 흐름, 주요 코드·SQL, 결과 시각화, 발표용 자료를 확인할 수 있도록 정리합니다.

---

## Note

이 저장소는 분석기법의 개수를 보여주는 것보다 **문제 정의 → 검증 → 해석 → 의사결정**의 흐름을 보여주는 것을 목표로 합니다.
