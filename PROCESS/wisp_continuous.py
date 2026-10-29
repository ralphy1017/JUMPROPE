"""[nep-miri] Continuous, source-protected residual wisp models.

Residual templates are learned from OTHER exposures, never the evaluated frame.
Sky/row/column nuisance estimates are used only for fitting. Science pixels are
never inpainted. Signed corrections replace the positive-only dynamic floor.
"""
from pathlib import Path
import numpy as np
from scipy import ndimage as ndi, sparse
from scipy.sparse.linalg import spsolve
from scipy.optimize import lsq_linear


def robust_sigma(a):
    a=np.asarray(a);a=a[np.isfinite(a)]
    if not a.size:raise ValueError('No finite noise samples')
    return float(1.4826*np.median(np.abs(a-np.median(a))))


def _line_median(a,axis,minimum=24):
    import warnings
    with warnings.catch_warnings():
        warnings.simplefilter('ignore',RuntimeWarning)
        value=np.nanmedian(a,axis=axis)
    count=np.isfinite(a).sum(axis=axis);ok=(count>=minimum)&np.isfinite(value)
    if ok.sum()<2:raise ValueError('Insufficient unmasked samples for stripe baseline')
    idx=np.arange(len(value));return np.interp(idx,idx[ok],value[ok])


def baseline(data,source_mask,support,valid,iterations=3):
    """Common source/wisp-protected sky and stripe baseline for BOTH models."""
    bg=valid&~source_mask&~ndi.binary_dilation(support,iterations=24)
    if bg.sum()<1000:raise ValueError('Insufficient protected background')
    sky=float(np.median(data[bg]));work=np.where(bg,data-sky,np.nan)
    sigma=robust_sigma(work[bg]);use=bg&(np.abs(data-sky)<5*max(sigma,1e-12))
    rows=np.zeros(data.shape[0]);cols=np.zeros(data.shape[1])
    for _ in range(iterations):
        residual=np.where(use,data-sky-cols[None,:],np.nan)
        rows=_line_median(residual,axis=1)
        residual=np.where(use,data-sky-rows[:,None],np.nan)
        cols=_line_median(residual,axis=0)
        sky+=float(np.median((rows[:,None]+cols[None,:])[bg]))
        rows-=float(np.median(rows));cols-=float(np.median(cols))
    stripes=rows[:,None]+cols[None,:]
    shift=float(np.median((data-sky-stripes)[bg]));sky+=shift
    return sky,stripes,bg


def support_taper(region,margin=32):
    extended=ndi.binary_dilation(region,iterations=margin)
    distance=ndi.distance_transform_edt(extended)
    x=np.minimum(1,distance/float(margin));weight=x*x*(3-2*x)
    weight[~extended]=0
    return weight


