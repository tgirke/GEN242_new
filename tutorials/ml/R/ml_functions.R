## ml_functions.R — helper functions for ml_tutorial.qmd
## Organized by section: Data, Exploratory, Random Forest, XGBoost, SVM,
## Model Comparison, DE Comparison.
##
## Load order: source this file AFTER loading all packages so that caret::train
## is already registered and the conflictRules() call in the QMD has taken effect.

# ── Data loading and preparation ──────────────────────────────────────────────

#' Load and VST-normalize the airway RNA-Seq dataset
#'
#' Strips ExperimentHub metadata to avoid nvimcom GlobalEnv scanner crash,
#' runs DESeq2 VST normalization, and assembles sample metadata.
#'
#' @return Named list: expr_mat (genes × samples), meta (data.frame with
#'   columns dex, cell, label), dds (DESeqDataSet, size-factors estimated).
load_airway_data <- function() {
  library(DESeq2)
  library(airway)
  data(airway)
  # Remove ExperimentHub reference — causes slotNames() crash in some editors
  metadata(airway) <- list()
  dds <- DESeqDataSet(airway, design = ~ dex)
  dds <- estimateSizeFactors(dds)
  vsd <- vst(dds, blind = TRUE)
  expr_mat <- assay(vsd)
  meta <- as.data.frame(colData(airway)) |>
    dplyr::select(dex, cell) |>
    dplyr::mutate(label = ifelse(dex == "trt", "Treated", "Untreated"))
  list(expr_mat = expr_mat, meta = meta, dds = dds)
}

#' Load and VST-normalize the fission RNA-Seq dataset
#'
#' S. pombe time-course: wild-type (wt) and atf21-delta mutant (mut) cells at
#' 6 time points (0-180 min) under oxidative stress, 3 replicates each (n=36).
#' Classification target: strain (WT vs Mut).
#'
#' @return Named list: expr_mat (genes x samples), meta (data.frame with
#'   columns strain, minute, replicate, label), dds (DESeqDataSet, size-factors estimated).
load_fission_data <- function() {
  library(DESeq2)
  library(fission)
  data(fission)
  dds <- DESeqDataSet(fission, design = ~ strain)
  dds <- estimateSizeFactors(dds)
  vsd <- vst(dds, blind = TRUE)
  expr_mat <- assay(vsd)
  meta <- as.data.frame(colData(fission)) |>
    dplyr::select(strain, minute, replicate) |>
    dplyr::mutate(label = ifelse(as.character(strain) == "wt", "WT", "Mut"))
  list(expr_mat = expr_mat, meta = meta, dds = dds)
}

