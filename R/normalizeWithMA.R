# -----------------------------------------------------------------------------#
#' Multi-dimensional MA normalization for plate effect
#'
#' Normalize data to minimize the difference among the subgroups of the samples 
#' generated by experimental factor such as multiple plates (batch effects)\cr
#'  - the primary method is Multi-MA, but other fitting function, \emph{f} in 
#'    the reference (e.g. loess) is available, too.\cr
#'  This method is based on the assumptions stated below\cr
#'  \enumerate{
#'  \item The geometric mean value of the samples in each subgroup (or plate) 
#'        for a single target is ideally same as those from the other subgroups.
#'  \item The subgroup (or plate) effects that influence those mean values for 
#'        multiple observed targets are dependent on the values themselves. 
#'        (intensity dependent effects)
#'  }
#'
#' @param mD a \code{matrix} of measured values in which columns are the measured
#'           molecules and rows are samples 
#' @param expGroup a \code{vector} of experimental grouping variable such as 
#'                 plate. The length of \code{expGroup} must be same as the 
#'                 number of rows of \code{mD}.
#' @param represent_FUN a \code{function} that computes representative values 
#'                      for each experimental group (e.g. plate). The default is
#'                      mean ignoring any NA 
#' @param fitting_FUN \code{NULL} or a \code{function} that fits to data in 
#'                    MA-coordinates.\cr 
#'        If it is \code{NULL} as the default, 'Multi-MA' method is employed.\cr
#'        If a \code{function} is used, two arguments of \code{m_j} and \code{A}
#'        are required, which are \eqn{\mathbf{m}_j}{m_j} coordinate in 
#'        \eqn{M_d} and \eqn{A} coordinate, respectively. 
#' @param isLog TRUE or FALSE, if the normalization should be conducted after 
#'              log-transformation. The affinity proteomics data from suspension
#'              bead arrays is recommended to be normalized using the default,
#'              \code{isLog = TRUE}.
#' 
#' @return The data after normalization in a \code{matrix}
#' 
#' @references Hong M-G, Lee W, Nilsson P, Pawitan Y, & Schwenk JM (2016) 
#' 	Multidimensional normalization to minimize plate effects of suspension 
#'  bead array data. \emph{J. Proteome Res.}, 15(10) pp 3473-80.
#' 
#' @author Mun-Gwan Hong \email{mun-gwan.hong@scilifelab.se}
#' @examples
#' data(sba1)
#' B <- normn_MA(sba1$X, sba$plate)		# Multi-MA normalization
#' 
#' # MA-loess normalization
#' B <- normn_MA(sba1$X, sba$plate, fitting_FUN= function(m_j, A) loess(m_j ~ A)$fitted)
#' 
#' # On MA coordinates, weighted linear regression normalization
#' B <- normn_MA(sba1$X, sba$plate, fitting_FUN= function(m_j, A) {
#' 	beta <- lm(m_j ~ A, weights= 1/A)$coefficients
#' 	beta[1] + beta[2] * A
#' })
#' 
#' # On MA coordinates, robust linear regression normalization
#' if(any(search() == "package:MASS")) {	# excutable only when MASS package was loaded.
#' 	B <- normn_MA(sba1$X, sba$plate, fitting_FUN= function(m_j, A) {
#' 		beta <- rlm(m_j ~ A, maxit= 100)$coefficients
#' 		beta[1] + beta[2] * A
#' 	})
#' }
#'
#' @export
# -----------------------------------------------------------------------------#

normn_MA <- function(mD, expGroup, represent_FUN= function(x) mean(x, na.rm= T), fitting_FUN= NULL, isLog= TRUE) {
	
	stopifnot(!missing(mD))
	stopifnot(!missing(expGroup))
	stopifnot(nrow(mD) == length(expGroup))
	if(!inherits(expGroup, "factor")) expGroup <- factor(expGroup)
	
	if(isLog) mD <- log(mD)

	# matrix of representative values of every experimental group 
	represent_FUN <- match.fun(represent_FUN)
	X <- sapply(
	    levels(expGroup), 
	    function(x) apply(mD[expGroup == x, , drop= F], 2, represent_FUN),
	    simplify= F
	)
	X <- as.matrix(as.data.frame(X, check.names= F))
	X_names <- colnames(X)
	
	## NA full column -> excluded in normalization
	naCol <- apply(X, 2, function(ij) all(is.na(ij)))
	if(any(naCol)) {
		warning(paste(names(naCol)[naCol], "contains only NAs. The warning above is likely due to that."))
		X <- X[, !naCol, drop= F]
	}
	
	nP <- ncol(X)	# the number of the experimental groups (e.g. plates)
	stopifnot(nP > 1)	# This function is designed to normalize multiple dimensional data
	
	# A = x1 + x2 + x3 + x4 + ... / nP = (the vector that pass through origin and line of identity)
	
	# >> Orth : an Orthogonal matrix for projection onto the subspace perpendicular to A <<
	# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	Orth <- t( svd(rep(1, nP), nu = nP)$u )		# incl. A = u[, 1]
	# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	if(Orth[1,1] < 0) Orth <- -1*Orth			# let the first element positive

	# >>> M and A values <<<
	# ~~~~~~~~~~~~~~~~~~~~~~~~
	MA <- t( Orth %*% t(X) )			# the values of X on M and A coordinates
	M <- as.matrix(MA[ ,2:nP, drop= F])			# matrix
	A <- MA[ , 1]						# vector
	# ~~~~~~~~~~~~~~~~~~~~~~~~

	## M(normalized) = M(raw) - rbind(0, "Md")
	##                                    **
	Md <- sapply(1:(nP-1), function(j) {
		m_j <- M[, j]
		# >>> Find fitted value <<<
		# ****************************************************
		if(is.null(fitting_FUN)) (m_j)
		else {
			fitting_FUN <- match.fun(fitting_FUN)
			fitting_FUN(m_j= m_j, A= A)
		}
		# ****************************************************
	}, simplify= F)
	Md <- as.matrix(as.data.frame(Md, col.names= 1:(nP-1)))
	Md <- rbind(0, t(Md))
	
	## M = (Orth) %*% X
	## X(normalized) = X - solve(Orth) %*% Md    (solve(Orth) = t(Orth))
	##                     ******************
	Xn <- t(t(Orth) %*% Md)

	## NA full column -> NA column
	if(any(naCol)) {
		for(ii in c(which(naCol) - 1)) {
			Xn <- if(ii == ncol(Xn)) {
				cbind(Xn, matrix(nrow= nrow(Xn), ncol= 1))
			} else {
				cbind(Xn[, min(1, ii):ii, drop= F], 
				      matrix(nrow= nrow(Xn), ncol= 1), 
				      Xn[, (ii+1):ncol(Xn), drop= F])
			}
		}
	}
	
	colnames(Xn) <- X_names

	# normalize individual values
	x_normn <- mD - t(Xn)[expGroup, , drop= F]
	if(isLog) x_normn <- exp(x_normn)
	
	return(invisible( x_normn ))
}
