import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

function model(){const ctx=vm.createContext({window:{},Date,Map});vm.runInContext(fs.readFileSync(new URL('../assets/model.js',import.meta.url),'utf8'),ctx);return ctx.window.ProcurementModel;}
test('original request IDs retain multiple items; tracking fallback does not duplicate full rows',()=>{
 const m=model();const result=m.map({requests:[{id:'REQ-REAL-1',requester_name:'Requester',project:'Project',requested_at:'2026-10-01T10:00:00+05:30'}],items:[{id:'a',request_id:'REQ-REAL-1',item_name:'Item A',quantity:5,required_by:'2026-10-30',current_stage:'Quotation',data:{Timestamp:'2026-10-01T10:00:00+05:30','Vendor 1 Quote File URL':'https://drive.google.com/file/d/example/view'}},{id:'b',request_id:'REQ-REAL-1',item_name:'Item B',quantity:10,current_stage:'Completed',data:{}}],tracking:[{item_id:'a',request_id:'REQ-REAL-1',item_name:'Item A'},{item_id:'c',request_id:'REQ-REAL-2',item_name:'Restricted item',quantity:1,current_stage:'PO'}],catalog:[],events:[],employees:[]},'2026-10-28T10:00:00+05:30');
 assert.equal(result.requests.length,2);assert.equal(result.items.length,3);assert.equal(result.items.filter(i=>i.requestId==='REQ-REAL-1').length,2);
 const restricted=result.items.find(i=>i.id==='c');assert.equal(restricted.restricted,true);assert.equal(restricted.elapsed,null);assert.equal(restricted.fields['PO Amount'],undefined);
 assert.equal(result.items[0].fields['Vendor 1 Quote File URL'],'https://drive.google.com/file/d/example/view');
});
test('legacy working calendar excludes Sundays and second Saturdays, but includes other Saturdays',()=>{
 const m=model();assert.equal(m.workingHours('2026-10-09T17:30:00+05:30','2026-10-12T09:30:00+05:30'),0);
 assert.equal(m.workingHours('2026-10-17T09:30:00+05:30','2026-10-17T17:30:00+05:30'),8);
 assert.equal(m.workingHours(46285,'2026-10-28'),null);
 assert.equal(m.workingHours('2026-10-28','2026-10-01'),null);
 assert.equal(m.stageStart('Accounting',{'QC Timestamp':'2026-10-01','Invoice Timestamp':'2026-10-02'}),'2026-10-01');
});
test('historical configured-owner attribution is labelled and never presented as a verified actor',()=>{
 const result=model().map({requests:[{id:'r'}],items:[{id:'a',request_id:'r',item_name:'A',current_stage:'Completed',data:{}}],events:[{item_id:'a',stage:'PO',completed_at:'2026-10-01',owner_ids:['p'],color:'Green',working_hours:1,tat_hours:6,attribution:'configured_stage_owner_not_verified_historical_actor'}],employees:[{id:'p',full_name:'Person'}]},'2026-10-28');
 assert.match(result.items[0].history[0].actor,/Configured owner/);assert.match(result.items[0].history[0].remark,/not verified/);
});

function client(fetcher){const storage=new Map(),window={};const ctx=vm.createContext({window,Date,Error,JSON,Number,AbortController,setTimeout,clearTimeout,sessionStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},fetch:fetcher});vm.runInContext(fs.readFileSync(new URL('../assets/data.js',import.meta.url),'utf8'),ctx);return window.ProcurementData;}
const response=(body,status=200)=>({ok:status<400,status,json:async()=>body});
test('authenticated data loading paginates past 1000 rows and never writes business tables',async()=>{
 const calls=[];const api=client(async(url,options)=>{
  calls.push({url,options});if(url.includes('/auth/v1/token'))return response({access_token:'test-session',refresh_token:'test-refresh',expires_in:3600});
  if(url.endsWith('/auth/v1/user'))return response({email:'person@example.test'});
  if(url.includes('/employees?select=id,email,full_name,is_active&email='))return response([{id:'p',email:'person@example.test',is_active:true}]);
  if(url.includes('/catalog_items?'))return response(url.includes('offset=1000')?[{source_row:1001}]:Array.from({length:1000},(_,i)=>({source_row:i+1})));
  return response([]);
 });
 assert.equal(api.hasSession(),false);await api.signIn('Person@example.test','test-password');const data=await api.load();assert.equal(data.catalog.length,1001);
 const reads=calls.filter(c=>c.url.includes('/rest/v1/'));assert(reads.every(c=>c.options.method==='GET'));assert(reads.every(c=>c.options.headers.Authorization==='Bearer test-session'));
 await api.signOut();assert.equal(api.hasSession(),false);
});
test('rejected authentication creates no usable session',async()=>{
 const api=client(async()=>response({error_code:'invalid_credentials'},400));await assert.rejects(()=>api.signIn('person@example.test','wrong-password'),/No matching Procurement login/);assert.equal(api.hasSession(),false);
});
test('catalog uses column M codes and N categories while resolving historical column A codes',()=>{
 const result=model().map({catalog:[{item_code:'OLD-TEST',alternate_code:'NEW-TEST',item_name:'Test item',data:{Code_type:'TEST'}}],items:[{id:'test',request_id:'test',item_name:'Test item',item_code:'OLD-TEST',current_stage:'Completed'}]});
 assert.equal(result.catalog[0].code,'NEW-TEST');
 assert.equal(result.catalog[0].category,'TEST');
 assert.equal(result.catalog[0].legacyCode,'OLD-TEST');
 assert.equal(result.items[0].code,'NEW-TEST');
 assert.equal(result.items[0].name,'Test item');
});

test('submission uses the authenticated RPC with a stable client token and reports server errors',async()=>{
 const calls=[];let fail=false;
 const api=client(async(url,options)=>{
  calls.push({url,options});
  if(url.includes('/auth/v1/token'))return response({access_token:'test-session',expires_in:3600});
  return fail?response({message:'Invalid quantity'},400):response({request_id:'REQ-SYNTHETIC',stage:'Request Approval'});
 });
 await assert.rejects(()=>api.submitRequest('token',{}),/Please sign in/);assert.equal(calls.length,0);
 await api.signIn('person@example.test','test-password');
 const payload={project:'Synthetic project',items:[{name:'Synthetic item',quantity:1,required_by:'2026-11-15'}]};
 const result=await api.submitRequest('client-token',payload);assert.equal(result.request_id,'REQ-SYNTHETIC');
 const call=calls.at(-1);assert.match(call.url,/rpc\/submit_procurement_request$/);assert.equal(call.options.method,'POST');assert.equal(call.options.headers.Authorization,'Bearer test-session');
 assert.deepEqual(JSON.parse(call.options.body),{client_token:'client-token',payload});
 fail=true;await assert.rejects(()=>api.submitRequest('client-token',payload),e=>e.status===400&&e.message==='Invalid quantity');
});