#' Load and log2-normalize TCGA BRCA RNA-Seq data with PAM50 subtype labels
#'
#' Downloads upper-quartile-normalized BRCA expression and PAM50 subtype
#' annotations via curatedTCGAData (RNASeq2GeneNorm assay). Applies
#' log2(x + 1) transformation, subsamples to n_per_subtype per subtype
#' (Basal, HER2, LumA, LumB), and caches to an RDS file for fast re-loading.
#'
#' Requires: BiocManager::install("curatedTCGAData")
#'
#' @param n_per_subtype Max samples per PAM50 subtype (default 75L; limited by HER2 ~80).
#' @param cache_file    Path for cached expression matrix + labels.
#' @param seed          Random seed for subsampling (default 42).
#' @return Named list: expr_mat (genes x samples log2 matrix), meta (data.frame
#'   with label column), dds (NULL; kept for API compatibility).
load_brca_data <- function(n_per_subtype = 75L,
                           cache_file    = "data/brca_subtypes.rds",
                           seed          = 42L) {
  library(curatedTCGAData)
  library(MultiAssayExperiment)

  if (file.exists(cache_file)) {
    message("Loading from cache: ", cache_file)
    cached   <- readRDS(cache_file)
    expr_mat <- cached$expr_mat
    labels   <- unname(cached$labels)
  } else {
    message("Downloading TCGA BRCA via curatedTCGAData (first run only, ~3-5 min) ...")
    dir.create(dirname(cache_file), showWarnings = FALSE, recursive = TRUE)

    mae <- curatedTCGAData::curatedTCGAData(
      "BRCA", assays = "RNASeq2GeneNorm", dry.run = FALSE, version = "2.1.1"
    )

    # Extract the normalized expression experiment
    exp_name <- names(mae)[grepl("RNASeq2GeneNorm", names(mae))][1]
    message("Using experiment: ", exp_name)
    se <- mae[[exp_name]]

    # Clinical data and PAM50 column
    clin      <- as.data.frame(MultiAssayExperiment::colData(mae))
    pam50_col <- grep("PAM50|pam50", names(clin), value = TRUE)
    if (length(pam50_col) == 0)
      stop("No PAM50 column. First 40 names: ", paste(head(names(clin), 40), collapse = ", "))
    pam50_col <- if ("paper_BRCA_Subtype_PAM50" %in% pam50_col)
      "paper_BRCA_Subtype_PAM50" else pam50_col[1]

    # Use MAE sampleMap to get patient IDs — more reliable than barcode substring
    sm         <- as.data.frame(MultiAssayExperiment::sampleMap(mae))
    sm_exp     <- sm[sm$assay == exp_name, ]
    patient_ids <- sm_exp$primary[match(colnames(se), sm_exp$colname)]

    pam50_vals  <- clin[[pam50_col]][match(patient_ids, rownames(clin))]
    label_map   <- c("Basal-like"    = "Basal", "Basal" = "Basal",
                     "HER2-enriched" = "HER2",  "Her2"  = "HER2",
                     "Luminal A"     = "LumA",  "LumA"  = "LumA",
                     "Luminal B"     = "LumB",  "LumB"  = "LumB")
    subtypes    <- label_map[as.character(pam50_vals)]

    # Write diagnostics to file for inspection
    diag_df <- data.frame(
      colname     = head(colnames(se), 10),
      patient_id  = head(patient_ids,  10),
      pam50_raw   = head(as.character(pam50_vals), 10),
      subtype_map = head(subtypes,     10)
    )
    write.csv(diag_df, file.path(dirname(cache_file), "brca_debug.csv"))
    message("PAM50 distribution (all patients): ")
    print(table(clin[[pam50_col]], useNA = "ifany"))
    message("Mapped subtypes (", sum(!is.na(subtypes)), " / ", length(subtypes), " matched):")
    print(table(subtypes, useNA = "ifany"))

    if (sum(!is.na(subtypes)) == 0)
      stop("Label mapping failed. Diagnostics written to ",
           file.path(dirname(cache_file), "brca_debug.csv"))

    # Filter to matched subtypes only (curatedTCGAData RNA-Seq is already primary tumor)
    keep     <- !is.na(subtypes)
    se       <- se[, keep]
    subtypes <- subtypes[keep]

    # Subsample to balance classes
    set.seed(seed)
    idx <- unlist(lapply(c("Basal", "HER2", "LumA", "LumB"), function(s) {
      i <- which(subtypes == s)
      sample(i, min(n_per_subtype, length(i)))
    }))
    se       <- se[, idx]
    subtypes <- subtypes[idx]
    message("After subsampling (", ncol(se), " samples):")
    print(table(subtypes))

    # log2(x + 1) normalization — data is already UQ-normalized
    expr_mat <- log2(as.matrix(assay(se, 1)) + 1)
    labels   <- unname(subtypes)

    saveRDS(list(expr_mat = expr_mat, labels = labels), cache_file)
    message("Cached to: ", cache_file, " (",
            round(file.size(cache_file) / 1e6, 1), " MB)")
  }

  message("Genes: ", nrow(expr_mat), " | Samples: ", ncol(expr_mat))
  meta <- data.frame(label = factor(labels), row.names = colnames(expr_mat))
  list(expr_mat = expr_mat, meta = meta, dds = NULL)
}

#' Select features: top variable signal genes mixed with random noise genes
#'
#' Keeps the top n_signal most variable genes as true signal, then randomly
#' samples n_noise genes from the remainder as noise. Near-zero-variance genes
#' (var < 1e-8) are excluded from the noise pool to prevent prcomp(scale.=TRUE)
#' errors on constant columns.
#'
#' @param expr_mat Genes × samples expression matrix.
#' @param meta     Sample metadata data.frame with a \code{label} column.
#' @param n_signal Number of top-variance genes to include as signal (default 50).
#' @param n_noise  Number of random genes to include as noise (default 450).
#' @param seed     Random seed for reproducibility (default 42).
#' @return Named list: X (samples × features matrix), y (factor response),
#'   top_signal (signal gene names), noise_genes (noise gene names).
select_features <- function(expr_mat, meta, n_signal = 50, n_noise = 450, seed = 42) {
  set.seed(seed)
  gene_vars        <- apply(expr_mat, 1, var)
  all_genes_sorted <- names(sort(gene_vars, decreasing = TRUE))
  top_signal       <- all_genes_sorted[seq_len(n_signal)]
  noise_pool       <- all_genes_sorted[(n_signal + 1):length(all_genes_sorted)]
  noise_pool       <- noise_pool[gene_vars[noise_pool] > 1e-8]
  noise_genes      <- sample(noise_pool, n_noise)
  X <- t(expr_mat[c(top_signal, noise_genes), ])
  y <- factor(meta$label)
  list(X = X, y = y, top_signal = top_signal, noise_genes = noise_genes)
}

