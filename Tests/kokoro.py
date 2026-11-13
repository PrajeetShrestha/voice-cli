"""Portable adapter contract/security tests, no neural packages required."""
import importlib.util, pathlib, unittest, subprocess, sys, json, urllib.request, urllib.error
P=pathlib.Path(__file__).resolve().parents[1]/'Sources/VoiceStudio/kokoro_bridge.py'
spec=importlib.util.spec_from_file_location('bridge',P); b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
class Tests(unittest.TestCase):
 def test_catalog(self):
  self.assertEqual(len(b.VOICES),54);self.assertEqual(len(b.IDS),54)
  self.assertEqual(sum(v['id'].startswith('am_') for v in b.VOICES),9)
 def test_validation(self):
  data=dict(text='Hello',voice='af_heart',rate=1)
  self.assertEqual(b.validate(data),('Hello','af_heart',1))
  for key,val in [('text',''),('text',' '*10),('text','x'*10001),('voice','../../a'),('rate',float('nan')),('rate',True),('rate',2.1),('allowDownloads','yes'),('engine','unknown')]:
   with self.assertRaises((ValueError,TypeError)):b.validate({**data,key:val})
 def test_server(self):
  p=subprocess.Popen([sys.executable,str(P),'serve','--no-open'],stdout=subprocess.PIPE,text=True)
  try:
   for line in p.stdout:
    if line.startswith('Open: '):url,key=line.strip()[6:].split('/#');break
   def req(path,payload=None,auth=True,origin=None):
    headers={'Authorization':'Bearer '+key} if auth else {}
    if origin:headers['Origin']=origin
    if payload is not None:headers['Content-Type']='application/json'
    r=urllib.request.Request(url+path,data=None if payload is None else json.dumps(payload).encode(),headers=headers)
    try:
     with urllib.request.urlopen(r,timeout=10) as result:return result.status,result.read()
    except urllib.error.HTTPError as e:return e.code,e.read()
   self.assertEqual(req('/api/status',auth=False)[0],403)
   self.assertEqual(req('/api/status',origin='https://evil.example')[0],403)
   status,body=req('/api/status');self.assertEqual(status,200);self.assertEqual(json.loads(body)['engines'][0]['id'],'kokoro')
   self.assertEqual(req('/')[0],200)
   self.assertEqual(req('/api/audio/../../etc/passwd')[0],404)
   self.assertEqual(req('/api/generate',dict(text='hi',voice='bad',rate=1))[0],400)
  finally:p.terminate();p.wait(timeout=10);p.stdout.close()
if __name__=='__main__':unittest.main()
