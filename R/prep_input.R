#' Preparing output for the STAN run of the STEPPS Model
#'
#' @param veg A table of vegetation data, generally gridded.
#' @param pollen A table of available pollen data.
#' @param target_taxa The taxa to be reconstructed.  Must appear in both the vegetation and pollen data.
#' @param grid
#' @param hood
#' @param dist_scale
#'
#' @return A list with parameters:
#'  * K  - Number of taxa
#'  * N_cores - Number of cores
#'  * N_cells - Number of cells in the veg data
#'  * N_hood - Number of veg cells contributing to each pollen sample site
#'  * y - Pollen counts (*n* cores x *p* taxa - a wide table)
#'  * r - Veg proportions (same structure)
#'  * idx_cores - The index of the veg cell for each core
#'  * idx_hood - The indices of cells for each contributing neighborhood
#'  * d - distance matrix (spatial distance from cores to veg cells)
#'  * N_pot - Number of potential contributing cells
#'  * d_pot - The actual contributing cells for each pollen sample
#' @md
#'
#' @importFrom sp spTransform CRS
#' @importFrom raster extract pointDistance ncell xyFromCell
#' @importFrom purrr map
#' @importFrom plyr rbind.fill.matrix
#' @export
#'
#' @examples {
#'    stepps_input <- prep_input(veg    = veg_table,
#'                               pollen = pol_table,
#'                               target_taxa = target_taxa,
#'                               grid   = reconst_grid)
#' }

prep_input <- function (veg, pollen, target_taxa, grid, hood =7e+05, dist_scale = 1e+06) {
  if (!class(veg) == "SpatialPointsDataFrame") {
    stop("veg data must be a SpatialPointsDataFrame, use `to_stepps_shape()`")
  }
  if (!class(pollen) == "SpatialPointsDataFrame") {
    stop("veg data must be a SpatialPointsDataFrame, use `to_stepps_shape()`")
  }
  #used next line to produce d_pot
  coord_pot = seq(0, hood, by=abs(unique(diff(sort(unique(veg@coords[,1])))))) #abs is probably not needed
  veg <- sp::spTransform(veg, CRSobj = sp::CRS(proj4string(grid)))
  pollen <- sp::spTransform(pollen, CRSobj = sp::CRS(proj4string(grid)))
  col_test <- all(na.omit(target_taxa) %in% names(veg)) & all(target_taxa %in%
                                                                names(pollen))

  assertthat::assert_that(col_test, msg = "All defined taxa must be in both the pollen and vegetation data.")
  output_list <- list(K = length(target_taxa), N_cores = nrow(pollen),
                      N_cells = nrow(veg), y = round(pollen@data[,target_taxa]), #had to remove the transformation to proportions, stan needs counts
                      r = analogue::tran(veg@data[, target_taxa], "proportion"), #had to change pollen@data to veg@data
                      d = (raster::pointDistance(pollen,veg))) #had to transpose object

  #used a rectangular grid with more cells than vegetation cells (this causes problems for stan as cores can have higher indexes than the
  #number of cells with vegetation)
  #num_grid <- raster::setValues(grid, 1:raster::ncell(grid))
  #output_list$veg_coord <- veg@coords


  num_grid <- 1:nrow(veg) #number of grids may only go from 1 to the number of vegetation cells
  #find minimum distance of cores to vegetation cells. Core is in the cell with minimum distance
  output_list$idx_cores <- apply(output_list$d,1,function(x) which.min(x))#raster::extract(num_grid, pollen)
  d_cells <- (raster::pointDistance(veg[output_list$idx_cores,],veg)) #Andria uses the distance of vegetation cells and not of
  #lake position within cell

  #output_list$idx_hood <- (plyr::rbind.fill.matrix(apply(output_list$d,
  #                                                      1, function(x) t(which(x <= hood)))))
  output_list$idx_hood <- (plyr::rbind.fill.matrix(apply(d_cells,
                                                         1, function(x) t(which(x <= hood)))))

  #idx_hood has dimension N_cores x N_cells
  output_list$idx_hood <- replace(output_list$idx_hood,is.na(output_list$idx_hood),0) #make sure there are no NAs
  dim_idx_hood <- dim(output_list$idx_hood)
  fill.matrix <- matrix(data=0,nrow = dim_idx_hood[1],ncol=output_list$N_cells-dim_idx_hood[2])
  output_list$idx_hood <- cbind(output_list$idx_hood,fill.matrix)




  coord_pot <- unique(c(-rev(coord_pot),coord_pot))
  coord_pot = expand.grid(coord_pot, coord_pot)
  d_pot <- t(rdist(matrix(c(0,0), ncol=2), as.matrix(coord_pot, ncol=2)))

  #d_pot <- round(raster::pointDistance(c(apply(coords, 2, mean)),
  #                               coords, lonlat = FALSE))#added round if we work in meters we can round. This might be a bad idea
  #using other units
  idx_circ <- which(d_pot <= hood)
  #coord_pot <- coord_pot[idx_circ, ]
  d_pot <- d_pot[idx_circ]
  output_list$d_pot <- cbind(sort(unique(d_pot)),unname(as.matrix(table(d_pot))))
  output_list$d_pot <- output_list$d_pot[-1,]# remove distance of 0
  output_list$N_pot <- nrow(output_list$d_pot)
  # number of potential neighbours number of cells - number of cells outside the search radius
  output_list$N_hood <- ncol(output_list$idx_hood) - apply(output_list$idx_hood,1,function(x) sum(x==0)) - 1
  output_list$d <- t(d_cells)#t(output_list$d)

  #rescaling distances
  output_list$d <- output_list$d/dist_scale
  output_list$d_pot[,1] <- output_list$d_pot[,1]/dist_scale 

  return(output_list)
}
