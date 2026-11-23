from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import urllib.request, hashlib, json, datetime, sys
repo=Path(sys.argv[1]);out=Path(sys.argv[2]);out.parent.mkdir(parents=True,exist_ok=True)
manifest=json.loads((repo/'website/snapshot.json').read_text())
def check(item):
    url='https://saytile.com/'+item['path']
    try:
        with urllib.request.urlopen(urllib.request.Request(url,headers={'Cache-Control':'no-cache','User-Agent':'Saytile-Release-Verification/1.0'}),timeout=45) as r:
            data=r.read();status=r.status;final=r.url;etag=r.headers.get('ETag')
        digest=hashlib.sha256(data).hexdigest()
        return {'path':item['path'],'url':url,'final_url':final,'http_status':status,'bytes':len(data),'sha256':digest,'expected_sha256':item['sha256'],'etag':etag,'status':'PASS' if status==200 and digest==item['sha256'] and len(data)==item['bytes'] else 'FAIL'}
    except Exception as e:return {'path':item['path'],'url':url,'status':'FAIL','error':str(e)}
with ThreadPoolExecutor(max_workers=4) as pool: results=list(pool.map(check,manifest['runtime_files']))
receipt={'verified_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'production':'https://saytile.com/','files':results,'status':'PASS' if all(i['status']=='PASS' for i in results) else 'FAIL'}
out.write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'status':receipt['status'],'files':len(results),'failed':[i['path'] for i in results if i['status']!='PASS']}));sys.exit(receipt['status']!='PASS')
