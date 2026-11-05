// Pure mapping of authorized database rows. No fabricated records or grades.
window.ProcurementModel=(()=>{
  const normal=v=>String(v??'').trim().toLowerCase();
  function dateValue(v){if(typeof v!=='string'||!/^\d{4}-\d{2}-\d{2}/.test(v))return null;const date=new Date(String(v).length===10?v+'T00:00:00+05:30':v);return Number.isNaN(date.getTime())?null:date;}
  function workingHours(from,to){
    const a=dateValue(from),b=dateValue(to);if(!a||!b||b<a)return null;
    // Count the same start-anchored 15-minute ticks, one office day at a time.
    const start=a.getTime(),end=b.getTime(),step=900000,offset=19800000;
    let ticks=0,day=Math.floor((start+offset)/86400000)*86400000-offset;
    for(;day<end;day+=86400000){const d=new Date(day+offset),w=d.getUTCDay(),n=d.getUTCDate();if(w===0||(w===6&&n>=8&&n<=14))continue;
      const lo=Math.max(0,Math.ceil((day+570*60000-start)/step));
      const hi=Math.ceil((Math.min(end,day+1020*60000)-start)/step);
      ticks+=Math.max(0,hi-lo);
    }
    return ticks/4;
  }

  function stageStart(stage,f){
    const fallback={
      'Request Approval':['Timestamp'],Quotation:['Request Approval Timestamp','Timestamp'],
      'Vendor Approval':['Quotation Timestamp','Request Approval Timestamp','Timestamp'],
      PO:['Approval Timestamp','Quotation Timestamp','Timestamp'],
      'Fund Approval':['PO Timestamp','Approval Timestamp','Timestamp'],
      Payment:['Fund Approval Timestamp','PO Timestamp','Timestamp'],
      Dispatch:['Payment Timestamp','Payment Date','PO Timestamp','Timestamp'],
      QC:['Dispatch Timestamp','Dispatch Date','Payment Timestamp','Payment Date','Timestamp'],
      Invoice:['QC Timestamp','QC Date','Dispatch Timestamp','Dispatch Date','Timestamp'],
      Accounting:['QC Timestamp','QC Date','Dispatch Timestamp','Dispatch Date','Timestamp']
    };
    return (fallback[stage]||[]).map(k=>f[k]).find(v=>dateValue(v))||null;
  }
  function map(payload,now=new Date().toISOString()){
    const catalog=(payload.catalog||[]).map(c=>({code:c.alternate_code||'',legacyCode:c.item_code,alternateCode:c.item_code,name:c.item_name,unit:c.uom||'',category:c.data?.['Item Code_Category']||c.data?.Code_type||'',status:c.status||'Unspecified'}));
    const byName=new Map(catalog.map(c=>[normal(c.name),c])),byCode=new Map(catalog.flatMap(c=>[c.code,c.legacyCode].filter(Boolean).map(code=>[code,c])));
    const requests=(payload.requests||[]).map(r=>({id:r.id,displayId:r.display_id||r.id,project:r.project||'',requester:r.requester_name||r.requester_email||'',created:r.requested_at,required:null,remarks:''}));
    const reqMap=new Map(requests.map(r=>[r.id,r])),people=new Map((payload.employees||[]).map(p=>[p.id,p.full_name]));
    const full=new Map((payload.items||[]).map(i=>[i.id,i]));
    const raw=[...(payload.items||[]),...(payload.tracking||[]).filter(t=>!full.has(t.item_id)).map(t=>({...t,id:t.item_id,data:{},restricted:true}))];
    const items=raw.map(i=>{
      const fields=i.data||{},cat=byCode.get(i.item_code)||byName.get(normal(i.item_name));
      if(!reqMap.has(i.request_id)){const r={id:i.request_id,project:fields['Project/Client Name']||'Details restricted',requester:fields['Requester Name']||'',created:fields.Timestamp||null,required:i.required_by,remarks:''};reqMap.set(r.id,r);requests.push(r);}
      const r=reqMap.get(i.request_id);if(i.required_by&&(!r.required||i.required_by<r.required))r.required=i.required_by;if(fields.Remarks&&!r.remarks)r.remarks=fields.Remarks;
      const events=(payload.events||[]).filter(e=>e.item_id===i.id).sort((a,b)=>String(a.completed_at).localeCompare(String(b.completed_at)));
      const history=[...(r.created?[{stage:'Request created',date:r.created,actor:r.requester,remark:'Original request timestamp'}]:[]),...events.map(e=>({stage:e.stage,date:e.completed_at,actor:e.attribution==='verified_admin_action'?'Recorded admin action':e.attribution==='verified_stage_owner_action'?'Recorded stage action':'Configured owner: '+(e.owner_ids.map(id=>people.get(id)).filter(Boolean).join(' / ')||'Not available'),remark:e.attribution==='verified_admin_action'?'Recorded admin stage action':e.attribution==='verified_stage_owner_action'?'Recorded stage measurement':'Imported measurement; historical actor not verified',grade:e.color,workingHours:e.working_hours,tatHours:e.tat_hours}))];
      const stage=i.current_stage,elapsed=stage==='Completed'||stage==='Rejected'?null:workingHours(stageStart(stage,fields),now);
      return {id:i.id,requestId:i.request_id,requestLabel:r.displayId||r.id,name:i.item_name,code:cat?cat.code||'':i.item_code||'',unit:fields.Unit||cat?.unit||'',quantity:i.quantity,required:i.required_by,stage,elapsed,fields,history,restricted:!!i.restricted,version:i.version,sourceRow:i.source_row};
    });
    return {requests,items,catalog,events:payload.events||[],profile:payload.profile,stageOwners:payload.stageOwners||[],files:payload.files||[],connections:payload.connections||{},importedAt:payload.importedAt,sourceModifiedAt:payload.sourceModifiedAt,loadedAt:payload.loadedAt||now};
  }
  return {map,workingHours,stageStart};
})();
