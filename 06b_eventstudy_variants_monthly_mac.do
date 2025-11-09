****************************************************
* 06b_eventstudy_variants_monthly_mac.do  (Stata 18)
* Monthly market-model CARs with multiple windows:
*   W1: (-1, +1)  Feb–Apr 2020
*   W2: (0, +2)   Mar–May 2020
*   W3: (-2, +2)  Jan–May 2020
* Estimation window: 2019m1–2020m1 (pre-COVID)
* Outputs: event_cars_monthly_variants.dta/.csv
****************************************************
version 18
clear all
set more off

* -------- Paths --------
local root "/Users/johnmohmedi/Desktop/MGT3009"

cap mkdir "`root'/output"
cap mkdir "`root'/output/tables"
cap mkdir "`root'/output/figures"

* -------- Windows --------
local EST_START = tm(2019m1)
local EST_END   = tm(2020m1)
local MID       = tm(2020m3)   // not used for tables, useful for plots

* Event windows (inclusive)
local W1_START  = tm(2020m2)   // (-1,+1) around Mar-2020 => Feb–Apr
local W1_END    = tm(2020m4)

local W2_START  = tm(2020m3)   // (0,+2) => Mar–May
local W2_END    = tm(2020m5)

local W3_START  = tm(2020m1)   // (-2,+2) => Jan–May
local W3_END    = tm(2020m5)

* -------- Result table --------
tempname P
postfile `P' str6 ticker str8 window double CAR SE_CAR T P using ///
    "`root'/output/tables/event_cars_monthly_variants.dta", replace

* We will loop across tickers and event windows inline (no program define)
local windows "W1 W2 W3"

foreach s in goog msft ma hd {

    preserve
        use "`root'/output/data/monthly_returns.dta", clear
        tsset m, monthly

        * 1) Estimate market model on PRE-event window
        regress r_`s'_m r_mkt_m if inrange(m, `EST_START', `EST_END')
        scalar rmse = e(rmse)
        scalar df   = e(df_r)

        * 2) For each window, compute CAR, SE, T, P
        foreach w of local windows {
            local A = ``w'_START'
            local B = ``w'_END'

            tempvar u evt cp cartot
            predict double `u' if inrange(m, `A', `B'), resid
            gen byte `evt' = inrange(m, `A', `B')

            bysort `evt' (m): gen double `cp' = cond(`evt', sum(`u'), .)
            egen double `cartot' = total(`u') if `evt'

            quietly summarize `cartot', meanonly
            scalar CAR = r(max)

            quietly count if `evt'
            scalar K = r(N)

            scalar SE  = rmse*sqrt(K)
            scalar Tst = .
            if SE>0 scalar Tst = CAR/SE
            scalar Pv  = .
            if SE>0 scalar Pv  = 2*ttail(df, abs(Tst))

            local wlab = cond("`w'"=="W1","(-1,+1)", ///
                         cond("`w'"=="W2","(0,+2)","(-2,+2)"))

            post `P' ("`s'") ("`wlab'") (CAR) (SE) (Tst) (Pv)

            drop `u' `evt' `cp' `cartot'
        }
    restore
}

postclose `P'

* -------- Export CSV --------
use "`root'/output/tables/event_cars_monthly_variants.dta", clear
order ticker window CAR SE_CAR T P
format CAR SE_CAR %9.4f
export delimited using "`root'/output/tables/event_cars_monthly_variants.csv", replace

di as result "Saved -> `root'/output/tables/event_cars_monthly_variants.csv"
