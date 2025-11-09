****************************************************
* 04_performance_factor_regs_mac.do  (Stata 18)
* Portfolio metrics, factor regressions, rolling CAPM,
* attribution, and sub-period diagnostics.
****************************************************
version 18
clear all
set more off

* ---------- Paths ----------
local root "/Users/johnmohmedi/Desktop/MGT3009"

cap mkdir "`root'/output"
cap mkdir "`root'/output/data"
cap mkdir "`root'/output/tables"
cap mkdir "`root'/output/figures"

* ---------- Load master ----------
use "`root'/output/data/master_monthly.dta", clear
tsset m, monthly                      // m is %tm

* ---------- Guards for standalone runs ----------
* If someone runs 04 alone, ensure simple-return series exist
capture confirm variable rp_rb_s
if _rc gen double rp_rb_s = exp(r_p_rb_m) - 1

capture confirm variable r_mkt_s
if _rc gen double r_mkt_s = exp(r_mkt_m) - 1

* Window + recession band (NBER recession used for shading)
local W_START = tm(2015m1)
quietly su m, meanonly
local W_END   = r(max)
local REC_START = tm(2020m2)
local REC_END   = tm(2020m4)

* Yearly tick labels at 45°
local yfirst = yofd(dofm(`W_START'))
local ylast  = yofd(dofm(`W_END'))
local XLABS
forvalues Y = `yfirst'/`ylast' {
    local XLABS `XLABS' `=ym(`Y',1)' "01/01/`Y'"
}

****************************************************
* 1) Performance metrics (+M², Treynor, Calmar, Omega, Up/Down, Hit)
****************************************************
* Portfolio log-excess stats (Sharpe/IR/TE)
quietly su rp_rb_ex
scalar mu_ex  = r(mean)
scalar sd_ex  = r(sd)
scalar sharpe_ann = (12*mu_ex)/(sqrt(12)*sd_ex)

* Tracking error & Information ratio vs log market excess
gen double ex_diff = rp_rb_ex - r_mkt_ex
quietly su ex_diff
scalar te_ann = sqrt(12)*r(sd)
scalar ir_ann = (12*r(mean))/te_ann

* Sortino (true downside deviation, monthly threshold 0)
gen double _negsq = cond(rp_rb_ex < 0, rp_rb_ex^2, 0)
quietly su _negsq, meanonly
scalar _dd_m = sqrt(r(mean))
scalar sortino = .
if _dd_m>0 scalar sortino = (sqrt(12)*mu_ex)/_dd_m
drop _negsq

* Value path & max drawdown (log)
gen double v_rb = exp(sum(r_p_rb_m))
gen double peak = v_rb
replace peak = max(peak[_n-1], v_rb) if _n>1
gen double drawdown = (v_rb/peak) - 1
quietly su drawdown
scalar maxdd = r(min)

* Additional standard metrics (on correct units)
quietly su r_mkt_ex
scalar mu_mkt_ex = r(mean)
scalar sd_mkt_ex = r(sd)

* Treynor (annual) using OLS beta from CAPM (log)
quietly regress rp_rb_ex r_mkt_ex
scalar beta_ols = _b[r_mkt_ex]
scalar treynor_ann = .
if beta_ols!=0 scalar treynor_ann = 12*mu_ex / beta_ols

* M^2 (excess form): Sharpe_p*σ_mkt − μ_mkt; monthly then annual
scalar M2_m  = (mu_ex/sd_ex)*sd_mkt_ex - mu_mkt_ex
scalar M2_ann = 12*M2_m

* Annual return (geometric, log) and Calmar
quietly su r_p_rb_m
scalar mu_port_m = r(mean)
scalar ann_return = exp(12*mu_port_m) - 1
scalar calmar = .
if maxdd<0 scalar calmar = ann_return/abs(maxdd)

* Omega(0) using SIMPLE returns (compute sums safely as mean*N)
capture confirm variable rp_rb_s
if _rc gen double rp_rb_s = exp(r_p_rb_m) - 1
gen double gain = cond(rp_rb_s>0,  rp_rb_s, 0)
gen double loss = cond(rp_rb_s<0, -rp_rb_s, 0)
quietly su gain, meanonly
scalar G = r(mean)*r(N)
quietly su loss, meanonly
scalar L = r(mean)*r(N)
scalar omega0 = .
if L>0 scalar omega0 = G/L
drop gain loss

* Up/Down capture & Hit ratio (simple vs market simple)
capture confirm variable r_mkt_s
if _rc gen double r_mkt_s = exp(r_mkt_m) - 1
gen byte up_mkt   = r_mkt_s > 0
gen byte down_mkt = r_mkt_s <= 0
quietly su rp_rb_s if up_mkt
scalar cap_up_p = r(mean)
quietly su r_mkt_s if up_mkt
scalar cap_up_m = r(mean)
quietly su rp_rb_s if down_mkt
scalar cap_dn_p = r(mean)
quietly su r_mkt_s if down_mkt
scalar cap_dn_m = r(mean)
scalar UpCapture   = .
scalar DownCapture = .
if cap_up_m!=0   scalar UpCapture   = cap_up_p / cap_up_m
if cap_dn_m!=0   scalar DownCapture = cap_dn_p / cap_dn_m
gen byte beat = (rp_rb_s > r_mkt_s)
quietly su beat
scalar HitRatio = r(mean)
drop up_mkt down_mkt beat

* Export performance metrics
postfile P str32 metric value using "`root'/output/tables/perf_metrics.dta", replace
post P ("Sharpe (ann excess)") (sharpe_ann)
post P ("Tracking error (ann)") (te_ann)
post P ("Info ratio (ann)")     (ir_ann)
post P ("Sortino (ann)")        (sortino)
post P ("Treynor (ann)")        (treynor_ann)
post P ("M2 (ann)")             (M2_ann)
post P ("Omega (0)")            (omega0)
post P ("Up Capture")           (UpCapture)
post P ("Down Capture")         (DownCapture)
post P ("Hit Ratio")            (HitRatio)
post P ("Calmar")               (calmar)
post P ("Max drawdown")         (maxdd)
postclose P
use "`root'/output/tables/perf_metrics.dta", clear
export delimited using "`root'/output/tables/perf_metrics.csv", replace

****************************************************
* 2) Factor regressions (HAC lag=6) — CAPM (log), FF5+UMD (simple)
****************************************************
use "`root'/output/data/master_monthly.dta", clear
tsset m, monthly

