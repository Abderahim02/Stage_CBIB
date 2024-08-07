#!/usr/bin/env Rscript
Sys.setenv(RETICULATE_MINICONDA_ENABLED = "FALSE")
library(RCTD)
library(Matrix)
library(Seurat)
library(org.Hs.eg.db)

par <- list(
    cell_min = 5
)
par <- list(
    cell_min = 5,
    annot = "cell_type",
    sc_input = "datafiles_st_deconvolution/core_GBMap.rds",
    sp_input = "datafiles_st_deconvolution/UKF243_T_ST_1_raw.rds",
    num_cores = 12
)


convert_query_geneSymbol_to_ensemblID <- function(spatial_query){
  
  ## Function to convert gene symbols in query to ensemble IDs [e.g. GBMap is in ENSEMBL while Visium is in Symbol]
  ## The following code chunk is to be applied only if the reference single cell dataset
  ## contains ENSEMBL identifiers instead of gene symbols (as in Visium data)
  
  master_gene_table <- mapIds(org.Hs.eg.db, keys = rownames(spatial_query@counts), keytype = "SYMBOL", column="ENSEMBL")
  #master_gene_table <- as.data.frame(master_gene_table)
    cat ("oaak\n")
  # get the Ensembl ids with gene symbols i.e. remove those with NA's for gene symbols
  inds <- which(!is.na(master_gene_table))
  found_genes <- master_gene_table[inds]
  
  # subset your data frame based on the found_genes
  df2 <- spatial_query@counts[names(found_genes), ]
  rownames(df2) <- found_genes
  spatial_query@counts <- df2
  
  return(spatial_query)
}

# Replace default values by user input
args <- R.utils::commandArgs(trailingOnly=TRUE, asValues=TRUE)
par[names(args)] <- args
print(par)

## START ##
cat("Reading input scRNA-seq reference from", par$sc_input, "\n")
seurat_obj_scRNA <- readRDS(par$sc_input)
ncelltypes <- length(unique(seurat_obj_scRNA[[par$annot, drop=TRUE]]))
cat("Found ", ncelltypes, "cell types in the reference.\n")

cat("Converting to Reference object...\n")
cell_types <- stringr::str_replace_all(seurat_obj_scRNA[[par$annot, drop=TRUE]],
                                       "[/ .]", "") # Replace prohibited characters
names(cell_types) <- colnames(seurat_obj_scRNA)
DefaultAssay(seurat_obj_scRNA) <- "RNA"
reference_obj <- Reference(counts = GetAssayData(seurat_obj_scRNA, slot="counts"),
                           cell_types = as.factor(cell_types))

cat("Reading input spatial data from", par$sp_input, "\n")
spatial_data <- readRDS(par$sp_input)

cat("Converting spatial data to SpatialRNA object...\n")
if (class(spatial_data) != "Seurat"){
  spatialRNA_obj_visium <- RCTD:::SpatialRNA(counts = spatial_data$counts,
                                           use_fake_coords = TRUE)
} else { # If it is Seurat object, check if there is images slot
    use_fake_coords <- length(spatial_data@images) == 0
    coords <- NULL
    if (length(spatial_data@images)){
        coords <- GetTissueCoordinates(spatial_data)
    }
    DefaultAssay(spatial_data) <- names(spatial_data@assays)[grep("RNA|Spatial",names(spatial_data@assays))[1]]
    spatialRNA_obj_visium <- RCTD:::SpatialRNA(coords = coords,
                                    counts = GetAssayData(spatial_data, slot="counts"),
                                    use_fake_coords = use_fake_coords)
}

spatialRNA_obj_visium = convert_query_geneSymbol_to_ensemblID(spatialRNA_obj_visium)
cat("Running RCTD with", par$num_cores, "cores...\n")
start_time <- Sys.time()
RCTD_deconv <- create.RCTD(spatialRNA_obj_visium, reference_obj, max_cores = as.numeric(par$num_cores),
                            CELL_MIN_INSTANCE = as.numeric(par$cell_min))
RCTD_deconv <- run.RCTD(RCTD_deconv, doublet_mode = "full")
end_time <- Sys.time()
cat("Runtime: ", round((end_time-start_time)[[1]], 2), "s\n", sep="")

cat("Printing results...\n")
deconv_matrix <- as.matrix(sweep(RCTD_deconv@results$weights, 1, rowSums(RCTD_deconv@results$weights), '/'))

# Remove all spaces and dots from cell names, sort them
colnames(deconv_matrix) <- stringr::str_replace_all(colnames(deconv_matrix), "[/ .&-]", "")
deconv_matrix <- deconv_matrix[,sort(colnames(deconv_matrix), method="shell")]


# # à corriger en mettant spatial_data@assays@counts dans spatial_data$counts 
# if (nrow(deconv_matrix) != ncol(spatial_data$counts)){
#     cat ("okkkkkk\n")
#   message("The following rows were removed, possibly due to low number of genes: ",
#           paste0("'", colnames(spatial_data$counts)[!colnames(spatial_data$counts) %in% rownames(deconv_matrix)], "'", collapse=", "))
# }

write.table(deconv_matrix, file=par$output, sep="\t", quote=FALSE, row.names=TRUE)
# write.table(matrix("hello world, this is rctd"), file=par$output, sep="\t", quote=FALSE, row.names=FALSE)
