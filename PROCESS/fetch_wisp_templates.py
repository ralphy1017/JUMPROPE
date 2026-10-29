"""Download the pinned F200W templates once; no network during science processing."""
import argparse,hashlib,json,urllib.request
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('destination',type=Path);a=p.parse_args()
m=json.loads((Path(__file__).parent/'vendor/nmfwisp_templates.json').read_text())
for name,expected in m['files'].items():
    target=a.destination/name;target.parent.mkdir(parents=True,exist_ok=True)
    if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest()==expected:continue
    url=f"https://raw.githubusercontent.com/zihaowu-astro/NMFwisp/{m['commit']}/nmfwisp/templates/{name}"
    data=urllib.request.urlopen(url,timeout=120).read()
    if hashlib.sha256(data).hexdigest()!=expected:raise RuntimeError('Template hash mismatch: '+name)
    temporary=target.with_suffix('.download');temporary.write_bytes(data);temporary.replace(target)
    print(target)