* ---------- CAPM (log) vs SPXT proxy ----------
newey rp_rb_ex r_mkt_ex, lag(6)
scalar alpha_capm    = _b[_cons]
scalar alpha_se_capm = _se[_cons]
test _cons = 0
scalar p_alpha_capm  = r(p)
quietly regress rp_rb_ex r_mkt_ex if e(sample)
scalar r2_capm = e(r2)
scalar n_capm  = e(N)

* ---------- FF5+UMD (simple) — textbook Fama–French ----------
newey rp_rb_ex_s mkt_rf smb hml rmw cma umd, lag(6)
scalar alpha_ff6    = _b[_cons]
scalar alpha_se_ff6 = _se[_cons]
test _cons = 0
scalar p_alpha_ff6  = r(p)
quietly regress rp_rb_ex_s mkt_rf smb hml rmw cma umd if e(sample)
scalar r2_ff6 = e(r2)
scalar n_ff6  = e(N)

* ---------- Optional: CAPM (simple, FF market) ----------
newey rp_rb_ex_s mkt_rf, lag(6)
scalar alpha_capm_s    = _b[_cons]
scalar alpha_se_capm_s = _se[_cons]
test _cons = 0
scalar p_alpha_capm_s  = r(p)
quietly regress rp_rb_ex_s mkt_rf if e(sample)
scalar r2_capm_s = e(r2)
scalar n_capm_s  = e(N)

* Export factor summary (wrap each scalar in scalar() to avoid r(133))
tempname F
postfile `F' str20 model double alpha alpha_se p_alpha r2 N using ///
    "`root'/output/tables/factor_regs_summary.dta", replace
