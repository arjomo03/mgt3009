****************************************************
* 02_macro_merge_MAC.do  (Stata 18)
****************************************************
version 18
clear all
set more off

local root "/Users/johnmohmedi/Desktop/MGT3009"
local f_macro "`root'/Macroeconomic_Data.xlsx"

cap mkdir "`root'/output"
cap mkdir "`root'/output/data"

* Import macro sheet
import excel using "`f_macro'", sheet("FREDPostInvestment") firstrow clear

* Monthly date m (robust)
capture confirm string variable date
if !_rc {
    gen double m = monthly(date,"YM")
    replace m = mofd(daily(date,"YMD")) if missing(m)
    replace m = mofd(daily(date,"DMY")) if missing(m)
}
else {
    gen double m = mofd(date)
    replace m = mofd(date + td(30dec1899)) if m < tm(1990m1) | m > tm(2035m12)
}
format m %tm
drop if missing(m)
sort m
tsset m, monthly

* Canonical names
capture rename CPIAUCSL cpi
capture rename UNRATE  unrate
capture rename FEDFUNDS fedfunds
capture rename UMCSENT umcsent

* EPU -> epu
capture confirm variable EPUTRADE
if !_rc {
    gen double epu = EPUTRADE
}
else {
    capture confirm variable EPU
    if !_rc {
        gen double epu = EPU
    }
    else {
        di as error "!! No EPU column found (expected EPUTRADE or EPU)."
        exit 111
    }
}

foreach v in cpi unrate fedfunds umcsent epu {
    cap destring `v', replace ignore(",")
}

* Transforms
gen double ln_cpi  = ln(cpi)
gen double infl    = D.ln_cpi

gen double d_unrate = D.unrate
gen double d_fed    = D.fedfunds

gen double ln_umcsent = cond(umcsent>0, ln(umcsent), .)
gen double d_sent     = D.ln_umcsent
label var d_sent "Δ ln(UMich sentiment)"

gen double ln_epu   = cond(epu>0, ln(epu), .)
gen double d_logepu = D.ln_epu
label var d_logepu "Δ ln(EPU)"

* COVID era dummy for macro regs (distinct from NBER recession shading)
gen byte covid_era = inrange(m, tm(2020m3), tm(2021m12))
label var covid_era "COVID era (2020m3–2021m12)"

* Keep window
keep if inrange(m, tm(2015m1), tm(2025m9))

save "`root'/output/data/macro_monthly.dta", replace

* Merge with returns
use "`root'/output/data/monthly_returns.dta", clear
merge 1:1 m using "`root'/output/data/macro_monthly.dta", keep(match) nogenerate

save "`root'/output/data/returns_macro.dta", replace
export delimited using "`root'/output/data/returns_macro.csv", replace
di as result "Saved -> `root'/output/data/returns_macro.dta"
