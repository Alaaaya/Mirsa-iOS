"""Check actual Swift-generated CAML, not source fingerprints."""
import json,pathlib,re,sys,zipfile,xml.etree.ElementTree as ET,hashlib
root=pathlib.Path(sys.argv[1])
report=json.loads((root/'mechanism-report.json').read_text())
assert len(report)==70 and len({r['mechanism'] for r in report})==70
seen={}
for row in report:
 if row['status']=='EXPLICIT_UNSUPPORTED':
  assert row.get('reason')
  continue
 with zipfile.ZipFile(root/row['archive']) as z:
  assert z.testzip() is None
  documents=[]
  for name in sorted(n for n in z.namelist() if n.endswith('/main.caml')):
   doc=ET.fromstring(z.read(name))
   # Ignore identifiers, labels and UUIDs, but retain schema/property/value differences.
   for node in doc.iter():
    for key,value in list(node.attrib.items()):
     if key in ('name','id'): node.attrib[key]='ID'
     else: node.attrib[key]=re.sub(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}','UUID',value)
   documents.append(ET.canonicalize(ET.tostring(doc,encoding='unicode')))
  fingerprint=hashlib.sha256('\n'.join(documents).encode()).hexdigest()
  assert fingerprint not in seen,(row['mechanism'],seen.get(fingerprint),'duplicate generated CAML')
  seen[fingerprint]=row['mechanism']
  row['canonicalCAML_SHA256']=fingerprint
(root/'mechanism-report-canonical.json').write_text(json.dumps(report,indent=2)+'\n')
print('Actual unique generated CAML',len(seen),'Explicit unsupported',len(report)-len(seen))
