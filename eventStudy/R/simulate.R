
#' @export
ES_simulate_data <- function(units = 1e4,
                             min_cal_time = 1999,
                             max_cal_time = 2005,
                             min_onset_time = 2001,
                             max_onset_time = 2006,
                             epsilon_sd = 0.2,
                             homogeneous_ATT = TRUE,
                             oversample_one_year = TRUE,
                             cohort_specific_trends = FALSE,
                             post_treat_dynamics = TRUE,
                             anticipation = FALSE,
                             cohort_specific_anticipation = FALSE,
                             treated_subset = FALSE,
                             control_subset = FALSE,
                             time_vary_confounds_low_dim = FALSE,
                             time_vary_confounds_high_dim = FALSE,
                             time_vary_confounds_cont = FALSE,
                             add_never_treated = FALSE) {

  Units <- 1:units
  Times <- min_cal_time:max_cal_time
  W <- min_onset_time:max_onset_time

  # Make balanced panel in calendar time
  sim_data <- data.table(tin = rep(Units, length(Times)))
  setorderv(sim_data, "tin")
  sim_data[, tax_yr := rep(Times, length(Units))]

  # Different cohorts determined by time of treatment
  win_yr_data <- data.table(tin = Units, win_yr = sample(W, size = length(Units), replace = TRUE))
  sim_data <- merge(sim_data, win_yr_data, by = "tin")
  win_yr_data <- NULL

  if (oversample_one_year == TRUE) {

    # $@$ Randomly make the 2003 cohort much larger
    sim_data[, recode := runif(1, min = 0, max = 1), list(tin)]
    sim_data[recode > 0.50, win_yr := 2003]
  }

  if(add_never_treated == TRUE){

    # $@$ Randomly make some individuals never-treated with an onset_time_var of max() + 1; will change to NA upon concluding
    sim_data[, recode := runif(1, min = 0, max = 1), list(tin)]
    sim_data[recode < 0.10, win_yr := NA]

    never_treated <- max( max(sim_data$win_yr, na.rm = TRUE), max(sim_data$tax_yr, na.rm = TRUE))  + 1
    sim_data[is.na(win_yr), win_yr := never_treated]

  }

  # Different initial condition by cohort (just to generate level differences)
  cohort_fes <- data.table(win_yr = sort(unique(sim_data$win_yr)), alpha_e = runif(uniqueN(sim_data$win_yr), min = 0.6, max = 0.9))
  sim_data <- merge(sim_data, cohort_fes, by = "win_yr")
  gc()

  if(add_never_treated == TRUE){
    # change back to NA
    sim_data[win_yr == never_treated, win_yr := NA]
    cohort_fes[win_yr == never_treated, win_yr := NA]
  }

  # Generic (but parallel) trend
  tax_yr_fes <- data.table(tax_yr = sort(unique(sim_data$tax_yr)), delta_t = runif(uniqueN(sim_data$tax_yr), min = -0.1, max = 0.1))
  sim_data <- merge(sim_data, tax_yr_fes, by = "tax_yr")
  gc()

  if (homogeneous_ATT == FALSE) {

    # Different on-impact treatment effect by cohort
    cohort_specific_te_0 <- data.table(
      win_yr = sort(unique(sim_data$win_yr)),
      # te_0 = c(-0.2431251, -0.2135971, -0.2690795, -0.2816714, -0.2741780, -0.2002287)
      te_0 = (-2:3 - 3.5) / 10
    )

    # Nonlinear cohort-specific dynamics (growing TE) after "on-impact"
    # will do a quadratic in event_time post-treatment with cohort-specific loadings
    cohort_specific_post_linear <- data.table(
      win_yr = sort(unique(sim_data$win_yr)),
      linear_load = (-2:3 - 3.5) / 100
    )
    cohort_specific_post_quad <- data.table(
      win_yr = sort(unique(sim_data$win_yr)),
      quad_load = (-2:3 - 3.5) / 10000
    )

    params <- merge(cohort_specific_te_0, cohort_specific_post_linear, by = "win_yr", all = TRUE)
    params <- merge(params, cohort_specific_post_quad, by = "win_yr", all = TRUE)
    params[, win_yr := as.character(win_yr)]

    sim_data <- merge(sim_data, cohort_specific_te_0, by = "win_yr", all.x = TRUE)
    sim_data <- merge(sim_data, cohort_specific_post_linear, by = "win_yr", all.x = TRUE)
    sim_data <- merge(sim_data, cohort_specific_post_quad, by = "win_yr", all.x = TRUE)
    # ^ Need "all.x = TRUE" above so as not to drop the never-treated (win_yr == NA) cohort from sim_data
    gc()
  } else {

    # Homogeneous on-impact treatment effect by cohort
    te_0 <- -0.2431251

    # Nonlinear homogeneous dynamics (growing TE) after "on-impact"
    # will do a quadratic in event_time post-treatment
    linear_load <- -0.01784453
    quad_load <- -0.0001432203

    params <- c(te_0, linear_load, quad_load)
    names(params) <- c("te_0", "linear_load", "quad_load")
  }

  if (cohort_specific_trends == TRUE) {

    # Different linear calendar time trends by cohort
    cohort_specific_cal_time_trend <- data.table(
      win_yr = sort(unique(sim_data$win_yr)),
      cal_linear_trend = (1:6 - 3.5) / 100
    )
    sim_data <- merge(sim_data, cohort_specific_cal_time_trend, by = "win_yr", all.x = TRUE)
    # ^ Need "all.x = TRUE" above so as not to drop the never-treated (win_yr == NA) cohort from sim_data
    sim_data[!is.na(win_yr), delta_t := delta_t + (tax_yr - min_cal_time) * cal_linear_trend]
    gc()
  }

  if (post_treat_dynamics == FALSE & homogeneous_ATT == TRUE) {
    linear_load <- 0
    quad_load <- 0
    params[names(params) %in% c("linear_load", "quad_load")] <- 0
  } else if (post_treat_dynamics == FALSE & homogeneous_ATT == FALSE) {
    sim_data[, linear_load := 0]
    sim_data[, quad_load := 0]
    params[, linear_load := 0]
    params[, quad_load := 0]
  }

  if(homogeneous_ATT == T & anticipation == T & cohort_specific_anticipation == F){
    antic_params <- c(-.1,-.1)
    params <- c(params,antic_params[1],antic_params[2])
  } else if(homogeneous_ATT == T & anticipation == T & cohort_specific_anticipation == T){

    # Different two-period anticipation effects by cohort
    cohort_specific_antic_params <- data.table(
      win_yr = sort(unique(sim_data$win_yr)),
      antic_1 = (-3:2) / 10,
      antic_2 = (-3:2) / 10
    )

    sim_data <- merge(sim_data, cohort_specific_antic_params, by = "win_yr", all.x = TRUE)
    # ^ Need "all.x = TRUE" above so as not to drop the never-treated (win_yr == NA) cohort from sim_data
    cohort_specific_antic_params[, win_yr := as.character(win_yr)]
    gc()

  }

  if(treated_subset == T & control_subset == F){
    # Still need to come up with a more interesting illustration here
    sim_data[, subset_var := tin %% 2]
  } else if(treated_subset == F & control_subset == T){
    # Still need to come up with a more interesting illustration here
    sim_data[, subset_var := tin %% 2]
  } else if(treated_subset == T & control_subset == T){

    # Different calendar time trends by binary subset_var (i.e., conditional parallel trends)
    # Furthermore, will skew subset_var towards 1 earlier in the sample

    cohort_specific_subset_propensity <- data.table(
      win_yr = sort(unique(sim_data$win_yr)),
      pr_subset = (7:2 + 0.5)/10
    )

    sim_data <- merge(sim_data, cohort_specific_subset_propensity, by = "win_yr", all.x = TRUE)
    # ^ Need "all.x = TRUE" above so as not to drop the never-treated (win_yr == NA) cohort from sim_data
    gc()

    sim_data[, subset_index := runif(1, min = 0, max = 1), list(tin)]
    sim_data[!is.na(win_yr), subset_var := as.integer(subset_index <= pr_subset)]
    sim_data[is.na(win_yr), subset_var := as.integer(subset_index <= 0.5)]

    tax_yr_fes_subset0 <- data.table(tax_yr = sort(unique(sim_data$tax_yr)),
                                     subset_delta_t = sort(runif(uniqueN(sim_data$tax_yr), min = 0.10, max = 0.20)),
                                     subset_var = 0)
    tax_yr_fes_subset1 <- data.table(tax_yr = sort(unique(sim_data$tax_yr)),
                                     subset_delta_t = sort(runif(uniqueN(sim_data$tax_yr), min = -0.20, max = -0.10), decreasing = TRUE),
                                     subset_var = 1)

    tax_yr_fes_subset <- rbindlist(list(tax_yr_fes_subset0, tax_yr_fes_subset1), use.names = TRUE)
    sim_data <- merge(sim_data, tax_yr_fes_subset, by = c("tax_yr", "subset_var"))
    gc()

    sim_data[, delta_t := subset_delta_t]
    sim_data[, c("pr_subset", "subset_index", "subset_delta_t") := NULL]
    gc()
  }

  if(time_vary_confounds_low_dim==TRUE){

    # Aging -- young (0) and old (1)

    # Earlier cohorts start older on average
    sim_data[win_yr == 2001, time_vary_var := as.integer(runif(1) <= 0.45), list(tin)]
    sim_data[win_yr == 2002, time_vary_var := as.integer(runif(1) <= 0.40), list(tin)]
    sim_data[win_yr == 2003, time_vary_var := as.integer(runif(1) <= 0.35), list(tin)]
    sim_data[win_yr == 2004, time_vary_var := as.integer(runif(1) <= 0.30), list(tin)]
    sim_data[win_yr == 2005, time_vary_var := as.integer(runif(1) <= 0.25), list(tin)]
    sim_data[win_yr == 2006, time_vary_var := as.integer(runif(1) <= 0.2), list(tin)]
    sim_data[is.na(win_year), time_vary_var := as.integer(runif(1) <= 0.325), list(tin)]


    # Earlier cohorts age more in the post-treatment period on average
    sim_data[time_vary_var == 0 & tax_yr >= win_yr & win_yr == 2001, time_vary_var := as.integer(runif(1) <= 0.90), list(tin)]
    sim_data[time_vary_var == 0 & tax_yr >= win_yr & win_yr == 2002, time_vary_var := as.integer(runif(1) <= 0.80), list(tin)]
    sim_data[time_vary_var == 0 & tax_yr >= win_yr & win_yr == 2003, time_vary_var := as.integer(runif(1) <= 0.70), list(tin)]
    sim_data[time_vary_var == 0 & tax_yr >= win_yr & win_yr == 2004, time_vary_var := as.integer(runif(1) <= 0.60), list(tin)]
    sim_data[time_vary_var == 0 & tax_yr >= win_yr & win_yr == 2005, time_vary_var := as.integer(runif(1) <= 0.50), list(tin)]
    sim_data[time_vary_var == 0 & tax_yr >= win_yr & win_yr == 2006, time_vary_var := as.integer(runif(1) <= 0.40), list(tin)]

    # Add age change effect
    age_change = -0.20
    sim_data[time_vary_var == 1, delta_t := delta_t + age_change]
    gc()
  }

  if(time_vary_confounds_high_dim==TRUE & add_never_treated==FALSE){

    # Age distribution at event time the same across cohorts
    ages = 18:75
    sim_data[, time_vary_var_at_event := sample(x = ages, 1, replace = T, prob = rep(0.1, length(ages))), list(tin)]
    sim_data[, time_vary_var_high_dim := tax_yr - (win_yr - time_vary_var_at_event)]

    # Add age change effects
    # Let's set 36 as the reference age
    # Will try and match the age profile seen for lottery winners
    observed_ages = sort(unique(sim_data$time_vary_var_high_dim))
    age_changes = data.table(time_vary_var_high_dim = sort(observed_ages))
    age_changes[time_vary_var_high_dim < 18, age_effect := 0]
    age_changes[between(time_vary_var_high_dim, 18, 35, incbounds = TRUE), age_effect := (time_vary_var_high_dim / 30) - .4]
    age_changes[between(time_vary_var_high_dim, 36, 61, incbounds = TRUE), age_effect := (35 / 30) - .4]
    age_changes[between(time_vary_var_high_dim, 61, max(observed_ages), incbounds = TRUE), age_effect := (35:17 / 30) - .4]
    ref_level = age_changes[time_vary_var_high_dim == 36]$age_effect
    age_changes[, age_change := age_effect - ref_level]
    age_changes[, age_effect := NULL]
    age_changes[time_vary_var_high_dim != 36, age_change := age_change + sample(c(-0.02, 0,  0.02), 1, replace = TRUE, prob = c(1/3, 1/3, 1/3)), list(time_vary_var_high_dim)]
    sim_data = merge(sim_data, age_changes, by = "time_vary_var_high_dim")
    sim_data[, delta_t := delta_t + age_change]

    sim_data[between(time_vary_var_high_dim, -Inf, 10, incbounds = TRUE), time_vary_var_bin := 1]
    sim_data[between(time_vary_var_high_dim, 11, 20, incbounds = TRUE), time_vary_var_bin := 2]
    sim_data[between(time_vary_var_high_dim, 21, 30, incbounds = TRUE), time_vary_var_bin := 3]
    sim_data[between(time_vary_var_high_dim, 31, 40, incbounds = TRUE), time_vary_var_bin := 4]
    sim_data[between(time_vary_var_high_dim, 41, 50, incbounds = TRUE), time_vary_var_bin := 5]
    sim_data[between(time_vary_var_high_dim, 51, 60, incbounds = TRUE), time_vary_var_bin := 6]
    sim_data[between(time_vary_var_high_dim, 61, 70, incbounds = TRUE), time_vary_var_bin := 7]
    sim_data[between(time_vary_var_high_dim, 71, 80, incbounds = TRUE), time_vary_var_bin := 8]
    sim_data[between(time_vary_var_high_dim, 80, Inf, incbounds = TRUE), time_vary_var_bin := 9]

    gc()
  }

  if(time_vary_confounds_cont==TRUE){

    # STILL TO-DO -- CAN THINK ABOUT A POLYNOMIAL IN AGE

  }

  setorderv(sim_data, c("tin", "tax_yr"))
  sim_data[, event_time := tax_yr - win_yr]

  # Have all the ingredients in place to determine the observed outcome, but for structural error
  sim_data[, epsilon := rnorm(dim(sim_data)[1], mean = 0, sd = epsilon_sd)]

  sim_data[, outcome := alpha_e + delta_t + epsilon]
  sim_data[event_time >= 0 & !is.na(win_yr), outcome := outcome + te_0 + (event_time * linear_load) + ((event_time)^2 * quad_load)]
  if(homogeneous_ATT == T & anticipation == T & cohort_specific_anticipation == F){
    sim_data[event_time < 0 & !is.na(win_yr), outcome := outcome + (event_time==(-2))*antic_params[1] + (event_time==(-1))*antic_params[2]]
  } else if(homogeneous_ATT == T & anticipation == T & cohort_specific_anticipation == T){
    sim_data[event_time < 0 & !is.na(win_yr), outcome := outcome + (event_time==(-2))*antic_1 + (event_time==(-1))*antic_2]
  }

  output <- list()
  output[[1]] <- sim_data
  output[[2]] <- params

  if(homogeneous_ATT == T & anticipation == T & cohort_specific_anticipation == T){
    output[[3]] <- cohort_specific_antic_params
  }

  if(time_vary_confounds_high_dim==TRUE){
    output[[4]] <- age_changes
  }

  output[["observed"]] <- sim_data[,list(individual=tin,year=tax_yr,treatment_year=win_yr,outcome=outcome)]

  return(output)
}

