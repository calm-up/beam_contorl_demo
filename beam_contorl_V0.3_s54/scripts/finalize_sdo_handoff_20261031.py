from pathlib import Path
import csv,hashlib,json,zipfile
from pypdf import PdfReader

base=Path(r'D:\beam_control\交付归档')
root=base/'SDO调试交接_20261031'
expected='83CF37BFFDB07A1673AC4493448A4E142C640C050CEF572EF43371E2CC34F9DD'
assert hashlib.sha256((root/'01_最新版s53/program/beam_control_v03_s53.bit').read_bytes()).hexdigest().upper()==expected
source=root/'01_最新版s53/source'
for row in json.loads((root/'01_最新版s53/source_manifest.json').read_text(encoding='utf-8')):
 assert hashlib.sha256((source/row['path']).read_bytes()).hexdigest().upper()==row['sha256'],row['path']
pdf=PdfReader(base/'qa_sdo_report_20261031/report.pdf')
assert len(pdf.pages)==23
assert all(len(p.extract_text() or '')>300 for p in pdf.pages)
for folder in ['s50','s51','s52','s53']:
 a=list((root/'02_历史版本'/folder).glob('*.bit'));b=list((root/'02_历史版本'/folder).glob('*.ltx'))
 assert len(a)==len(b)==1
files=sorted(f for f in root.rglob('*') if f.is_file() and f.name!='SHA256SUMS.csv')
with (root/'SHA256SUMS.csv').open('w',encoding='utf-8-sig',newline='') as f:
 w=csv.writer(f);w.writerow(['relative_path','bytes','sha256'])
 for p in files:w.writerow([p.relative_to(root).as_posix(),p.stat().st_size,hashlib.sha256(p.read_bytes()).hexdigest().upper()])
archive=base/'SDO调试交接_20261031_完整包.zip'
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in sorted(root.rglob('*')):
  if p.is_file():z.write(p,root.name+'/'+p.relative_to(root).as_posix())
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 print('ZIP_FILES',len(z.infolist()))
digest=hashlib.sha256(archive.read_bytes()).hexdigest().upper()
archive.with_suffix('.sha256.txt').write_text(digest+'  '+archive.name+'\n',encoding='utf-8')
print(json.dumps({'report_pages':len(pdf.pages),'files':len(files)+1,'zip_MB':round(archive.stat().st_size/1e6,2),'zip_sha256':digest,'zip_crc':'PASS','source_manifest':'PASS','latest_bit':'PASS'},ensure_ascii=False),flush=True)
