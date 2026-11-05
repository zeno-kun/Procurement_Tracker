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
test('stage form shows readable numbers while notification keys stay internal',()=>{
 const window={};vm.runInNewContext(fs.readFileSync(new URL('../assets/stage-form.js',import.meta.url),'utf8'),{window});const html=window.ProcurementStageForm.render('Quotation',[{id:'item',requestId:'REQ-internal',requestLabel:'REQ-2026-000193',name:'Part',fields:{},quantity:1,unit:'Nos',version:1}],String,true);assert(html.includes('REQ-2026-000193'));assert(!html.includes('REQ-internal'));
});
test('bulk choices update selected items only and do not save',()=>{
 const choices=[{checked:true,value:'a'},{checked:false,value:'b'}];
 const fields=choices.map(c=>({dataset:{stageItem:c.value,stageKey:'QC Status'},type:'select',value:'Passed',disabled:false}));
 const bulk={dataset:{applyKey:'QC Status'},value:'Failed'},state={},save={},all={};
 const boxes=choices.map((choice,n)=>({classList:{toggle(){}},querySelector:()=>choice,querySelectorAll:()=>[fields[n]]}));
 const f={addEventListener(){},querySelector(selector){if(selector==='.stage-choose')return choices[0];if(selector.startsWith('.stage-choose[value='))return choices.find(c=>selector.includes('"'+c.value+'"'));return {'#stage-action-state':state,'#save-stage-action':save,'#stage-select-all':all}[selector]||null;},querySelectorAll(selector){return {'.stage-choose':choices,'[data-form-item]':boxes,'[data-stage-key]':fields,'[data-apply-key]':[bulk]}[selector]||[];}};
 const window={};vm.runInNewContext(fs.readFileSync(new URL('../assets/stage-form.js',import.meta.url),'utf8'),{window,document:{querySelector:()=>f}});
 window.ProcurementStageForm.bind('QC',[{id:'a'},{id:'b'}],{},()=>{throw Error('Unexpected save');});
 bulk.onchange();assert.equal(fields[0].value,'Failed');assert.equal(fields[1].value,'Passed');assert.equal(fields[1].disabled,true);assert.equal(state.textContent,'1 selected item(s)');
});