#' Simulate a binary classification dataset with controlled signal and noise
#'
#' The first n_signal columns carry a mean shift of effect_size SD units between
#' classes; the remaining columns are pure noise. Column names are Gene1…GeneN.
#'
#' @param n_samples   Number of samples (default 200, balanced 50/50).
#' @param n_features  Total number of features (default 500).
#' @param n_signal    Number of features with true signal (default 20).
#' @param effect_size Mean shift for signal features in SD units (default 0.8).
#' @param seed        Random seed (default 123).
#' @return Named list: X_sim (n_samples × n_features matrix), y_sim (factor),
#'   y_sim_int (integer 0/1 label vector).
simulate_data <- function(n_samples   = 200,
                          n_features  = 500,
                          n_signal    = 20,
                          effect_size = 0.8,
                          seed        = 123) {
  set.seed(seed)
  X_sim     <- matrix(rnorm(n_samples * n_features), nrow = n_samples)
  y_sim_int <- rep(c(0L, 1L), each = n_samples / 2)
  X_sim[, seq_len(n_signal)] <- X_sim[, seq_len(n_signal)] +
    outer(y_sim_int, rep(1, n_signal)) * effect_size
  y_sim <- factor(ifelse(y_sim_int == 1L, "Case", "Control"))
  colnames(X_sim) <- paste0("Gene", seq_len(n_features))
  list(X_sim = X_sim, y_sim = y_sim, y_sim_int = y_sim_int)
}

#' Build a caret trainControl for stratified k-fold CV
#'
#' Saves final held-out predictions so ROC curves can be computed from the
#' cross-validated probabilities without a separate prediction step.
#'
#' @param k Number of CV folds (default 5).
#' @return A \code{trainControl} object.
make_cv_control <- function(k = 5) {
  caret::trainControl(
    method          = "cv",
    number          = k,
    classProbs      = TRUE,
    summaryFunction = caret::multiClassSummary,
    savePredictions = "final"
  )
}

# ── Exploratory analysis ──────────────────────────────────────────────────────

#' PCA plot of the feature matrix coloured by class label
#'
#' @param X            Samples x features matrix (passed to prcomp with scale.=TRUE).
#' @param meta         Sample metadata data.frame with a \code{label} column.
#' @param shape_col    Name of a meta column to use for point shape (default NULL = no shape).
#' @param color_values Named character vector mapping label levels to colours (default NULL = ggplot defaults).
#' @param color_label  Legend title for the colour aesthetic (default "Condition").
#' @param shape_label  Legend title for the shape aesthetic (default shape_col value).
#' @return A ggplot object.
plot_pca <- function(X, meta,
                     shape_col    = NULL,
                     color_values = NULL,
                     color_label  = "Condition",
                     shape_label  = NULL) {
  pca_res       <- prcomp(X, scale. = TRUE)
  var_explained <- summary(pca_res)$importance[2, 1:2] * 100
  pca_df        <- as.data.frame(pca_res$x[, 1:2]) |>
    dplyr::mutate(label = meta$label)
  if (!is.null(shape_col)) pca_df$shape_var <- meta[[shape_col]]

  p <- ggplot2::ggplot(pca_df, ggplot2::aes(x = PC1, y = PC2, color = label)) +
    ggplot2::geom_point(size = 4, alpha = 0.9) +
    ggplot2::labs(
      title = "PCA of Mixed Feature Set (50 signal + 450 noise genes)",
      x     = paste0("PC1 (", round(var_explained[1], 1), "% variance)"),
      y     = paste0("PC2 (", round(var_explained[2], 1), "% variance)"),
      color = color_label
    ) +
    ggplot2::theme_bw(base_size = 13)

  if (!is.null(color_values))
    p <- p + ggplot2::scale_color_manual(values = color_values)

  if (!is.null(shape_col)) {
    p <- p +
      ggplot2::aes(shape = shape_var) +
      ggplot2::labs(shape = if (!is.null(shape_label)) shape_label else shape_col)
  }
  p
}

#' Annotated heatmap of selected genes from the expression matrix
#'
#' @param expr_mat      Genes x samples expression matrix.
#' @param top_signal    Character vector of gene names to display (rows).
#' @param meta          Sample metadata data.frame with a \code{label} column.
#' @param extra_col     Name of a second meta column to annotate (default NULL).
#' @param color_values  Named vector of colours for the label levels (default NULL).
#' @param extra_colors  Named vector of colours for extra_col levels (default NULL).
#' @param extra_label   Display name for the extra column in the legend (default extra_col).
plot_heatmap <- function(expr_mat, top_signal, meta,
                         extra_col    = NULL,
                         color_values = NULL,
                         extra_colors = NULL,
                         extra_label  = NULL) {
  ann_col <- data.frame(Condition = meta$label, row.names = rownames(meta))
  if (!is.null(extra_col)) {
    lbl <- if (!is.null(extra_label)) extra_label else extra_col
    ann_col[[lbl]] <- meta[[extra_col]]
  }
  ann_colors <- list()
  if (!is.null(color_values)) ann_colors$Condition <- color_values
  if (!is.null(extra_col) && !is.null(extra_colors)) {
    lbl <- if (!is.null(extra_label)) extra_label else extra_col
    ann_colors[[lbl]] <- extra_colors
  }
  pheatmap::pheatmap(
    expr_mat[top_signal, ],
    annotation_col    = ann_col,
    annotation_colors = if (length(ann_colors) > 0) ann_colors else NA,
    scale             = "row",
    show_rownames     = FALSE,
    fontsize_col      = 10,
    main              = "Top 50 Most Variable Genes (signal component)"
  )
}

