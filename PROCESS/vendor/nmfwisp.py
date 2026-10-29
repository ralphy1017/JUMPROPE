import numpy as np
import scipy
import os
from pathlib import Path
from importlib import resources
from astropy.io import fits
from scipy.interpolate import interp1d
from astropy.stats import sigma_clipped_stats
import warnings

__all__ = ["fit_wisp"]

# ---- Core Solvers for Amplitudes ----

def _solve_amps_nnls_single(data, wisp_template, err, mask):
    """
    Solve NNLS for a single 1D exposure.

    Parameters
    ----------
    data : np.ndarray
        The 1D data array of length n_pixel.
    wisp_template : np.ndarray
        The 2D array (n_template, n_pixel) of template components.
    err : np.ndarray
        The 1D array of uncertainties (n_pixel).
    mask : np.ndarray
        Boolean array (n_pixel). True where data is masked/invalid.

    Returns
    -------
    W : np.ndarray
        The best-fit amplitude array (n_template,).
    chi2 : float
        The chi-square statistic for the fit.
    """
    err[mask] = np.inf
    Xe = wisp_template / err[None, :]
    Ye = data / err

    W, chi2 = scipy.optimize.nnls(Xe.T, Ye)
    return W, chi2


def _solve_amp_linear_single(data, wisp_template, err, mask):
    """
    Solve for amplitudes of the WISP templates using linear least squares.

    Parameters
    ----------
    data : np.ndarray
        1D data array (n_pixel).
    wisp_template : np.ndarray
        2D array (n_template, n_pixel) of template components.
    err : np.ndarray
        1D array of uncertainties (n_pixel).
    mask : np.ndarray
        Boolean array (n_pixel). True where data is masked/invalid.

    Returns
    -------
    W : np.ndarray
        template amplitudes (n_template,).
    We : np.ndarray
        Standard errors of the amplitudes (n_template,).
    """
    err[mask] = np.inf
    Xe = wisp_template / err[None, :]
    Ye = data / err
    XX = np.matmul(Xe, Xe.T)
    inv_XX = np.linalg.inv(XX)
    W = np.matmul(inv_XX, np.matmul(Xe, Ye))
    We = np.sqrt(np.diag(inv_XX))
    return W, We

def _solve_amp_uncertainties_single(wisp_template, err, mask):
    """
    Solve for the uncertainties of the amplitudes using the linear least squares method.
    """
    err[mask] = np.inf
    Xe = wisp_template / err[None, :]
    XX = np.matmul(Xe, Xe.T)
    inv_XX = np.linalg.inv(XX)
    We = np.sqrt(np.diag(inv_XX))
    return  We

# ---- High-Level Interfaces ----
MAX_TMEPLATE_NUM = 10

def auto_config_if_None(data, err, mask):
    if err is None:
        err = np.ones_like(data)
    if mask is None:
        mask = np.zeros_like(data, dtype=bool)
    return err, mask


def solve_amps_nnls(data, wisp_template, err=None, mask=None):
    """
    High-level interface for NNLS solvers.

    Handles single or multiple exposures.

    Parameters
    ----------
    data : np.ndarray
        Data array (n_pixel) or (n_exposure, n_pixel).
    wisp_template : np.ndarray
        Template array (n_template, n_pixel).
    err : np.ndarray, optional, same shape as data
        Uncertainties array. Defaults to ones.
    mask : np.ndarray, optional, same shape as data
        Boolean mask array. Defaults to all False.

    Returns
    -------
    W : np.ndarray
        Amplitudes (n_exposure, n_template).
    chi2 : np.ndarray
        Chi-squared values (n_exposure).
    """
    err, mask = auto_config_if_None(data, err, mask)

    if data.ndim == 1:
        W, chi2 = _solve_amps_nnls_single(data, wisp_template, err, mask)
        W = W[None, :]
    else:
        n_exposure = data.shape[0]
        W = np.zeros((n_exposure, wisp_template.shape[0]))
        chi2 = np.zeros(n_exposure)
        for i in range(n_exposure):
            W[i], chi2[i] = _solve_amps_nnls_single(data[i], wisp_template, err[i], mask[i])

    return W, chi2