post `F' ("CAPM (log)")     (scalar(alpha_capm))   (scalar(alpha_se_capm))   (scalar(p_alpha_capm))   (scalar(r2_capm))   (scalar(n_capm))
post `F' ("FF5+UMD (simp)") (scalar(alpha_ff6))    (scalar(alpha_se_ff6))    (scalar(p_alpha_ff6))    (scalar(r2_ff6))    (scalar(n_ff6))
post `F' ("CAPM (simp)")    (scalar(alpha_capm_s)) (scalar(alpha_se_capm_s)) (scalar(p_alpha_capm_s)) (scalar(r2_capm_s)) (scalar(n_capm_s))
postclose `F'
use "`root'/output/tables/factor_regs_summary.dta", clear
export delimited using "`root'/output/tables/factor_regs_summary.csv", replace

****************************************************
* 3) Rolling 36m CAPM — both variants (log & simple)
****************************************************
* (a) Log CAPM roll (rp_rb_ex on r_mkt_ex)
use "`root'/output/data/master_monthly.dta", clear
tsset m, monthly
rolling _b, window(36) saving("`root'/output/data/rollcapm_log.dta", replace): ///
    regress rp_rb_ex r_mkt_ex
use "`root'/output/data/rollcapm_log.dta", clear
gen m = end
format m %tm
rename _b_cons alpha
capture confirm variable _b_r_mkt_ex
if !_rc {
    rename _b_r_mkt_ex beta
}
else {
    di as error "No rolling beta column (_b_r_mkt_ex) for log roll."
    exit 111
}
keep m alpha beta
save "`root'/output/data/rollcapm_log_clean.dta", replace

* (b) Simple CAPM roll (rp_rb_ex_s on mkt_rf)
use "`root'/output/data/master_monthly.dta", clear
tsset m, monthly
rolling _b, window(36) saving("`root'/output/data/rollcapm_simp.dta", replace): ///
    regress rp_rb_ex_s mkt_rf
use "`root'/output/data/rollcapm_simp.dta", clear
gen m = end
format m %tm
rename _b_cons alpha
capture confirm variable _b_mkt_rf
if !_rc {
    rename _b_mkt_rf beta
}
else {
    di as error "No rolling beta column (_b_mkt_rf) for simple roll."
    exit 111
}
keep m alpha beta
save "`root'/output/data/rollcapm_simp_clean.dta", replace

****************************************************
* 4) Figures — Growth, Rolling β (both), Drawdown, Sentiment scatter
****************************************************
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

* 4a) Growth of $1
use "`root'/output/data/master_monthly.dta", clear
gen double v_port = exp(sum(r_p_rb_m))
gen double v_spxt = exp(sum(r_mkt_m))
replace v_port = v_port / v_port[1]
replace v_spxt = v_spxt / v_spxt[1]
gen byte rec = inrange(m, `REC_START', `REC_END')
_make_band v_port
twoway ///
 (rbar y0 y1 m if rec, bcolor(gs12%60) lcolor(none)) ///
 (line v_port m, lwidth(medthick)) ///
 (line v_spxt m, lpattern(dash) lwidth(medthick)), ///
 legend(order(2 "Portfolio (RB)" 3 "S&P 500 TR") pos(11) ring(0) col(1)) ///
 title("Growth of $1 (2015–`=yofd(dofm(`W_END'))')", color(black)) ///
 subtitle("Recession shaded", color(black)) ///
 xtitle("Month") ytitle("Cumulative value") ///
 xlabel(`XLABS', angle(45)) xscale(range(`W_START' `W_END')) ///
 graphregion(color(white)) plotregion(color(white))
graph save   "`root'/output/figures/fig_cum_value.gph", replace
graph export "`root'/output/figures/fig_cum_value.png", width(2200) replace

* 4b) Rolling β — log
use "`root'/output/data/rollcapm_log_clean.dta", clear
gen byte rec = inrange(m, tm(2020m2), tm(2020m4))
quietly su beta
gen double y0 = r(min)
gen double y1 = r(max)
twoway ///
  (rbar y0 y1 m if rec, bcolor(gs12%60) lcolor(none)) ///
  (line beta m, lwidth(medthick) lcolor(cranberry)), ///
  title("Rolling 36m CAPM β (log MKT-RF)") subtitle("Recession shaded") legend(off) ///
  xtitle("Month") ytitle("β to log market excess") ///
  graphregion(color(white)) plotregion(color(white))
graph save   "`root'/output/figures/fig_rolling_beta_log.gph", replace
graph export "`root'/output/figures/fig_rolling_beta_log.png", width(2200) replace

