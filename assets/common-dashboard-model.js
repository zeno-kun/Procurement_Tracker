(function(root){
const normalize=email=>String(email||'').trim().toLowerCase();
function checkedPeople(snapshot){const seen=new Set();return (snapshot?.people||[]).map(p=>({...p,email:normalize(p.email)})).filter(p=>{if(!p.email||seen.has(p.email))throw Error('The tracker returned a missing or duplicate employee email.');seen.add(p.email);return true;});}
function combine(taskops,procurement){const task=checkedPeople(taskops),proc=new Map(checkedPeople(procurement).map(p=>[p.email,p]));return task.filter(t=>proc.has(t.email)).map(t=>{const p=proc.get(t.email);return {email:t.email,name:t.name||p.name,team:t.team||'',taskops:t,procurement:p,open:Number(t.open)+Number(p.open),overdue:Number(t.overdue)+Number(p.overdue),green:Number(t.green)+Number(p.green),yellow:Number(t.yellow)+Number(p.yellow),red:Number(t.red)+Number(p.red),measured:Number(t.measured)+Number(p.measured)};}).sort((a,b)=>a.name.localeCompare(b.name));}
function distribution(row){const total=Number(row.measured)||0;return ['green','yellow','red'].map(c=>total?Number(row[c]||0)/total*100:null);}
function totals(rows){return rows.reduce((a,r)=>{for(const k of ['open','overdue','green','yellow','red','measured'])a[k]+=Number(r[k]||0);return a;},{open:0,overdue:0,green:0,yellow:0,red:0,measured:0});}
function monday(date){const d=new Date(date+'T00:00:00Z');if(!Number.isFinite(d.getTime()))throw Error('Choose a valid week.');d.setUTCDate(d.getUTCDate()-(d.getUTCDay()+6)%7);return d.toISOString().slice(0,10);}
root.TrackersDashboardModel={normalize,checkedPeople,combine,distribution,totals,monday};
})(typeof window==='undefined'?globalThis:window);
