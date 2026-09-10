"""Run tests with real companions; verify lossless reads were actually used."""
from pathlib import Path
import os,subprocess,sys,tempfile,shutil
hew=Path(os.environ['HEW_BIN']).resolve()
gramide=Path(os.environ['GRAMIDE_BIN']).resolve()
with tempfile.TemporaryDirectory() as tmp:
 root=Path(tmp);trace=root/'calls';proxy=root/'hew'
 proxy.write_text('#!'+sys.executable+'\nimport os,sys\nwith open('+repr(str(trace))+',"a") as log: log.write(" ".join(sys.argv[1:])+"\\n")\nos.execv('+repr(str(hew))+',['+repr(str(hew))+',*sys.argv[1:]])\n')
 proxy.chmod(0o755)
 grammar_trace=root/'grammar-calls'
 grammar_proxy=root/'gramide'
 grammar_proxy.write_text('#!'+sys.executable+'\nimport os,sys\nwith open('+repr(str(grammar_trace))+',"a") as log: log.write(" ".join(sys.argv[1:])+"\\n")\nos.execv('+repr(str(gramide))+',['+repr(str(gramide))+',*sys.argv[1:]])\n')
 grammar_proxy.chmod(0o755)
 env=dict(os.environ,PATH=str(root)+os.pathsep+str(gramide.parent)+os.pathsep+os.environ.get('PATH',''),HEW_OUTLINE_BIN='')
 subprocess.run([os.environ.get('ALMIDE_BIN','almide'),'test'],env=env,check=True)
 # Compile a probe using the real gate module, without a model call.
 probe=root/'gate-probe';(probe/'src').mkdir(parents=True)
 for module in (Path(__file__).resolve().parents[1]/'src').glob('*.almd'):
  if module.name != 'main.almd':shutil.copyfile(module,probe/'src'/module.name)
 (probe/'almide.toml').write_text('[package]\nname = "gate_probe"\nversion = "0.1.0"\nedition = "2026"\n')
 (probe/'src/main.almd').write_text('import self.gate\neffect fn main() -> Unit = {\n  let c = gate.checker_for("example.go")!\n  assert_eq(c.label, "gramide")\n}\n')
 subprocess.run([os.environ.get('ALMIDE_BIN','almide'),'run'],cwd=probe,env=env,check=True)
 assert 'languages\n' in grammar_trace.read_text()
 calls=trace.read_text()
 assert 'read-json ' in calls and '--max-chars 24000' in calls and '--max-chars 96000' in calls,calls
print('Real gramide → hew → cairn integration passed; language discovery and both read budgets exercised')
