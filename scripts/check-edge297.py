import sys,json
from pathlib import Path
from PIL import Image
results=[]
for p in sorted(Path(sys.argv[1]).glob("fullwindow*.png")):
 im=Image.open(p).convert("RGB");w,h=im.size
 # Ignore rounded corner cutouts and central Dynamic Island/home glyph.
 checks={}
 for name,y in [("top1",1),("status",int(h*.035)),("home",h-2),("belowDock",int(h*.975))]:
  xs=list(range(int(w*.20),int(w*.30)))+list(range(int(w*.70),int(w*.80)))
  pixels=[im.getpixel((x,y)) for x in xs]
  ratio=sum(max(rgb)<=2 for rgb in pixels)/len(pixels)
  checks[name]=round(ratio,4)
 results.append({"file":p.name,"size":[w,h],"black_ratios":checks})
print(json.dumps(results,indent=2))
Path(sys.argv[1],"edge297-pixels.json").write_text(json.dumps(results,indent=2))
assert len(results)>=16, f"Only {len(results)} full-device captures"
assert all(max(r["black_ratios"].values())<.10 for r in results),"Solid black safe-area strip remains"
