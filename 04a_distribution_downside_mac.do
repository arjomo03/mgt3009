****************************************************
* 04a_distribution_downside_mac.do  (Stata 18)
* Monthly distribution & downside risk for RB portfolio
* - Skewness, excess kurtosis, Jarque–Bera
* - Historical VaR(5%) and CVaR(5%) (simple returns)
****************************************************
version 18
clear all
set more off

* ---------- Paths ----------
local root "/Users/johnmohmedi/Desktop/MGT3009"
cap mkdir "`root'/output"
cap mkdir "`root'/output/tables"

* ---------- Data ----------
use "`root'/output/data/master_monthly.dta", clear
tsset m, monthly

* Ensure simple returns exist
capture confirm variable rp_rb_s
if _rc gen double rp_rb_s = exp(r_p_rb_m) - 1

* Core stats
quietly count if !missing(rp_rb_s)
scalar N = r(N)

quietly summarize rp_rb_s, detail
scalar mu_s  = r(mean)
scalar sd_s  = r(sd)
scalar sk    = r(skewness)
scalar kurt  = r(kurtosis)
scalar exk   = kurt - 3
scalar var5  = r(p5)

* CVaR: average below VaR
quietly summarize rp_rb_s if rp_rb_s <= var5, meanonly
scalar cvar5 = r(mean)

* Jarque–Bera test statistic & p-value
scalar JB  = N/6 * (sk^2 + (exk^2)/4)
scalar pJB = chi2tail(2, JB)

* ---------- Export ----------
postfile D str28 metric double value using ///
    "`root'/output/tables/distribution_downside.dta", replace
post D ("N (months)")            (N)
post D ("Mean (simple)")         (mu_s)
post D ("SD (simple)")           (sd_s)
post D ("Skewness")              (sk)
post D ("Excess kurtosis")       (exk)
post D ("Jarque–Bera chi2")      (JB)
post D ("JB p-value")            (pJB)
post D ("VaR 5% (hist)")         (var5)
post D ("CVaR 5% (hist)")        (cvar5)
postclose D

use "`root'/output/tables/distribution_downside.dta", clear
export delimited using "`root'/output/tables/distribution_downside.csv", replace
di as result "Wrote -> output/tables/distribution_downside.csv"