ES_simulate_estimator_comparison <- function(units = 1e4,
                                             seed = 1,
                                             oversample_one_year = FALSE,
                                             omitted_event_time = -2,
                                             cohort_specific_trends = FALSE,
                                             correct_pre_trends = FALSE,
                                             anticipation = FALSE,
                                             max_control_gap = Inf,
                                             min_control_gap = 1,
                                             homogeneous_ATT = TRUE,
                                             cohort_specific_anticipation = FALSE,
                                             treated_subset = FALSE,
                                             treated_subset_event_time = -1,
                                             correct_for_treated_subset = FALSE,
                                             control_subset = FALSE,
                                             control_subset_event_time = -1,
                                             correct_for_control_subset = FALSE,
                                             time_vary_confounds_low_dim = FALSE,
                                             time_vary_confounds_high_dim = FALSE,
                                             time_vary_confounds_cont = FALSE,
                                             ipw_composition_change = FALSE,
                                             correct_time_vary_confounds = FALSE,
                                             ipw_covars_discrete = NA,
                                             ipw_covars_cont = NA) {

  set.seed(seed)

  sim_result <- ES_simulate_data(units,
                                 oversample_one_year = oversample_one_year,
                                 cohort_specific_trends = cohort_specific_trends,
                                 anticipation = anticipation,
                                 homogeneous_ATT = homogeneous_ATT,
                                 cohort_specific_anticipation = cohort_specific_anticipation,
                                 treated_subset = treated_subset,
                                 control_subset = control_subset,
                                 time_vary_confounds_low_dim = time_vary_confounds_low_dim,
                                 time_vary_confounds_high_dim = time_vary_confounds_high_dim,
                                 time_vary_confounds_cont = time_vary_confounds_cont)

  long_dt <- copy(sim_result[[1]])

  if (correct_pre_trends == TRUE) {
    long_dt <- ES_parallelize_trends(long_data = sim_result[[1]],outcomevar = "outcome",unit_var="tin",cal_time_var = "tax_yr",onset_time_var = "win_yr"
    )
  }

  if(time_vary_confounds_high_dim == TRUE){
    age_changes <- sim_result[[4]]
  }

  if(correct_time_vary_confounds == TRUE & time_vary_confounds_low_dim == TRUE & is.na(ipw_covars_discrete) & is.na(ipw_covars_cont)){

    long_dt <- ES_residualize_time_varying_covar(long_data = sim_result[[1]],
                                                   outcomevar = "outcome",
                                                   unit_var="tin",
                                                   cal_time_var = "tax_yr",
                                                   onset_time_var = "win_yr",
                                                   time_vary_covar = "time_vary_var")

  }

  params <- sim_result[[2]]

  if(homogeneous_ATT == T & anticipation == T & cohort_specific_anticipation == T){
    cohort_specific_antic_params <- sim_result[[3]]
  }

  if(treated_subset==T & control_subset==F & correct_for_treated_subset==T){
    ES_data <- ES_clean_data(
      long_data = long_dt,
      outcomevar = "outcome",
      unit_var = "tin",
      cal_time_var = "tax_yr",
      onset_time_var = "win_yr",
      min_control_gap = min_control_gap,
      max_control_gap = max_control_gap,
      omitted_event_time = omitted_event_time,
      treated_subset_var = "subset_var",
      treated_subset_event_time = treated_subset_event_time
    )
  } else if(treated_subset==F & control_subset==T & correct_for_control_subset==T){
    ES_data <- ES_clean_data(
      long_data = long_dt,
      outcomevar = "outcome",
      unit_var = "tin",
      cal_time_var = "tax_yr",
      onset_time_var = "win_yr",
      min_control_gap = min_control_gap,
      max_control_gap = max_control_gap,
      omitted_event_time = omitted_event_time,
      control_subset_var = "subset_var",
      control_subset_event_time = control_subset_event_time
    )
  } else if(treated_subset==T & control_subset==T & correct_for_treated_subset==T & correct_for_control_subset==T){
    ES_data <- ES_clean_data(
      long_data = long_dt,
      outcomevar = "outcome",
      unit_var = "tin",
      cal_time_var = "tax_yr",
      onset_time_var = "win_yr",
      min_control_gap = min_control_gap,
      max_control_gap = max_control_gap,
      omitted_event_time = omitted_event_time,
      treated_subset_var = "subset_var",
      treated_subset_event_time = treated_subset_event_time,
      control_subset_var = "subset_var",
      control_subset_event_time = control_subset_event_time
    )
  } else if((time_vary_confounds_high_dim == TRUE | time_vary_confounds_cont == TRUE | !is.na(ipw_covars_discrete) | !is.na(ipw_covars_cont)) & correct_time_vary_confounds == TRUE){
    ES_data <- ES_clean_data(
      long_data = long_dt,
      outcomevar = "outcome",
      unit_var = "tin",
      cal_time_var = "tax_yr",
      onset_time_var = "win_yr",
      min_control_gap = min_control_gap,
      max_control_gap = max_control_gap,
      omitted_event_time = omitted_event_time,
      ipw = TRUE,
      ipw_model = "linear",
      ipw_covars_discrete = ipw_covars_discrete,
      ipw_covars_cont = ipw_covars_cont,
      ipw_composition_change = ipw_composition_change
    )
  } else {
    ES_data <- ES_clean_data(
      long_data = long_dt,
      outcomevar = "outcome",
      unit_var = "tin",
      cal_time_var = "tax_yr",
      onset_time_var = "win_yr",
      min_control_gap = min_control_gap,
      max_control_gap = max_control_gap,
      omitted_event_time = omitted_event_time
    )
  }

  mean2003_2002 = mean(ES_data[win_yr == 2002 & tax_yr == 2003]$outcome)
  mean1999_2002 = mean(ES_data[win_yr == 2002 & tax_yr == 1999]$outcome)
  mean2003_2006 = mean(ES_data[win_yr == 2006 & tax_yr == 2003]$outcome)
  mean1999_2006 = mean(ES_data[win_yr == 2006 & tax_yr == 1999]$outcome)

  event_time_1_coh_2002 = (mean2003_2002 - mean1999_2002) - (mean2003_2006 - mean1999_2006)

  ref_cohort_check = list()
  z = 0
  for(w in sort(unique(ES_data$ref_onset_time))){
    z = z + 1
    ref_cohort_check[[z]] = setorderv(ES_data[ref_onset_time == w, .N, by = c("win_yr", "ref_onset_time", "ref_event_time")], c("win_yr", "ref_onset_time", "ref_event_time"))
  }
  ref_cohort_check = rbindlist(ref_cohort_check, use.names = TRUE)

  # check how we are doing against true values

  ES_results_heterog <- ES_estimate_ATT(
    ES_data = ES_data,
    outcomevar = "outcome",
    onset_time_var = "win_yr",
    cluster_vars = c("tin", "tax_yr"),
    homogeneous_ATT = FALSE,
    omitted_event_time = omitted_event_time,
    ipw = ((time_vary_confounds_high_dim == TRUE | time_vary_confounds_cont == TRUE | !is.na(ipw_covars_discrete) | !is.na(ipw_covars_cont)) & correct_time_vary_confounds == TRUE),
    ipw_composition_change = ipw_composition_change
  )

  ES_results_homog <- ES_estimate_ATT(
    ES_data = ES_data,
    outcomevar = "outcome",
    onset_time_var = "win_yr",
    cluster_vars = c("tin", "tax_yr"),
    homogeneous_ATT = TRUE,
    omitted_event_time = omitted_event_time,
    ipw = ((time_vary_confounds_high_dim == TRUE | time_vary_confounds_cont == TRUE | !is.na(ipw_covars_discrete) | !is.na(ipw_covars_cont)) & correct_time_vary_confounds == TRUE),
    ipw_composition_change = ipw_composition_change

  )

  if(treated_subset==T & control_subset==T & correct_for_treated_subset==T & correct_for_control_subset==T){
    es_results <- ES_estimate_std_did(
      long_data = sim_result[[1]],
      outcomevar = "outcome",
      unit_var = "tin",
      cal_time_var = "tax_yr",
      onset_time_var = "win_yr",
      correct_pre_trends = correct_pre_trends,
      omitted_event_time = omitted_event_time,
      cluster_vars = NULL,
      std_subset_var = "subset_var",
      std_subset_event_time = -1,
      correct_time_vary_confounds = correct_time_vary_confounds,
      time_vary_covar = "time_vary_var"
    )
  } else{
    es_results <- ES_estimate_std_did(
      long_data = sim_result[[1]],
      outcomevar = "outcome",
      unit_var = "tin",
      cal_time_var = "tax_yr",
      onset_time_var = "win_yr",
      correct_pre_trends = correct_pre_trends,
      omitted_event_time = omitted_event_time,
      cluster_vars = NULL,
      correct_time_vary_confounds = correct_time_vary_confounds,
      time_vary_covar = "time_vary_var"
    )
  }

  figdata <- rbindlist(list(ES_results_heterog, ES_results_homog, es_results), use.names = TRUE)

  if(homogeneous_ATT==T & cohort_specific_anticipation==F){

    # getting true value in
    figdata_temp <- copy(figdata)
    figdata_temp[, te_0 := params[1]]
    figdata_temp[, linear_load := params[2]]
    figdata_temp[, quad_load := params[3]]
    figdata_temp[event_time < 0, true_value := 0]
    if(anticipation){
      figdata_temp[event_time < 0, true_value := (event_time==(-2))*params[4] + (event_time==(-1))*params[5]]
    }
    figdata_temp[event_time >= 0, true_value := te_0 + (event_time * linear_load) + ((event_time)^2 * quad_load)]

    figdata_temp <- figdata_temp[win_yr == "Standard DiD"]
    figdata_temp <- figdata_temp[, list(rn, win_yr, event_time, true_value)]
    figdata_temp[win_yr == "Standard DiD", win_yr := "True Value"]
    setnames(figdata_temp, c("true_value"), c("estimate"))

    figdata <- rbindlist(list(figdata, figdata_temp), use.names = TRUE, fill = TRUE)
    figdata[is.na(cluster_se), cluster_se := 0]

    figdata[, jitter := .GRP, by = win_yr]

    fig <- ggplot(aes(
      x = event_time + (jitter - 3.5) / 14,
      y = estimate, colour = factor(win_yr)
    ), data = figdata) + geom_point() + theme_bw(base_size = 16) +
      geom_errorbar(aes(ymin = estimate - 1.96 * cluster_se, ymax = estimate + 1.96 * cluster_se)) +
      scale_x_continuous(breaks = pretty_breaks()) +
      labs(x = "Event Time", y = "ATT", color = "Estimator") +
      annotate(geom = "text", x = omitted_event_time, y = 0, label = "(Omitted)", size = 4)

    event_time_1_coh_2002 = c(event_time_1_coh_2002, figdata[win_yr == "True Value" & event_time == 1]$estimate)
    names(event_time_1_coh_2002) <- c("by_hand_DiD", "true_value")

    results = list()
    results[[1]] = fig
    results[[2]] = ref_cohort_check
    results[[3]] = event_time_1_coh_2002

  } else if(homogeneous_ATT==T & anticipation==T & cohort_specific_anticipation==T){

    # getting true value in
    figdata_temp <- copy(figdata)
    figdata_temp[, te_0 := params[1]]
    figdata_temp[, linear_load := params[2]]
    figdata_temp[, quad_load := params[3]]
    figdata_temp[event_time < 0, true_value := 0]
    if(anticipation == T & cohort_specific_anticipation == F){
      figdata_temp[event_time < 0, true_value := (event_time==(-2))*params[4] + (event_time==(-1))*params[5]]
    }
    figdata_temp[event_time >= 0, true_value := te_0 + (event_time * linear_load) + ((event_time)^2 * quad_load)]

    figdata_temp = merge(figdata_temp, cohort_specific_antic_params, by = "win_yr", all = TRUE)
    figdata_temp[between(event_time, omitted_event_time, 0, incbounds = FALSE), true_value := (event_time==(-2))*antic_1 + (event_time==(-1))*antic_2]
    figdata_temp[event_time <= omitted_event_time, true_value := 0]

    figdata_temp <- figdata_temp[win_yr == "Standard DiD"]
    figdata_temp <- figdata_temp[, list(rn, win_yr, event_time, true_value)]
    figdata_temp[win_yr == "Standard DiD", win_yr := "True Value"]
    setnames(figdata_temp, c("true_value"), c("estimate"))

    figdata <- rbindlist(list(figdata, figdata_temp), use.names = TRUE, fill = TRUE)
    figdata[is.na(cluster_se), cluster_se := 0]

    figdata = merge(figdata, cohort_specific_antic_params, by = "win_yr", all = TRUE)
    figdata[between(event_time, omitted_event_time, 0, incbounds = FALSE), true_value := (event_time==(-2))*antic_1 + (event_time==(-1))*antic_2]
    figdata[event_time <= omitted_event_time & !(win_yr %in% c("Pooled", "Standard DiD", "True Value")), true_value := NA]

    figdata[, jitter := .GRP, by = win_yr]

    fig <- ggplot(aes(
      x = event_time + (jitter - 3.5) / 14,
      y = estimate, colour = factor(win_yr)
    ), data = figdata) + geom_point() + theme_bw(base_size = 16) +
      geom_errorbar(aes(ymin = estimate - 1.96 * cluster_se, ymax = estimate + 1.96 * cluster_se)) +
      geom_point(aes(y = true_value), color = "#000000", shape = 4)+
      scale_x_continuous(breaks = pretty_breaks()) +
      labs(x = "Event Time", y = "ATT", color = "Win Year") +
      annotate(geom = "text", x = omitted_event_time, y = 0, label = "(Omitted)", size = 4)

    event_time_1_coh_2002 = c(event_time_1_coh_2002, figdata[win_yr == "True Value" & event_time == 1]$estimate)
    names(event_time_1_coh_2002) <- c("by_hand_DiD", "true_value")

    results = list()
    results[[1]] = fig
    results[[2]] = ref_cohort_check
    results[[3]] = event_time_1_coh_2002

  } else{

    # getting true value in
    figdata_temp <- copy(figdata)
    figdata_temp = merge(figdata_temp, params, by = "win_yr", all = TRUE)
    figdata_temp[event_time < 0 & !(win_yr %in% c("Pooled", "Standard DiD")), true_value := 0]
    figdata_temp[event_time >= 0, true_value := te_0 + (event_time * linear_load) + ((event_time)^2 * quad_load)]

    figdata_temp[, jitter := .GRP, by = win_yr]

    fig <- ggplot(aes(
      x = event_time + (jitter - 3.5) / 14,
      y = estimate, colour = factor(win_yr)
    ), data = figdata_temp) + geom_point() + theme_bw(base_size = 16) +
      geom_errorbar(aes(ymin = estimate - 1.96 * cluster_se, ymax = estimate + 1.96 * cluster_se)) +
      geom_point(aes(y = true_value), color = "#000000", shape = 4)+
      scale_x_continuous(breaks = pretty_breaks()) +
      labs(x = "Event Time", y = "ATT", color = "Estimator") +
      annotate(geom = "text", x = omitted_event_time, y = 0, label = "(Omitted)", size = 4)

    results = list()
    results[[1]] = fig
    results[[2]] = ref_cohort_check

  }

  return(results)
}
