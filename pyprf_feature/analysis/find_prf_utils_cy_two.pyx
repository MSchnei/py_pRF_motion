# -*- coding: utf-8 -*-
"""Cythonised least squares GLM model fitting with 2 predictors."""

# Part of pyprf_feature library
# Copyright (C) 2018  Omer Faruk Gulban & Ingo Marquardt & Marian Schneider
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


# *****************************************************************************
# *** Import modules & adjust cython settings for speedup

import numpy as np
cimport numpy as np
cimport cython
from libc.math cimport pow, sqrt

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
# *****************************************************************************


# *****************************************************************************
# *** Main function for least squares solution, with 2 predictor

cpdef tuple cy_lst_sq_two(
    np.ndarray[np.float32_t, ndim=2] aryPrfTc,
    np.ndarray[np.float32_t, ndim=2] aryFuncChnk):
    """
    Cythonised least squares GLM model fitting.

    Parameters
    ----------
    aryPrfTc : np.array
        2D numpy array, at float32 precision, containing two pRF model
        time courses as two columns. Dimensionality: aryPrfTc[time,
        2].

    aryFuncChnk : np.array
        2D numpy array, at float32 precision, containing a chunk of functional
        data (i.e. voxel time courses). Dimensionality: aryFuncChnk[time,
        voxel].

    Returns
    -------
    vecPe : np.array
        2D numpy array with parameter estimates for all voxels in the chunk of
        functional data. Dimensionality: vecPe[2, voxel]
    vecRes : np.array
        1D numpy array with model residuals for all voxels in the chunk of
        functional data. Dimensionality: vecRes[voxel]
    

    Notes
    -----
    Computes the least-squares solution for the model fit between the pRF time
    course model, and all voxel time courses. Assumes removal of the mean from
    the functional data and the model. Needs to be compiled before execution
    (see `cython_leastsquares_setup.py`).
    """

    cdef:
        float varVarX1, varVarX2, varVarX1X2
        unsigned long varNumVoxChnk, idxVox
        unsigned int idxVol, varNumVols

    # Initial variances and covariances
    varVarX1 = 0
    varVarX2 = 0
    varVarX1X2 = 0

    # Number of voxels in the input data chunk:
    varNumVoxChnk = int(aryFuncChnk.shape[1])

    # Define 1D array for results (i.e. for residuals of least squares
    # solution):
    cdef np.ndarray[np.float32_t, ndim=1] vecRes = np.zeros(varNumVoxChnk,
                                                            dtype=np.float32)

    # Define 2D array for results - parameter estimate:
    cdef np.ndarray[np.float32_t, ndim=2] vecPe = np.zeros((varNumVoxChnk, 2),
                                                           dtype=np.float32)

    # Memory view on array for results:
    cdef float[:] vecRes_view = vecRes

    # Memory view on array for parameter estimates:
    cdef float [:, :] vecPe_view = vecPe

    # Memory view on predictor time courses:
    cdef float [:, :] aryPrfTc_view = aryPrfTc

    # Memory view on numpy array with functional data:
    cdef float [:, :] aryFuncChnk_view = aryFuncChnk

    # Calculate variance of pRF model time course (i.e. variance in the model):
    varNumVols = int(aryPrfTc.shape[0])

    # get the variance for x1
    for idxVol in range(varNumVols):
        varVarX1 += aryPrfTc_view[idxVol, 0] ** 2
        varVarX2 += aryPrfTc_view[idxVol, 1] ** 2
        varVarX1X2 += aryPrfTc_view[idxVol, 0] * aryPrfTc_view[idxVol, 1]

    # Call optimised cdef function for calculation of residuals:
    vecRes_view, vecPe_view = func_cy_res_two(aryPrfTc_view,
                                              aryFuncChnk_view,
                                              vecRes_view,
                                              vecPe_view,
                                              varNumVoxChnk,
                                              varNumVols,
                                              varVarX1,
                                              varVarX2,
                                              varVarX1X2)

    # Convert memory view to numpy array before returning it:
    vecRes = np.asarray(vecRes_view)
    vecPe = np.asarray(vecPe_view).T

    return vecPe, vecRes


# *****************************************************************************

# *****************************************************************************
# *** Function for fast calculation of residuals for 2 predictor time courses

cdef (float[:], float[:, :]) func_cy_res_two(float[:, :] aryPrfTc_view,
                                             float[:, :] aryFuncChnk_view,
                                             float[:] vecRes_view,
                                             float[:, :] vecPe_view,
                                             unsigned long varNumVoxChnk,
                                             unsigned int varNumVols,
                                             float varVarX1,
                                             float varVarX2,
                                             float varVarX1X2):

    cdef:
        float varCovX1y, varCovX2y, varRes, varSlope, varXhat
        unsigned int idxVol
        unsigned long idxVox

    # Loop through voxels:
    for idxVox in range(varNumVoxChnk):

        # Covariance and residuals of current voxel:
        varCovX1y = 0
        varCovX2y = 0
        varRes = 0

        # Loop through volumes and calculate covariance between the model and
        # the current voxel:
        for idxVol in range(varNumVols):
            varCovX1y += (aryFuncChnk_view[idxVol, idxVox]
                          * aryPrfTc_view[idxVol, 0])
            varCovX2y += (aryFuncChnk_view[idxVol, idxVox]
                          * aryPrfTc_view[idxVol, 1])
        # Obtain the slope of the regression of the model on the data:
        varSlope1 = varVarX2 * varCovX1y - varVarX1X2 * varCovX2y
        varSlope2 = varVarX1 * varCovX2y - varVarX1X2 * varCovX1y
        # calculate denominator
        varDen = varVarX1 * varVarX2 - varVarX1X2 ** 2
        # normalize
        varSlope1 /= varDen
        varSlope2 /= varDen

        # Loop through volumes again in order to calculate the error in the
        # prediction:
        for idxVol in range(varNumVols):
            # The predicted voxel time course value:
            varXhat = (aryPrfTc_view[idxVol, 0] * varSlope1 +
                       aryPrfTc_view[idxVol, 1] * varSlope2)
            # Mismatch between prediction and actual voxel value (variance):
            varRes += (aryFuncChnk_view[idxVol, idxVox] - varXhat) ** 2

        vecRes_view[idxVox] = varRes
        vecPe_view[idxVox, 0] = varSlope1
        vecPe_view[idxVox, 1] = varSlope2

    # Return memory view:
    return vecRes_view, vecPe_view
# *****************************************************************************