def solve_amps_linear(data, wisp_template, err, mask):
    """
    High-level interface for linear least squares solvers.

    Handles single or multiple exposures.

    Parameters
    ----------
    data : np.ndarray
        Data array (n_pixel) or (n_exposure, n_pixel).
    wisp_template : np.ndarray
        Template array (n_template, n_pixel).
    err : np.ndarray, optional, same shape as data
        Uncertainties array. Defaults to ones.
    mask : np.ndarray, optional, same shape as data
        Boolean mask array. Defaults to all False.

    Returns
    -------
    W : np.ndarray
        Amplitudes (n_exposure, n_template).
    We : np.ndarray
        Standard errors of the amplitudes (n_exposure, n_template).
    """
    err, mask = auto_config_if_None(data, err, mask)

    if data.ndim == 1:
        W, We = _solve_amp_linear_single(data, wisp_template, err, mask)
        W, We = W[None, :], We[None, :]
    else:
        n_exposure = data.shape[0]
        W = np.zeros((n_exposure, wisp_template.shape[0]))
        We = np.zeros((n_exposure, wisp_template.shape[0]))
        for i in range(n_exposure):
            W[i], We[i] = _solve_amp_linear_single(data[i], wisp_template, err[i], mask[i])

    return W, We

def solve_amp_uncertainties(data, wisp_template, err, mask):
    """
    Solve for the uncertainties of the amplitudes using the linear least squares method.
    """
    err, mask = auto_config_if_None(data, err, mask)

    if data.ndim == 1:
        We = _solve_amp_uncertainties_single(wisp_template, err, mask)
        We = We[None, :]
    else:
        n_exposure = data.shape[0]
        We = np.zeros((n_exposure, wisp_template.shape[0]))
        for i in range(n_exposure):
            We[i] = _solve_amp_uncertainties_single(wisp_template, err[i], mask[i])

    return We

def solve_amp(data, wisp_template, err=None, mask=None, bool_weighted=False):
    """
    Solve for the amplitudes of the WISP templates using the non-negative least squares method.
    """
    We = solve_amp_uncertainties(data, wisp_template, err, mask)
    if bool_weighted:
        weights = (wisp_template[0] / np.std(wisp_template[0]))**int(bool_weighted)
        #weights = np.clip(weights, 1, np.inf)
    else:
        weights = 1

    W = solve_amps_nnls(data, wisp_template, err/weights, mask)[0]
    return W, We

def calc_wisp_err(W, We, wisp_template, template_err):
    """
    Calculate the error of the WISP template.
    Error propagation from the uncertainties of the amplitudes and the template.
    if template_err is None, only the contribution from the amplitude uncertainties is considered.
    """
    if template_err is not None:
        err_from_We = np.einsum('ij,jmn->imn', We, wisp_template)
        err_from_template = np.sqrt(np.sum(W**2, axis=1))[:, None, None] * template_err[None, :]
        wisp_err = np.sqrt(err_from_We**2 + err_from_template**2)

    else:
        wisp_err = np.einsum('ij,jmn->imn', We, wisp_template)

    return wisp_err


