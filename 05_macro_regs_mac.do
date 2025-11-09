****************************************************
* 05_macro_regs_mac.do  (Stata 18)
* Macro regressions using portfolio excess returns.
* - MAIN contemporaneous spec with HAC(6)
* - Optional predictive spec (t+1) guarded
* - Robust export; no crashes on missing/short windows
****************************************************
version 18
clear all
set more off

* ---------- Paths ----------
local root "/Users/johnmohmedi/Desktop/MGT3009"

cap mkdir "`root'/output"
cap mkdir "`root'/output/tables"
cap mkdir "`root'/output/figures"

* ---------- Load master ----------
use "`root'/output/data/master_monthly.dta", clear
tsset m, monthly   // %tm, 2015m1–2025m8

* ---------- Build / verify macro regressors ----------
* Targets:
*   infl        : inflation rate
*   d_unrate    : Δ unemployment (pp)
*   d_fed       : Δ fed funds (pp)
*   d_sent      : Δ ln(UMich sentiment)
*   d_logepu    : Δ ln(EPU)
*   covid       : 1 for 2020m2–2020m4

capture confirm variable infl
if _rc {
    capture confirm variable cpi_yoy
    if !_rc gen infl = cpi_yoy
}

capture confirm variable d_unrate
if _rc {
    capture confirm variable unrate
    if !_rc gen d_unrate = D.unrate
}

capture confirm variable d_fed
if _rc {
    capture confirm variable fedfunds
    if !_rc gen double d_fed = D.fedfunds
    else {
        capture confirm variable fed
        if !_rc gen double d_fed = D.fed
    }
}

capture confirm variable d_sent
if _rc {
    capture confirm variable umcsent
    if !_rc {
        gen double ln_umcsent = cond(umcsent>0, ln(umcsent), .)
        gen double d_sent = D.ln_umcsent
        label var d_sent "Δ ln(UMich sentiment)"
    }
}

capture confirm variable d_logepu
if _rc {
    local E ""
    foreach e in epu EPU epu_idx {
        capture confirm variable `e'
        if !_rc local E "`e'"
    }
    if "`E'" != "" {
        gen double ln_epu = cond(`E'>0, ln(`E'), .)
        gen double d_logepu = D.ln_epu
        label var d_logepu "Δ ln(EPU)"
    }
}

capture confirm variable covid
if _rc gen byte covid = inrange(m, tm(2020m2), tm(2020m4))

* Final check
foreach v in infl d_unrate d_fed d_sent d_logepu covid {
    capture confirm variable `v'
    if _rc {
        di as error "Missing regressor: `v'. Please create or merge it."
        exit 111
    }
}

* Keep usable rows (no NA in regressands/regressors)
keep if !missing(rp_rb_ex, infl, d_unrate, d_fed, d_sent, d_logepu, covid)

****************************************************
* MAIN: Newey–West (lag=6) on contemporaneous log-excess
****************************************************
newey rp_rb_ex infl d_unrate d_fed d_sent d_logepu covid, lag(6)

* Joint significance of macro block
test infl d_unrate d_fed d_sent d_logepu covid
scalar p_joint = r(p)

* ---------- Tidy export ----------
tempname fh
postfile `fh' str20 var double beta se pval using ///
    "`root'/output/tables/macro_regression.dta", replace

matrix B = e(b)
matrix V = e(V)
local names : colfullnames B
scalar df = e(df_r)

foreach nm of local names {
    scalar b = B[1,"`nm'"]
    scalar s = sqrt(V["`nm'","`nm'"])
    scalar p = 2*ttail(df, abs(b/s))
    post `fh' ("`nm'") (b) (s) (p)
}
postclose `fh'

use "`root'/output/tables/macro_regression.dta", clear
drop if var=="_cons"
format beta se %9.4f

* Append joint p-value
set obs `=_N+1'
replace var  = "Joint (all macros)" in L
replace pval = p_joint               in L

export delimited using "`root'/output/tables/macro_regression.csv", replace
di as result "Saved -> `root'/output/tables/macro_regression.csv"

****************************************************
* OPTIONAL: Predictive spec (guarded)
****************************************************
* Uncomment to run:
* newey F1.rp_rb_ex infl d_unrate d_fed d_sent d_logepu covid, lag(6)
* newey F1.rp_rb_ex L(0/3).infl L(0/3).d_unrate L(0/3).d_fed ///
*                    L(0/3).d_sent L(0/3).d_logepu covid, lag(6)
* reg  rp_rb_ex infl d_unrate d_fed d_sent d_logepu covid
* estat vif
