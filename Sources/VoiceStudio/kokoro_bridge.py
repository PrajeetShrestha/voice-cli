#!/usr/bin/env python3
"""Optional Kokoro adapter and portable, loopback-only Voice Studio server.
Detection never imports the model or downloads assets. Synthesis is a child process
with a bounded lifetime so errors and resource use cannot wedge the HTTP server.
"""
import argparse, importlib.util, json, math, os, pathlib, platform, secrets, shutil
import subprocess, sys, tempfile, threading, time, urllib.parse, webbrowser, signal
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

GROUPS = {
 'af': ('en-US','Female','heart alloy aoede bella jessica kore nicole nova river sarah sky'),
 'am': ('en-US','Male','adam echo eric fenrir liam michael onyx puck santa'),
 'bf': ('en-GB','Female','alice emma isabella lily'), 'bm': ('en-GB','Male','daniel fable george lewis'),
 'jf': ('ja-JP','Female','alpha gongitsune nezumi tebukuro'), 'jm': ('ja-JP','Male','kumo'),
 'zf': ('zh-CN','Female','xiaobei xiaoni xiaoxiao xiaoyi'), 'zm': ('zh-CN','Male','yunjian yunxi yunxia yunyang'),
 'ef': ('es','Female','dora'), 'em': ('es','Male','alex santa'), 'ff': ('fr-FR','Female','siwis'),
 'hf': ('hi-IN','Female','alpha beta'), 'hm': ('hi-IN','Male','omega psi'),
 'if': ('it-IT','Female','sara'), 'im': ('it-IT','Male','nicola'),
 'pf': ('pt-BR','Female','dora'), 'pm': ('pt-BR','Male','alex santa')}
VOICES = [dict(id=p+'_'+n,name=n.title(),language=lang,gender=gender,quality='Neural',engine='kokoro')
          for p,(lang,gender,names) in GROUPS.items() for n in names.split()]
IDS = {v['id'] for v in VOICES}

def detect():
    importlib.invalidate_caches()
    missing = [p for p in ('kokoro','torch','soundfile') if importlib.util.find_spec(p) is None]
    if sys.version_info < (3,10): missing.append('Python 3.10+')
    return dict(id='kokoro', name='Kokoro', available=not missing, python=sys.executable,
                reason=('Missing Python packages: '+', '.join(missing)) if missing else 'Python packages detected. Model/language assets are checked during generation.',
                voices=VOICES if not missing else [],
                setup='Install kokoro, torch and soundfile in a Python 3.10+ virtual environment; set VOICE_STUDIO_KOKORO_PYTHON to its python executable, then restart. No automatic installation.')

def validate(data):
    if not isinstance(data,dict): raise ValueError('Expected a JSON object.')
    if data.get('engine','kokoro') != 'kokoro': raise ValueError('Only Kokoro is available on this server.')
    text=data.get('text'); voice=data.get('voice'); speed=data.get('rate',1.0)
    if not isinstance(text,str) or not text.strip() or len(text)>10000: raise ValueError('Provide 1–10,000 characters.')
    if voice not in IDS: raise ValueError('Unknown Kokoro voice.')
    if isinstance(speed,bool) or not isinstance(speed,(int,float)) or not math.isfinite(speed) or not .5<=speed<=2: raise ValueError('Kokoro speed must be between 0.5 and 2.0.')
    if not isinstance(data.get('allowDownloads',False),bool): raise ValueError('allowDownloads must be boolean.')
    return text,voice,speed