# ── Random Forest ─────────────────────────────────────────────────────────────

#' Train a Random Forest classifier via caret with k-fold CV
#'
#' Calls caret::train() explicitly to avoid the generics::train() masking issue
#' that occurs when DESeq2 dependencies are loaded.
#'
#' @param X         Samples × features matrix.
#' @param y         Factor response variable.
#' @param ctrl      trainControl object from \code{make_cv_control()}.
#' @param mtry_grid Integer vector of mtry values to search (default c(10,22,50)).
#' @param seed      Random seed (default 42).
#' @return A trained caret model object.
train_rf <- function(X, y, ctrl, mtry_grid = c(10L, 22L, 50L), seed = 42) {
  set.seed(seed)
  caret::train(
    x          = X,
    y          = y,
    method     = "rf",
    trControl  = ctrl,
    metric     = "AUC",
    tuneGrid   = data.frame(mtry = mtry_grid),
    importance = TRUE
  )
}

#' Plot top genes by Random Forest variable importance
#'
#' @param rf_model     Trained caret RF model object.
#' @param top_n        Number of top genes to show (default 20).
#' @param signal_genes Character vector of true signal gene names for annotation;
#'   pass NULL to omit annotation (default NULL).
#' @return A ggplot object.
plot_rf_importance <- function(rf_model, top_n = 20, signal_genes = NULL) {
  imp    <- caret::varImp(rf_model)$importance
  imp_df <- data.frame(
    Gene       = rownames(imp),
    Importance = rowMeans(imp)
  ) |>
    dplyr::arrange(dplyr::desc(Importance)) |>
    head(top_n) |>
    dplyr::mutate(
      Signal = if (!is.null(signal_genes)) {
        ifelse(Gene %in% signal_genes, "Signal", "Noise")
      } else {
        "Feature"
      }
    )
  ggplot2::ggplot(imp_df,
                  ggplot2::aes(x = reorder(Gene, Importance),
                               y = Importance, fill = Signal)) +
    ggplot2::geom_col(alpha = 0.85) +
    ggplot2::scale_fill_manual(
      values = c(Signal = "#E63946", Noise = "#888780", Feature = "#457B9D")) +
    ggplot2::coord_flip() +
    ggplot2::labs(
      title    = paste("Top", top_n, "Genes by Random Forest Importance"),
      subtitle = if (!is.null(signal_genes))
        "Red = true signal genes (Gene1\u2013Gene20), grey = noise" else NULL,
      x = "Gene", y = "Mean Decrease in Gini", fill = NULL
    ) +
    ggplot2::theme_bw(base_size = 12)
}

# ── XGBoost ───────────────────────────────────────────────────────────────────

#' Default XGBoost hyperparameters for small n (logloss metric, fixed nrounds)
#'
#' Uses logloss rather than AUC because logloss is defined per sample whereas
#' AUC requires both classes to be present in a fold — not guaranteed at n=8.
#'
#' @return Named list of xgboost parameters.
xgb_params_small_n <- function() {
  list(
    objective        = "binary:logistic",
    eval_metric      = "logloss",
    eta              = 0.1,
    max_depth        = 2,     # shallow trees — robust at small n
    subsample        = 0.8,
    colsample_bytree = 0.8
  )
}

#' Default XGBoost hyperparameters for moderate / large n (AUC metric)
#'
#' @return Named list of xgboost parameters.
xgb_params_large_n <- function() {
  list(
    objective        = "binary:logistic",
    eval_metric      = "auc",
    eta              = 0.05,
    max_depth        = 3,
    subsample        = 0.8,
    colsample_bytree = 0.5,
    min_child_weight = 5
  )
}

#' XGBoost hyperparameters for multiclass classification (softprob + mlogloss)
#'
#' @param num_class Number of classes (default 4).
#' @return Named list of xgboost parameters.
xgb_params_multiclass <- function(num_class = 4L) {
  list(
    objective        = "multi:softprob",
    num_class        = num_class,
    eval_metric      = "mlogloss",
    eta              = 0.05,
    max_depth        = 4L,
    subsample        = 0.8,
    colsample_bytree = 0.5,
    min_child_weight = 5
  )
}

