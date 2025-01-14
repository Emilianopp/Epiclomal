suppressMessages(library(argparse))
suppressMessages(library(pheatmap))
suppressMessages(library(gtools))
suppressMessages(library(Rcpp))

parser <- ArgumentParser()

parser$add_argument("--mean_methylation_file", default="None", type="character", help="file path contianing mean methylation per region")
parser$add_argument("--true_file", default=NULL, type="character", help="Path to true cluster information")
parser$add_argument("--data_ID", type="character", help="ID of dataset")
parser$add_argument("--output_directory", type="character", help="Path to the output directory")
parser$add_argument("--coef_threshold", default=0.95, type="double",help="Threshold of Pearson correlation coefficient")
parser$add_argument("--mean_diff_threshold", default=0.05, type="double",help="Threshold of max difference between mean region cluster methylation")
parser$add_argument("--n_to_keep", default=1000, type="integer", help="Keep the top N most variant regions")


args <- parser$parse_args()

print(args)

data_id <- args$data_ID
mean_meth_file <- args$mean_methylation_file
true_file <- args$true_file
outdir <- args$output_directory
dir.create(outdir, showWarnings = FALSE, recursive=TRUE)

coef_t <- args$coef_threshold
N <- args$n_to_keep
mean_diff_threshold <- args$mean_diff_threshold

# assume filter_regions.cpp is in the same directory as this file
# trying to figure out the path of this file so I can source filter_regions.cpp
initial.options <- commandArgs(trailingOnly = FALSE)
file.arg.name <- "--file="
script.name <- sub(file.arg.name, "", initial.options[grep(file.arg.name, initial.options)])
script.basename <- dirname(script.name)
sourceCpp(file.path(script.basename, "filter_regions.cpp"))


load_mean_meth <- function(filename) {
    mean_meth_matrix <- read.csv(filename, sep = "\t", header = TRUE)
    mean_meth_matrix <- t(mean_meth_matrix)
    return(mean_meth_matrix)
}

set_annotation_row <- function(data) {
    annotation_row <- as.data.frame(data$epigenotype_id)
    colnames(annotation_row) <- "true_cluster"
    annotation_row$true_cluster <- as.factor(annotation_row$true_cluster)
    rownames(annotation_row) <- data$cell_id
    return(annotation_row)
}

set_index_gaps <- function(data) {
    index <- 1:dim(data)[1]
    index_gaps <- index[!duplicated(data[order(data),])] - 1
    index_gaps <- index_gaps[which(index_gaps != 0)]
    return(index_gaps)
}

# # find correlated regions to remove, outdated, using c++ version
# find_correlated_regions <- function(mean_meth_matrix, coef_t) {
#     correlated_regions <- data.frame(region=colnames(mean_meth_matrix))
#     correlated_regions$keep_region <- TRUE
#     correlated_regions$weight <- 1

#     for (r1 in 1:(ncol(mean_meth_matrix) - 1)) {
#         # print(r1)
#         if (!correlated_regions[r1, 'keep_region']) {
#             # print("r1 already in regions_to_remove")
#             next
#         }
#         for (r2 in (r1+1):ncol(mean_meth_matrix)) {
#             # print(r2)
#             if (!correlated_regions[r2, 'keep_region']) {
#                 # print(paste(r2, "already in regions_to_remove"))
#                 next
#             } else {

#                 pearson_corr <- cor(mean_meth_matrix[,r1], mean_meth_matrix[,r2], method = "pearson", use = "na.or.complete")

#                 if (is.na(pearson_corr)) {
#                     next
#                 }

#                 if ((pearson_corr > coef_t) || (pearson_corr < (-1 * coef_t))) {
#                     #remove region with greater NAs
#                     if (sum(is.na(mean_meth_matrix[,r2])) >= sum(is.na(mean_meth_matrix[,r1]))) {
#                         correlated_regions[r2, 'keep_region'] <- FALSE
#                         correlated_regions[r1, 'weight'] <- correlated_regions[r1, 'weight'] + correlated_regions[r2, 'weight']
#                     } else {
#                         correlated_regions[r1, 'keep_region'] <- FALSE
#                         correlated_regions[r2, 'weight'] <- correlated_regions[r1, 'weight'] + correlated_regions[r2, 'weight']
#                         break
#                     }
#                 }
#             }
#         }
#     }
#     return(correlated_regions)
# }

find_most_variant_regions <- function(data, N) {
    data <- data[, order(-apply(data, 2, var, na.rm=TRUE))]
    data <- data[,1:N]
    return(data[, mixedsort(colnames(data))])
}

find_cluster_means <- function(data, true_clusters) {
    data <- t(data)
    epi_means <- NULL
    for (epi in unique(true_clusters$epigenotype_id)) {
        epi_means <- cbind(epi_means, rowMeans(data[,true_clusters$epigenotype_id == epi], na.rm = TRUE))
    }
    epi_means <- as.data.frame(epi_means)
    #find the largest difference in means
    epi_means$max_diff <- apply(epi_means, 1, function(x) diff(range(x, na.rm = TRUE)))

    return(epi_means)
}

plot_heatmap <- function(data, filename, main, annotation_row, index_gaps) {
    pheatmap(data, cluster_cols = FALSE, cluster_rows = FALSE,
        annotation_row = annotation_row, fontsize = 8,
        main = main,
        gap_row = index_gaps, fontsize_row = 4, fontsize_col = 6,
        annotation_names_row = FALSE, border_color = NA, show_colnames = TRUE, labels_col = NULL,
        filename = filename)

}