def render(data,output):
    text,voice,speed=validate(data)
    if not data.get('allowDownloads',False):
        os.environ['HF_HUB_OFFLINE']='1'; os.environ['TRANSFORMERS_OFFLINE']='1'
    os.environ.setdefault('TOKENIZERS_PARALLELISM','false')
    import torch, soundfile as sf
    from kokoro import KPipeline
    torch.set_num_threads(min(4,os.cpu_count() or 1))
    # English G2P otherwise tries a pip download. Require explicit asset consent.
    if voice[0] in 'ab' and not data.get('allowDownloads',False):
        model='en_core_web_sm'
        if importlib.util.find_spec(model) is None:
            raise RuntimeError('English language asset en_core_web_sm is missing. Enable asset downloads for first use, or install it in your Kokoro environment.')
    pipe=KPipeline(lang_code=voice[0],repo_id='hexgrad/Kokoro-82M',device='cpu')
    count=0
    with sf.SoundFile(output,mode='w',format='WAV',samplerate=24000,channels=1,subtype='PCM_16') as f:
        for _,_,audio in pipe(text,voice=voice,speed=speed):
            if audio is not None:
                f.write(audio.detach().cpu().numpy() if hasattr(audio,'detach') else audio); count+=len(audio)
    if not count: raise RuntimeError('Kokoro produced no audio.')

def encode(data,root):
    validate(data)
    ident=secrets.token_hex(16); wav=root/(ident+'.wav'); mp3=root/(ident+'.mp3'); inp=root/(ident+'.json')
    inp.write_text(json.dumps(data),encoding='utf8'); inp.chmod(0o600)
    try:
        result=subprocess.run([sys.executable,__file__,'render',str(inp),str(wav)],capture_output=True,text=True,timeout=300)
        if result.returncode: raise RuntimeError('Kokoro could not generate audio. Check installed model/language assets. '+result.stderr[-1000:])
        subprocess.run([shutil.which('ffmpeg'),'-v','error','-nostdin','-n','-i',str(wav),'-codec:a','libmp3lame','-q:a','2',str(mp3)],capture_output=True,check=True,timeout=120)
        return ident
    except Exception:
        mp3.unlink(missing_ok=True); raise
    finally:
        wav.unlink(missing_ok=True); inp.unlink(missing_ok=True)

