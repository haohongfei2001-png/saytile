import {createHmac, createHash, timingSafeEqual} from 'node:crypto';

export class Fault extends Error {
  constructor(code, status = 400) { super(code); this.status = status; }
}
export const uuid = s => typeof s === 'string' && /^[\da-f]{8}-(?:[\da-f]{4}-){3}[\da-f]{12}$/i.test(s);
export const digest = s => createHash('sha256').update(s).digest('hex');

export function platform(env) {
  const url = env.SUPABASE_URL || env.NEXT_PUBLIC_SUPABASE_URL;
  const publicKey = env.SUPABASE_PUBLISHABLE_KEY || env.SUPABASE_ANON_KEY || env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const secret = env.SUPABASE_SECRET_KEY || env.SUPABASE_SERVICE_ROLE_KEY;
  let safePublic=typeof publicKey==='string' && publicKey.startsWith('sb_publishable_');
  if(!safePublic && typeof publicKey==='string'){try{safePublic=JSON.parse(Buffer.from(publicKey.split('.')[1],'base64url')).role==='anon'}catch{}}
  const configured = safePublic && publicKey!==secret && url && /^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(url) && publicKey && secret;
  const request = async (path, options) => {
    if (!configured) throw new Fault('service_unconfigured',503);
    try { return await fetch(url + path, {...options, redirect:'error', signal:AbortSignal.timeout(5000)}); }
    catch { throw new Fault('service_unavailable',503); }
  };
  return {
    config() { if (!configured) throw new Fault('service_unconfigured',503); return {url, publishableKey:publicKey}; },
    async user(requestHeaders) {
      const token = requestHeaders.authorization;
      if (typeof token !== 'string' || !/^Bearer [^\s]{16,8192}$/.test(token)) throw new Fault('login_required',401);
      const response = await request('/auth/v1/user',{headers:{authorization:token,apikey:publicKey}});
      if (!response.ok) throw new Fault(response.status>=500?'service_unavailable':'login_required',response.status>=500?503:401);
      const user = await response.json();
      if (!uuid(user.id) || user.is_anonymous || !user.email_confirmed_at) throw new Fault('confirmed_account_required',403);
      return user.id;
    },
    async rpc(fn,params) {
      const response = await request('/rest/v1/rpc/st_'+fn,{method:'POST',headers:{apikey:secret,...(secret.startsWith('sb_secret_')?{}:{authorization:'Bearer '+secret}),'content-type':'application/json'},body:JSON.stringify(params)});
      if (!response.ok) {
        const msg = (await response.json().catch(()=>({}))).message;
        if (['no_entitlement','quota','rate_limit','budget','already_admitted','offline'].includes(msg)) throw new Fault(msg,403);
        throw new Fault('ledger_unavailable',503);
      }
      const data=await response.text(); return data ? JSON.parse(data) : null;
    },
    sign(payload) {
      if (!configured) throw new Fault('service_unconfigured',503);
      const body=Buffer.from(JSON.stringify(payload)).toString('base64url');
      return body+'.'+createHmac('sha256',secret).update('saytile.evidence.v1/'+body).digest('base64url');
    },
    verify(value) {
      if (typeof value!=='string'||value.length>2048) throw new Fault('invalid_evidence');
      const [body,sig,extra]=value.split('.'); if(extra!==undefined)throw new Fault('invalid_evidence');
      if (!sig || !configured) throw new Fault('invalid_evidence');
      const mac=createHmac('sha256',secret).update('saytile.evidence.v1/'+body).digest();
      const provided=Buffer.from(sig,'base64url');
      if (provided.length!==mac.length || !timingSafeEqual(mac,provided)) throw new Fault('invalid_evidence');
      return JSON.parse(Buffer.from(body,'base64url'));
    }
  };
}
