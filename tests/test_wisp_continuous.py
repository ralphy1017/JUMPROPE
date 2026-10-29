"""[nep-miri] Background continuity and source-exclusion regression checks."""
import sys,unittest
from pathlib import Path
import numpy as np
from scipy import ndimage as ndi
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'PROCESS'))
import wisp_continuous as w

class ContinuousWispTests(unittest.TestCase):
 def test_constant_signed_residual_survives_a_hole(self):
  yy,xx=np.indices((256,256));known=(xx-128)**2+(yy-128)**2>60**2
  field=np.full((256,256),-.2)
  result=w.harmonic_fill(field,known)
  self.assertLess(float(np.max(np.abs(result+.2))),1e-10)
 def test_source_exclusion_and_background_zero(self):
  rng=np.random.default_rng(4);yy,xx=np.indices((256,256))
  support=(xx>70)&(xx<186)&(yy>70)&(yy<186)
  mask=(xx-128)**2+(yy-128)**2<18**2
  prior=.5*np.exp(-((xx-128)**2+(yy-128)**2)/(2*30**2))*support
  ridge=.3*np.exp(-(xx-126)**2/(2*3**2))*np.exp(-(yy-128)**2/(2*22**2))
  high=ndi.gaussian_filter(ridge,2);low=ndi.gaussian_filter(high,2)
  taper=w.support_taper(support);basis=np.array([low*taper,(high-low)*taper])
  truth=prior+.8*basis[0]+1.3*basis[1]
  data=5+truth+rng.normal(0,.005,truth.shape);err=np.full(data.shape,.005)
  first=w.fit(data,err,prior,mask,support,support,basis)
  altered=data.copy();altered[mask]+=100
  second=w.fit(altered,err,prior,mask,support,support,basis)
  self.assertTrue(np.array_equal(first['model'],second['model']))
  off=~ndi.binary_dilation(support,iterations=32)
  self.assertTrue(np.all(first['model'][off]==0))
  self.assertLess(float(np.max(np.abs(first['model']-truth))),.03)

 def test_portable_preparation_and_verification(self):
  import tempfile,json,hashlib
  from astropy.io import fits
  from unittest.mock import patch
  import prepare_wisp_continuous as prepare
  rng=np.random.default_rng(7);yy,xx=np.indices((256,256))
  support=(xx>70)&(xx<186)&(yy>70)&(yy<186)
  prior=.1*np.exp(-((xx-128)**2+(yy-128)**2)/(2*25**2))*support
  mask=(xx-125)**2+(yy-125)**2<12**2
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp);records=[];originals={}
   for i in range(3):
    path=root/f'frame{i}_cal.fits';data=.2+prior+rng.normal(0,.005,prior.shape)
    primary=fits.PrimaryHDU();primary.header['DETECTOR']='NRCA3';primary.header['FILTER']='F200W'
    sci=fits.ImageHDU((data-prior).astype('f4'),name='SCI');sci.header['WISPMETH']='NMF'
    hd=[primary,sci,fits.ImageHDU(data.astype('f4'),name='SCI_ORIG'),
      fits.ImageHDU(np.full(data.shape,.005,dtype='f4'),name='ERR'),
      fits.ImageHDU(np.zeros(data.shape,dtype='i2'),name='DQ'),
      fits.ImageHDU(prior.astype('f4'),name='WISP_TEMPLATE'),
      fits.ImageHDU(mask.astype('u1'),name='WISP_SOURCE_MASK'),
      fits.ImageHDU(np.zeros(data.shape,dtype='f4'),name='WISP_ERR')]
    fits.HDUList(hd).writeto(path);records.append(dict(input=str(path)))
    originals[path]=hashlib.sha256(path.read_bytes()).hexdigest()
   cache=root/'cache'
   with patch.object(prepare.nmfwisp,'load_wisp_templates',return_value=(None,None,support,support)):
    prepare.group_worker((records,str(cache),'unused',2,2,.99999))
   prepare.verify(records,cache/'basis',cache/'priors')
   for i in range(3):
    meta=json.loads((cache/'basis'/f'frame{i}.json').read_text())
    self.assertNotIn(f'frame{i}',meta['reference_frames'])
    self.assertEqual(meta['parameters']['clip_threshold'],.99999)
   for path,checksum in originals.items():self.assertEqual(checksum,hashlib.sha256(path.read_bytes()).hexdigest())

if __name__=='__main__':unittest.main()
