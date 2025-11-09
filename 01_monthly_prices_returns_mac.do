version 18
clear all
set more off

* Paths
local root "/Users/johnmohmedi/Desktop/MGT3009"
local f_month "`root'/GOOGL_MSFT_MA_HD_MONTHLY.xlsx"

cap mkdir "`root'/output"
cap mkdir "`root'/output/data"

* BL weights
scalar Wg = 0.366003594
scalar Wm = 0.390981129
scalar Wa = 0.101758435
scalar Wh = 0.141256842

* --- Import monthly PostInvestment sheet (2015–2025) ---
import excel using "`f_month'", sheet("PostInvestment") firstrow clear

* --- Monthly date m (simple & robust to string vs numeric) ---
capture confirm string variable date
if !_rc {
    gen double m = monthly(date,"YM")
    replace m = mofd(daily(date,"YMD")) if missing(m)
    replace m = mofd(daily(date,"DMY")) if missing(m)
}
else {
    * date is numeric: try Stata daily first; if implausible, assume Excel serial
    gen double m = mofd(date)
    replace m = mofd(date + td(30dec1899)) if m < tm(1990m1) | m > tm(2035m12)
}
format m %tm
drop if missing(m)
sort m
tsset m, monthly

* --- Map the five price columns (raw headers) ---
rename GOOGL goog_adj
rename MSFT  msft_adj
rename MA    ma_adj
rename HD    hd_adj
rename SPXT  spxt_tr

* Make sure numeric
foreach v in goog_adj msft_adj ma_adj hd_adj spxt_tr {
    cap destring `v', replace ignore(",")
}

* --- Monthly log returns ---
gen double r_goog_m = ln(goog_adj/L.goog_adj)
gen double r_msft_m = ln(msft_adj/L.msft_adj)
gen double r_ma_m   = ln(ma_adj/L.ma_adj)
gen double r_hd_m   = ln(hd_adj/L.hd_adj)
gen double r_mkt_m  = ln(spxt_tr/L.spxt_tr)

* --- Portfolios (RB, EW) ---
gen double r_p_rb_m = Wg*r_goog_m + Wm*r_msft_m + Wa*r_ma_m + Wh*r_hd_m
gen double r_p_ew_m = 0.25*(r_goog_m + r_msft_m + r_ma_m + r_hd_m)

* --- Buy-and-hold (BH) via value path ---
gen double v_g  = Wg*exp(sum(cond(missing(r_goog_m),0,r_goog_m)))
gen double v_mx = Wm*exp(sum(cond(missing(r_msft_m),0,r_msft_m)))
gen double v_a  = Wa*exp(sum(cond(missing(r_ma_m),  0,r_ma_m  )))
gen double v_h  = Wh*exp(sum(cond(missing(r_hd_m),  0,r_hd_m  )))
gen double v_bh = v_g + v_mx + v_a + v_h
gen double r_p_bh_m = ln(v_bh/L.v_bh)

* Keep assignment window (you said PostInvestment covers 2015–2025)
keep if inrange(m, tm(2015m1), tm(2025m9))

save "`root'/output/data/monthly_returns.dta", replace
export delimited using "`root'/output/data/monthly_returns.csv", replace
di as result "Saved -> `root'/output/data/monthly_returns.dta"
