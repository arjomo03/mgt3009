****************************************************
* 00_master.do  (Stata 18)
* Rebuilds everything, monthly only
****************************************************
version 18
clear all
set more off

local root "/Users/johnmohmedi/Desktop/MGT3009"
cap mkdir "`root'/output"
cap mkdir "`root'/output/data"
cap mkdir "`root'/output/tables"
cap mkdir "`root'/output/figures"

log using "`root'/output/run_log.smcl", replace

* 1) Data build
do "`root'/01_monthly_prices_returns_mac.do"
do "`root'/02_macro_merge_MAC.do"
do "`root'/03_factors_merge_mac.do"

* 2) Core analysis (already in repo)
do "`root'/04_performance_factor_regs_mac.do"
do "`root'/05_macro_regs_mac.do"
do "`root'/06_eventstudy_monthly_mac.do"

* 3) Upgrades (this message)
capture noisily do "`root'/04a_distribution_downside_mac.do"
capture noisily do "`root'/04b_sharpe_inference_mac.do"
capture noisily do "`root'/04c_rolling_alpha_robustness_mac.do"
capture noisily do "`root'/05b_macro_predictability_oos_mac.do"
capture noisily do "`root'/06b_eventstudy_variants_monthly_mac.do"

log close
di as result "Master pipeline finished. Outputs in /output/."
