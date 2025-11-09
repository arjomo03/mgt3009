****************************************************
* 03_factors_merge_mac.do  (Stata 18)
****************************************************
version 18
clear all
set more off

local root "/Users/johnmohmedi/Desktop/MGT3009"
local f_macro "`root'/Macroeconomic_Data.xlsx"

cap mkdir "`root'/output"
cap mkdir "`root'/output/data"

local M_START = tm(2015m1)
local M_END   = tm(2025m9)

* === Fama–French 5 (monthly) ===
import excel using "`f_macro'", sheet("FamaFrenchFiveFactor") firstrow clear
gen double m = .
capture confirm numeric variable Date
if !_rc {
    cap destring Date, replace ignore(",") force
    gen int yy = floor(Date/100)
    gen int mm = mod(Date,100)
    replace m = ym(yy,mm)
}
capture confirm string variable date
if !_rc {
    replace m = monthly(date,"YM") if missing(m)
    replace m = ym(real(substr(date,1,4)), real(substr(date,6,2))) if missing(m) & length(date)>=7
    replace m = ym(real(substr(date,1,4)), real(substr(date,5,2))) if missing(m) & length(date)==6
}
capture confirm numeric variable date
if !_rc {
    replace m = mofd(date) if missing(m)
    replace m = mofd(date + td(30dec1899)) if missing(m)
    replace m = ym(floor(date/100), mod(date,100)) if missing(m) & inrange(date,190001,210012)
}
format m %tm
drop if missing(m)
sort m

capture rename Mkt-RF Mkt_RF
capture rename MktRF  Mkt_RF
capture rename Mkt_RF mkt_rf
capture rename SMB    smb
capture rename HML    hml
capture rename RMW    rmw
capture rename CMA    cma
capture rename RF     rf

capture confirm variable mkt_rf
if _rc {
    foreach v of varlist _all {
        capture confirm string variable `v'
        if !_rc cap destring `v', replace ignore(",")
    }
    ds, has(type numeric)
    local nums `r(varlist)'
    local keep
    foreach v of local nums {
        if inlist("`v'","m","Date","date","yy","mm") continue
        local keep `keep' `v'
    }
    local n : word count `keep'
    if `n'<6 {
        di as error "FF5: expected 6 numeric factor columns after Date; found `n'."
        exit 111
    }
    rename `: word 1 of `keep'' mkt_rf
    rename `: word 2 of `keep'' smb
    rename `: word 3 of `keep'' hml
    rename `: word 4 of `keep'' rmw
    rename `: word 5 of `keep'' cma
    rename `: word 6 of `keep'' rf
}

foreach v in mkt_rf smb hml rmw cma rf {
    cap destring `v', replace ignore(",")
    replace `v' = `v'/100
}
keep m mkt_rf smb hml rmw cma rf
duplicates tag m, gen(dup)
count if dup
if r(N)>0 collapse (mean) mkt_rf smb hml rmw cma rf, by(m)
isid m
keep if inrange(m, `M_START', `M_END')
save "`root'/output/data/ff5_monthly.dta", replace

* === Momentum (UMD) ===
clear
import excel using "`f_macro'", sheet("FamaFrenchMomentum") firstrow clear
gen double m = .
capture confirm numeric variable Date
if !_rc {
    cap destring Date, replace ignore(",") force
    gen int yy = floor(Date/100)
    gen int mm = mod(Date,100)
    replace m = ym(yy,mm)
}
capture confirm string variable date
if !_rc {
    replace m = monthly(date,"YM") if missing(m)
    replace m = ym(real(substr(date,1,4)), real(substr(date,6,2))) if missing(m) & length(date)>=7
    replace m = ym(real(substr(date,1,4)), real(substr(date,5,2))) if missing(m) & length(date)==6
}
capture confirm numeric variable date
if !_rc {
    replace m = mofd(date) if missing(m)
    replace m = mofd(date + td(30dec1899)) if missing(m)
    replace m = ym(floor(date/100), mod(date,100)) if missing(m) & inrange(date,190001,210012)
}
format m %tm
drop if missing(m)
sort m
capture rename UMD umd
capture rename Mom umd
cap destring umd, replace ignore(",")
replace umd = umd/100
keep m umd
duplicates tag m, gen(dup)
count if dup
if r(N)>0 collapse (mean) umd, by(m)
isid m
keep if inrange(m, `M_START', `M_END')
save "`root'/output/data/mom_monthly.dta", replace

* === Merge with returns & build excess returns ===
use "`root'/output/data/returns_macro.dta", clear
merge 1:1 m using "`root'/output/data/ff5_monthly.dta",  keep(match) nogenerate
merge 1:1 m using "`root'/output/data/mom_monthly.dta", keep(match) nogenerate

* 1) Log rf for log excess
gen double rf_log = ln(1 + rf)
gen double rp_rb_ex = r_p_rb_m - rf_log
gen double r_mkt_ex = r_mkt_m  - rf_log
gen double rp_bh_ex = r_p_bh_m - rf_log

* 2) Simple returns & excess (for FF)
gen double rp_rb_s = exp(r_p_rb_m)  - 1
gen double r_mkt_s = exp(r_mkt_m)   - 1
gen double rp_bh_s = exp(r_p_bh_m)  - 1
gen double rp_rb_ex_s = rp_rb_s - rf
gen double r_mkt_ex_s = r_mkt_s - rf
gen double rp_bh_ex_s = rp_bh_s - rf

label var rp_rb_ex    "Excess return (RB, log)"
label var r_mkt_ex    "MKT-RF (log)"
label var rp_bh_ex    "Excess return (BH, log)"
label var rp_rb_ex_s  "Excess return (RB, simple)"
label var r_mkt_ex_s  "MKT-RF (simple)"
label var rp_bh_ex_s  "Excess return (BH, simple)"

save "`root'/output/data/master_monthly.dta", replace
export delimited using "`root'/output/data/master_monthly.csv", replace
di as result "Saved -> `root'/output/data/master_monthly.dta"
