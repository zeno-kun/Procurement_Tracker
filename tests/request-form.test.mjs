import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs';
test('new request draft form is visible without enabling database submission',()=>{
 const ctx=vm.createContext({window:{},Date});vm.runInContext(fs.readFileSync(new URL('../assets/request-form.js',import.meta.url),'utf8'),ctx);
 const html=ctx.window.ProcurementRequestForm.render({full_name:'Test Person'},[],v=>String(v??''));
 assert.match(html,/Project \/ client/);assert.match(html,/Requested items/);assert.match(html,/Add item/);assert.match(html,/Save draft/);assert.match(html,/disabled title="Request submission needs backend activation"/);
 assert(!html.includes('type="email"')); // requester comes from the signed-in employee profile
 ctx.window.ProcurementRequestForm.clear();
});
