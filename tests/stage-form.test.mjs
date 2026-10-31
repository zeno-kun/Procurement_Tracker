import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import fs from 'node:fs';
test('all ten stages expose their permitted controls, bulk approval, version and gated file inputs',()=>{
 const window={};vm.runInNewContext(fs.readFileSync(new URL('../assets/stage-form.js',import.meta.url),'utf8'),{window});
 const form=window.ProcurementStageForm,items=[{id:'qa-a',requestId:'QA',name:'Synthetic A',quantity:2,unit:'Nos',version:3,fields:{}},{id:'qa-b',requestId:'QA',name:'Synthetic B',quantity:1,unit:'Nos',version:1,fields:{}}];
 assert.equal(Object.keys(form.definitions).length,10);
 for(const stage of Object.keys(form.definitions)){const html=form.render(stage,items,String,false);assert.match(html,/stage-action-form/);assert.match(html,/version 3/);assert(!html.includes('data-stage-key="Requester Email"'));}
 assert.match(form.render('Vendor Approval',items,String,true),/data-apply-key="Approved Vendor Type"/);
 assert.match(form.render('Fund Approval',items,String,true),/data-apply-key="Fund Approval Status"/);
 assert.match(form.render('Invoice',items,String,false),/accept="[^"]+" disabled/);
 assert(!/accept="[^"]+" disabled/.test(form.render('Invoice',items,String,true)));
});