#' Leave-one-out CV for XGBoost on small datasets
#'
#' With n=8 LOOCV is the only evaluation strategy that guarantees both classes
#' appear in training. Uses xgb.train() (not the higher-level xgboost() wrapper)
#' for compatibility across recent xgboost versions.
#'
#' @param X              Samples × features matrix.
#' @param y              Factor response variable.
#' @param positive_class Name of the positive class level.
#' @param params         xgboost parameter list (default \code{xgb_params_small_n()}).
#' @param nrounds        Number of boosting rounds (default 50).
#' @param seed           Random seed (default 42).
#' @return Numeric vector of leave-one-out predicted probabilities (length = nrow(X)).
xgb_loocv <- function(X, y, positive_class,
                      params  = xgb_params_small_n(),
                      nrounds = 50L,
                      seed    = 42) {
  set.seed(seed)
  probs <- numeric(nrow(X))
  for (i in seq_len(nrow(X))) {
    dtrain <- xgboost::xgb.DMatrix(
      data  = X[-i, , drop = FALSE],
      label = as.integer(y[-i] == positive_class)
    )
    dtest    <- xgboost::xgb.DMatrix(data = X[i, , drop = FALSE])
    m        <- xgboost::xgb.train(params  = params, data    = dtrain,
                                   nrounds = nrounds, verbose = 0)
    probs[i] <- predict(m, dtest)
  }
  probs
}

#' Tune XGBoost nrounds via xgb.cv with early stopping (Stage 1 of 3)
#'
#' @param X_sim                Samples × features matrix.
#' @param y_sim_int            Integer label vector (0/1).
#' @param params               xgboost parameter list (default \code{xgb_params_large_n()}).
#' @param nrounds_max          Maximum rounds to search (default 500).
#' @param nfold                Number of CV folds (default 5).
#' @param early_stopping_rounds Stop if no improvement after this many rounds (default 20).
#' @return Optimal nrounds as an integer; prints best CV AUC as a side effect.
tune_xgb_nrounds <- function(X_sim, y_sim_int,
                             params                = xgb_params_large_n(),
                             nrounds_max           = 500L,
                             nfold                 = 5L,
                             early_stopping_rounds = 20L) {
  dtrain     <- xgboost::xgb.DMatrix(data = X_sim, label = y_sim_int)
  cv_res     <- xgboost::xgb.cv(
    params                = params,
    data                  = dtrain,
    nrounds               = nrounds_max,
    nfold                 = nfold,
    stratified            = TRUE,
    early_stopping_rounds = early_stopping_rounds,
    verbose               = FALSE
  )
  metric     <- params$eval_metric          # e.g. "auc" or "mlogloss"
  metric_col <- paste0("test_", metric, "_mean")
  maximize   <- metric == "auc"
  best <- if (!is.null(cv_res$best_iteration) && !is.na(cv_res$best_iteration)) {
    cv_res$best_iteration
  } else if (maximize) {
    which.max(cv_res$evaluation_log[[metric_col]])
  } else {
    which.min(cv_res$evaluation_log[[metric_col]])
  }
  best_val <- cv_res$evaluation_log[[metric_col]][best]
  cat("Optimal nrounds:", best, "| Best CV", toupper(metric), ":",
      round(best_val, 4), "\n")
  best
}

#' k-fold CV loop for XGBoost: returns held-out probabilities (Stage 2 of 3)
#'
#' For binary classification returns a length-n numeric vector.
#' For multiclass (params$num_class > 2) returns an n x K matrix with
#' column names matching levels(y_sim).
#'
#' @param X_sim        Samples x features matrix.
#' @param y_sim        Factor response variable (for stratified fold creation).
#' @param y_sim_int    Integer label vector (0-indexed).
#' @param params       xgboost parameter list.
#' @param best_nrounds Optimal nrounds from \code{tune_xgb_nrounds()}.
#' @param k            Number of folds (default 5).
#' @param seed         Random seed (default 42).
#' @return Numeric vector (binary) or n x K matrix (multiclass).
xgb_cv_probs <- function(X_sim, y_sim, y_sim_int,
                         params       = xgb_params_large_n(),
                         best_nrounds,
                         k            = 5L,
                         seed         = 42) {
  set.seed(seed)
  folds     <- caret::createFolds(y_sim, k = k, returnTrain = FALSE)
  num_class <- params$num_class
  is_multi  <- !is.null(num_class) && num_class > 2L
  probs     <- if (is_multi) {
    m <- matrix(0, nrow = nrow(X_sim), ncol = num_class)
    colnames(m) <- levels(y_sim)
    m
  } else {
    numeric(nrow(X_sim))
  }
  for (fold in folds) {
    dtrain_f <- xgboost::xgb.DMatrix(
      data  = X_sim[-fold, , drop = FALSE],
      label = y_sim_int[-fold]
    )
    dtest_f <- xgboost::xgb.DMatrix(data = X_sim[fold, , drop = FALSE])
    m_f     <- xgboost::xgb.train(params  = params, data    = dtrain_f,
                                   nrounds = best_nrounds, verbose = 0)
    raw     <- predict(m_f, dtest_f)
    if (is_multi) {
      # Recent xgboost (>=1.7) returns a matrix (n x num_class) directly;
      # older versions return a flat vector in sample-major order (byrow=FALSE).
      if (is.matrix(raw)) {
        probs[fold, ] <- raw
      } else {
        probs[fold, ] <- matrix(raw, nrow = length(fold), ncol = num_class,
                                byrow = FALSE)
      }
    } else {
      probs[fold] <- raw
    }
  }
  probs
}

