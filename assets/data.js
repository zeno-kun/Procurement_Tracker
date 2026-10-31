// Browser-safe publishable key. Data access remains controlled by Supabase RLS.
// No service-role key or embedded business records. Writes use the scoped submission RPC.
window.ProcurementData=(()=>{
  const root='https://bezpksgfxkecfpwavndz.supabase.co';
  const key='sb_publishable_qNOYoeK7lSptBJMZwomJUw_FVSNiUNO';
  const sessionKey='brightbots-procurement-auth-v1';
  let memorySession=null,pendingGoogle=null;
  const oauthKey='procurement-google-pkce';
  function readSession(){try{return memorySession||JSON.parse(sessionStorage.getItem(sessionKey)||'null')}catch{return memorySession}}
  function saveSession(data){memorySession={access_token:data.access_token,refresh_token:data.refresh_token,expires_in:data.expires_in,expires_at:data.expires_at||Math.floor(Date.now()/1000)+Number(data.expires_in||3600)};try{sessionStorage.setItem(sessionKey,JSON.stringify(memorySession))}catch{}}
  function clearSession(){memorySession=null;try{sessionStorage.removeItem(sessionKey)}catch{}}
  async function auth(path,body,token){
    const r=await fetch(root+'/auth/v1/'+path,{method:body===undefined?'GET':'POST',headers:{apikey:key,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:body===undefined?undefined:JSON.stringify(body)});
    const data=await r.json().catch(()=>({}));
    if(!r.ok){const error=new Error(data.error_code==='invalid_credentials'?'No matching Procurement login. If this is your first visit, create a Procurement account. TaskOps passwords are not copied automatically.':data.error_code==='email_not_confirmed'?'Email confirmation is still enabled in the project settings; it must be disabled there to remove this step.':data.msg||data.error_description||data.message||'Authentication failed.');error.status=r.status;throw error;}
    return data;
  }
  async function accessToken(){
    let s=readSession();if(!s)throw new Error('Please sign in to Procurement.');
    if(Number(s.expires_at)*1000<Date.now()+45000){try{s=await auth('token?grant_type=refresh_token',{refresh_token:s.refresh_token});saveSession(s)}catch(e){clearSession();throw e}}
    return s.access_token;
  }
  async function read(path){
    const token=await accessToken();
    const r=await fetch(root+'/rest/v1/'+path,{method:'GET',headers:{apikey:key,Authorization:'Bearer '+token,'Cache-Control':'no-cache'},cache:'no-store'});
    const data=await r.json().catch(()=>({}));if(!r.ok){if(r.status===401)clearSession();const e=new Error(data.message||'Could not read Procurement records.');e.status=r.status;throw e;}return data;
  }
  async function submitRequest(clientToken,payload){
    const token=await accessToken();
    const controller=new AbortController();
    const timer=setTimeout(()=>controller.abort(),25000);
    try{
      const r=await fetch(root+'/rest/v1/rpc/submit_procurement_request',{
        method:'POST',headers:{apikey:key,Authorization:'Bearer '+token,'Content-Type':'application/json'},
        body:JSON.stringify({client_token:clientToken,payload}),signal:controller.signal
      });
      const data=await r.json().catch(()=>null);
      if(!r.ok){const e=new Error(data?.message||'Request submission failed.');e.status=r.status;throw e;}
      if(!data?.request_id)throw new Error('The submission response was incomplete. Retry to check the same request.');
      return data;
    }finally{clearTimeout(timer);}
  }
  async function rpc(name,body){
    const token=await accessToken();const r=await fetch(root+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:key,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body)});
    const d=await r.json().catch(()=>null);if(!r.ok){const e=new Error(d?.message||'Operation failed');e.status=r.status;e.code=d?.code;throw e;}return d;
  }
  async function services(body){
    const token=await accessToken(),multipart=body instanceof FormData;
    const r=await fetch(root+'/functions/v1/procurement-google-services',{method:'POST',headers:{apikey:key,Authorization:'Bearer '+token,...(multipart?{}:{'Content-Type':'application/json'})},body:multipart?body:JSON.stringify(body)});
    if(body.action==='download'&&r.ok)return r.blob();
    const d=await r.json().catch(()=>null);if(!r.ok){const e=new Error(d?.message||'Google service failed');e.status=r.status;e.code=d?.code;throw e;}return d;
  }
  const base64url=bytes=>btoa(String.fromCharCode(...bytes)).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');
  async function signInGoogle(connect=false){
    if(!crypto.subtle)throw Error('Google sign-in requires HTTPS or localhost.');
    const verifier=base64url(crypto.getRandomValues(new Uint8Array(48)));
    const challenge=base64url(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(verifier))));
    sessionStorage.setItem(oauthKey,JSON.stringify({verifier,connect,created:Date.now()}));
    const redirect=new URL(location.href);redirect.search='';redirect.hash='';
    const url=new URL(root+'/auth/v1/authorize');
    url.search=new URLSearchParams({provider:'google',redirect_to:redirect.href,code_challenge:challenge,code_challenge_method:'s256',...(connect?{scopes:'openid email profile https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/gmail.send',access_type:'offline',prompt:'consent select_account'}:{prompt:'select_account'})}).toString();
    location.assign(url.href);
  }
  async function consumeOAuthCallback(){
    const url=new URL(location.href),code=url.searchParams.get('code'),error=url.searchParams.get('error_description')||url.searchParams.get('error');
    if(!code&&!error)return false;
    let saved;try{saved=JSON.parse(sessionStorage.getItem(oauthKey)||'null')}catch{}
    url.searchParams.delete('code');url.searchParams.delete('error');url.searchParams.delete('error_code');url.searchParams.delete('error_description');history.replaceState(null,'',url.pathname+url.search+url.hash);
    sessionStorage.removeItem(oauthKey);
    if(error)throw Error('Google sign-in was not completed. Please try again.');
    if(!saved?.verifier||Date.now()-saved.created>10*60000)throw Error('Google sign-in expired. Start again from this tab.');
    const d=await auth('token?grant_type=pkce',{auth_code:code,code_verifier:saved.verifier});
    if(!d.access_token)throw Error('Google did not return a session.');saveSession(d);
    if(saved.connect)pendingGoogle={refresh_token:d.provider_refresh_token};
    return saved.connect;
  }
  async function connectGoogleServices(clientId,clientSecret){
    if(!pendingGoogle?.refresh_token)throw Error('Choose Authorize owner Google account first and approve offline access.');
    const d=await services({action:'connect',client_id:clientId.trim(),client_secret:clientSecret.trim(),refresh_token:pendingGoogle.refresh_token});pendingGoogle=null;return d;
  }
  async function notifyMail(requestId){try{return await services({action:'mail',request_id:requestId||null});}catch{return {queued:true};}}
  async function uploadFile(item,stage,field,file,uploadId){const body=new FormData();Object.entries({action:'upload',item_id:item.id,stage,field_key:field,version:item.version,upload_id:uploadId}).forEach(([k,v])=>body.append(k,String(v)));body.append('file',file);return services(body);}
  async function downloadFile(file){const blob=await services({action:'download',file_id:file.id});const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=file.filename;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
  async function all(path){const rows=[];for(let offset=0;offset<100000;offset+=1000){const part=await read(path+'&limit=1000&offset='+offset);if(!Array.isArray(part))throw Error('Invalid data response.');rows.push(...part);if(part.length<1000)return rows;}throw Error('Too many records. Please narrow the query.');}
  async function load(){
    const user=await auth('user',undefined,await accessToken());
    const profiles=await read('employees?select=id,email,full_name,is_active&email=eq.'+encodeURIComponent(user.email));
    const profile=profiles.find(p=>p.email===user.email);if(!profile?.is_active)throw Error('This email is not enabled in the Procurement employee directory.');
    const [requests,items,tracking,catalog,events,employees,stageOwners,imports,files,connections]=await Promise.all([
      all('requests?select=*&order=requested_at.desc.nullslast,id.desc'),
      all('request_items?select=*&order=source_row.asc.nullslast,id.asc'),
      all('request_tracking?select=*&order=item_id.asc'),
      all('catalog_items?select=source_row,item_code,alternate_code,item_name,uom,status,data&order=source_row.asc'),
      all('stage_events?select=*&order=completed_at.desc,id.asc'),
      all('employees?select=id,email,full_name,is_active&order=id.asc'),
      all('stage_owners?select=*&order=stage.asc,employee_id.asc'),
      read('import_runs?select=imported_at,source_modified_at,counts&order=imported_at.desc&limit=1'),
      all('procurement_files?select=id,item_id,drive_file_id,filename,stage&order=created_at.desc,id.asc'),
      read('rpc/procurement_connection_status')
    ]);
    return {profile,requests,items,tracking,catalog,events,employees,stageOwners,files,connections,importedAt:imports[0]?.imported_at||null,sourceModifiedAt:imports[0]?.source_modified_at||null,loadedAt:new Date().toISOString()};
  }
  return {
    hasSession:()=>!!readSession(),
    signIn:async(email,password)=>{const d=await auth('token?grant_type=password',{email:email.trim().toLowerCase(),password});saveSession(d);return d;},
    signUp:async(email,password)=>{const d=await auth('signup',{email:email.trim().toLowerCase(),password});if(d.access_token)saveSession(d);return d;},
    signOut:async()=>{const s=readSession();clearSession();if(s?.access_token)try{await fetch(root+'/auth/v1/logout',{method:'POST',headers:{apikey:key,Authorization:'Bearer '+s.access_token}})}catch{}},
    clearSession,load,submitRequest,rpc,signInGoogle,consumeOAuthCallback,connectGoogleServices,hasGoogleGrant:()=>!!pendingGoogle?.refresh_token,notifyMail,uploadFile,downloadFile,
    stageAction:(stage,items,common,clientToken)=>rpc('apply_procurement_stage',{stage,items,common,client_token:clientToken})
  };
})();
