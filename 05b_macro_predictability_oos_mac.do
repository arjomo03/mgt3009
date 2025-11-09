****************************************************
* 05b_macro_predictability_oos_mac.do  (Stata 18)
* Monthly predictive regressions with strict OOS split
*   y_{t+1} = X_t * beta  (predict next-month log excess)
*
* Models:
*   A) F1.rp_rb_ex ~ zX_t + COVID
*   B) F1.rp_rb_ex ~ L(0/3).zX_t + COVID
*
* Outputs:
*   - output/tables/macro_predict_oos.dta/.csv
*   - output/tables/macro_predict_in_sample_coefs.dta/.csv
*   - output/tables/macro_predict_oos_timeseries.csv
****************************************************
version 18
clear all
set more off

* ---------- Paths ----------
local root "/Users/johnmohmedi/Desktop/MGT3009"
cap mkdir "`root'/output"
cap mkdir "`root'/output/tables"
cap mkdir "`root'/output/figures"

* ---------- Load master (monthly) ----------
use "`root'/output/data/master_monthly.dta", clear
tsset m, monthly

* ---------- Must-have dependent series ----------
capture confirm variable rp_rb_ex
if _rc {
    di as err "Missing required series rp_rb_ex (monthly log-excess)."
    exit 111
}

* ---------- Build/verify predictors (create fallbacks if needed) ----------
* infl
capture confirm variable infl
if _rc {
    capture confirm variable cpi_yoy
    if !_rc gen double infl = cpi_yoy
}

* d_unrate
capture confirm variable d_unrate
if _rc {
    capture confirm variable unrate
    if !_rc gen double d_unrate = D.unrate
}

* d_fed
capture confirm variable d_fed
if _rc {
    capture confirm variable fedfunds
    if !_rc gen double d_fed = D.fedfunds
    else {
        capture confirm variable fed
        if !_rc gen double d_fed = D.fed
    }
}

* d_sent = Δ ln(UMich sentiment)
capture confirm variable d_sent
if _rc {
    capture confirm variable umcsent
    if !_rc {
        gen double ln_umcsent = cond(umcsent>0, ln(umcsent), .)
        gen double d_sent     = D.ln_umcsent
        label var d_sent "Δ ln(UMich sentiment)"
    }
}

* d_logepu = Δ ln(EPU) (try common names)
capture confirm variable d_logepu
if _rc {
    local E ""
    foreach e in epu EPU epu_idx EPUTRADE {
        capture confirm variable `e'
        if !_rc local E "`e'"
    }
    if "`E'" != "" {
        gen double ln_epu   = cond(`E'>0, ln(`E'), .)
        gen double d_logepu = D.ln_epu
        label var d_logepu "Δ ln(EPU)"
    }
}

* COVID dummy (covid OR covid_era; create if absent)
local COVIDVAR "covid"
capture confirm variable covid
if _rc {
    capture confirm variable covid_era
    if !_rc local COVIDVAR "covid_era"
    else {
        gen byte covid = inrange(m, tm(2020m2), tm(2020m4))
        local COVIDVAR "covid"
    }
}

* Final guard on X_t presence
foreach v in infl d_unrate d_fed d_sent d_logepu `COVIDVAR' {
    capture confirm variable `v'
    if _rc {
        di as err "Missing required predictor: `v'."
        exit 111
    }
}

* Keep rows with complete X_t (y_{t+1} handled downstream)
keep if !missing(rp_rb_ex, infl, d_unrate, d_fed, d_sent, d_logepu, `COVIDVAR')
sort m

* ---------- Split: first half train, second half OOS ----------
quietly count
local N = r(N)
if `N' < 24 {
    di as err "Not enough monthly observations (`N') for an OOS split."
    exit 200
}
local split   = floor(`N'/2)
local m_split = m[`split']     // last training month index

* ---------- Standardize X using TRAIN ONLY (robust to sd=.)
tempname STATS
postfile `STATS' str12 var double Ntrain mean sd sd_used using ///
    "`root'/output/tables/macro_train_stats.dta", replace

local SDFLOOR = 1e-8

preserve
    keep in 1/`split'
    foreach v in infl d_unrate d_fed d_sent d_logepu {
        quietly su `v', meanonly
        scalar mu_`v' = r(mean)
        scalar sd_`v' = r(sd)
        if missing(sd_`v') | sd_`v'<=0 scalar sd_`v' = `SDFLOOR'
        post `STATS' ("`v'") (r(N)) (mu_`v') (r(sd)) (sd_`v')
    }
restore
postclose `STATS'

foreach v in infl d_unrate d_fed d_sent d_logepu {
    gen double z_`v' = (`v' - mu_`v')/sd_`v'
}

* ---------- Prep dependent (for convenience) ----------
gen double y_A = F1.rp_rb_ex          // next-month log excess
label var y_A "F1.rp_rb_ex"

* ---------- Tables to post ----------
tempname OOS COEF
postfile `OOS'  str28 model int N_train N_oos double R2_OOS RMSE_model RMSE_mean ///
    using "`root'/output/tables/macro_predict_oos.dta", replace
postfile `COEF' str20 model str30 var double beta se t p ///
    using "`root'/output/tables/macro_predict_in_sample_coefs.dta", replace

