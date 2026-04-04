# Consumer Pattern Transition Analysis

## Overview
This project analyzes quarterly card sales data to identify **consumer pattern transitions** and examine whether such transitions can be interpreted as an early signal of future commercial risk.

The analysis was conducted using SQL, Python, and R, with a focus on:
- transition detection,
- cohort and retention structure,
- statistical testing,
- and predictive modeling.

## Project Goal
The main goal of this project is to test whether changes in consumption patterns can be used as a leading indicator of future business instability.

## Data
- Source: Seoul Open Data Plaza
- Data type: Quarterly card sales / commercial district-level data
- Unit of analysis: commercial district × quarter

## Workflow

### 1. SQL
Used for:
- raw table creation
- panel data construction
- time-share feature generation
- peak shift definition
- cohort / transition table generation

📁 File: `sql/01_data_pipeline.sql`

### 2. Python
Used for:
- train dataset preparation
- feature selection
- logistic regression modeling
- model evaluation (ROC-AUC, PR-AUC, confusion matrix)

📁 File: `python/02_modeling.py`

### 3. R
Used for:
- preprocessing for hypothesis testing
- summary statistics
- Mann–Whitney U test comparing shift vs non-shift groups

📁 File: `r/03_statistical_test.R`

## Key Idea
If a commercial district’s consumer pattern changes significantly from one quarter to the next, that transition may serve as an **early warning signal** for elevated future risk.

## Outputs
- Portfolio presentation PDF
- model / cohort / transition analysis code

📁 Output folder: `outputs/`

## Notes
This repository is organized for portfolio presentation purposes.  
Some file paths in the scripts are preserved from the original local analysis environment.
