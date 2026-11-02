// Pure, scoped report calculations. A stage is counted only after it was reached.
window.ProcurementReports=(()=>{
 const names=['Request Approval','Quotation','Vendor Approval','PO','Fund Approval','Payment','Dispatch','QC','Invoice + Accounting'];
 const tats=[8,24,8,6,4,16,24,6,8],colors=['Green','Yellow','Red'];
 const normalize=s=>['Invoice','Accounting'].includes(s)?'Invoice + Accounting':s;
 const day=s=>new Date(s+'T00:00:00+05:30').getTime();
 const iso=t=>new Date(t+19800000).toISOString().slice(0,10);
 const add=(s,n)=>iso(day(s)+n*86400000);
 const week=s=>add(s,-((new Date(day(s)+19800000).getUTCDay()+6)%7));
 const fy=s=>s.slice(0,4)-(Number(s.slice(5,7))<4?1:0)+'-04-01';
 const valid=v=>typeof v==='string'&&/^\d{4}-\d{2}-\d{2}/.test(v)&&Number.isFinite(new Date(v.length===10?v+'T00:00:00+05:30':v).getTime());
 const first=(f,keys)=>keys.map(k=>f[k]).find(valid)||null;
 const ends=[['Request Approval Timestamp'],['Quotation Timestamp'],['Approval Timestamp'],['PO Timestamp'],['Fund Approval Timestamp'],['Payment Timestamp','Payment Date'],['Dispatch Timestamp','Dispatch Date'],['QC Timestamp','QC Date'],['Accounting Timestamp']];
 function measurements(db,now=new Date().toISOString()){
  const out=[],seen=new Set(),events=new Map((db.events||[]).map(e=>[e.item_id+'|'+normalize(e.stage),e]));
  for(const item of db.items){if(item.restricted)continue;const f=item.fields||{},current=names.indexOf(normalize(item.stage));
   for(let n=0;n<names.length;n++){const stage=names[n],event=events.get(item.id+'|'+stage),end=first(f,ends[n]);
    const reached=current>=n||item.stage==='Completed'||!!end||!!event;
    if(!reached)continue;
    const start=event?.started_at||window.ProcurementModel.stageStart(n===8?'Invoice':stage,f);if(!valid(start))continue;
    if(stage==='Fund Approval'&&new Date(start)<new Date('2026-06-03T00:00:00+05:30'))continue;
    // Invoice and accounting share one interval; an invoice alone does not close it.
    const open=current===n,completed=open?null:end||(n!==8||item.stage==='Completed'?event?.completed_at:null);
    if(!completed&&!open)continue;
    const stop=completed||now,hours=window.ProcurementModel.workingHours(start,stop);if(hours===null)continue;
    const color=hours<=tats[n]?'Green':hours<=tats[n]+8?'Yellow':'Red';
    out.push({itemId:item.id,requestId:item.requestId,stage,start,end:completed||null,hours,tat:tats[n],color,item});seen.add(item.id+'|'+stage);
   }
  }
  // Retain authorized historical measurements when full item details are no longer visible.
  for(const e of db.events||[]){const stage=normalize(e.stage),key=e.item_id+'|'+stage;if(seen.has(key)||!names.includes(stage)||stage==='Invoice + Accounting')continue;
   if(!valid(e.started_at)||!valid(e.completed_at))continue;
   const hours=Number(e.working_hours),tat=tats[names.indexOf(stage)];if(!Number.isFinite(hours))continue;
   out.push({itemId:e.item_id,stage,start:e.started_at,end:e.completed_at,hours,tat,color:hours<=tat?'Green':hours<=tat+8?'Yellow':'Red'});
  }
  return out;
 }
 function distribution(rows){const counts=colors.map(c=>rows.filter(r=>r.color===c).length),total=counts.reduce((a,b)=>a+b,0);return {counts,total,percent:counts.map(n=>total?n/total*100:null)};}
 function actual(rows,from,to){const a=day(from),b=day(add(to,1));return distribution(rows.filter(r=>r.end&&new Date(r.end)>=a&&new Date(r.end)<b));}
 function carry(rows,weekStart,stage){const cutoff=day(weekStart);return new Set(rows.filter(r=>r.stage===stage&&new Date(r.start)<cutoff&&(!r.end||new Date(r.end)>=cutoff)).map(r=>r.itemId)).size;}
 function split(total,weights=[80,15,5]){const raw=weights.map(w=>total*w/100),counts=raw.map(Math.floor);let left=total-counts.reduce((a,b)=>a+b,0);const order=raw.map((v,i)=>({i,r:v-counts[i]})).sort((a,b)=>b.r-a.r||a.i-b.i);for(let n=0;n<left;n++)counts[order[n].i]++;return counts;}
 function targetStatus(actual,target){if(!actual.total)return 'No data';if(!target)return 'No target';if(!target.carry_count)return 'No backlog';const p=[target.green_count,target.yellow_count,target.red_count].map(v=>v/target.carry_count*100);return actual.percent[0]+.000001>=p[0]&&actual.percent[1]<=p[1]+.000001&&actual.percent[2]<=p[2]+.000001?'Achieved':'Not achieved';}
 return {names,tats,colors,normalize,day,iso,add,week,fy,measurements,distribution,actual,carry,split,targetStatus};
})();
