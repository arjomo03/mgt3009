****************************************************
* 06_eventstudy_monthly_mac.do   (Stata 18)
* Monthly market-model CARs for GOOG, MSFT, MA, HD
* Event window: Feb–Apr 2020
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
local EVT_START = tm(2020m2)
local EVT_MID   = tm(2020m3)
local EVT_END   = tm(2020m4)
local K         = 3    // number of event months

* -------- CAR table --------
tempname P
postfile `P' str6 ticker double CAR SE_CAR T P using ///
    "`root'/output/tables/event_cars_monthly.dta", replace

* -------- Loop across tickers --------
foreach s in goog msft ma hd {

    preserve
        use "`root'/output/data/monthly_returns.dta", clear
        tsset m, monthly

        * 1) Estimate market model on PRE-event window
        * (OLS is standard; Newey–West can be used but is optional)
        regress r_`s'_m r_mkt_m if inrange(m, `EST_START', `EST_END')
        scalar rmse = e(rmse)
        scalar df   = e(df_r)

        * 2) Abnormal returns in the event window (residuals)
        predict double u if inrange(m, `EVT_START', `EVT_END'), resid

        * 3) CAR path and total
        gen byte evt = inrange(m, `EVT_START', `EVT_END')
        bysort evt (m): gen double car_path = cond(evt, sum(u), .)
        egen double car_total = total(u) if evt
        quietly summarize car_total, meanonly
        scalar CAR   = r(max)
        scalar SE_CAR = rmse*sqrt(`K')
        scalar Tstat  = CAR/SE_CAR
        scalar Pval   = 2*ttail(df, abs(Tstat))

        * Write row
        post `P' ("`s'") (CAR) (SE_CAR) (Tstat) (Pval)

        * 4) Plot CAR path (full-height grey band)
        keep if evt
        sort m
        quietly summarize car_path
        local lo  = r(min)
        local hi  = r(max)
        local pad = 0.03*(`hi' - `lo')
        if `pad'==0 local pad = 0.01
        local y0 = `lo' - `pad'
        local y1 = `hi' + `pad'
        gen double ylo = `y0'
        gen double yhi = `y1'

        twoway ///
          (rbar yhi ylo m, bcolor(gs14%60) lcolor(none)) ///
          (line car_path m, lwidth(medthick) lcolor(cranberry)), ///
          yscale(range(`y0' `y1')) ///
          xscale(range(`EVT_START' `EVT_END')) ///
          xlabel(`EVT_START'(1)`EVT_END', format(%tmMon_CCYY) angle(45)) ///
          xline(`EVT_MID', lpattern(dash)) ///
          title("`=upper("`s'")' CAR (Feb–Apr 2020)") ///
          ytitle("Cumulative abnormal return") xtitle("Month") legend(off) ///
          graphregion(color(white)) plotregion(color(white))

        graph save   "`root'/output/figures/event_car_`s'_monthly.gph", replace
        graph export "`root'/output/figures/event_car_`s'_monthly.png", width(2000) replace
    restore
}

postclose `P'

* -------- Export CAR results --------
use "`root'/output/tables/event_cars_monthly.dta", clear
order ticker CAR SE_CAR T P
format CAR SE_CAR %9.4f
export delimited using "`root'/output/tables/event_cars_monthly.csv", replace
display as result "Saved -> `root'/output/tables/event_cars_monthly.csv"

* -------- 2×2 panel --------
capture noisily graph combine ///
    "`root'/output/figures/event_car_goog_monthly.gph" ///
    "`root'/output/figures/event_car_msft_monthly.gph" ///
    "`root'/output/figures/event_car_ma_monthly.gph"   ///
    "`root'/output/figures/event_car_hd_monthly.gph",  ///
    col(2) imargin(2 2 2 2) graphregion(color(white))
if _rc==0 {
    graph save   "`root'/output/figures/event_car_panel.gph", replace
    graph export "`root'/output/figures/event_car_panel.png", width(2400) replace
}
