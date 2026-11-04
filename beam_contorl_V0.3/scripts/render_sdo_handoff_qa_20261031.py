from pathlib import Path
import importlib.util
import pypdfium2 as pdfium
from pypdf import PdfReader
from PIL import Image,ImageOps,ImageDraw

OUT=Path(r'D:\beam_control\交付归档\qa_sdo_report_20261031')
pdf=OUT/'report.pdf'
skill=Path(r'C:\Users\LENOVO\.codex\plugins\cache\openai-primary-runtime\documents\26.1026.10807\skills\documents\render_docx.py')
spec=importlib.util.spec_from_file_location('doc_renderer',skill)
renderer=importlib.util.module_from_spec(spec);spec.loader.exec_module(renderer)
# The packaged LibreOffice converter is unavailable. Word exported the PDF;
# keep the packaged rasterize pipeline and use bundled PDFium for page images.
renderer.convert_to_pdf=lambda *args,**kwargs:(str(pdf),'Microsoft Word ExportAsFixedFormat')
def convert(path,dpi,fmt,thread_count,output_folder,paths_only,output_file):
 d=pdfium.PdfDocument(path);paths=[]
 for i,page in enumerate(d):
  im=page.render(scale=dpi/72).to_pil()
  p=Path(output_folder)/f'page0001-{i+1:02d}.png';im.save(p);paths.append(str(p))
 return paths
renderer.convert_from_path=convert
images=renderer.rasterize(str(OUT/'preview.docx'),str(OUT),130,False,False)
reader=PdfReader(pdf)
for i,page in enumerate(reader.pages):
 t=page.extract_text() or ''
 print(i+1,len(t),t[:80].replace('\n',' '))
thumbs=[]
for i,p in enumerate(images):
 im=Image.open(p).convert('RGB'); im.thumbnail((330,440))
 tile=Image.new('RGB',(350,470),'#dddddd');tile.paste(im,((350-im.width)//2,5))
 ImageDraw.Draw(tile).text((12,448),str(i+1),fill='black');thumbs.append(tile)
for start in range(0,len(thumbs),8):
 group=thumbs[start:start+8];sheet=Image.new('RGB',(1400,940),'white')
 for j,im in enumerate(group):sheet.paste(im,((j%4)*350,(j//4)*470))
 sheet.save(OUT/f'contact_{start//8+1}.png')