#' Train a final XGBoost model on all data for feature importance (Stage 3 of 3)
#'
#' @param X_sim     Samples × features matrix.
#' @param y_sim_int Integer label vector (0/1).
#' @param params    xgboost parameter list (default \code{xgb_params_large_n()}).
#' @param nrounds   Number of boosting rounds (from \code{tune_xgb_nrounds()}).
#' @return A trained \code{xgb.Booster} object.
train_xgb_final <- function(X_sim, y_sim_int,
                            params  = xgb_params_large_n(),
                            nrounds) {
  dtrain <- xgboost::xgb.DMatrix(data = X_sim, label = y_sim_int)
  xgboost::xgb.train(params = params, data = dtrain,
                     nrounds = nrounds, verbose = 0)
}

# ── SVM ───────────────────────────────────────────────────────────────────────

#' Train an SVM (RBF kernel) classifier via caret with k-fold CV
#'
#' Centers and scales features internally via caret's preProcess argument;
#' hyperparameters C and sigma are tuned by grid search over tune_length
#' combinations. Calls caret::train() explicitly to avoid generics masking.
#'
#' @param X           Samples × features matrix.
#' @param y           Factor response variable.
#' @param ctrl        trainControl object from \code{make_cv_control()}.
#' @param tune_length Number of hyperparameter combinations to try (default 5).
#' @param seed        Random seed (default 42).
#' @return A trained caret model object.
train_svm <- function(X, y, ctrl, tune_length = 5L, seed = 42) {
  set.seed(seed)
  caret::train(
    x          = X,
    y          = y,
    method     = "svmRadial",
    trControl  = ctrl,
    metric     = "AUC",
    preProcess = c("center", "scale"),
    tuneLength = tune_length
  )
}

# ── Model comparison ──────────────────────────────────────────────────────────

#' One-vs-rest ROC curves for three classifiers on a multiclass problem
#'
#' Plots a 2x2 panel grid (one per class). Each panel shows RF, XGBoost, and
#' SVM one-vs-rest ROC curves with per-class AUC in the legend.
#'
#' @param y_true    Factor of true class labels (K levels).
#' @param rf_probs  n x K probability matrix (columns = class levels).
#' @param xgb_probs n x K probability matrix.
#' @param svm_probs n x K probability matrix.
#' @param title     Overall plot title.
#' @return Invisibly, nested list roc_all[[class]][[model]].
plot_roc_multiclass <- function(y_true, rf_probs, xgb_probs, svm_probs,
                                title = "One-vs-Rest ROC Curves \u2014 5-fold CV") {
  classes  <- levels(y_true)
  colors   <- c(RF = "#E63946", XGBoost = "#2A9D8F", SVM = "#F4A261")
  old_par  <- par(mfrow = c(2L, 2L), mar = c(4, 4, 3, 1), oma = c(0, 0, 2, 0))
  on.exit(par(old_par))
  roc_all  <- list()
  for (cls in classes) {
    binary  <- as.integer(y_true == cls)
    roc_rf  <- pROC::roc(binary, rf_probs[, cls],  quiet = TRUE)
    roc_xgb <- pROC::roc(binary, xgb_probs[, cls], quiet = TRUE)
    roc_svm <- pROC::roc(binary, svm_probs[, cls],  quiet = TRUE)
    roc_all[[cls]] <- list(RF = roc_rf, XGBoost = roc_xgb, SVM = roc_svm)
    pROC::plot.roc(roc_rf,  col = colors["RF"],      lwd = 2, main = cls)
    pROC::plot.roc(roc_xgb, col = colors["XGBoost"], lwd = 2, add = TRUE)
    pROC::plot.roc(roc_svm, col = colors["SVM"],     lwd = 2, add = TRUE)
    legend("bottomright",
           legend = sprintf("%s (%.3f)", names(colors),
                            c(pROC::auc(roc_rf), pROC::auc(roc_xgb),
                              pROC::auc(roc_svm))),
           col = colors, lwd = 2, cex = 0.75, bty = "n")
  }
  title(title, outer = TRUE)
  invisible(roc_all)
}