def harmonic_fill(image,known,block=8):
    """Coarse harmonic extension of MODEL residuals; no science data filling."""
    ny,nx=image.shape
    if ny%block or nx%block:raise ValueError('Residual image must divide into interpolation blocks')
    shape=(ny//block,block,nx//block,block)
    count=known.reshape(shape).sum((1,3))
    values=np.where(known,image,0).reshape(shape).sum((1,3))/np.maximum(count,1)
    fixed=count>=max(4,block*block//4)
    if fixed.sum()<100:raise ValueError('Insufficient independent residual support')
    unknown=~fixed;coords=np.argwhere(unknown)
    if not len(coords):return ndi.zoom(values,block,order=1)
    index=np.full(values.shape,-1,int);index[unknown]=np.arange(len(coords))
    rr=[];cc=[];vv=[];rhs=np.zeros(len(coords))
    for i,(y,x) in enumerate(coords):
        degree=0
        for dy,dx in ((-1,0),(1,0),(0,-1),(0,1)):
            yy,xx=y+dy,x+dx
            if 0<=yy<values.shape[0] and 0<=xx<values.shape[1]:
                degree+=1
                if unknown[yy,xx]:rr.append(i);cc.append(index[yy,xx]);vv.append(-1.)
                else:rhs[i]+=values[yy,xx]
        rr.append(i);cc.append(i);vv.append(float(degree))
    matrix=sparse.csr_matrix((vv,(rr,cc)),shape=(len(coords),len(coords)))
    values[unknown]=spsolve(matrix,rhs)
    if not np.isfinite(values).all():raise ValueError('Residual interpolation did not converge')
    return ndi.zoom(values,block,order=1)


def residual_basis(residuals,good,support,sigma_hi=2.,sigma_lo=2.,clip_threshold=.99999):
    import warnings
    with warnings.catch_warnings():
        warnings.simplefilter('ignore',RuntimeWarning)
        count=np.sum(good,axis=0)
        median=np.nanmedian(np.where(good,residuals,np.nan),axis=0)
    known=(count>=2)&np.isfinite(median)
    # The correction has a common zero outside physical wisp support.
    region=ndi.binary_dilation(support,iterations=32)
    known|=~region;median[~region]=0
    use=known&region
    if use.sum()<500:raise ValueError('Insufficient independent wisp measurements')
    lo,hi=np.quantile(median[use],[1-clip_threshold,clip_threshold])
    known &= (~region)|((median>=lo)&(median<=hi))
    interpolated=harmonic_fill(np.nan_to_num(median),known)
    filled=np.where(known,median,interpolated)
    high=ndi.gaussian_filter(filled,float(sigma_hi))
    low=ndi.gaussian_filter(high,float(sigma_lo))
    taper=support_taper(support)
    return np.asarray([low*taper,(high-low)*taper]),count


def fit(data,err,prior,source_mask,support,high_snr,basis,valid=None):
    """Fit only global signed amplitudes. No mask-shaped model replacement."""
    if valid is None:valid=np.isfinite(data)&np.isfinite(err)&(err>0)
    sky,stripes,bg=baseline(data,source_mask,support,valid)
    selected=valid&~source_mask&high_snr
    if selected.sum()<500:raise ValueError('Insufficient protected wisp fit pixels')
    idx=np.flatnonzero(selected);idx=idx[::max(1,len(idx)//120000)]
    # Discard the fitted constant nuisance term; it never becomes wisp light.
    noise=max(robust_sigma((data-sky-stripes)[bg]),1e-12)
    design=np.c_[basis[0].ravel()[idx]/noise,basis[1].ravel()[idx]/noise,np.ones(len(idx))]
    target=(data-sky-stripes-prior).ravel()[idx]/noise
    weight=noise/np.maximum(err.ravel()[idx],noise*.1)
    keep=np.isfinite(target)&np.isfinite(design).all(axis=1)&np.isfinite(weight)
    coef=np.zeros(3)
    for _ in range(4):
        sol=lsq_linear(design[keep]*weight[keep,None],target[keep]*weight[keep],
             bounds=([-4.,-4.,-2.],[4.,4.,2.]),tol=1e-8)
        if not sol.success:raise ValueError('Continuous residual fit failed')
        coef=sol.x;res=target-design@coef
        spread=max(.5,robust_sigma(res[keep]));center=np.median(res[keep])
        keep=np.isfinite(res)&(np.abs(res-center)<4*spread)
    correction=coef[0]*basis[0]+coef[1]*basis[1]
    latent=prior+correction
    # Physical constraint acts on an independently learned model, not pixel noise.
    model=np.maximum(0,latent)
    model[~valid]=0
    if not np.isfinite(model).all():raise ValueError('Nonfinite continuous model')
    return dict(model=model,sky=sky,stripes=stripes,meta=dict(method='continuous_dynamic',
        sky=sky,coefficients=coef[:2].tolist(),discarded_nuisance_offset=float(coef[2]*noise),
        n_fit=int(keep.sum()),source_fraction=float(source_mask.mean()),noise=noise,
        n_negative_latent=int(np.sum(latent<0)),target_pixels_used_to_build_basis=False))
