import HTTPTypes
import Hummingbird
import NIOCore

public func addUIRoutes(to router: Router<BasicRequestContext>) {
    router.get("ui") { _, _ in
        var headers = HTTPFields()
        headers[.contentType] = "text/html; charset=utf-8"
        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(string: simingUIHTML))
        )
    }
}

private let simingUIHTML = #"""
<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Siming FHIR Browser</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-size:14px;background:#f5f6f8;color:#1a1a2e;height:100vh;display:flex;flex-direction:column}
header{background:#1a1a2e;color:#fff;padding:0 20px;height:52px;display:flex;align-items:center;gap:12px;flex-shrink:0}
header .logo{font-size:18px;font-weight:700;letter-spacing:.5px}
header .tag{font-size:11px;background:#3B82F6;border-radius:4px;padding:2px 7px;font-weight:600}
header .server{margin-left:auto;font-size:12px;color:#94a3b8;font-family:monospace}
.layout{display:flex;flex:1;overflow:hidden}
.sidebar{width:200px;background:#fff;border-right:1px solid #e2e8f0;overflow-y:auto;flex-shrink:0}
.sidebar-title{padding:12px 16px 8px;font-size:11px;font-weight:600;color:#64748b;text-transform:uppercase;letter-spacing:.6px}
.sidebar ul{list-style:none}
.sidebar li a{display:block;padding:7px 16px;color:#374151;border-left:3px solid transparent;transition:all .15s;cursor:pointer}
.sidebar li a:hover{background:#f1f5f9;color:#1d4ed8}
.sidebar li a.active{background:#eff6ff;color:#1d4ed8;border-left-color:#3B82F6;font-weight:500}
.sidebar li a .count{float:right;font-size:11px;color:#94a3b8;font-weight:400}
.content{flex:1;overflow:auto;padding:24px}
.content-header{display:flex;align-items:center;gap:12px;margin-bottom:16px;flex-wrap:wrap}
.content-header h2{font-size:18px;font-weight:600;flex:1}
.btn{border:none;border-radius:6px;padding:6px 14px;font-size:13px;cursor:pointer;white-space:nowrap;font-family:inherit}
.btn-primary{background:#3B82F6;color:#fff}.btn-primary:hover{background:#2563eb}
.btn-secondary{background:#f1f5f9;color:#374151;border:1px solid #d1d5db}.btn-secondary:hover{background:#e2e8f0}
.btn-danger{background:#fff;color:#dc2626;border:1px solid #fca5a5}.btn-danger:hover{background:#fef2f2}
.btn-success{background:#059669;color:#fff}.btn-success:hover{background:#047857}
.search-row{display:flex;gap:8px}
.search-row input{border:1px solid #d1d5db;border-radius:6px;padding:6px 12px;font-size:13px;outline:none;width:220px;font-family:inherit}
.search-row input:focus{border-color:#3B82F6;box-shadow:0 0 0 2px #dbeafe}
.card{background:#fff;border-radius:8px;border:1px solid #e2e8f0;overflow:hidden}
table{width:100%;border-collapse:collapse}
thead th{padding:10px 14px;text-align:left;font-size:12px;font-weight:600;color:#6b7280;text-transform:uppercase;letter-spacing:.4px;border-bottom:1px solid #e2e8f0;background:#f9fafb}
tbody tr{border-bottom:1px solid #f1f5f9;cursor:pointer;transition:background .1s}
tbody tr:last-child{border-bottom:none}
tbody tr:hover{background:#f8faff}
tbody td{padding:10px 14px;color:#374151}
tbody td.id-cell{font-family:monospace;font-size:12px;color:#6b7280;max-width:180px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
tbody td.summary-cell{max-width:240px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
tbody td.date-cell{font-size:12px;color:#6b7280;white-space:nowrap}
tbody td.action-cell{width:60px;text-align:right}
.pagination{display:flex;align-items:center;gap:8px;padding:12px 14px;border-top:1px solid #e2e8f0;background:#f9fafb}
.pagination button{background:#fff;border:1px solid #d1d5db;border-radius:5px;padding:5px 12px;font-size:12px;cursor:pointer;color:#374151}
.pagination button:hover:not(:disabled){background:#f1f5f9}
.pagination button:disabled{opacity:.4;cursor:default}
.pagination .page-info{font-size:12px;color:#6b7280;flex:1;text-align:center}
.back-btn{display:inline-flex;align-items:center;gap:6px;color:#3B82F6;font-size:13px;cursor:pointer;margin-bottom:16px;padding:6px 10px;border-radius:6px}
.back-btn:hover{background:#eff6ff}
.detail-meta{display:flex;gap:16px;margin-bottom:16px;flex-wrap:wrap}
.detail-meta .meta-item{font-size:12px;color:#6b7280}
.detail-meta .meta-item strong{color:#374151;display:block;font-size:11px;text-transform:uppercase;letter-spacing:.4px;margin-bottom:2px}
.json-wrap{background:#fff;border:1px solid #e2e8f0;border-radius:8px;overflow:auto}
pre{padding:20px;font-family:"SF Mono",Fira Code,monospace;font-size:12.5px;line-height:1.6;white-space:pre-wrap;word-break:break-all}
.j-key{color:#0550ae}.j-str{color:#0a7c00}.j-num{color:#b5530b}.j-bool{color:#8250df}.j-null{color:#cf222e}
.editor-wrap{background:#fff;border:1px solid #e2e8f0;border-radius:8px;overflow:hidden}
.editor-toolbar{display:flex;align-items:center;gap:8px;padding:10px 14px;border-bottom:1px solid #e2e8f0;background:#f9fafb}
.editor-toolbar .editor-title{font-size:13px;font-weight:500;flex:1;color:#374151}
textarea.json-editor{width:100%;min-height:480px;padding:20px;font-family:"SF Mono",Fira Code,monospace;font-size:12.5px;line-height:1.6;border:none;outline:none;resize:vertical;tab-size:2}
.empty-state{text-align:center;padding:64px 24px;color:#6b7280}
.empty-state .icon{font-size:40px;margin-bottom:12px}
.error-banner{background:#fef2f2;border:1px solid #fecaca;border-radius:6px;padding:10px 14px;color:#b91c1c;font-size:13px;margin-bottom:16px}
.success-banner{background:#f0fdf4;border:1px solid #bbf7d0;border-radius:6px;padding:10px 14px;color:#166534;font-size:13px;margin-bottom:16px}
.modal-overlay{position:fixed;inset:0;background:rgba(0,0,0,.4);display:flex;align-items:center;justify-content:center;z-index:100}
.modal{background:#fff;border-radius:10px;padding:24px;max-width:400px;width:90%;box-shadow:0 20px 60px rgba(0,0,0,.2)}
.modal h3{font-size:16px;margin-bottom:8px}
.modal p{font-size:13px;color:#6b7280;margin-bottom:20px;line-height:1.5}
.modal-actions{display:flex;gap:8px;justify-content:flex-end}
</style>
</head>
<body>
<header>
  <span class="logo">Siming</span>
  <span class="tag">FHIR R4</span>
  <span class="server" id="serverUrl"></span>
</header>
<div class="layout">
  <aside class="sidebar">
    <div class="sidebar-title">Resources</div>
    <ul id="sidebarList"></ul>
  </aside>
  <main class="content" id="mainContent">
    <div class="empty-state">
      <div class="icon">⚕</div>
      <p>Select a resource type from the sidebar to begin.</p>
    </div>
  </main>
</div>
<div id="modalOverlay" class="modal-overlay" style="display:none">
  <div class="modal">
    <h3 id="modalTitle"></h3>
    <p id="modalMsg"></p>
    <div class="modal-actions">
      <button class="btn btn-secondary" onclick="closeModal()">Cancel</button>
      <button class="btn btn-danger" id="modalConfirmBtn">Delete</button>
    </div>
  </div>
</div>
<script>
const TYPES=['Patient','Observation','Encounter','Condition','Medication','MedicationRequest',
'AllergyIntolerance','Procedure','DiagnosticReport','Immunization','Practitioner',
'Organization','Location','RelatedPerson','ServiceRequest','Specimen',
'DocumentReference','CarePlan','Goal','MedicationStatement',
'FamilyMemberHistory','Appointment','MedicationAdministration'];

const BASE=window.location.origin;
let currentType=null,nextUrl=null,prevStack=[],searchTerm='';

document.getElementById('serverUrl').textContent=BASE;

// sidebar
const ul=document.getElementById('sidebarList');
TYPES.forEach(t=>{
  const li=document.createElement('li');
  li.innerHTML=`<a id="nav-${t}" onclick="selectType('${t}');return false">${t}<span class="count" id="cnt-${t}"></span></a>`;
  ul.appendChild(li);
});

// prefetch counts
TYPES.forEach(async t=>{
  try{
    const r=await fhirFetch(`/${t}?_count=0&_total=accurate`);
    if(r.ok){const b=await r.json();if(b.total!=null)document.getElementById(`cnt-${t}`).textContent=b.total;}
  }catch{}
});

function fhirFetch(url,opts={}){
  return fetch(url,{...opts,headers:{...(opts.headers||{}),'Accept':'application/fhir+json'}});
}

function selectType(type){
  if(currentType!==type){prevStack=[];searchTerm='';}
  currentType=type;
  document.querySelectorAll('.sidebar li a').forEach(a=>a.classList.remove('active'));
  document.getElementById(`nav-${type}`)?.classList.add('active');
  loadList(type,`/${type}?_count=20&_sort=-_lastUpdated`);
}

async function loadList(type,url){
  const main=document.getElementById('mainContent');
  main.innerHTML=`<div class="empty-state"><p>Loading…</p></div>`;
  try{
    const t0=performance.now();
    const r=await fhirFetch(url);
    const b=await r.json();
    const ms=Math.round(performance.now()-t0);
    if(!r.ok){showError(main,b);return;}
    renderList(type,b,url,ms);
  }catch(e){main.innerHTML=`<div class="error-banner">Network error: ${e.message}</div>`;}
}

function renderList(type,bundle,currentUrl,ms){
  const entries=(bundle.entry||[]).map(e=>e.resource).filter(Boolean);
  const total=bundle.total;
  nextUrl=(bundle.link||[]).find(l=>l.relation==='next')?.url||null;

  const msColor=ms<50?'#059669':ms<200?'#d97706':'#dc2626';
  const statsHtml=total!=null
    ?`<p style="margin-bottom:10px;font-size:12px;color:#6b7280">
        ${total} resource${total!==1?'s':''} total
        &nbsp;·&nbsp;
        <span style="color:${msColor};font-weight:600">${ms} ms</span>
      </p>`
    :`<p style="margin-bottom:10px;font-size:12px;color:#6b7280">
        <span style="color:${msColor};font-weight:600">${ms} ms</span>
      </p>`;

  const main=document.getElementById('mainContent');
  main.innerHTML=`
    <div class="content-header">
      <h2>${type}</h2>
      <div class="search-row">
        <input id="searchInput" type="text" placeholder="name=Wang / identifier=A123…" value="${esc(searchTerm)}"
          onkeydown="if(event.key==='Enter')doSearch()">
        <button class="btn btn-secondary" onclick="doSearch()">Search</button>
        ${searchTerm?`<button class="btn btn-secondary" onclick="clearSearch()">Clear</button>`:''}
      </div>
      <button class="btn btn-primary" onclick="showCreate('${type}')">+ New ${type}</button>
    </div>
    ${statsHtml}
    <div class="card">
      <table>
        <thead><tr><th style="width:180px">ID</th><th>Summary</th><th style="width:160px">Last Updated</th><th style="width:60px"></th></tr></thead>
        <tbody id="tableBody"></tbody>
      </table>
      <div class="pagination">
        <button onclick="goBack()" ${prevStack.length===0?'disabled':''}>← Prev</button>
        <span class="page-info">${entries.length} shown</span>
        <button onclick="goNext('${esc(currentUrl)}')" ${!nextUrl?'disabled':''}>Next →</button>
      </div>
    </div>`;

  const tbody=document.getElementById('tableBody');
  if(entries.length===0){
    tbody.innerHTML=`<tr><td colspan="4" style="text-align:center;padding:24px;color:#6b7280">No resources found</td></tr>`;
    return;
  }
  entries.forEach(res=>{
    const tr=document.createElement('tr');
    tr.innerHTML=`
      <td class="id-cell" title="${res.id}">${res.id}</td>
      <td class="summary-cell">${esc(getSummary(res))}</td>
      <td class="date-cell">${fmtDate(res.meta?.lastUpdated)}</td>
      <td class="action-cell"><button class="btn btn-secondary" style="padding:3px 10px;font-size:11px"
        onclick="event.stopPropagation();showDetail('${type}','${res.id}')">View</button></td>`;
    tr.onclick=()=>showDetail(type,res.id);
    tbody.appendChild(tr);
  });
}

function doSearch(){
  const val=document.getElementById('searchInput')?.value.trim()||'';
  searchTerm=val;
  prevStack=[];
  const url=val?`/${currentType}?_count=20&_sort=-_lastUpdated&${val}`:`/${currentType}?_count=20&_sort=-_lastUpdated`;
  loadList(currentType,url);
}
function clearSearch(){searchTerm='';selectType(currentType);}
function goNext(cur){if(!nextUrl)return;prevStack.push(cur);loadList(currentType,nextUrl);}
function goBack(){const url=prevStack.pop();if(url)loadList(currentType,url);}

async function showDetail(type,id){
  const main=document.getElementById('mainContent');
  main.innerHTML=`<div class="empty-state"><p>Loading…</p></div>`;
  try{
    const r=await fhirFetch(`/${type}/${id}`);
    const res=await r.json();
    if(!r.ok){showError(main,res);return;}
    renderDetail(type,res);
  }catch(e){main.innerHTML=`<div class="error-banner">Network error: ${e.message}</div>`;}
}

function renderDetail(type,res){
  const main=document.getElementById('mainContent');
  main.innerHTML=`
    <div class="back-btn" onclick="selectType('${type}')">← ${type}</div>
    <div class="content-header">
      <h2>${type}/${res.id}</h2>
      <button class="btn btn-secondary" onclick="showEdit('${type}',${JSON.stringify(JSON.stringify(res))})">Edit</button>
      <button class="btn btn-danger" onclick="confirmDelete('${type}','${res.id}')">Delete</button>
    </div>
    <div class="detail-meta">
      <div class="meta-item"><strong>Version</strong>${res.meta?.versionId||'—'}</div>
      <div class="meta-item"><strong>Last Updated</strong>${fmtDate(res.meta?.lastUpdated)}</div>
      <div class="meta-item"><strong>Summary</strong>${esc(getSummary(res))}</div>
    </div>
    <div class="json-wrap"><pre>${syntaxHL(JSON.stringify(res,null,2))}</pre></div>`;
}

function showCreate(type){
  const template=JSON.stringify({resourceType:type},null,2);
  renderEditor(type,null,template);
}

function showEdit(type,jsonStr){
  try{
    const res=JSON.parse(jsonStr);
    renderEditor(type,res.id,JSON.stringify(res,null,2));
  }catch{renderEditor(type,null,jsonStr);}
}

function renderEditor(type,id,json){
  const isNew=!id;
  const main=document.getElementById('mainContent');
  main.innerHTML=`
    <div class="back-btn" onclick="${isNew?`selectType('${type}')`:`showDetail('${type}','${id}')`}">
      ← ${isNew?type:`${type}/${id}`}
    </div>
    <div class="content-header">
      <h2>${isNew?`New ${type}`:`Edit ${type}/${id}`}</h2>
    </div>
    <div id="editorMsg"></div>
    <div class="editor-wrap">
      <div class="editor-toolbar">
        <span class="editor-title">application/fhir+json</span>
        <button class="btn btn-secondary" onclick="${isNew?`selectType('${type}')`:`showDetail('${type}','${id}')`}">Cancel</button>
        <button class="btn btn-success" onclick="saveResource('${type}','${id||''}')">Save</button>
      </div>
      <textarea class="json-editor" id="jsonEditor" spellcheck="false">${esc(json)}</textarea>
    </div>`;

  // tab key in textarea
  document.getElementById('jsonEditor').addEventListener('keydown',e=>{
    if(e.key==='Tab'){e.preventDefault();
      const t=e.target,s=t.selectionStart,en=t.selectionEnd;
      t.value=t.value.substring(0,s)+'  '+t.value.substring(en);
      t.selectionStart=t.selectionEnd=s+2;}
  });
}

async function saveResource(type,id){
  const raw=document.getElementById('jsonEditor')?.value||'';
  let body;
  try{body=JSON.parse(raw);}
  catch(e){showEditorMsg('error',`Invalid JSON: ${e.message}`);return;}

  const isNew=!id;
  const url=isNew?`/${type}`:`/${type}/${id}`;
  const method=isNew?'POST':'PUT';

  try{
    const r=await fetch(url,{
      method,
      headers:{'Content-Type':'application/fhir+json','Accept':'application/fhir+json'},
      body:JSON.stringify(body)
    });
    const result=await r.json();
    if(r.ok){
      const newId=result.id||id;
      // refresh sidebar count
      refreshCount(type);
      showDetail(type,newId);
    }else{
      const msg=result?.issue?.[0]?.diagnostics||JSON.stringify(result);
      showEditorMsg('error',`${r.status}: ${msg}`);
    }
  }catch(e){showEditorMsg('error',`Network error: ${e.message}`);}
}

function showEditorMsg(kind,msg){
  const el=document.getElementById('editorMsg');
  if(!el)return;
  el.innerHTML=`<div class="${kind==='error'?'error-banner':'success-banner'}">${esc(msg)}</div>`;
}

function confirmDelete(type,id){
  document.getElementById('modalTitle').textContent=`Delete ${type}/${id}?`;
  document.getElementById('modalMsg').textContent='This action cannot be undone. The resource will be marked as deleted.';
  document.getElementById('modalConfirmBtn').onclick=()=>doDelete(type,id);
  document.getElementById('modalOverlay').style.display='flex';
}

function closeModal(){document.getElementById('modalOverlay').style.display='none';}

async function doDelete(type,id){
  closeModal();
  try{
    const r=await fetch(`/${type}/${id}`,{method:'DELETE',headers:{Accept:'application/fhir+json'}});
    if(r.ok||r.status===204){
      refreshCount(type);
      selectType(type);
    }else{
      const b=await r.json().catch(()=>({}));
      const main=document.getElementById('mainContent');
      showError(main,b);
    }
  }catch(e){
    document.getElementById('mainContent').innerHTML=`<div class="error-banner">Network error: ${e.message}</div>`;
  }
}

async function refreshCount(type){
  try{
    const r=await fhirFetch(`/${type}?_count=0&_total=accurate`);
    if(r.ok){const b=await r.json();if(b.total!=null)document.getElementById(`cnt-${type}`).textContent=b.total;}
  }catch{}
}

function getSummary(r){
  switch(r.resourceType){
    case 'Patient':case 'Practitioner':case 'RelatedPerson':{
      const n=r.name?.[0];
      if(n)return[n.family,...(n.given||[])].filter(Boolean).join(' ');
      return r.identifier?.[0]?.value||'—';}
    case 'Organization':case 'Location':return r.name||'—';
    case 'Medication':return r.code?.coding?.[0]?.display||r.code?.text||'—';
    case 'Observation':{
      const label=r.code?.coding?.[0]?.display||r.code?.text||'';
      const val=r.valueQuantity?` ${r.valueQuantity.value} ${r.valueQuantity.unit||''}`:
                r.valueString?` "${r.valueString}"`:'';
      return(label+val)||'—';}
    default:
      return r.code?.coding?.[0]?.display||r.code?.text||r.status||r.title||r.description||'—';
  }
}

function fmtDate(s){
  if(!s)return'—';
  try{return new Date(s).toLocaleString('zh-TW',{year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit'});}
  catch{return s;}
}

function esc(s){return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');}

function syntaxHL(json){
  return esc(json).replace(
    /("(\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?)/g,
    m=>{
      if(/^"/.test(m))return/:$/.test(m)?`<span class="j-key">${m}</span>`:`<span class="j-str">${m}</span>`;
      if(/true|false/.test(m))return`<span class="j-bool">${m}</span>`;
      if(/null/.test(m))return`<span class="j-null">${m}</span>`;
      return`<span class="j-num">${m}</span>`;
    }
  );
}

function showError(el,body){
  const msg=body?.issue?.[0]?.diagnostics||body?.message||JSON.stringify(body);
  el.innerHTML=`<div class="error-banner">${esc(String(msg))}</div>`;
}
</script>
</body>
</html>
"""#
