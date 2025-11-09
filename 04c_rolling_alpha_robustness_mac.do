****************************************************
* 04c_rolling_alpha_robustness_mac.do  (Stata 18)
* Rolling 60m alphas:
*   - CAPM (log)
*   - FF5+UMD (simple)
* Optional: HXZ q-factors (simple) if variables exist
****************************************************
version 18
clear all
set more off

local root "/Users/johnmohmedi/Desktop/MGT3009"
cap mkdir "`root'/output"
cap mkdir "`root'/output/data"
cap mkdir "`root'/output/figures"

* ---------- Helpers ----------
program drop _all
program define _make_band
    syntax varlist(min=1 max=1)
    quietly su `varlist'
    local lo = r(min)
    local hi = r(max)
    local pad = 0.03*(`hi' - `lo')
    gen double y0 = `lo' - `pad'
    gen double y1 = `hi' + `pad'
end

* ---------- CAPM (log) rolling alpha ----------
use "`root'/output/data/master_monthly.dta", clear
tsset m, monthly
rolling _b, window(60) saving("`root'/output/data/rollalpha_capm_log60.dta", replace): ///
    regress rp_rb_ex r_mkt_ex
use "`root'/output/data/rollalpha_capm_log60.dta", clear
gen m = end
format m %tm
rename _b_cons alpha
keep m alpha
save "`root'/output/data/rollalpha_capm_log60_clean.dta", replace

use "`root'/output/data/rollalpha_capm_log60_clean.dta", clear
gen byte rec = inrange(m, tm(2020m2), tm(2020m4))
_make_band alpha
twoway (rbar y0 y1 m if rec, bcolor(gs12%60) lcolor(none)) ///
       (line alpha m, lwidth(medthick)), ///
       title("Rolling 60m α — CAPM (log)") ///
       ytitle("Monthly α") xtitle("Month") legend(off) ///
       graphregion(color(white)) plotregion(color(white))
graph save   "`root'/output/figures/fig_rolling_alpha_capm_log60.gph", replace
graph export "`root'/output/figures/fig_rolling_alpha_capm_log60.png", width(2200) replace

* ---------- FF5+UMD (simple) rolling alpha ----------
use "`root'/output/data/master_monthly.dta", clear
tsset m, monthly
rolling _b, window(60) saving("`root'/output/data/rollalpha_ff6_simp60.dta", replace): ///
    regress rp_rb_ex_s mkt_rf smb hml rmw cma umd
use "`root'/output/data/rollalpha_ff6_simp60.dta", clear
gen m = end
format m %tm
rename _b_cons alpha
keep m alpha
save "`root'/output/data/rollalpha_ff6_simp60_clean.dta", replace

use "`root'/output/data/rollalpha_ff6_simp60_clean.dta", clear
gen byte rec = inrange(m, tm(2020m2), tm(2020m4))
_make_band alpha
twoway (rbar y0 y1 m if rec, bcolor(gs12%60) lcolor(none)) ///
       (line alpha m, lwidth(medthick)), ///
       title("Rolling 60m α — FF5+UMD (simple)") ///
       ytitle("Monthly α") xtitle("Month") legend(off) ///
       graphregion(color(white)) plotregion(color(white))
graph save   "`root'/output/figures/fig_rolling_alpha_ff6_simp60.gph", replace
graph export "`root'/output/figures/fig_rolling_alpha_ff6_simp60.png", width(2200) replace

* ---------- Optional: HXZ q-factors (simple) ----------
use "`root'/output/data/master_monthly.dta", clear
tsset m, monthly
capture confirm variable q_mkt
if !_rc {
    capture confirm variable q_me
    capture confirm variable q_ia
    capture confirm variable q_ro
}
if !_rc {
    rolling _b, window(60) saving("`root'/output/data/rollalpha_hxz60.dta", replace): ///
        regress rp_rb_ex_s q_mkt q_me q_ia q_ro
    use "`root'/output/data/rollalpha_hxz60.dta", clear
    gen m = end
    format m %tm
    rename _b_cons alpha
    keep m alpha
    save "`root'/output/data/rollalpha_hxz60_clean.dta", replace

    use "`root'/output/data/rollalpha_hxz60_clean.dta", clear
    gen byte rec = inrange(m, tm(2020m2), tm(2020m4))
    _make_band alpha
    twoway (rbar y0 y1 m if rec, bcolor(gs12%60) lcolor(none)) ///
           (line alpha m, lwidth(medthick)), ///
           title("Rolling 60m α — HXZ q-factors (simple)") ///
           ytitle("Monthly α") xtitle("Month") legend(off) ///
           graphregion(color(white)) plotregion(color(white))
    graph export "`root'/output/figures/fig_rolling_alpha_hxz60.png", width(2200) replace
}
else {
    di as txt "HXZ q-factors not found in master_monthly; skipping robustness alpha."
}
di as result "Wrote rolling alpha figures to output/figures/"
