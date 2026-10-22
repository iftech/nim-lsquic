import os,subprocess,json,datetime,sys,itertools
from pathlib import Path
os.sched_setaffinity(0,{0})
confirmation = sys.argv[1] == '--confirmation'
args = sys.argv[2:] if confirmation else sys.argv[1:]
name=args[0];variants=args[1:];n=len(variants)
orders=[variants]+[variants[i:]+variants[:i] for i in range(n)]+[list(reversed(variants[i:]+variants[:i])) for i in range(n)]
if confirmation:
 assert n == 3
 orders=[variants]+list(itertools.permutations(variants))*2
records=[]
for trial,order in enumerate(orders):
 for position,variant in enumerate(order):
  started=datetime.datetime.now(datetime.timezone.utc).isoformat()
  result=subprocess.run(['/tmp/udp-bench-'+variant],capture_output=True,text=True,timeout=180,check=True)
  rows=[json.loads(line) for line in result.stdout.splitlines() if line.startswith('{')]
  assert len(rows)==3,result.stdout
  for row in rows:row.update(variant=variant,trial=trial,cpu=0,warmup=trial==0,position=position,started_utc=started)
  records.extend(rows)
  Path('/tmp/udp-experiment-'+name+'.json').write_text(json.dumps(records,indent=2))
  print(trial,variant,rows[0]['mbps'],flush=True)
