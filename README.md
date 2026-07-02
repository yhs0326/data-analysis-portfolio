# Data Analysis Portfolio

R, SQL, Python을 활용해 데이터 전처리, 분석용 데이터마트 구축, 통계 분석, 모델링, 시각화까지 수행한 데이터 분석 포트폴리오입니다.

이 저장소는 단순한 코드 모음이 아니라, **문제 정의 → 데이터 구성 → 분석 방법 → 핵심 결과 → 활용 가능성**의 흐름이 보이도록 정리했습니다.

---

## About Me

- Major: Mathematics
- Double Major: Applied Statistics
- Tools: SQL, Python, R, PostgreSQL
- Certificate: ADsP, SQLD
- Interests: Data Analysis, BI, CRM/Marketing Analytics, Public Data Analysis

---

## Portfolio Focus

- 비즈니스·사회 문제를 분석 가능한 지표로 정의
- SQL 기반 분석 단위 데이터마트 생성
- Python/R 기반 군집분석, 회귀분석, 비모수 검정, KPI 설계
- 결과를 수치와 시각화로 해석하고 의사결정 관점에서 정리

---

## Portfolio Projects

| No. | Project | Problem | Methods | Key Result |
|---|---|---|---|---|
| 1 | [Consumer Pattern Transition](projects/01_consumer_pattern_transition/) | 소비 구조 전이가 다음 분기 위험 신호가 될 수 있는가 | SQL, Python, R, Clustering, Cohort Analysis | 전이 집단 위험률 47.9%, 유지 집단 26.8%, 약 1.8배 증가 |
| 2 | [Youth Quality of Work Analysis](projects/02_youth_quality_of_work/) | 청년 고용 문제는 취업 여부가 아니라 노동의 질 문제인가 | R, SQL, Python, KMeans, Logistic Regression, OLS | 청년 노동의 질 3.2319 → 3.1347, 취약 노동유형 33.17% |
| 3 | [Consumer Pattern Clustering](projects/03_consumer_pattern_clustering/) | 업종별 소비 시간대는 어떻게 달라졌는가 | SQL, Python, KMeans, Silhouette | 패턴 유지율 40.9%, 피크 시간대 변경률 81.8% |
| 4 | [Chronic Disease Management KPI](projects/04_chronic_disease_management_kpi/) | 만성질환 관리는 어디에서 막히는가 | R, PostgreSQL, Logistic Regression, PCA, Clustering | 복합관리 KPI 설계, 지역별 관리 격차 및 취약집단 도출 |

---

## Representative Projects

### 1. Consumer Pattern Transition

서울 카드매출 분기 데이터를 활용해 소비 구조 전이를 탐지하고, 전이 발생 집단의 다음 분기 위험 발생률이 유지 집단보다 높은지 분석했습니다.

**Problem**  
매출 감소는 이미 결과가 나타난 뒤 확인되는 사후 지표입니다. 따라서 매출이 악화되기 전, 소비 시간대 구조의 변화가 상권 리스크를 미리 알려주는 선행 신호가 될 수 있는지 확인했습니다.

**Key Results**
- 전이 집단 위험률: 47.9%
- 유지 집단 위험률: 26.8%
- 전이 발생 시 다음 분기 위험 약 1.8배 증가

**Skills**  
SQL 데이터마트 생성, Python 군집분석 및 전이 탐지, R 통계검정

---

### 2. Youth Quality of Work Analysis

KWCS 2017·2023 데이터를 활용해 청년 노동의 질 지수를 구성하고, 청년 노동의 질 변화와 취약 노동유형을 분석했습니다.

**Problem**  
청년 고용 문제는 취업률과 실업률만으로 설명하기 어렵습니다. 본 프로젝트는 취업 이후의 노동 경험을 노동의 질 관점에서 분석했습니다.

**Key Results**
- 청년 노동의 질: 3.2319 → 3.1347
- 중장년 노동의 질: 거의 변화 없음
- 취약 노동유형 비중: 33.17%
- 2023년, 임시직, 일용직은 취약 노동유형과 양의 관련

**Skills**  
R 전처리 및 지표 구성, SQL 데이터 결합, Python KMeans·회귀분석·시각화

---

### 3. Consumer Pattern Clustering

서울 소비 데이터를 업종 중분류 단위로 정리하고, 시간대별 소비 비중을 기준으로 업종별 소비 패턴을 군집화했습니다.

