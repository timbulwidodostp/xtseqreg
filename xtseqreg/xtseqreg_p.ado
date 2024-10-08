*! version 1.2.4  02sep2021
*! Sebastian Kripfganz, www.kripfganz.de

*==================================================*
***** predictions and residuals after xtseqreg *****

*** Citation ***

/*	Kripfganz, S., and C. Schwarz (2015).
	Estimation of linear dynamic panel data models with time-invariant regressors.
	Journal of Applied Econometrics 34: 526-546.		*/

program define xtseqreg_p, sort
	version 12.1
	syntax [anything] [if] [in] [, XB SCores EQuation(passthru) *]
	if "`scores'" != "" {							// parameter-level scores
		xtseqreg_p_scores `0'
		exit
	}

	loc 0				`"`anything' `if' `in' , `options'"'
	loc options			"UE E U XBU"
	_pred_se "`options'" `0'
	if `s(done)' {
		exit
	}
	loc vtype			"`s(typ)'"
	loc varn			"`s(varn)'"
	loc 0				`"`s(rest)'"'
	syntax [if] [in] [, `options']
	marksample touse

	loc prediction		"`ue'`e'`u'`xbu'"
	if "`prediction'" == "" {						// linear prediction excluding unit-specific error component (default)
		if "`xb'" == "" {
			di as txt "(option xb assumed; fitted values)"
		}
		_predict `vtype' `varn' if `touse', xb `equation'
		exit
	}
	if "`prediction'" == "ue" {						// combined residual
		tempvar xb
		qui predict double `xb' if `touse', xb `equation'
		gen `vtype' `varn' = `e(depvar)' - `xb' if `touse'
		lab var `varn' "u[`e(ivar)'] + e[`e(ivar)',`e(tvar)']"
		exit
	}
	qui replace `touse' = 0 if !e(sample)
	if "`prediction'" == "e" {						// idiosyncratic error component
		tempvar xb u
		qui predict double `xb' if `touse', xb `equation'
		qui predict double `u' if `touse', u `equation'
		gen `vtype' `varn' = `e(depvar)' - `xb' - `u' if `touse'
		lab var `varn' "e[`e(ivar)',`e(tvar)']"
		exit
	}
	tempvar smpl
	qui gen byte `smpl' = e(sample)
	if "`prediction'" == "u" | "`prediction'" == "xbu" {
		tempvar xb u y_bar xb_bar
		qui predict double `xb' if `smpl', xb `equation'
		qui by `e(ivar)': egen double `y_bar' = mean(`e(depvar)') if `smpl'
		qui by `e(ivar)': egen double `xb_bar' = mean(`xb') if `smpl'
		qui gen double `u' = `y_bar' - `xb_bar' if `smpl'
		if "`prediction'" == "u" {					// unit-specific error component
			gen `vtype' `varn' = `u' if `touse'
			lab var `varn' "u[`e(ivar)']"
		}
		else {										// linear prediction including unit-specific error component
			gen `vtype' `varn' = `xb' + `u' if `touse'
			lab var `varn' "Xb + u[`e(ivar)']"
		}
		exit
	}
	error 198
end

*==================================================*
**** repost one-step estimates ****
program define xtseqreg_p_onestep, eclass
	version 12.1

	tempname b W
	mat `b'				= e(b_onestep)
	mat `W'				= e(W_onestep)
	eret repost b = `b', rename
	eret mat W			= `W'
end

