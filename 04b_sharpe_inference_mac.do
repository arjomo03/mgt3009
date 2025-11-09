****************************************************
* 04b_sharpe_inference_mac.do  (Stata 18)
* Robust Sharpe inference for monthly log excess
* - Annualized Sharpe (from monthly)
* - Lo (2002): HAC t-stat for mean=0 with lag(6)
****************************************************
version 18
clear all
set more off

local root "/Users/johnmohmedi/Desktop/MGT3009"
cap mkdir "`root'/output"
cap mkdir "`root'/output/tables"

use "`root'/output/data/master_monthly.dta", clear
tsset m, monthly

* Monthly Sharpe on log-excess
quietly summarize rp_rb_ex
scalar mu = r(mean)
scalar sd = r(sd)
scalar Sharpe_m   = mu/sd
scalar Sharpe_ann = sqrt(12)*Sharpe_m

* Lo (2002): HAC t-stat for mu=0 (which is the Sharpe=0 null)
newey rp_rb_ex, lag(6)
scalar t_Lo = _b[_cons]/_se[_cons]
scalar p_Lo = 2*ttail(e(df_r), abs(t_Lo))
scalar N    = e(N)

postfile S str32 stat double value using ///
    "`root'/output/tables/sharpe_inference.dta", replace
post S ("Sharpe_ann (log-excess)") (Sharpe_ann)
post S ("Lo HAC t-stat (mu=0)")    (t_Lo)
post S ("Lo HAC p-value")          (p_Lo)
post S ("N (months)")              (N)
postclose S

use "`root'/output/tables/sharpe_inference.dta", clear
export delimited using "`root'/output/tables/sharpe_inference.csv", replace
di as result "Wrote -> output/tables/sharpe_inference.csv"