**Problem**  
업종별 소비 전략은 매출 규모뿐 아니라 소비가 집중되는 시간대에 따라 달라질 수 있습니다. 본 프로젝트는 업종별 소비 시간대를 유형화하고, 전후 시점에서 소비 패턴과 피크 시간이 어떻게 이동했는지 분석했습니다.

**Key Results**
- 패턴 유지율: 40.9%
- 군집 이동률: 59.1%
- 피크 시간대 변경률: 81.8%
- 최다 피크 이동: 퇴근 → 점심

**Skills**  
SQL 데이터마트 생성, Python KMeans 군집분석, 실루엣 점수 기반 군집 수 선택, 시각화

---

### 4. Chronic Disease Management KPI

CHS와 KNHANES 데이터를 활용해 만성질환 관리 수준을 복합관리 KPI로 정의하고, 지역별 관리 격차와 취약집단을 분석했습니다.

**Problem**  
만성질환 관리는 인지, 치료, 복약, 관리교육, 생활행태 등 여러 요인이 함께 작용하지만, 이를 통합적으로 비교할 수 있는 기준이 부족합니다. 본 프로젝트는 복합관리 KPI를 설계해 관리 사각지대를 식별하고자 했습니다.

**Key Results**
- 지역별 복합관리율 차이 확인
- 인지·관리교육·소득 수준이 관리 성공과 관련
- 평균 개선 시나리오만으로는 변화폭이 제한적
- 취약 지역 및 취약 유형 중심의 타깃 접근 필요

**Skills**  
R 전처리 및 KPI 산출, PostgreSQL 데이터 추출, 로지스틱 회귀분석, PCA, KMeans/EM 군집분석

---

## Repository Structure

```text
data-analysis-portfolio/
├── README.md
├── assets/
│   └── images/
│
├── projects/
│   ├── 01_consumer_pattern_transition/
│   │   ├── README.md
│   │   ├── sql/
│   │   │   ├── 01_create_base_table.sql
│   │   │   ├── 02_feature_engineering.sql
│   │   │   ├── 03_transition_detection.sql
│   │   │   └── 04_summary_tables.sql
│   │   ├── python/
│   │   │   ├── 01_clustering.py
│   │   │   ├── 02_transition_analysis.py
│   │   │   ├── 03_risk_analysis.py
│   │   │   └── 04_visualization.py
│   │   ├── r/
│   │   │   └── 01_statistical_test.R
│   │   ├── outputs/
│   │   │   ├── figures/
│   │   │   └── portfolio.pdf
│   │   └── data/
│   │       └── README.md
│   │
│   ├── 02_youth_quality_of_work/
│   │   ├── README.md
│   │   ├── r/
│   │   │   ├── 01_preprocessing.R
│   │   │   └── 02_index_generation.R
│   │   ├── sql/
│   │   │   └── 01_merge_2017_2023.sql
│   │   ├── python/
│   │   │   ├── 01_clustering.py
│   │   │   ├── 02_regression.py
│   │   │   └── 03_visualization.py
│   │   ├── outputs/
│   │   │   ├── figures/
│   │   │   └── portfolio.pdf
│   │   └── data/
│   │       └── README.md
│   │
│   ├── 03_consumer_pattern_clustering/
│   │   ├── README.md
│   │   ├── sql/
│   │   ├── python/
│   │   ├── outputs/
│   │   └── data/
│   │       └── README.md
│   │
│   └── 04_chronic_disease_management_kpi/
│       ├── README.md
│       ├── sql/
│       ├── r/
│       ├── outputs/
│       └── data/
│           └── README.md
│
├── requirements.txt
└── .gitignore
```

---

## Project README Format

각 프로젝트 폴더의 README는 다음 기준으로 정리합니다.

1. Project Summary
2. Problem
3. Data
4. Method
5. Key Results
6. Skills
7. Files
8. Conclusion

---

## Data Notice

원본 데이터는 제공처 이용 조건상 저장소에 포함하지 않았습니다.  
대신 분석 흐름, 주요 코드, SQL 쿼리, 결과 시각화, 발표용 PDF를 확인할 수 있도록 정리했습니다.

---

## Note

이 저장소는 채용자가 프로젝트의 문제 정의, 분석 과정, 사용 기술, 핵심 결과를 빠르게 확인할 수 있도록 구성했습니다. 각 프로젝트는 면접에서 설명 가능한 수준으로 분석 흐름과 결과 해석을 함께 정리하는 것을 목표로 합니다.