#' Build a model performance summary for knitr::kable (multiclass)
#'
#' Computes multiclass AUC (Hand-Till method) via pROC::multiclass.roc().
#'
#' @param y_true    Factor of true class labels.
#' @param rf_probs  n x K probability matrix.
#' @param xgb_probs n x K probability matrix.
#' @param svm_probs n x K probability matrix.
#' @param rf_model  Trained caret RF model (for bestTune$mtry).
#' @param svm_model Trained caret SVM model (for bestTune C and sigma).
#' @param best_nrounds Optimal XGBoost nrounds.
#' @return data.frame with columns Model, AUC_multiclass, Best_params.
make_perf_summary <- function(y_true, rf_probs, xgb_probs, svm_probs,
                              rf_model, svm_model, best_nrounds) {
  auc_rf  <- as.numeric(pROC::auc(pROC::multiclass.roc(y_true, rf_probs,  quiet = TRUE)))
  auc_xgb <- as.numeric(pROC::auc(pROC::multiclass.roc(y_true, xgb_probs, quiet = TRUE)))
  auc_svm <- as.numeric(pROC::auc(pROC::multiclass.roc(y_true, svm_probs, quiet = TRUE)))
  data.frame(
    Model          = c("Random Forest", "XGBoost", "SVM"),
    AUC_multiclass = round(c(auc_rf, auc_xgb, auc_svm), 3),
    Best_params    = c(
      paste("mtry =", rf_model$bestTune$mtry),
      paste("nrounds =", best_nrounds),
      paste("C =", round(svm_model$bestTune$C,     3),
            "| sigma =", round(svm_model$bestTune$sigma, 4))
    )
  )
}

# ── SHAP values (treeshap / shapviz) ─────────────────────────────────────────

# Internal helper: normalise raw treeshap $shaps output and build shapviz /
# mshapviz objects directly from their list structure, bypassing S3 dispatch.
# Older shapviz versions lack shapviz.matrix / shapviz.default, so we avoid
# those entry points entirely.
.treeshap_to_sv <- function(shap, X_df) {
  n <- nrow(X_df)
  S <- shap$shaps

  # data.frame internals look like a list to is.list(); convert first
  if (is.data.frame(S)) S <- as.matrix(S)

  # Zero-fill NAs (treeshap returns NA when a feature is absent from a tree path)
  if (is.list(S)) {
    S <- lapply(S, function(m) { m[is.na(m)] <- 0; m })
  } else {
    S[is.na(S)] <- 0
    # Some treeshap versions stack K classes into one (n*K)×p matrix; split it
    if (nrow(S) != n && nrow(S) %% n == 0L) {
      K <- nrow(S) %/% n
      S <- lapply(seq_len(K), function(k)
        S[seq.int((k - 1L) * n + 1L, k * n), , drop = FALSE])
    }
  }

  make_sv <- function(mat) structure(list(S = mat, X = X_df, baseline = 0L),
                                     class = "shapviz")
  if (is.list(S)) {
    sv_list <- lapply(S, make_sv)
    names(sv_list) <- if (!is.null(names(S))) names(S) else paste0("Class_", seq_along(S) - 1L)
    structure(sv_list, class = "mshapviz")
  } else {
    make_sv(S)
  }
}

#' Extract one class's shapviz object from an mshapviz
#'
#' Some shapviz versions define \code{[[.mshapviz} to return the raw SHAP
#' matrix rather than the \code{shapviz} object. This helper bypasses that
#' dispatch via \code{unclass()} so the returned object has class
#' \code{"shapviz"} and works with \code{sv_importance()}, \code{sv_waterfall()}, etc.
#'
#' @param sv An \code{mshapviz} object (output of \code{compute_shap_xgb()} or
#'   \code{compute_shap_rf()} on a multiclass model).
#' @param i  Integer index of the class to extract (default 1L).
#' @return A \code{shapviz} object for class \code{i}.
shap_class <- function(sv, i = 1L) unclass(sv)[[i]]

#' Compute TreeSHAP values for an XGBoost model
#'
#' Unifies the model via \code{treeshap::xgboost.unify()}, runs
#' \code{treeshap::treeshap()}, and wraps the result in a
#' \code{shapviz} / \code{mshapviz} object ready for
#' \code{sv_importance()}, \code{sv_waterfall()}, etc.
#'
#' @param xgb_model xgb.Booster trained by \code{xgb.train()}.
#' @param X         Samples × features numeric matrix used for training.
#' @return A \code{shapviz} (binary) or \code{mshapviz} (multiclass) object.
compute_shap_xgb <- function(xgb_model, X) {
  X_df    <- as.data.frame(X)
  unified <- treeshap::xgboost.unify(xgb_model, X_df)
  shap    <- treeshap::treeshap(unified, X_df, verbose = FALSE)
  .treeshap_to_sv(shap, X_df)
}

#' Compute TreeSHAP values for a caret Random Forest model
#'
#' Extracts the bare \code{randomForest} object from the caret wrapper,
#' unifies it via \code{treeshap::randomForest.unify()}, and returns a
#' \code{shapviz} / \code{mshapviz} object.
#'
#' @param rf_model_caret Trained caret model object (output of \code{train_rf()}).
#' @param X              Samples × features numeric matrix used for training.
#' @return A \code{shapviz} (binary) or \code{mshapviz} (multiclass) object.
compute_shap_rf <- function(rf_model_caret, X) {
  X_df    <- as.data.frame(X)
  unified <- treeshap::randomForest.unify(rf_model_caret$finalModel, X_df)
  shap    <- treeshap::treeshap(unified, X_df, verbose = FALSE)
  .treeshap_to_sv(shap, X_df)
}