# ---- Auto-Reshaping and Preprocessing ----
def verify_shapes(data, wisp, err, mask):
    """
    Verify that the input shapes are consistent.
    """
    assert data.shape == err.shape, \
        f"data and err have different shapes. data: {data.shape}, err: {err.shape}"
    assert data.shape == mask.shape, \
        f"data and mask have different shapes. data: {data.shape}, mask: {mask.shape}"
    assert wisp.shape[0] < MAX_TMEPLATE_NUM, \
        "The first dimension of wisp should be the number of templates. wisp.shape: {}".format(wisp.shape)
    
    if wisp.ndim == 2:
        assert data.shape[-1] == wisp.shape[-1], \
            "data and wisp have different dimensions in the pixel dimension. \
                data: {}, wisp: {}".format(data.shape, wisp.shape)
    
    elif wisp.ndim == 3:
        assert data.shape[-2:] == wisp.shape[-2:], \
            "data and wisp have different pixel dimensions. \
                data: {}, wisp: {}".format(data.shape, wisp.shape)


def auto_identify_format(data, wisp):
    """
    identify:
    1. multi-exposure or single exposure
    2. 1D or 2D in the pixel dimension
    return:
    {IsMultiExposure: bool, Is2DPixel: bool}
    """
    if wisp.ndim == 2:
        Is1DPixel = True
    elif wisp.ndim == 3:
        Is1DPixel = False
    else:
        raise ValueError("Invalid shape for wisp.")
    
    IsMultiExposure = None
    if data.ndim == 1:
        IsMultiExposure = False
    elif data.ndim == 2:
        if Is1DPixel:
            IsMultiExposure = True
        elif (not Is1DPixel):
            IsMultiExposure = False
    elif data.ndim == 3:
        if (not Is1DPixel) and (data.shape[-2:] == wisp.shape[-2:]):
            IsMultiExposure = True
    if IsMultiExposure is None:
        raise ValueError("Invalid shape for data or wisp.")
    
    return {"IsMultiExposure": IsMultiExposure, "Is2DPixel": not Is1DPixel}


def auto_reshape(data, wisp, err, mask):
    """
    Reshape to the (n_exposure, n_pixel) format. Accept single or multiple exposures. Accept 1D or 2D in the pixel dimension.

    Parameters
    ----------
    data : np.ndarray
        The input data array, which can have shapes:
        (n_exposure, n_pixel), (n_pixel), (n_y, n_x), or (n_pixel, n_y, n_x).
    wisp : np.ndarray
        The template array, which can have shapes:
        (n_template, n_pixel) or (n_template, n_y, n_x).
    err : np.ndarray or None
        The error array with the same shape as `data`. If None, defaults to ones.
    mask : np.ndarray or None
        The boolean mask array with the same shape as `data`. If None, defaults to all False.
    """
    err, mask = auto_config_if_None(data, err, mask)
    format = auto_identify_format(data, wisp)
    # err = err.copy()
    # err[mask] = np.inf
    
    if format["Is2DPixel"]:
        wisp = wisp.reshape(wisp.shape[0], -1)
        if format["IsMultiExposure"]:
            data = data.reshape(data.shape[0], -1)
            err = err.reshape(err.shape[0], -1)
            mask = mask.reshape(mask.shape[0], -1)
        else:
            data = data.reshape(-1)[None, :]
            err = err.reshape(-1)[None, :]
            mask = mask.reshape(-1)[None, :]
    
    return data, wisp, err, mask

def reshape_back(format, shape, high_snr_region, *data):
    """
    Reshape back to the original format.
    """
    if format["Is2DPixel"]:
        new_data = []
        for d in data:
            new_d = np.zeros((d.shape[0], *shape), dtype=d.dtype)
            new_d[:, high_snr_region] = d
            new_data.append(new_d)
        data = new_data
    
    if not format["IsMultiExposure"]:
        data = [d[0] for d in data]
    
    return tuple(data)


def select_region(region, *data):
    """
    Select a region from the data arrays.
    """
    out = []
    for i in range(len(data)):
        out.append(data[i][:, region])
    return out

def select_high_snr_region(high_snr_region, *data):
    """
    Select the high SNR region from the data arrays.
    """
    if high_snr_region is None:
        return data
    else:
        high_snr_region = high_snr_region.reshape(-1)
        return select_region(high_snr_region, *data)