* 4c) Rolling β — simple
use "`root'/output/data/rollcapm_simp_clean.dta", clear
gen byte rec = inrange(m, tm(2020m2), tm(2020m4))
quietly su beta
gen double y0 = r(min)
gen double y1 = r(max)
twoway ///
  (rbar y0 y1 m if rec, bcolor(gs12%60) lcolor(none)) ///
  (line beta m, lwidth(medthick) lcolor(cranberry)), ///
  title("Rolling 36m CAPM β (FF MKT_RF)") subtitle("Recession shaded") legend(off) ///
  xtitle("Month") ytitle("β to FF market (simple)") ///
  graphregion(color(white)) plotregion(color(white))
graph save   "`root'/output/figures/fig_rolling_beta_simple.gph", replace
graph export "`root'/output/figures/fig_rolling_beta_simple.png", width(2200) replace

* 4d) Portfolio drawdown
use "`root'/output/data/master_monthly.dta", clear
gen double v_rb2 = exp(sum(r_p_rb_m))
gen double peak2 = v_rb2
replace peak2 = max(peak2[_n-1], v_rb2) if _n>1
gen double drawdown = (v_rb2/peak2) - 1
gen byte rec = inrange(m, `REC_START', `REC_END')
_make_band drawdown
twoway ///
 (rbar y0 y1 m if rec, bcolor(gs12%60) lcolor(none)) ///
 (line drawdown m, lwidth(medthick)), ///
 title("Portfolio drawdown", color(black)) ///
 subtitle("Recession shaded", color(black)) legend(off) ///
 ytitle("Drawdown") xtitle("Month") ///
 xlabel(`XLABS', angle(45)) xscale(range(`W_START' `W_END')) ///
 graphregion(color(white)) plotregion(color(white))
graph save   "`root'/output/figures/fig_drawdown.gph", replace
graph export "`root'/output/figures/fig_drawdown.png", width(2200) replace

* 4e) Excess vs Δln sentiment scatter + slope/p-value
use "`root'/output/data/master_monthly.dta", clear
tsset m, monthly
capture drop ln_sent d_ln_sent rec
gen double ln_sent  = ln(umcsent) if umcsent>0
gen double d_ln_sent = D.ln_sent
label var d_ln_sent "Δ ln(UMich sentiment)"
gen byte rec = inrange(m, tm(2020m2), tm(2020m4))
keep if !missing(rp_rb_ex, d_ln_sent)
twoway ///
 (scatter rp_rb_ex d_ln_sent if rec,   msize(vsmall) msymbol(O) mcolor(gs8)) ///
 (scatter rp_rb_ex d_ln_sent if !rec,  msize(vsmall) mcolor(navy)) ///
 (lfit    rp_rb_ex d_ln_sent, lwidth(medthick) lcolor(forest_green)), ///
 title("Excess return vs Δ log sentiment") ///
 ytitle("Portfolio excess (monthly)") xtitle("{&Delta} ln(UMich sentiment)") ///
 legend(order(2 "Non-recession" 1 "Recession (grey)" 3 "OLS fit") pos(11) ring(0) col(1)) ///
 note("Recession months (2020m2–2020m4) are shown in grey", size(small)) ///
 graphregion(color(white)) plotregion(color(white))
graph save   "`root'/output/figures/fig_sent_scatter.gph", replace
graph export "`root'/output/figures/fig_sent_scatter.png", width(2200) replace

quietly reg rp_rb_ex d_ln_sent
scalar slope_dln = _b[d_ln_sent]
scalar p_dln     = 2*ttail(e(df_r),abs(_b[d_ln_sent]/_se[d_ln_sent]))
postfile Q str20 stat value using "`root'/output/tables/sent_scatter_fit.dta", replace
post Q ("slope_dlnsent") (scalar(slope_dln))
post Q ("p_value")       (scalar(p_dln))
postclose Q
use "`root'/output/tables/sent_scatter_fit.dta", clear
export delimited using "`root'/output/tables/sent_scatter_fit.csv", replace

****************************************************
* 5) Attribution by stock: return & risk contribution (simple)
****************************************************
use "`root'/output/data/master_monthly.dta", clear