#' Build a three-way gene importance comparison table (Gini / Gain / SHAP)
#'
#' Ranks genes by (1) RF mean-decrease-Gini, (2) XGBoost gain, and (3) mean
#' absolute SHAP from each model. Prints Spearman rank correlations and returns
#' the top-\code{top_n} genes sorted by SHAP-XGBoost rank.
#'
#' For multiclass (\code{mshapviz}) objects, mean |SHAP| is averaged across
#' all output classes before ranking.
#'
#' @param sv_xgb     shapviz / mshapviz object for XGBoost (from \code{compute_shap_xgb()}).
#' @param sv_rf      shapviz / mshapviz object for RF (from \code{compute_shap_rf()}).
#' @param rf_model   Caret RF model (for Gini importance).
#' @param imp_xgb_df data.frame from \code{xgboost::xgb.importance()} (must have Feature and Gain columns).
#' @param top_n      Number of top genes to return (default 20).
#' @return data.frame with rank columns; Spearman correlations printed as a side-effect.
make_shap_rank_table <- function(sv_xgb, sv_rf, rf_model, imp_xgb_df, top_n = 20) {
  mean_abs_shap <- function(sv) {
    # Access $S directly — works for both our hand-built shapviz objects and
    # native shapviz objects regardless of whether get_shap_values() is exported.
    if (inherits(sv, "mshapviz")) {
      mats <- lapply(seq_len(length(sv)), function(i) abs(unclass(sv)[[i]]$S))
      colMeans(Reduce("+", mats) / length(mats))
    } else {
      colMeans(abs(sv$S))
    }
  }

  shap_xgb <- mean_abs_shap(sv_xgb)
  gini     <- rf_model$finalModel$importance[, "MeanDecreaseGini"]
  xgb_gain <- setNames(imp_xgb_df$Gain, imp_xgb_df$Feature)

  genes <- Reduce(intersect, list(names(gini), names(xgb_gain), names(shap_xgb)))

  df <- data.frame(
    Gene          = genes,
    SHAP_XGB_rank = rank(-shap_xgb[genes]),
    Gain_rank     = rank(-xgb_gain[genes]),
    Gini_rank     = rank(-gini[genes])
  ) |>
    dplyr::arrange(SHAP_XGB_rank) |>
    head(top_n)

  safe_cor <- function(x, y) {
    if (sd(x, na.rm = TRUE) == 0 || sd(y, na.rm = TRUE) == 0) NA_real_
    else cor(x, y, method = "spearman")
  }

  cat("Spearman rank correlations (top", top_n, "by SHAP-XGBoost):\n")
  cat("  Gini vs SHAP-XGB:", round(safe_cor(df$Gini_rank, df$SHAP_XGB_rank), 3), "\n")
  cat("  Gain vs SHAP-XGB:", round(safe_cor(df$Gain_rank, df$SHAP_XGB_rank), 3), "\n")

  df
}

# ── Differential expression comparison ───────────────────────────────────────

#' Run DESeq2 on an existing DESeqDataSet and return a tidy results data frame
#'
#' @param dds      DESeqDataSet with size factors already estimated.
#' @param contrast Character vector c(factor, numerator, denominator).
#' @return data.frame ordered by padj (ascending), with a Gene column added.
run_deseq2 <- function(dds, contrast = c("dex", "trt", "untrt")) {
  dds2 <- DESeq2::DESeq(dds)
  res  <- DESeq2::results(dds2, contrast = contrast)
  as.data.frame(res) |>
    dplyr::filter(!is.na(padj)) |>
    dplyr::mutate(Gene = rownames(res[!is.na(res$padj), ])) |>
    dplyr::arrange(padj)
}

#' Compare top ML signal genes with top differentially expressed genes
#'
#' Prints the number and names of overlapping genes; returns them invisibly.
#'
#' @param res_df     data.frame from \code{run_deseq2()}.
#' @param top_signal Character vector of ML variance-selected signal gene names.
#' @param top_n      Number of top DE genes to compare against (default 50).
#' @return Character vector of overlapping gene names (invisible).
compare_ml_de <- function(res_df, top_signal, top_n = 50) {
  top_de  <- head(res_df$Gene, top_n)
  overlap <- intersect(top_de, top_signal)
  cat("Top", top_n, "DE genes overlapping with top", length(top_signal),
      "variance-selected signal genes:", length(overlap), "\n")
  cat("Overlap genes:", paste(overlap, collapse = ", "), "\n")
  invisible(overlap)
}