# ---- 1/f correction ----
def _clip_residual(residual, sigma=2, n_iter=10):
    """
    residual: (n_exp, n_y, n_x)
    """
    n_exp, n_y, n_x = residual.shape
    residual = residual.reshape(n_exp, -1)
    for i in range(n_iter):
        median, std = np.nanmedian(residual, axis=1), np.nanstd(residual, axis=1)
        bool_clip = np.abs(residual - median[:, None]) > sigma * std[:, None]
        residual[bool_clip] = np.nan
    return residual.reshape(n_exp, n_y, n_x)

def interpolate_hstripes(hstripes, bool_valid_arr, idx):
    """
    linear interpolate non-valid along the vertical direction
    """
    n_exp, n_y, n_x = hstripes.shape
    for i in range(n_exp):
        for j in range(4):
            hstrips_comp = hstripes[i, :, (idx[j]+idx[j+1])//2]
            bool_valid = bool_valid_arr[i, :, j]
            x = np.arange(n_y)[bool_valid]
            y = hstrips_comp[bool_valid]
            f = interp1d(x, y, kind='linear', fill_value=0., bounds_error=False)
            hstripes[i, :, idx[j]:idx[j+1]] = f(np.arange(n_y))[:, None]
    return hstripes

def _correct1f(residual, mask, sigma=2):
    """
    Can be optimized using wisp mask. Reshaped with width as the amplifier.

    Parameters
    ----------
    residual: ndarray of shape (n_exp, n_y, n_x).
        The data to correct for 1/f

    mask: ndarray of shape (n_exp, n_y, n_x).
        Boolean mask with True for pixels to ignore during estimation

    Returns
    -------
    stripes : ndarray of shape (n_exp, n_y, n_x).
        The 1/f estimates to remove from the input

    """
    n_exp, n_y, n_x = residual.shape
    residual = residual.copy()
    mask = mask.astype(bool)
    # print(residual.shape, mask.shape)
    residual[mask] = np.nan
    residual = _clip_residual(residual, sigma=sigma)
    hstripes = np.zeros_like(residual)
    bool_valid_arr = np.zeros((n_exp, n_y, 4), dtype=bool)
    n_div = n_x // 4
    idx = [4, n_div, 2*n_div, 3*n_div, 4*n_div-4]
    min_pix = int(n_x * 0.02)
    for i in range(4):
        hstripe_value = np.nanmedian(residual[:, :, idx[i]:idx[i+1]], axis=2, keepdims=True)
        bool_valid = np.sum(~np.isnan(residual[:, :, idx[i]:idx[i+1]]), axis=2) > min_pix
        hstripes[:, :, idx[i]:idx[i+1]] = hstripe_value * bool_valid[:, :, None]
        bool_valid_arr[:, :, i] = bool_valid
    hstripes = interpolate_hstripes(hstripes, bool_valid_arr, idx)
    hstripes = np.nan_to_num(hstripes)
    vstripes = np.nanmedian(residual - hstripes, axis=1, keepdims=True)
    vstripes = np.nan_to_num(vstripes)

    return hstripes + vstripes


def gaussian_interpolate(data, sigma=3, axes=None):
    """
    Interpolate NaN values in a 2D array using a Gaussian filter.

    Parameters
    ----------
    data : 2D array
        The input data array.
    sigma : float
        The standard deviation of the Gaussian filter.

    Returns
    -------
    interpolated : 2D array
        The interpolated data array.
    """
    from scipy.ndimage import gaussian_filter
    mask = np.isnan(data)
    if axes is None:
        axes = np.arange(data.ndim)

    data[mask] = 0.
    smoothed = gaussian_filter(data, sigma=sigma, axes=axes)
    pix_num = np.ones_like(data)
    pix_num[mask] = 0.
    pix_num = gaussian_filter(pix_num, sigma=sigma, axes=axes)
    
    pix_num[np.isnan(pix_num)] = 0.5
    pix_num = np.clip(pix_num, 0.5, None)
    interpolated = smoothed/pix_num

    data[mask] = interpolated[mask]
    return data


def clip_strip_outlier(stripes, sigma=3):
    """
    Clip outliers in horizontal or vertical stripes.
    """
    _, _, std = sigma_clipped_stats(stripes, axis=(1, 2), sigma=sigma, maxiters=10,)
    mask_outlier = np.abs(stripes) > 10 * std[:, None, None]
    stripes[mask_outlier] = np.nan
    stripes = gaussian_interpolate(stripes, sigma=5, axes=(1, 2))
    return stripes


def estimate_1f_noise_beta(bsub, mask, split_amplifier=False):
    import bottleneck as bn
    bsub_temp = np.where(mask, np.nan, bsub)
    min_pix = 15

    if split_amplifier:
        hstripes = np.empty_like(bsub_temp)
        n_cols = bsub_temp.shape[-1]
        idx = np.linspace(0, n_cols, 5, dtype=int)
        
        for i in range(4):
            sliced = bsub_temp[:, :, idx[i]:idx[i+1]]
            med = bn.nanmedian(sliced, axis=2)[:, :, None]
            mad = bn.nanmedian(np.abs(sliced - med), axis=2)[:, :, None]
            outlier_mask = np.abs(sliced - med) > 5 * 1.4826 * mad
            
            sliced_clean = np.where(outlier_mask, np.nan, sliced)
            median_vals = bn.nanmedian(sliced_clean, axis=2)[:, :, None]
            valid_count = np.sum(~np.isnan(sliced), axis=2)[:, :, None]
            median_vals[valid_count < min_pix] = np.nan
            hstripes[:, :, idx[i]:idx[i+1]] = median_vals
    else:
        med = bn.nanmedian(bsub_temp, axis=2)[:, :, None]
        mad = bn.nanmedian(np.abs(bsub_temp - med), axis=2)[:, :, None]
        outlier_mask = np.abs(bsub_temp - med) > 5 * 1.4826 * mad
        
        bsub_clean = np.where(outlier_mask, np.nan, bsub_temp)
        hstripes = bn.nanmedian(bsub_clean, axis=2)[:, :, None]
        
        valid_count = np.sum(~np.isnan(bsub_temp), axis=2)[:, :, None]
        hstripes[valid_count < min_pix] = np.nan

    hstripes = clip_strip_outlier(hstripes).data

    diff = bsub_temp - hstripes
    vstripes = bn.nanmedian(diff, axis=1)[:, None, :]
    valid_count_v = np.sum(~np.isnan(bsub_temp), axis=1)[:, None, :]
    vstripes[valid_count_v < min_pix] = np.nan
    vstripes = clip_strip_outlier(vstripes).data

    hstripes = np.asarray(hstripes)
    vstripes = np.asarray(vstripes)
    strips = hstripes + vstripes

    return strips

def correct1f(data, mask):
    """
    High-level function to correct 1/f noise
    compatible with single and multiple exposures format of data.
    """
    try:
        import bottleneck as bn
        _HAS_BOTTLENECK = True
    except ImportError:
        _HAS_BOTTLENECK = False
        warnings.warn(
        "bottleneck is not installed. 1/f correction will be slow. "
        "Recommended: pip install bottleneck",
        RuntimeWarning,
        stacklevel=2,
        )
    
    with warnings.catch_warnings():
        warnings.filterwarnings(
            "ignore",
            message=".*Input data contains invalid values.*",
            category=Warning,
        )
        warnings.filterwarnings(
            "ignore",
            category=RuntimeWarning,
            message="All-NaN slice encountered",
        )

        single = (data.ndim == 2)
        if single:
            data = data[None, :, :]
            mask = mask[None, :, :]
        if _HAS_BOTTLENECK:
            stripes = estimate_1f_noise_beta(data, mask, split_amplifier=False)
        else:
            stripes = _correct1f(data, mask, sigma=2)
        if single:
            stripes = stripes[0]

    return stripes


# ---- Mischellaneous ----
def subtract_median(data, *mask):
    mask = np.any(mask, axis=0)
    median = np.nanmedian(data[~mask])
    return data - median


# ---- io functions ----

def oversample(data, factor=(4, 4)):
    """
    Parameters:
        data (ndarray): Input 2D array.
        factor (int or tuple): Oversampling factor (single int or tuple of two ints).

    Returns:
        ndarray: Oversampled array.
    """
    from scipy.ndimage import zoom
    factor = (factor, factor) if isinstance(factor, int) else factor
    return zoom(data, zoom=factor, order=1)


def _load_wisp_templates(filename, oversample_factor=None):
    """
    Load WISP data from a FITS file, with optional oversampling.

    Parameters:
        filename (str): Path to the FITS file.
        oversample_factor (int or tuple, optional): Oversampling factor. Default is None.

    Returns:
        tuple: WISP template (3D ndarray), WISP mask (2D ndarray), high SNR region (2D ndarray).
    """
    if hasattr(filename, "open") and not isinstance(filename, (str, bytes, os.PathLike)):
        with filename.open("rb") as fileobj:
            with fits.open(fileobj) as hdul:
                wisp_ext = [f'WISP_{i}' for i in range(10) if f'WISP_{i}' in hdul]
                wisp_template = np.array([hdul[ext].data for ext in wisp_ext])
                if wisp_template.ndim == 2:  # Ensure 3D format
                    wisp_template = wisp_template[None, :, :]

                high_snr_region = hdul['MASK_hSNR'].data.astype(bool)
                wmask = hdul['MASK'].data.astype(bool)
                if 'ERR' in hdul:
                    template_err = hdul['ERR'].data
                else:
                    template_err = None
    else:
        with fits.open(filename) as hdul:
            wisp_ext = [f'WISP_{i}' for i in range(10) if f'WISP_{i}' in hdul]
            wisp_template = np.array([hdul[ext].data for ext in wisp_ext])
            if wisp_template.ndim == 2:  # Ensure 3D format
                wisp_template = wisp_template[None, :, :]

            high_snr_region = hdul['MASK_hSNR'].data.astype(bool)
            wmask = hdul['MASK'].data.astype(bool)
            if 'ERR' in hdul:
                template_err = hdul['ERR'].data
            else:
                template_err = None

    # Apply oversampling if required
    if oversample_factor is not None:
        oversample_func = lambda data: oversample(data, factor=oversample_factor)
        wmask = oversample_func(wmask)
        high_snr_region = oversample_func(high_snr_region)
        wisp_template = np.array([oversample_func(wt) for wt in wisp_template])

    if template_err is not None:
        if template_err.shape[-1] != wisp_template.shape[-1]:
            template_err = oversample(template_err, factor=(4, 4))

    return wisp_template, template_err, wmask, high_snr_region


def load_wisp_templates(wisp_path, detector_name, filter_name):
    """
    High-level function to load WISP templates from a given path.
    """
    det, filt = detector_name.lower(), filter_name.lower()
    if wisp_path is None:
        path = resources.files("nmfwisp").joinpath("templates")
    else:
        path = Path(wisp_path)

    sampled_base = path.joinpath(det)
    org_base = path.joinpath(f"{det}_org")

    org_file = None
    sampled_file = None
    for ext in (".fits", ".fits.gz"):
        candidate = org_base.joinpath(f"{det}_{filt}_wisp{ext}")
        if candidate.is_file():
            org_file = candidate
            break

    for ext in (".fits", ".fits.gz"):
        candidate = sampled_base.joinpath(f"{det}_{filt}_wisp{ext}")
        if candidate.is_file():
            sampled_file = candidate
            break

    if org_file is not None:
        wisp_template, template_err, wmask, high_snr_region = _load_wisp_templates(org_file, oversample_factor=(1, 1))
    elif sampled_file is not None:
        wisp_template, template_err, wmask, high_snr_region = _load_wisp_templates(sampled_file, oversample_factor=(4, 4))
    else:
        return None, None, None, None

    return wisp_template, template_err, wmask, high_snr_region


# ---- Core Subtraction Functions ----

def _subtract_wisp(data, wisp_template, err=None, mask=None,
                  template_err=None, high_snr_region=None, bool_weighted=False):
    """
    Subtract WISP templates from the data.

    Parameters:
    ------------
    data: (n_exp, n_y, n_x)
    wisp_template: (n_template, n_y, n_x). WISP templates.
    err: (n_exp, n_y, n_x). Sigma image of the data.
    mask: (n_exp, n_y, n_x). Mask for bad pixels and sources. True for invalid pixels.
    high_snr_region: (n_y, n_x). Wisp high-SNR region used for the subtraction.

    Returns:
    ------------
    wsub: (n_exp, n_y, n_x). wisp subtracted data.
    wisp: (n_y, n_x). optimized wisp model.
    wsub_err: (n_exp, n_y, n_x). uncertainty of the wisp subtracted data.
    W: (n_exp, n_template). amplitudes of the wisp templates.
    We: (n_exp, n_template). uncertainties of the amplitudes.

    """
    _data, _templates, _err, _mask = auto_reshape(data, wisp_template, err, mask)
    _data, _templates, _err, _mask = select_high_snr_region(high_snr_region, _data, _templates, _err, _mask)

    W, We = solve_amp(_data, _templates, _err, _mask, bool_weighted)

    wisp = np.einsum('ij,jmn->imn', W, wisp_template)
    wsub = data - wisp
    wisp_e = calc_wisp_err(W, We, wisp_template, template_err)

    if data.ndim == 2:
        wisp = wisp[0]
        wisp_e = wisp_e[0]

    return wsub, wisp, wisp_e, W, We


def process_data(data, err, mask, wisp_mask):
    mask_nan = np.isnan(data) | np.isnan(err) | (err <= 0) | (~np.isfinite(data)) | (~np.isfinite(err))
    mask_nan[:4] = True
    mask_nan[-4:] = True
    mask_nan[:, :4] = True
    mask_nan[:, -4:] = True
    
    mask = mask.astype(bool) | mask_nan
    data = subtract_median(data, mask, wisp_mask)
    data[mask_nan] = 0.
    err = err.copy()
    err[mask_nan] = np.inf

    return data, err, mask

def estimate_wisp_standard(data, err, mask, wisp_path, detector_name, filter_name):
    """
    Estimate wisp. 

    Parameters:
    ------------
    data: (n_y, n_x) or (n_y, n_x). Data can be single or multiple exposures.
    mask: Mask for bad pixels and sources.


    Returns:
    ------------
    Estimated wisp and its uncertainty.

    """
    detector_name = detector_name.lower()
    filter_name = filter_name.upper()

    if wisp_path is not None:
        assert os.path.exists(wisp_path), f"Wisp path does not exist: {wisp_path}"
    if filter_name == 'F070W':
        warnings.warn("F070W does not have wisps, return zero array.")
        return np.zeros_like(data), np.zeros_like(data)
    if detector_name in ['nrca1', 'nrca2', 'nrcb1', 'nrcb2']:
        warnings.warn(f"{detector_name} detector does not have wisps, return zero array.")
        return np.zeros_like(data), np.zeros_like(data)
    assert detector_name in ['nrca3', 'nrca4', 'nrcb3', 'nrcb4'], f"Invalid detector name: {detector_name}"
    if filter_name not in ['F090W', 'F115W', 'F150W', 'F200W', 'F162M', 'F182M', 'F210M']:
        warnings.warn(f"{filter_name} templates are not available, return zero array.")
        return np.zeros_like(data), np.zeros_like(data)

    wisp_template, template_err, wmask, high_snr_region = load_wisp_templates(wisp_path, detector_name, filter_name)
    if wisp_template is None:
        warnings.warn(f"No wisp template found for detector '{detector_name}' and filter '{filter_name}', return zero array.")
        return np.zeros_like(data), np.zeros_like(data)
    if data.ndim == 2:
        data, err, mask = process_data(data, err, mask, wmask)
    else:
        _data, _err, _mask = np.zeros_like(data), np.zeros_like(data), np.zeros_like(data, dtype=bool)
        for i in range(data.shape[0]):
            _data[i], _err[i], _mask[i] = process_data(data[i], err[i], mask[i], wmask)
        data, err, mask = _data, _err, _mask
    wsub, wisp, wisp_e, W, We = _subtract_wisp(data, wisp_template, err, mask,
                                                 template_err, high_snr_region,
                                                 bool_weighted=False)
    return wisp, wisp_e



def estimate_wisp_with_1fcorrect(data, err, mask, wisp_path, detector_name, filter_name):
    """
    Subtract WISP templates from the data with iterative 1/f correction.

    Even advanced 1/f corrections can leave residual 1/f noise in the wisp region due to 
    their degeneracies, which degrades wisp subtraction. To address this, we apply a simple 
    median-based 1/f correction iteratively alongside wisp subtraction. This approach is 
    sufficient to reduce the influence of 1/f noise on wisp optimization, but it is not always
    accurate enough as a final 1/f solution. We recommend adding back the corrected 1/f noise 
    after wisp subtraction and using a more advanced 1/f correction method afterward.

    Parameters:
    ------------
    data: (n_exp, n_y, n_x)
    wisp_template: (n_template, n_y, n_x). WISP templates.
    err: (n_exp, n_y, n_x). Sigma image of the data.
    mask: (n_exp, n_y, n_x). Mask for bad pixels and sources. True for invalid pixels.
    high_snr_region: (n_y, n_x). Wisp high-SNR region used for the subtraction.
    n_iter: int. Number of iterations for 1/f correction.

    Returns:
    ------------
    wsub: (n_exp, n_y, n_x). wisp subtracted data.
    wisp: (n_y, n_x). optimized wisp model.
    wsub_err: (n_exp, n_y, n_x). uncertainty of the wisp subtracted data.
    W: (n_exp, n_template). amplitudes of the wisp templates.
    We: (n_exp, n_template). uncertainties of the amplitudes.
    stripes_tot: (n_exp, n_y, n_x). 1/f stripes obtained. 
    """
    wisp, wisp_e = estimate_wisp_standard(data, err, mask, wisp_path, detector_name, filter_name)
    
    n_iter = 3

    stripes_tot = np.zeros_like(data)
    for _ in range(n_iter):
        stripes = correct1f(data-wisp, mask)
        stripes_tot += stripes
        data = data - stripes
        wisp, wisp_e = estimate_wisp_standard(data, err, mask, wisp_path, detector_name, filter_name)
    return wisp, wisp_e


def fit_wisp(data, err, mask, wisp_path=None, detector_name=None, filter_name=None, correct_1f=False):
    """
    Estimate wisp. 

    Parameters:
    ------------
    data: (n_y, n_x) or (n_y, n_x). Data can be single or multiple exposures.
    mask: Mask for bad pixels and sources.


    Returns:
    ------------
    Estimated wisp and its uncertainty.

    """
    assert detector_name is not None, "detector_name is required"
    assert filter_name is not None, "filter_name is required"
    if correct_1f:
        wisp, wisp_e = estimate_wisp_with_1fcorrect(data, err, mask, wisp_path, detector_name, filter_name)
    else:
        wisp, wisp_e = estimate_wisp_standard(data, err, mask, wisp_path, detector_name, filter_name)
    return wisp, wisp_e
