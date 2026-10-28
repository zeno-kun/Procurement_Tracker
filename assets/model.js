// Pure mapping of authorized database rows. No fabricated records or grades.
window.ProcurementModel=(()=>{
  const normal=v=>String(v??'').trim().toLowerCase();
  function dateValue(v){if(typeof v!=='string'||!/^\d{4}-\d{2}-\d{2}/.test(v))return null;const date=new Date(String(v).length===10?v+'T00:00:00+05:30':v);return Number.isNaN(date.getTime())?null:date;}
  function workingHours(start,end){
    const a=dateValue(start),b=dateValue(end);if(!a||!b||b<a)return null;
    let minutes=0;
    // Match the legacy review's 15-minute working-calendar increments.
    for(let t=a.getTime();t<b.getTime();t+=900000){const d=new Date(t+19800000),day=d.getUTCDay(),date=d.getUTCDate(),m=d.getUTCHours()*60+d.getUTCMinutes();if(day!==0&&!(day===6&&date>=8&&date<=14)&&m>=570&&m<1050)minutes+=15;}
    return Math.round(minutes/60*100)/100;
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
    const catalog=(payload.catalog||[]).map(c=>({code:c.item_code,alternateCode:c.alternate_code,name:c.item_name,unit:c.uom||'—',category:c.data?.Category||'—',status:c.status||'Unspecified'}));
    const byName=new Map(catalog.map(c=>[normal(c.name),c])),byCode=new Map(catalog.filter(c=>c.code).map(c=>[c.code,c]));
    const requests=(payload.requests||[]).map(r=>({id:r.id,project:r.project||'—',requester:r.requester_name||r.requester_email||'—',created:r.requested_at,required:null,remarks:''}));
    const reqMap=new Map(requests.map(r=>[r.id,r])),people=new Map((payload.employees||[]).map(p=>[p.id,p.full_name]));
    const full=new Map((payload.items||[]).map(i=>[i.id,i]));
    const raw=[...(payload.items||[]),...(payload.tracking||[]).filter(t=>!full.has(t.item_id)).map(t=>({...t,id:t.item_id,data:{},restricted:true}))];
    const items=raw.map(i=>{
      const fields=i.data||{},cat=byCode.get(i.item_code)||byName.get(normal(i.item_name));
      if(!reqMap.has(i.request_id)){const r={id:i.request_id,project:fields['Project/Client Name']||'Details restricted',requester:fields['Requester Name']||'—',created:fields.Timestamp||null,required:i.required_by,remarks:''};reqMap.set(r.id,r);requests.push(r);}
      const r=reqMap.get(i.request_id);if(i.required_by&&(!r.required||i.required_by<r.required))r.required=i.required_by;if(fields.Remarks&&!r.remarks)r.remarks=fields.Remarks;
      const events=(payload.events||[]).filter(e=>e.item_id===i.id).sort((a,b)=>String(a.completed_at).localeCompare(String(b.completed_at)));
      const history=[...(r.created?[{stage:'Request created',date:r.created,actor:r.requester,remark:'Original request timestamp'}]:[]),...events.map(e=>({stage:e.stage,date:e.completed_at,actor:e.attribution==='verified_stage_owner_action'?'Recorded stage action':'Configured owner: '+(e.owner_ids.map(id=>people.get(id)).filter(Boolean).join(' / ')||'Not available'),remark:e.attribution==='verified_stage_owner_action'?'Recorded stage measurement':'Imported measurement; historical actor not verified',grade:e.color,workingHours:e.working_hours,tatHours:e.tat_hours}))];
      const stage=i.current_stage,elapsed=stage==='Completed'||stage==='Rejected'?null:workingHours(stageStart(stage,fields),now);
      return {id:i.id,requestId:i.request_id,name:i.item_name,code:i.item_code||cat?.code||'—',unit:cat?.unit||'—',quantity:i.quantity,required:i.required_by,stage,elapsed,fields,history,restricted:!!i.restricted,sourceRow:i.source_row};
    });
    return {requests,items,catalog,events:payload.events||[],profile:payload.profile,importedAt:payload.importedAt,sourceModifiedAt:payload.sourceModifiedAt,loadedAt:payload.loadedAt||now};
  }
  return {map,workingHours,stageStart};
})();
