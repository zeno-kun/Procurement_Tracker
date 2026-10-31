// Approved mail-only dispatcher: no Supabase API key is stored as a worker credential.
// Google credentials stay in Vault. Every browser request is authenticated server-side.
const root=Deno.env.get('SUPABASE_URL');
const serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const publicKey='sb_publishable_qNOYoeK7lSptBJMZwomJUw_FVSNiUNO';
const projectRef='bezpksgfxkecfpwavndz';
const ownerEmail='vidit@brightbots.in';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS'};
class ApiError extends Error { constructor(message,status=400){super(message);this.status=status;} }
const reply=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});
async function db(path,method='GET',body,token=serviceKey){
 const r=await fetch(root+'/rest/v1/'+path,{method,headers:{apikey:token===serviceKey?serviceKey:publicKey,Authorization:'Bearer '+token,'Content-Type':'application/json',Prefer:'return=representation'},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
 const data=await r.json().catch(()=>null);if(!r.ok)throw new ApiError('Procurement service could not complete this operation.',r.status>=500?503:403);return data;
}
async function google(url,token,options={}){
 const r=await fetch(url,{...options,headers:{Authorization:'Bearer '+token,...options.headers},signal:AbortSignal.timeout(25000)});
 if(!r.ok)throw new ApiError(r.status===403?'Google access was denied. Enable the Google Drive and Gmail APIs and approve the required permissions.':'Google connection failed. Reconnect the owner account.',r.status===403?403:503);
 return r;
}
async function freshGoogle(){
 const cfg=await db('rpc/procurement_service_config','POST',{});if(!cfg||cfg.email!==ownerEmail||!cfg.folder_id)throw new ApiError('The Drive owner must connect Google services first.',409);
 const r=await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:cfg.client_id,client_secret:cfg.client_secret,refresh_token:cfg.refresh_token,grant_type:'refresh_token'}),signal:AbortSignal.timeout(20000)});
 const token=await r.json();if(!r.ok||!token.access_token)throw new ApiError('Owner Google authorization expired or was revoked. Reconnect Google services.',409);return {token:token.access_token,cfg};
}
const allowedFiles={Quotation:['Vendor 1 Quote File URL','Vendor 2 Quote File URL','Vendor 3 Quote File URL'],PO:['PO File URL'],QC:['TC / Test Certificate File URL','Bill Received File URL','Item Photo URL'],Invoice:['Invoice File URL']};
const allowedMime=new Set(['application/pdf','image/jpeg','image/png','image/webp','text/plain','text/csv','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.openxmlformats-officedocument.wordprocessingml.document']);
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
async function authorizedItem(id,token,actor,stage,version){
 if(!uuid.test(id||''))throw new ApiError('Invalid item');
 const rows=await db('request_items?select=id,current_stage,version&id=eq.'+id,'GET',undefined,token);
 const item=rows?.[0];if(!item)throw new ApiError('Item access denied',403);
 if(stage){
 const owners=await db('stage_owners?select=employee_id&stage=eq.'+encodeURIComponent(stage)+'&employee_id=eq.'+actor.id);
 if(!owners.length||item.current_stage!==stage)throw new ApiError('Only the current stage owner may upload this file',403);
 if(item.version!==Number(version))throw new ApiError('Item changed. Refresh first.',409);
 }return item;
}
const b64url=bytes=>{let s='';for(const b of bytes)s+=String.fromCharCode(b);return btoa(s).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');};
async function processMail(actor,requestId){
 const {token,cfg}=await freshGoogle();
 const jobs=await db('rpc/procurement_claim_mail','POST',{actor:actor.id,request_key:requestId||null});let sent=0;
 for(const job of jobs){
 const safe=v=>String(v).replace(/[\r\n]/g,' ');
 const mime=['From: '+safe(cfg.email),'To: '+job.recipients.map(safe).join(', '),...(job.cc.length?['Cc: '+job.cc.map(safe).join(', ')]:[]),'Subject: =?UTF-8?B?'+btoa(unescape(encodeURIComponent(job.subject)))+'?=','Message-ID: <procurement-'+job.id+'@brightbots.in>','MIME-Version: 1.0','Content-Type: text/plain; charset=UTF-8','Content-Transfer-Encoding: base64','',btoa(unescape(encodeURIComponent(job.message+'\n\nRequest ID: '+job.request_id+'\nOpen the Procurement app to view details.')))].join('\r\n');
 let update;
 try{
 const r=await fetch('https://gmail.googleapis.com/gmail/v1/users/me/messages/send',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({raw:b64url(new TextEncoder().encode(mime))}),signal:AbortSignal.timeout(20000)});
 const result=await r.json().catch(()=>null);
 if(r.ok&&result?.id){update={status:'sent',provider_message_id:result.id,sent_at:new Date().toISOString(),last_error:null};sent++;}
 else if([400,401,403,429].includes(r.status))update={status:'failed',last_error:'Google rejected the send (HTTP '+r.status+').',next_attempt_at:new Date(Date.now()+300000).toISOString()};
 else update={status:'uncertain',last_error:'Send result uncertain. Check the sender mailbox before manually retrying.'};
 }catch{update={status:'uncertain',last_error:'Connection ended during send. Check the sender mailbox before manually retrying.'};}
 await db('procurement_mail_outbox?id=eq.'+job.id,'PATCH',update);
 }
 return {sent,processed:jobs.length};
}
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response(null,{headers:cors});
 if(req.method!=='POST')return reply({message:'POST required'},405);
 try{
 const workerToken=req.headers.get('X-Procurement-Mail-Token');
 if(workerToken){
 const expected=await db('rpc/procurement_mail_worker_token','POST',{});
 if(!expected||workerToken.length!==expected.length||Array.from(workerToken).reduce((diff,c,n)=>diff|(c.charCodeAt(0)^expected.charCodeAt(n)),0)!==0)throw new ApiError('Invalid mail worker',401);
 const job=await req.json();if(job.action!=='mail_worker')throw new ApiError('Mail-only credential cannot perform this operation',403);
 if(!await db('rpc/procurement_service_config','POST',{}))return reply({waiting_for_owner_connection:true});
 const profiles=await db('employees?select=id,email,is_active&email=eq.'+ownerEmail);const actor=profiles.find(e=>e.email===ownerEmail&&e.is_active);if(!actor)throw new ApiError('Owner disabled',403);return reply(await processMail(actor,null));
 }
 const authorization=req.headers.get('Authorization')||'';if(!authorization.startsWith('Bearer '))throw new ApiError('Sign in first',401);
 const token=authorization.slice(7);
 const check=await fetch(root+'/auth/v1/user',{headers:{apikey:publicKey,Authorization:authorization},signal:AbortSignal.timeout(15000)});
 const user=await check.json();if(!check.ok||!user.id||!user.email)throw new ApiError('Invalid session',401);
 const profiles=await db('employees?select=id,email,is_active&email=eq.'+encodeURIComponent(user.email),'GET',undefined,token);
 const actor=profiles.find(e=>e.email===user.email&&e.is_active);if(!actor)throw new ApiError('Employee not enabled',403);
 const multipart=(req.headers.get('Content-Type')||'').startsWith('multipart/form-data');
 if(Number(req.headers.get('Content-Length')||0)>12*1024*1024)throw new ApiError('Maximum upload is 10 MB',413);
 const body=multipart?await req.formData():await req.json();
 const action=multipart?body.get('action'):body.action;
 if(action==='connect'){
 if(actor.email!==ownerEmail)throw new ApiError('Only the configured Drive owner may connect services',403);
 if(!body.client_id||!body.client_secret||!body.refresh_token)throw new ApiError('Provide the OAuth client ID, client secret and a fresh Google authorization.');
 const response=await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:body.client_id,client_secret:body.client_secret,refresh_token:body.refresh_token,grant_type:'refresh_token'}),signal:AbortSignal.timeout(20000)});
 const grant=await response.json();if(!response.ok||!grant.access_token)throw new ApiError('Google authorization or client credentials are invalid.');
 const identity=await (await google('https://www.googleapis.com/oauth2/v3/userinfo',grant.access_token)).json();
 if(identity.email!==ownerEmail||!identity.email_verified)throw new ApiError('Connect the configured owner Google account: '+ownerEmail,403);
 if(!(grant.scope||'').split(' ').includes('https://www.googleapis.com/auth/gmail.send'))throw new ApiError('Approve the send-email permission when connecting Google.');
 const folderQuery="mimeType='application/vnd.google-apps.folder' and trashed=false and 'me' in owners and appProperties has { key='procurement_project' and value='"+projectRef+"' }";
 const existing=await (await google('https://www.googleapis.com/drive/v3/files?q='+encodeURIComponent(folderQuery)+'&orderBy=createdTime&fields=files(id,name)',grant.access_token)).json();
 let folder=existing.files?.[0];
 if(!folder)folder=await (await google('https://www.googleapis.com/drive/v3/files?fields=id,name',grant.access_token,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:'Procurement Tracker Supabase',mimeType:'application/vnd.google-apps.folder',parents:['root'],appProperties:{procurement_project:projectRef}})})).json();
 const folderId=folder?.id;if(!folderId)throw new ApiError('Could not create the owner upload folder.',503);
 await db('rpc/procurement_service_config','POST',{config:{client_id:body.client_id,client_secret:body.client_secret,refresh_token:body.refresh_token,email:identity.email,folder_id:folderId}});
 const workerToken=Array.from(crypto.getRandomValues(new Uint8Array(32)),b=>b.toString(16).padStart(2,'0')).join('');
 await db('rpc/register_procurement_mail_worker','POST',{worker_token:workerToken});
 return reply({connected:true,folder_id:folderId,email:identity.email});
 }
 if(action==='upload'){
 let claims;try{claims=JSON.parse(atob(token.split('.')[1].replaceAll('-','+').replaceAll('_','/')));}catch{}
 if(!claims?.amr?.some(a=>a.method==='oauth'))throw new ApiError('Sign in with Google before uploading stage files.',403);
 const id=body.get('item_id'),stage=body.get('stage'),field=body.get('field_key'),uploadId=body.get('upload_id'),file=body.get('file');
 await authorizedItem(id,token,actor,stage,body.get('version'));
 if(!allowedFiles[stage]?.includes(field)||!uuid.test(uploadId||''))throw new ApiError('Invalid upload field');
 if(!(file instanceof File)||file.size<1||file.size>10485760||!allowedMime.has(file.type))throw new ApiError('Use a PDF, image, text, CSV, DOCX or XLSX file up to 10 MB.');
 const prior=await db('procurement_files?id=eq.'+uploadId);
 if(prior.length){if(prior[0].item_id!==id||prior[0].uploaded_by!==actor.id||prior[0].field_key!==field)throw new ApiError('Upload token mismatch',409);return reply({url:'https://drive.google.com/file/d/'+prior[0].drive_file_id+'/view',id:uploadId});}
 const {token:googleToken,cfg}=await freshGoogle();const folderId=cfg.folder_id;
 const q="'"+folderId+"' in parents and trashed=false and appProperties has { key='upload_id' and value='"+uploadId+"' } and appProperties has { key='item_id' and value='"+id+"' } and appProperties has { key='uploaded_by' and value='"+actor.id+"' }";
 const found=await (await google('https://www.googleapis.com/drive/v3/files?q='+encodeURIComponent(q)+'&fields=files(id)',googleToken)).json();let driveId=found.files?.[0]?.id;
 if(!driveId){
 const metadata={name:file.name.replace(/[\x00-\x1f]/g,'').slice(0,200),parents:[folderId],appProperties:{upload_id:uploadId,item_id:id,uploaded_by:actor.id}};
 const start=await google('https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id',googleToken,{method:'POST',headers:{'Content-Type':'application/json','X-Upload-Content-Type':file.type,'X-Upload-Content-Length':String(file.size)},body:JSON.stringify(metadata)});
 const location=start.headers.get('Location');if(!location||!location.startsWith('https://www.googleapis.com/'))throw new ApiError('Could not start Drive upload',503);
 const uploaded=await (await google(location,googleToken,{method:'PUT',headers:{'Content-Type':file.type},body:file})).json();driveId=uploaded.id;
 }
 await db('procurement_files','POST',{id:uploadId,item_id:id,stage,field_key:field,drive_file_id:driveId,filename:file.name,mime_type:file.type,size_bytes:file.size,uploaded_by:actor.id});
 return reply({id:uploadId,url:'https://drive.google.com/file/d/'+driveId+'/view'});
 }
 if(action==='download'){
 if(!uuid.test(body.file_id||''))throw new ApiError('Invalid file');
 const files=await db('procurement_files?id=eq.'+body.file_id);const f=files[0];if(!f)throw new ApiError('File not found',404);
 await authorizedItem(f.item_id,token,actor);
 const {token:googleToken}=await freshGoogle();const data=await google('https://www.googleapis.com/drive/v3/files/'+f.drive_file_id+'?alt=media',googleToken);
 return new Response(data.body,{headers:{...cors,'Content-Type':f.mime_type,'Content-Disposition':"attachment; filename*=UTF-8''"+encodeURIComponent(f.filename),'Cache-Control':'no-store'}});
 }
 if(action==='mail')return reply(await processMail(actor,body.request_id));
 throw new ApiError('Unknown operation');
 }catch(e){return reply({message:e instanceof ApiError?e.message:'The operation could not be completed. Please retry.'},e instanceof ApiError?e.status:503);}
});
