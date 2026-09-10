"""Run tests with real companions; verify lossless reads were actually used."""
from pathlib import Path
import os,subprocess,sys,tempfile
hew=Path(os.environ['HEW_BIN']).resolve()
gramide=Path(os.environ['GRAMIDE_BIN']).resolve()
with tempfile.TemporaryDirectory() as tmp:
 root=Path(tmp);trace=root/'calls';proxy=root/'hew'
 proxy.write_text('#!'+sys.executable+'\nimport os,sys\nwith open('+repr(str(trace))+',"a") as log: log.write(" ".join(sys.argv[1:])+"\\n")\nos.execv('+repr(str(hew))+',['+repr(str(hew))+',*sys.argv[1:]])\n')
 proxy.chmod(0o755)
 env=dict(os.environ,PATH=str(root)+os.pathsep+str(gramide.parent)+os.pathsep+os.environ.get('PATH',''),HEW_OUTLINE_BIN='')
 subprocess.run([os.environ.get('ALMIDE_BIN','almide'),'test'],env=env,check=True)
 calls=trace.read_text()
 assert 'read-json ' in calls and '--max-chars 24000' in calls and '--max-chars 96000' in calls,calls
print('Real gramide → hew → cairn integration passed; both read budgets exercised')
