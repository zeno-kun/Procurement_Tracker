// Browser-safe publishable key. Data access remains controlled by Supabase RLS.
// No service-role key, embedded business records, or database writes belong here.
window.ProcurementData=(()=>{
  const root='https://bezpksgfxkecfpwavndz.supabase.co';
  const key='sb_publishable_qNOYoeK7lSptBJMZwomJUw_FVSNiUNO';
  const sessionKey='brightbots-procurement-auth-v1';
  let memorySession=null;
  function readSession(){try{return memorySession||JSON.parse(sessionStorage.getItem(sessionKey)||'null')}catch{return memorySession}}
  function saveSession(data){memorySession={...data,expires_at:data.expires_at||Math.floor(Date.now()/1000)+Number(data.expires_in||3600)};try{sessionStorage.setItem(sessionKey,JSON.stringify(memorySession))}catch{}}
  function clearSession(){memorySession=null;try{sessionStorage.removeItem(sessionKey)}catch{}}
  async function auth(path,body,token){
    const r=await fetch(root+'/auth/v1/'+path,{method:body===undefined?'GET':'POST',headers:{apikey:key,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:body===undefined?undefined:JSON.stringify(body)});
    const data=await r.json().catch(()=>({}));
    if(!r.ok){const error=new Error(data.error_code==='invalid_credentials'?'No matching Procurement login. If this is your first visit, create a Procurement account and confirm its email. TaskOps passwords are not copied automatically.':data.error_code==='email_not_confirmed'?'Confirm your email, then return here and sign in.':data.msg||data.error_description||data.message||'Authentication failed.');error.status=r.status;throw error;}
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
  async function all(path){const rows=[];for(let offset=0;offset<100000;offset+=1000){const part=await read(path+'&limit=1000&offset='+offset);if(!Array.isArray(part))throw Error('Invalid data response.');rows.push(...part);if(part.length<1000)return rows;}throw Error('Too many records. Please narrow the query.');}
  async function load(){
    const user=await auth('user',undefined,await accessToken());
    const profiles=await read('employees?select=id,email,full_name,is_active&email=eq.'+encodeURIComponent(user.email));
    const profile=profiles.find(p=>p.email===user.email);if(!profile?.is_active)throw Error('This email is not enabled in the Procurement employee directory.');
    const [requests,items,tracking,catalog,events,employees,stageOwners,imports]=await Promise.all([
      all('requests?select=*&order=requested_at.desc.nullslast,id.desc'),
      all('request_items?select=*&order=source_row.asc.nullslast,id.asc'),
      all('request_tracking?select=*&order=item_id.asc'),
      all('catalog_items?select=source_row,item_code,alternate_code,item_name,uom,status,data&order=source_row.asc'),
      all('stage_events?select=*&order=completed_at.desc,id.asc'),
      all('employees?select=id,email,full_name,is_active&order=id.asc'),
      all('stage_owners?select=*&order=stage.asc,employee_id.asc'),
      read('import_runs?select=imported_at,source_modified_at,counts&order=imported_at.desc&limit=1')
    ]);
    return {profile,requests,items,tracking,catalog,events,employees,stageOwners,importedAt:imports[0]?.imported_at||null,sourceModifiedAt:imports[0]?.source_modified_at||null,loadedAt:new Date().toISOString()};
  }
  return {
    hasSession:()=>!!readSession(),
    signIn:async(email,password)=>{const d=await auth('token?grant_type=password',{email:email.trim().toLowerCase(),password});saveSession(d);return d;},
    signUp:async(email,password)=>{const d=await auth('signup',{email:email.trim().toLowerCase(),password});if(d.access_token)saveSession(d);return d;},
    signOut:async()=>{const s=readSession();clearSession();if(s?.access_token)try{await fetch(root+'/auth/v1/logout',{method:'POST',headers:{apikey:key,Authorization:'Bearer '+s.access_token}})}catch{}},
    clearSession,load
  };
})();
