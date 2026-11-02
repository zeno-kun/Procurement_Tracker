import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import fs from 'node:fs';
const source=fs.readFileSync(new URL('../assets/app.js',import.meta.url),'utf8');const declaration=source.split('\n').find(l=>l.startsWith('const canAct='));
test('interface honors active admins and assigned owners while rejecting inactive and unrelated employees',()=>{
 for(const [profile,stageOwners,allowed] of [[{id:'a',is_active:true,is_admin:true},[],true],[{id:'a',is_active:true,is_admin:false},[{stage:'Quotation',employee_id:'a'}],true],[{id:'a',is_active:true,is_admin:false},[],false],[{id:'a',is_active:false,is_admin:true},[],false]]){
 const context={db:{profile,stageOwners}};assert.equal(vm.runInNewContext(declaration+'canAct("Quotation")',context),allowed);
 }
});