* Individual simple returns from log series (clean re-runs)
capture drop r_goog_s r_msft_s r_ma_s r_hd_s
gen r_goog_s = exp(r_goog_m) - 1
gen r_msft_s = exp(r_msft_m) - 1
gen r_ma_s   = exp(r_ma_m)   - 1
gen r_hd_s   = exp(r_hd_m)   - 1

* Fixed RB weights (repeat here for clarity) -> use scalar() in constructor
scalar Wg = 0.366003594
scalar Wm = 0.390981129
scalar Wa = 0.101758435
scalar Wh = 0.141256842
matrix w = ( scalar(Wg) \ scalar(Wm) \ scalar(Wa) \ scalar(Wh) )   // 4x1

* Contribution to return (elementwise product via diag)
quietly mean r_goog_s r_msft_s r_ma_s r_hd_s
matrix mu = e(b)'                           // 4x1 means
matrix c_ret = diag(w) * mu                 // 4x1

* Risk contributions (Euler): rc_i = w_i * (S * w)_i
quietly corr r_goog_s r_msft_s r_ma_s r_hd_s, cov
matrix S  = r(C)
matrix Sw = S * w
matrix Vp = w' * Sw
scalar port_var = Vp[1,1]
matrix rc = diag(w) * Sw
scalar invvar = 1/port_var
matrix rc_pct = rc * invvar

* Export tidy table
clear
set obs 4
gen str8 name = ""
replace name = "GOOGL" in 1
replace name = "MSFT"  in 2
replace name = "MA"    in 3
replace name = "HD"    in 4
gen double contrib_return   = .
gen double risk_contrib     = .
gen double risk_contrib_pct = .
forvalues i=1/4 {
    replace contrib_return   = c_ret[`i',1]  in `i'
    replace risk_contrib     = rc[`i',1]     in `i'
    replace risk_contrib_pct = rc_pct[`i',1] in `i'
}
export delimited using "`root'/output/tables/attribution_by_stock.csv", replace

****************************************************
* 6) Sub-period summary (Pre, Recession, COVID era, Post) — robust to short windows
****************************************************
use "`root'/output/data/master_monthly.dta", clear
tsset m, monthly
gen byte pre  = inrange(m, tm(2015m1), tm(2019m12))
gen byte rec  = inrange(m, tm(2020m2), tm(2020m4))
gen byte era  = inrange(m, tm(2020m3), tm(2021m12))   // COVID era
gen byte post = inrange(m, tm(2022m1), tm(2025m8))

tempname T
postfile `T' str10 period double sharpe sortino alpha_capm p_capm using ///
    "`root'/output/tables/subperiod_summary.dta", replace

foreach P in pre rec era post {
    preserve
        keep if `P'
        quietly count
        local N = r(N)

        * Sharpe & Sortino (annualized from monthly)
        quietly summarize rp_rb_ex
        scalar mu = r(mean)
        scalar sd = r(sd)
        scalar sh = .
        if sd>0 scalar sh = (sqrt(12)*mu)/sd
        gen double _negsq = cond(rp_rb_ex<0, rp_rb_ex^2, 0)
        quietly summarize _negsq, meanonly
        scalar dd = sqrt(r(mean))
        drop _negsq
        scalar so = .
        if dd>0 scalar so = (sqrt(12)*mu)/dd

        * Choose HAC lag based on sample size; fall back to OLS if needed
        scalar L = min(6, max(0, floor((`N'-2)/4)))
        local LAG = scalar(L)

        capture noisily newey rp_rb_ex r_mkt_ex, lag(`LAG')
        if _rc {
            * OLS fallback for ultra short windows (e.g., 3 months)
            regress rp_rb_ex r_mkt_ex
            scalar a  = _b[_cons]
            test _cons = 0
            scalar pa = r(p)
        }
        else {
            scalar a  = _b[_cons]
            test _cons = 0
            scalar pa = r(p)
        }

        post `T' ("`P'") (scalar(sh)) (scalar(so)) (scalar(a)) (scalar(pa))
    restore
}
postclose `T'
use "`root'/output/tables/subperiod_summary.dta", clear
export delimited using "`root'/output/tables/subperiod_summary.csv", replace

di as result "04 completed — metrics, factors, rolling β, attribution, and sub-period tables written."