****************************************************
* Model A: F1.rp_rb_ex ~ zX_t + COVID  (train only)
****************************************************
reg y_A z_infl z_d_unrate z_d_fed z_d_sent z_d_logepu `COVIDVAR' if m <= `m_split'
local N_train_A = e(N)

* Save tidy coefs
matrix bA = e(b)
matrix VA = e(V)
local colsA : colfullnames bA
scalar dfA = e(df_r)
foreach nm of local colsA {
    scalar b1 = bA[1,"`nm'"]
    scalar s1 = sqrt(VA["`nm'","`nm'"])
    scalar t1 = .
    if (s1>0) scalar t1 = b1/s1
    scalar p1 = .
    if (s1>0) scalar p1 = 2*ttail(dfA, abs(t1))
    post `COEF' ("Model A") ("`nm'") (b1) (s1) (t1) (p1)
}

* OOS metrics for Model A (mask & baseline aligned)
predict double yhat_A                     // fitted over all rows
egen _missA = rowmiss(y_A yhat_A)
gen  byte maskA = (m > `m_split') & (_missA==0)
drop _missA

* Compute SSE/RMSE/R2 using r(mean)*r(N)
gen double eA   = y_A - yhat_A      if maskA
gen double eA2  = eA^2              if maskA

quietly su eA2, meanonly
scalar SSE_A    = r(mean) * r(N)
scalar N_OOS_A  = r(N)

quietly su y_A if m <= `m_split', meanonly
scalar ybar_train = r(mean)

gen double eAVG_A2 = (y_A - ybar_train)^2 if maskA
quietly su eAVG_A2, meanonly
scalar SSE_AVG_A  = r(mean) * r(N)
scalar RMSE_A     = cond(N_OOS_A>0, sqrt(SSE_A/N_OOS_A), .)
scalar RMSE_AVG_A = cond(N_OOS_A>0, sqrt(SSE_AVG_A/N_OOS_A), .)
scalar R2_OOS_A   = cond(SSE_AVG_A>0, 1 - SSE_A/SSE_AVG_A, .)

post `OOS' ("F1 contemporaneous (Model A)") (`N_train_A') (N_OOS_A) ///
    (R2_OOS_A) (RMSE_A) (RMSE_AVG_A)

****************************************************
* Model B: F1.rp_rb_ex ~ L(0/3).zX_t + COVID  (train)
****************************************************
reg y_A L(0/3).z_infl L(0/3).z_d_unrate L(0/3).z_d_fed ///
       L(0/3).z_d_sent L(0/3).z_d_logepu `COVIDVAR' if m <= `m_split'
local N_train_B = e(N)

* Save tidy coefs
matrix bB = e(b)
matrix VB = e(V)
local colsB : colfullnames bB
scalar dfB = e(df_r)
foreach nm of local colsB {
    scalar b2 = bB[1,"`nm'"]
    scalar s2 = sqrt(VB["`nm'","`nm'"])
    scalar t2 = .
    if (s2>0) scalar t2 = b2/s2
    scalar p2 = .
    if (s2>0) scalar p2 = 2*ttail(dfB, abs(t2))
    post `COEF' ("Model B (lags 0–3)") ("`nm'") (b2) (s2) (t2) (p2)
}

* OOS metrics for Model B (its own mask & aligned baseline)
predict double yhat_B
egen _missB = rowmiss(y_A yhat_B)
gen  byte maskB = (m > `m_split') & (_missB==0)
drop _missB

gen double eB   = y_A - yhat_B      if maskB
gen double eB2  = eB^2              if maskB

quietly su eB2, meanonly
scalar SSE_B    = r(mean) * r(N)
scalar N_OOS_B  = r(N)

gen double eAVG_B2 = (y_A - ybar_train)^2 if maskB
quietly su eAVG_B2, meanonly
scalar SSE_AVG_B  = r(mean) * r(N)
scalar RMSE_B     = cond(N_OOS_B>0, sqrt(SSE_B/N_OOS_B), .)
scalar RMSE_AVG_B = cond(N_OOS_B>0, sqrt(SSE_AVG_B/N_OOS_B), .)
scalar R2_OOS_B   = cond(SSE_AVG_B>0, 1 - SSE_B/SSE_AVG_B, .)

post `OOS' ("F1 with lags 0–3 (Model B)") (`N_train_B') (N_OOS_B) ///
    (R2_OOS_B) (RMSE_B) (RMSE_AVG_B)

* ---------- Export OOS time-series BEFORE switching datasets ----------
preserve
    keep m y_A yhat_A yhat_B maskA maskB
    order m y_A yhat_A yhat_B maskA maskB
    format m %tm
    export delimited using "`root'/output/tables/macro_predict_oos_timeseries.csv", replace
restore

* ---------- Close & export tables ----------
postclose `COEF'
postclose `OOS'

use "`root'/output/tables/macro_predict_oos.dta", clear
export delimited using "`root'/output/tables/macro_predict_oos.csv", replace

use "`root'/output/tables/macro_predict_in_sample_coefs.dta", clear
export delimited using "`root'/output/tables/macro_predict_in_sample_coefs.csv", replace

di as result "05b complete — OOS metrics, in-sample coefs, and OOS timeseries written."
****************************************************
* End
****************************************************