*==================================================*
**** computation of parameter-level scores ****
program define xtseqreg_p_scores, rclass sort
	version 12.1
	syntax [anything] [if] [in] , SCores
	marksample touse

	if rowsof(e(stats)) == 2 {
		di as err "option scores not allowed after xtseqreg with two equations"
		exit 198
	}
	tempvar smpl
	qui gen byte `smpl' = e(sample)
	tempname b
	mat `b'				= e(b)
	loc indepvars		: coln `b'
	loc K				: word count `indepvars'
	loc indepvars		: subinstr loc indepvars "_cons" "`smpl'", w
	_stubstar2names `anything', nvars(`: word count `indepvars'') noverify
	loc vtypes			"`s(typlist)'"
	loc varn			"`s(varlist)'"
	if `: word count `varn'' != `K' {
		error 102
	}
	loc ivvars			"`e(ivvars_1)'"
	loc ivvars			: subinstr loc ivvars "_cons" "`smpl'", w
	if `: word count `e(dgmmivvars_1)'' > 0 | `: word count `e(divvars_1)'' > 0 {
		tempvar dsmpl
		qui gen byte `dsmpl' = `smpl'
		loc teffects		"`e(teffects)'"
		markout `dsmpl' D.`e(depvar)' D.(`: list indepvars - teffects')
		qui replace `dsmpl' = 0 if !(L.`smpl')
	}
	foreach var of loc varn {
		tempvar gen`var'
		qui gen double `gen`var'' = . if `smpl'
		loc projection		"`projection' `gen`var''"
		if "`e(vcetype)'" == "WC-Robust" {
			tempvar aux`var'
			qui gen double `aux`var'' = . if `smpl'
			loc projection1		"`projection1' `aux`var''"
		}
	}
	tempvar e
	qui predict double `e' if `smpl', ue
	fvrevar `indepvars' if `smpl'
	loc tindepvars		"`r(varlist)'"
	fvrevar `ivvars' if `smpl'
	loc tivvars			"`r(varlist)'"
	foreach tsvarlist in gmmivvars_1 divvars_1 dgmmivvars_1 ecivvars_1 ecgmmivvars_1 {
		fvrevar `e(`tsvarlist')' if `smpl'
		loc t`tsvarlist'	"`r(varlist)'"
	}
	if "`e(clustvar)'" != "" {
		sort `e(clustvar)' `_dta[_TSpanel]' `_dta[_TStvar]'
	}

	mata: xtseqreg_projection(	"`tindepvars'",				///
								"`projection'",				///
								"`tivvars'",				///
								"`tgmmivvars_1'",			///
								"`tdivvars_1'",				///
								"`tdgmmivvars_1'",			///
								"`tecivvars_1'",			///
								"`tecgmmivvars_1'",			///
								"`e(ivar)'",				///
								"`e(tvar)'",				///
								"`smpl'",					///
								"`dsmpl'",					///
								"",							///
								"",							///
								"e(W)",						///
								"",							///
								"`e(clustvar)'")
	foreach var of loc varn {
		qui replace `gen`var'' = `gen`var'' * `e' if `smpl'
	}

	if "`e(vcetype)'" == "WC-Robust" {				// Windmeijer correction
		if "`e(clustvar)'" != "" {
			qui xtset
		}
		tempname xtseqreg_e
		est sto `xtseqreg_e'
		xtseqreg_p_onestep
		tempvar e1
		qui predict double `e1' if `smpl', ue
		qui est res `xtseqreg_e'
		est drop `xtseqreg_e'
		if "`e(clustvar)'" != "" {
			sort `e(clustvar)' `_dta[_TSpanel]' `_dta[_TStvar]'
		}

		mata: xtseqreg_projection(	"`tindepvars'",				///
									"`projection1'",			///
									"`tivvars'",				///
									"`tgmmivvars_1'",			///
									"`tdivvars_1'",				///
									"`tdgmmivvars_1'",			///
									"`tecivvars_1'",			///
									"`tecgmmivvars_1'",			///
									"`e(ivar)'",				///
									"`e(tvar)'",				///
									"`smpl'",					///
									"`dsmpl'",					///
									"`e1'",						///
									"`e'",						///
									"e(W_onestep)",				///
									"e(W)",						///
									"`e(clustvar)'")
		foreach var of loc varn {
			qui replace `aux`var'' = `aux`var'' * `e1' if `smpl'
		}
		mata: xtseqreg_influence("`projection1'", "e(V_onestep)", "r(D)", "`smpl'")
		forv k = 1 / `K' {
			loc var				: word `k' of `varn'
			loc vtyp			: word `k' of `vtypes'
			gen `vtyp' `var' = `gen`var'' + `aux`var'' if `touse'
			lab var `var' "parameter-level score from `e(cmd)'"
		}
	}
	else {
		forv k = 1 / `K' {
			loc var				: word `k' of `varn'
			loc vtyp			: word `k' of `vtypes'
			gen `vtyp' `var' = `gen`var'' if `touse'
			lab var `var' "parameter-level score from `e(cmd)'"
		}
	}

	ret loc scorevars	`varn'
end
