import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs';
import {webcrypto} from 'node:crypto';
const source=fs.readFileSync(new URL('../backend/google-services.ts',import.meta.url),'utf8');
const json=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json'}});
function backend(fetcher){let handler;vm.runInNewContext(source,{Deno:{env:{get:k=>k==='SUPABASE_URL'?'https://db.example.test':'server-only-secret'},serve:f=>{handler=f}},fetch:fetcher,Response,Request,File,FormData,URLSearchParams,AbortSignal,Error,Set,TextEncoder,Uint8Array,btoa,atob,unescape,encodeURIComponent,crypto:webcrypto,Date});return handler;}
const itemId='11111111-1111-4111-8111-111111111111',actorId='22222222-2222-4222-8222-222222222222',fileId='33333333-3333-4333-8333-333333333333';
const oauthToken='header.'+Buffer.from(JSON.stringify({amr:[{method:'oauth'}]})).toString('base64url')+'.signature';
const post=body=>new Request('https://edge.example.test',{method:'POST',headers:{Authorization:'Bearer synthetic-user','Content-Type':'application/json'},body:JSON.stringify(body)});
test('Google services reject anonymous requests before touching any external service',async()=>{
 let calls=0;const handle=backend(async()=>{calls++;throw Error('Unexpected fetch')});const response=await handle(new Request('https://edge.example.test',{method:'POST',body:'{}'}));assert.equal(response.status,401);assert.equal(calls,0);
});
test('a non-owner cannot configure Google credentials or upload for an unassigned stage',async()=>{
 const calls=[];const handle=backend(async(url,opts)=>{calls.push(url);if(url.endsWith('/auth/v1/user'))return json({id:'auth',email:'employee@example.test'});if(url.includes('/employees?'))return json([{id:actorId,email:'employee@example.test',is_active:true}]);if(url.includes('/request_items?'))return json([{id:itemId,current_stage:'PO',version:1}]);if(url.includes('/stage_owners?'))return json([]);throw Error('Unexpected endpoint');});
 assert.equal((await handle(post({action:'connect',client_secret:'not-real'}))).status,403);
 const form=new FormData();Object.entries({action:'upload',item_id:itemId,stage:'PO',field_key:'PO File URL',version:1,upload_id:fileId}).forEach(([k,v])=>form.append(k,String(v)));form.append('file',new File(['test'],'test.pdf',{type:'application/pdf'}));
 const response=await handle(new Request('https://edge.example.test',{method:'POST',headers:{Authorization:'Bearer '+oauthToken},body:form}));assert.equal(response.status,403);assert(!calls.some(url=>url.includes('googleapis.com')));
});
test('file download rechecks item permissions and does not accept a caller-supplied Drive ID',async()=>{
 const calls=[];const handle=backend(async(url)=>{calls.push(url);if(url.endsWith('/auth/v1/user'))return json({id:'auth',email:'employee@example.test'});if(url.includes('/employees?'))return json([{id:actorId,email:'employee@example.test',is_active:true}]);if(url.includes('/procurement_files?'))return json([{id:fileId,item_id:itemId,drive_file_id:'bound-to-database'}]);if(url.includes('/request_items?'))return json([]);throw Error('Unexpected endpoint');});
 const response=await handle(post({action:'download',file_id:fileId,drive_file_id:'attacker-choice'}));assert.equal(response.status,403);assert(!calls.some(url=>url.includes('googleapis.com')));
});
test('notification send takes recipients from the queue and restricts the claim to the authenticated actor',async()=>{
 let claim,mime,update;
 const handle=backend(async(url,options={})=>{
 if(url.endsWith('/auth/v1/user'))return json({id:'auth',email:'employee@example.test'});
 if(url.includes('/employees?'))return json([{id:actorId,email:'employee@example.test',is_active:true}]);
 if(url.endsWith('/rpc/procurement_service_config'))return json({client_id:'synthetic',client_secret:'not-a-real-secret',refresh_token:'synthetic',email:'owner@example.test'});
 if(url==='https://oauth2.googleapis.com/token')return json({access_token:'synthetic-google-token'});
 if(url.endsWith('/rpc/procurement_claim_mail')){claim=JSON.parse(options.body);return json([{id:fileId,request_id:'QA',recipients:['assigned-owner@example.test'],cc:[],subject:'Synthetic notification',message:'Synthetic only'}]);}
 if(url.endsWith('/messages/send')){mime=Buffer.from(JSON.parse(options.body).raw,'base64url').toString();return json({id:'synthetic-mail-id'});}
 if(url.includes('/procurement_mail_outbox?')){update=JSON.parse(options.body);return json([]);}throw Error('Unexpected endpoint: '+url);
 });
 const response=await handle(post({action:'mail',request_id:'QA',recipients:['attacker@example.test'],actor:'attacker'}));assert.equal(response.status,200);assert.deepEqual(claim,{actor:actorId,request_key:'QA'});assert.match(mime,/To: assigned-owner@example.test/);assert(!mime.includes('attacker@example.test'));assert.equal(update.status,'sent');assert(!(await response.text()).includes('not-a-real-secret'));
});

test('a permitted upload is pinned to the configured folder and bound to its item and actor',async()=>{
 let metadata,record,query;
 const handle=backend(async(url,options={})=>{
 if(url.endsWith('/auth/v1/user'))return json({id:'auth',email:'employee@example.test'});
 if(url.includes('/employees?'))return json([{id:actorId,email:'employee@example.test',is_active:true}]);
 if(url.includes('/request_items?'))return json([{id:itemId,current_stage:'Quotation',version:3}]);
 if(url.includes('/stage_owners?'))return json([{employee_id:actorId}]);
 if(url.includes('/procurement_files?'))return json([]);
 if(url.endsWith('/rpc/procurement_service_config'))return json({client_id:'synthetic',client_secret:'synthetic',refresh_token:'synthetic'});
 if(url==='https://oauth2.googleapis.com/token')return json({access_token:'synthetic-google-token'});
 if(url.includes('/drive/v3/files?q=')){query=new URL(url).searchParams.get('q');return json({files:[]});}
 if(url.includes('uploadType=resumable')){metadata=JSON.parse(options.body);return new Response('',{status:200,headers:{Location:'https://www.googleapis.com/upload-session/synthetic'}});}
 if(url==='https://www.googleapis.com/upload-session/synthetic')return json({id:'synthetic-drive-id'});
 if(url.endsWith('/procurement_files')){record=JSON.parse(options.body);return json([record]);}throw Error('Unexpected endpoint: '+url);
 });
 const form=new FormData();Object.entries({action:'upload',item_id:itemId,stage:'Quotation',field_key:'Vendor 1 Quote File URL',version:3,upload_id:fileId,folder_id:'ignored-attacker-folder'}).forEach(([k,v])=>form.append(k,String(v)));form.append('file',new File(['synthetic'],'quote.pdf',{type:'application/pdf'}));
 const response=await handle(new Request('https://edge.example.test',{method:'POST',headers:{Authorization:'Bearer '+oauthToken},body:form}));assert.equal(response.status,200);assert.deepEqual(metadata.parents,['1ovaJdB4Gyx2OUiOudt7fGxO6Ri6IIYmU']);assert.equal(metadata.appProperties.uploaded_by,actorId);assert(query.includes(itemId)&&query.includes(actorId));assert.equal(record.item_id,itemId);assert.equal(record.uploaded_by,actorId);assert.equal((await response.json()).url,'https://drive.google.com/file/d/synthetic-drive-id/view');
});