def serve(no_open=False):
    engine=detect(); encoder=shutil.which('ffmpeg')
    try: encoder_ok=bool(encoder and 'libmp3lame' in subprocess.run([encoder,'-hide_banner','-encoders'],capture_output=True,text=True,timeout=10).stdout)
    except Exception: encoder_ok=False
    key=secrets.token_urlsafe(48); lock=threading.Lock(); outputs=[]
    with tempfile.TemporaryDirectory(prefix='voice-studio-') as folder:
        root=pathlib.Path(folder); root.chmod(0o700)
        class Handler(BaseHTTPRequestHandler):
            def log_message(self,*args): pass
            def setup(self):
                super().setup(); self.connection.settimeout(20)
            def reply(self,code,data,kind='application/json'):
                body=json.dumps(data).encode() if kind=='application/json' else data
                self.send_response(code); self.send_header('Content-Type',kind); self.send_header('Content-Length',str(len(body)))
                self.send_header('Cache-Control','no-store'); self.send_header('X-Content-Type-Options','nosniff'); self.send_header('Referrer-Policy','no-referrer')
                self.send_header('Content-Security-Policy',"default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; media-src blob:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
                self.end_headers(); self.wfile.write(body)
            def authorized(self):
                if self.headers.get('Host')!=host or self.headers.get('Origin',origin)!=origin:
                    self.reply(403,{'error':'Untrusted host or origin'}); return False
                if self.path=='/' and self.command=='GET': return True
                if self.headers.get('Authorization')!='Bearer '+key:
                    self.reply(403,{'error':'Open the URL printed by the CLI.'}); return False
                return True
            def do_GET(self):
                if not self.authorized(): return
                if self.path=='/': return self.reply(200,pathlib.Path(__file__).with_name('index.html').read_bytes(),'text/html; charset=utf-8')
                if self.path=='/api/status':
                    engine.update(detect())
                    free=shutil.disk_usage(root).free; blockers=[]
                    if not encoder_ok: blockers.append('ffmpeg with libmp3lame is required.')
                    if free<256*1024**2: blockers.append('Less than 256 MiB temporary disk space available.')
                    if not engine['available']: blockers.append(engine['reason'])
                    try: memory=os.sysconf('SC_PAGE_SIZE')*os.sysconf('SC_PHYS_PAGES')
                    except (ValueError,AttributeError): memory=0
                    specs=dict(os=platform.platform(),architecture=platform.machine(),cores=os.cpu_count(),memoryBytes=memory,diskFreeBytes=free,ffmpeg=encoder or 'Not found',encoderReady=encoder_ok,ready=not blockers,blockers=blockers,requirements=['Python 3.10+ with Kokoro, PyTorch and soundfile','ffmpeg with libmp3lame','Model/voice assets and language dependencies; first download needs internet','CPU inference; no NVIDIA GPU required','256 MiB temporary disk reserve'])
                    return self.reply(200,dict(specs=specs,voices=[],engines=[engine],busy=lock.locked()))
                if self.path.startswith('/api/audio/'):
                    ident=self.path[len('/api/audio/'):]
                    if ident in outputs: return self.reply(200,(root/(ident+'.mp3')).read_bytes(),'audio/mpeg')
                self.reply(404,{'error':'Not found'})
            def do_POST(self):
                if not self.authorized(): return
                if self.path!='/api/generate': return self.reply(404,{'error':'Not found'})
                try:
                    if self.headers.get('Transfer-Encoding') or len(self.headers.get_all('Content-Length',[]))!=1: raise ValueError('Invalid body framing.')
                    size=int(self.headers.get('Content-Length','0'))
                    if not 0<size<=65536 or not self.headers.get('Content-Type','').startswith('application/json'): raise ValueError('Invalid JSON request.')
                    data=json.loads(self.rfile.read(size)); validate(data)
                except (ValueError,TypeError): return self.reply(400,{'error':'Invalid input. Use a known voice, nonblank text up to 10,000 characters, and speed 0.5–2.0.'})
                if not engine['available'] or not encoder_ok or shutil.disk_usage(root).free<256*1024**2: return self.reply(503,{'error':'Requirements are unmet. Check Device readiness.'})
                if not lock.acquire(False): return self.reply(409,{'error':'Another generation is running.'})
                try:
                    ident=encode(data,root); outputs.append(ident)
                    if len(outputs)>20: (root/(outputs.pop(0)+'.mp3')).unlink(missing_ok=True)
                    self.reply(200,dict(id=ident,voice=data['voice'],download='/api/audio/'+ident))
                except Exception as exc: self.reply(422,{'error':str(exc)})
                finally: lock.release()
        class Server(ThreadingHTTPServer):
            slots=threading.BoundedSemaphore(8)
            def process_request(self,request,address):
                if not self.slots.acquire(False):
                    self.shutdown_request(request); return
                try: super().process_request(request,address)
                except Exception:
                    self.slots.release(); raise
            def process_request_thread(self,request,address):
                try: super().process_request_thread(request,address)
                finally: self.slots.release()
        server=Server(('127.0.0.1',0),Handler); server.daemon_threads=True
        host='127.0.0.1:'+str(server.server_port); origin='http://'+host; url=origin+'/#'+key
        print('Voice Studio\nLocal only. Stop with Control-C.\nOpen: '+url,flush=True)
        if not no_open: webbrowser.open(url)
        signal.signal(signal.SIGTERM,lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
        try: server.serve_forever()
        except KeyboardInterrupt: pass
        finally: server.server_close()

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('command',choices=['detect','render','serve']); parser.add_argument('paths',nargs='*'); parser.add_argument('--no-open',action='store_true'); args=parser.parse_args()
    if args.command=='detect': print(json.dumps(detect()))
    elif args.command=='serve': serve(args.no_open)
    elif len(args.paths)==2: render(json.loads(pathlib.Path(args.paths[0]).read_text()),args.paths[1])
    else: parser.error('render requires input JSON and output WAV')