main <- function(mean_meth_file, true_file, outdir, coef_t, mean_diff_threshold) {
    mean_meth_matrix <- load_mean_meth(mean_meth_file)

    c <- dim(mean_meth_matrix)[1]
    r <- dim(mean_meth_matrix)[2]
    print(paste("Number of cells", c))
    print(paste("Number of regions", r))

    print("Finding and removing highly correlated regions")

    correlated_regions <- find_correlated_regions_cpp(mean_meth_matrix, coef_t)

    redundant_matrix <- mean_meth_matrix[, !correlated_regions$keep_region]
    non_redundant_matrix <- mean_meth_matrix[, correlated_regions$keep_region]

    print(paste("Number of highly correlated regions", dim(redundant_matrix)[2]))
    print(paste("Number of non-redundant regions", dim(non_redundant_matrix)[2]))

    if (N < dim(non_redundant_matrix)[2]) {
        print(paste("Finding top", N, "most variant regions"))
        non_redundant_matrix <- find_most_variant_regions(non_redundant_matrix, N)
        redundant_matrix <- mean_meth_matrix[, !(colnames(mean_meth_matrix) %in% colnames(non_redundant_matrix))]
    } else {
        print("N is greater than number of non-redundant regions, keep all")
    }

    region_weights <- correlated_regions[correlated_regions$keep_region, c('region', 'weight'), drop=FALSE]
    region_weight_file <- gzfile(file.path(outdir, paste0("non_redundant_region_weights_", data_id, ".tsv.gz")))
    write.table(region_weights, file = region_weight_file, sep = "\t", quote=FALSE, row.names = FALSE, col.names = TRUE)

    if (!is.null(true_file)) {
        true_clone_membership <- read.csv(true_file, sep = "\t", header = TRUE)
        true_clone_membership <- true_clone_membership[order(as.character(true_clone_membership$cell_id)),]
        annotation_row <- set_annotation_row(true_clone_membership)
        index_gaps <- set_index_gaps(true_clone_membership)

        redundant_matrix <- redundant_matrix[order(as.character(true_clone_membership$epigenotype_id)),]
        non_redundant_matrix <- non_redundant_matrix[order(as.character(true_clone_membership$epigenotype_id)),]
    } else {
        annotation_row <- NULL
        index_gaps <- set_index_gaps(mean_meth_matrix)
    }

    redundant_file <- gzfile(file.path(outdir, paste0("redundant_regions_meth_", data_id, ".tsv.gz")))
    write.table(redundant_matrix, file = redundant_file, sep = "\t", quote=FALSE, row.names = TRUE, col.names = TRUE)

    non_redundant_file <- gzfile(file.path(outdir, paste0("to_keep_meth_", data_id, ".tsv.gz")))
    write.table(non_redundant_matrix, file = non_redundant_file, sep = "\t", quote=FALSE, row.names = TRUE, col.names = TRUE)

    regions_file <- file.path(outdir, paste0("filtered_regions_", data_id, ".tsv"))
    write.table(colnames(non_redundant_matrix), file = regions_file, sep = "\t", quote=FALSE, row.names = FALSE, col.names = FALSE)

    print("Plotting methylation of redundant regions")
    redundant_plot <- file.path(outdir, paste0("redundant_regions_plot_", data_id, ".png"))
    plot_heatmap(redundant_matrix, redundant_plot, "Mean methylation of redundant regions", annotation_row, index_gaps)

    print("Plotting methylation of regions to keep")
    non_redundant_plot <- file.path(outdir, paste0("regions_to_keep_plot_", data_id, ".png"))
    plot_heatmap(non_redundant_matrix, non_redundant_plot, "Mean methylation of regions to keep", annotation_row, index_gaps)

    if (!is.null(true_file)) {
        print("Finding and removing regions with low variance between clusters")
        cluster_means <- find_cluster_means(mean_meth_matrix, true_clone_membership)
        low_variance_regions <- rownames(cluster_means[cluster_means$max_diff < mean_diff_threshold,])

        print(paste("Number of low variance regions", length(low_variance_regions)))
        redundant_matrix <- mean_meth_matrix[, colnames(mean_meth_matrix) %in% low_variance_regions]
        non_redundant_matrix <- mean_meth_matrix[, !(colnames(mean_meth_matrix) %in% low_variance_regions)]

        print("Plotting histogram of max difference in methylation between clusters by region")
        png(file.path(outdir, paste0("mean_diff_hist_", data_id, ".png")))
        hist(cluster_means$max_diff, breaks = 100)
        dev.off()

        redundant_matrix <- redundant_matrix[order(as.character(true_clone_membership$epigenotype_id)),]
        non_redundant_matrix <- non_redundant_matrix[order(as.character(true_clone_membership$epigenotype_id)),]

        if (sum(!is.na(redundant_matrix)) > 0) {
            print("Plotting methylation of low variance regions")
            redundant_plot <- file.path(outdir, paste0("low_variance_regions_plot_", data_id, ".png"))
            plot_heatmap(redundant_matrix, redundant_plot, "Mean methylation of low variance regions", annotation_row, index_gaps)
        }

        if (sum(!is.na(non_redundant_matrix)) > 0) {
            print("Plotting methylation of variant regions")
            non_redundant_plot <- file.path(outdir, paste0("variant_regions_plot_", data_id, ".png"))
            plot_heatmap(non_redundant_matrix, non_redundant_plot, "Mean methylation of variant regions", annotation_row, index_gaps)
        }
    }
}

main(mean_meth_file, true_file, outdir, coef_t, mean_diff_threshold)
