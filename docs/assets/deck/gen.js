const P = require('pptxgenjs');
const pres = new P();
pres.layout = 'LAYOUT_WIDE';           // 13.333 x 7.5
pres.author = 'CoPartner';
pres.title  = 'CoPartner 進度全景';

// ---------- palette（沿用 panorama：冷灰綠底 + 磷光琥珀當「注意力」重點色）----------
const INK='14181B', INK2='3B4644', MUTED='697471', RULE='D2D8D5';
const SUNK='EDEFEE', WHITE='FFFFFF';
const ATTN='A9640B', ATTNL='E0A249', ATTNS='F6ECD9';
const DONE='2F6B57', DONES='DFEBE6';
const WAIT='6E7A77', WAITS='E7EAE9';

const SERIF='Cambria', SANS='Calibri', MONO='Courier New';
const W=13.333, H=7.5, M=0.62;                 // margin
const CW = W - M*2;                            // content width 12.09

const notes = [];

function slide(dark){
  const s = pres.addSlide();
  s.background = { color: dark ? INK : WHITE };
  return s;
}

// 視覺母題：小方磚（呼應 tile / foveated 擷取）
function tile(s, x, y, sz, color, opts={}){
  s.addShape(pres.ShapeType.roundRect, Object.assign({
    x, y, w: sz, h: sz, fill:{ color }, rectRadius: 0.02, line:{ type:'none' }
  }, opts));
}
function tileGrid(s, x, y, cols, rows, sz, gap, base, hot){
  for(let r=0;r<rows;r++) for(let c=0;c<cols;c++){
    const isHot = hot && hot(c,r);
    tile(s, x+c*(sz+gap), y+r*(sz+gap), sz, isHot || base);
  }
}
function eyebrow(s, text, x, y, color){
  s.addText(text, { x, y, w: CW, h:0.24, isTextBox:true, margin:0,
    fontFace:SANS, fontSize:11, bold:true, charSpacing:2.2, color: color||ATTN });
}
function title(s, text, x, y, opts={}){
  s.addText(text, Object.assign({ x, y, w: CW, h:0.8, isTextBox:true, margin:0,
    fontFace:SERIF, fontSize:33, bold:true, color: INK }, opts));
}
function sub(s, text, x, y, w, opts={}){
  s.addText(text, Object.assign({ x, y, w, h:0.5, isTextBox:true, margin:0,
    fontFace:SANS, fontSize:14, color: INK2, lineSpacing:22 }, opts));
}
function card(s, x, y, w, h, fill){
  s.addShape(pres.ShapeType.roundRect, { x, y, w, h, rectRadius:0.05,
    fill:{ color: fill || SUNK }, line:{ color: RULE, width:0.75 } });
}
function pill(s, x, y, w, text, fg, bg){
  s.addShape(pres.ShapeType.roundRect, { x, y, w, h:0.26, rectRadius:0.12,
    fill:{ color: bg }, line:{ type:'none' } });
  s.addText(text, { x, y, w, h:0.26, isTextBox:true, margin:0, align:'center',
    valign:'middle', fontFace:SANS, fontSize:10, bold:true, color: fg });
}
function n(s, text){ notes.push(text); s.addNotes(text); }

/* ============================ S1 封面 ============================ */
{
  const s = slide(true);
  // 母題：foveated tile 場（暗底、中央亮）
  tileGrid(s, 9.55, 0.9, 5, 4, 0.42, 0.09, '20272A',
    (c,r)=> (c===2&&r===1)?ATTNL : ((Math.abs(c-2)<=1&&Math.abs(r-1.2)<=1)?'6B4A17':null));
  eyebrow(s, 'V1  ·  MACOS AMBIENT ASSISTANT', M, 1.28, ATTNL);
  s.addText('CoPartner', { x:M, y:1.62, w:8.6, h:1.05, isTextBox:true, margin:0,
    fontFace:SERIF, fontSize:60, bold:true, color:WHITE });
  s.addText('一個會看著你工作、然後接手做完的 Mac 助理', { x:M, y:2.72, w:8.6, h:0.5,
    isTextBox:true, margin:0, fontFace:SANS, fontSize:21, color:'C9D2CF' });
  s.addText('不用跟它解釋你在幹嘛，因為它一直在旁邊看。而且從三週前開始，它會真的動手。',
    { x:M, y:3.34, w:8.4, h:0.6, isTextBox:true, margin:0, fontFace:SANS, fontSize:14,
      color:'8B9793', lineSpacing:22 });

  const stats=[['94%','V1 完成度'],['18%','OCR 像素吞吐'],['595','XCTest 案例']];
  stats.forEach((st,i)=>{
    const x = M + i*2.95;
    s.addText(st[0], { x, y:4.42, w:2.7, h:0.62, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:40, bold:true, color:ATTNL });
    s.addText(st[1], { x, y:5.06, w:2.7, h:0.3, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:12, color:'8B9793' });
  });
  s.addText('main @ 3f14bb6  ·  2026-09-03  ·  50 個 PR 已合併', { x:M, y:6.62, w:CW, h:0.3,
    isTextBox:true, margin:0, fontFace:MONO, fontSize:10, color:'6C7A76' });
  n(s,'今天講一個我做了幾個月的 side project。它不是聊天機器人——它是一個看著你工作的助理。你不用跟它解釋你在幹嘛，因為它一直在旁邊看。而且它已經會真的動手——執行命令與操作 UI 都已經在真機上驗過。\n\n全場只要記得這三個數字：94% 完成度、18% OCR 吞吐、595 個測試。');
}

/* ============================ S2 問題 ============================ */
{
  const s = slide();
  eyebrow(s,'問題', M, 0.62);
  title(s,'AI 助理最貴的成本，是重新解釋', M, 0.94);
  const rows=[
    ['你開一個新對話','它一直開著'],
    ['貼程式碼、貼錯誤、打一段背景說明','它已經看了你剛才三十分鐘做的每一步'],
    ['它從零開始猜你要幹嘛','它有你的因果史，直接續寫'],
    ['你花 3 分鐘描述上下文','你按一個熱鍵'],
  ];
  const cw=(CW-0.4)/2, top=2.05;
  card(s, M, top, cw, 4.3, SUNK);
  card(s, M+cw+0.4, top, cw, 4.3, ATTNS);
  s.addText('現在的 AI 助理', { x:M+0.3, y:top+0.26, w:cw-0.6, h:0.36, isTextBox:true, margin:0,
    fontFace:SERIF, fontSize:17, bold:true, color:MUTED });
  s.addText('CoPartner', { x:M+cw+0.7, y:top+0.26, w:cw-0.6, h:0.36, isTextBox:true, margin:0,
    fontFace:SERIF, fontSize:17, bold:true, color:ATTN });
  rows.forEach((r,i)=>{
    const y = top+0.86+i*0.83;
    s.addText(r[0], { x:M+0.3, y, w:cw-0.6, h:0.7, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:13.5, color:INK2, valign:'top', lineSpacing:20 });
    s.addText(r[1], { x:M+cw+0.7, y, w:cw-0.6, h:0.7, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:13.5, color:INK, valign:'top', lineSpacing:20 });
  });
  n(s,'每次要 AI 幫忙，最花時間的不是它回答，是你解釋。CoPartner 的賭注是：如果它從頭看到尾，你就一句話都不用說。');
}

/* ============================ S3 場景 ============================ */
{
  const s = slide();
  eyebrow(s,'設計錨點場景', M, 0.62);
  title(s,'一個下午的 open loop', M, 0.94);
  const steps=[
    ['14:02','你在 Xcode 改一個 WebSocket 重連邏輯，寫到一半去查文件'],
    ['14:07','你切到瀏覽器、開了三個分頁、複製了一段程式碼'],
    ['14:11','你切回 Xcode，游標停在那個沒寫完的函式上'],
  ];
  steps.forEach((st,i)=>{
    const y=2.0+i*0.72;
    s.addShape(pres.ShapeType.roundRect,{ x:M, y, w:1.0, h:0.34, rectRadius:0.05,
      fill:{color:SUNK}, line:{type:'none'} });
    s.addText(st[0],{ x:M, y, w:1.0, h:0.34, isTextBox:true, margin:0, align:'center',
      valign:'middle', fontFace:MONO, fontSize:11, bold:true, color:MUTED });
    s.addText(st[1],{ x:M+1.25, y:y-0.03, w:CW-1.25, h:0.42, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:14.5, color:INK2, valign:'middle' });
  });
  // 熱鍵那一下
  const hy=4.22;
  s.addShape(pres.ShapeType.roundRect,{ x:M, y:hy, w:1.0, h:0.34, rectRadius:0.05,
    fill:{color:ATTN}, line:{type:'none'} });
  s.addText('14:11',{ x:M, y:hy, w:1.0, h:0.34, isTextBox:true, margin:0, align:'center',
    valign:'middle', fontFace:MONO, fontSize:11, bold:true, color:WHITE });
  s.addText('你按下 ⌃⌥⌘Space',{ x:M+1.25, y:hy-0.03, w:CW-1.25, h:0.42, isTextBox:true,
    margin:0, fontFace:SANS, fontSize:14.5, bold:true, color:ATTN, valign:'middle' });

  card(s, M+1.25, hy+0.62, CW-1.25, 1.42, ATTNS);
  s.addText('「你在改 reconnect 的退避邏輯，剛查了指數退避的實作。\n下一步：把你複製的那段套進 line 84 的 TODO。要我做嗎？」',
    { x:M+1.55, y:hy+0.82, w:CW-1.85, h:1.05, isTextBox:true, margin:0,
      fontFace:SERIF, fontSize:17, bold:true, color:'7A4707', lineSpacing:30 });
  n(s,'注意它說的不是「我可以幫你什麼」，而是接續你沒做完的那件事。這叫 open loop——設計文件裡的正式名詞。');
}

/* ============================ S4 三大理念 ============================ */
{
  const s = slide();
  eyebrow(s,'三大理念', M, 0.62);
  title(s,'省、清、快', M, 0.94);
  sub(s,'省是省 CPU，清是給人看，快是省你的嘴——每一項都已經有真機數字，不是設計文件裡的願望。',
    M, 1.72, 10.4, { fontSize:13.5 });
  const items=[
    ['SMART CAPTURE ENGINE','看得省','不做定頻全畫面截圖。滑鼠與焦點區高解析高頻、周邊低解析低頻（借人眼中央窩），只對「變動的 tile」細看（借 KVM-over-IP／VNC 的增量更新）。','idle CPU  9%'],
    ['ACTION SCRIPT NARRATOR','記得清','截圖是單一瞬間，劇本是因果史。三層滾動彙總：L0 模板（零模型）→ L1 本地 3B → L2 段落摘要。階梯會回報自己用了哪一層。','L1 延遲  1373–2388ms'],
    ['CLOUD TAKEOVER','交棒快','按 ⌃⌥⌘Space，把因果史交給 Claude computer-use 續寫你沒做完的 open loop。回來的每個動作都是不可信提議，要過四道閘。','兩種執行能力都已真機驗過'],
  ];
  const cw=(CW-0.6)/3, top=2.48;
  items.forEach((it,i)=>{
    const x=M+i*(cw+0.3);
    card(s, x, top, cw, 3.85, SUNK);
    s.addText(it[0],{ x:x+0.28, y:top+0.28, w:cw-0.56, h:0.26, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:9.5, bold:true, charSpacing:1.4, color:MUTED });
    s.addText(it[1],{ x:x+0.28, y:top+0.58, w:cw-0.56, h:0.46, isTextBox:true, margin:0,
      fontFace:SERIF, fontSize:24, bold:true, color:INK });
    s.addText(it[2],{ x:x+0.28, y:top+1.16, w:cw-0.56, h:1.9, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:12.5, color:INK2, lineSpacing:20, valign:'top' });
    s.addText(it[3],{ x:x+0.28, y:top+3.26, w:cw-0.56, h:0.32, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:12, bold:true, color:ATTN });
  });
  n(s,'三個字概括：省、清、快。省是省 CPU，清是給人看，快是省你的嘴。這頁可以當全場地圖，後面每一段都掛在這三個字底下。');
}

/* ============================ S5 看得省 ============================ */
{
  const s = slide();
  eyebrow(s,'看得省 · Smart Capture Engine', M, 0.62);
  title(s,'不要全部看', M, 0.94);
  // foveation 圖：中央亮、周邊暗
  const gx=M, gy=2.0, sz=0.52, gap=0.08, cols=8, rows=6;
  s.addShape(pres.ShapeType.rect,{ x:gx-0.14, y:gy-0.14, w:cols*(sz+gap)+0.2, h:rows*(sz+gap)+0.2,
    fill:{color:WHITE}, line:{color:RULE, width:0.75} });
  tileGrid(s, gx, gy, cols, rows, sz, gap, SUNK, (c,r)=>{
    const d=Math.max(Math.abs(c-3.5),Math.abs(r-2.5));
    if(d<1) return ATTN; if(d<2) return ATTNS; return null;
  });
  s.addText('亮的是你在看的，暗的是周邊',{ x:gx, y:gy+rows*(sz+gap)+0.16, w:cols*(sz+gap), h:0.28,
    isTextBox:true, margin:0, fontFace:SANS, fontSize:11, color:MUTED });

  const bx = gx+cols*(sz+gap)+0.5, bw = W-M-bx;
  const pts=[
    ['中央窩成像','滑鼠與焦點區高解析高頻，周邊低解析低頻——人眼就是這樣運作的。'],
    ['增量更新','借鏡 KVM-over-IP／VNC，只處理「變動的 tile」。'],
    ['雙訊號交叉驗證','dirtyRects 當主訊號、Metal per-tile dHash 當 ground truth——不信任單一來源。'],
    ['冷熱狀態機','影片區自動標 DYNAMIC 並跳過 OCR。'],
  ];
  pts.forEach((p,i)=>{
    const y=2.0+i*1.02;
    tile(s, bx, y+0.07, 0.12, ATTN);
    s.addText(p[0],{ x:bx+0.3, y, w:bw-0.3, h:0.3, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:14, bold:true, color:INK });
    s.addText(p[1],{ x:bx+0.3, y:y+0.31, w:bw-0.3, h:0.62, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:12.5, color:INK2, lineSpacing:19, valign:'top' });
  });
  card(s, bx, 6.02, bw, 0.86, ATTNS);
  s.addText('真機實測　idle CPU 9%　·　operating 25%',
    { x:bx+0.26, y:6.02, w:bw-0.52, h:0.86, isTextBox:true, margin:0, valign:'middle',
      fontFace:SANS, fontSize:14, bold:true, color:'7A4707' });
  n(s,'定頻全螢幕截圖加全螢幕 OCR，在 24GB 的 M4 上長時間跑，光影片區就燙手。所以第一個決定就是：不要全部看。\n\n左邊這張圖就是實際的擷取策略——亮的區塊高解析高頻，暗的低解析低頻。');
}

/* ============================ S6 記得清 ============================ */
{
  const s = slide();
  eyebrow(s,'記得清 · Action Script Narrator', M, 0.62);
  title(s,'截圖是單一瞬間，劇本是因果史', M, 0.94);
  const lw=6.85;
  card(s, M, 2.0, lw, 3.5, SUNK);
  const script = [
    { text:'L0  ', options:{ fontFace:MONO, fontSize:11, bold:true, color:ATTN }},
    { text:'14:07:12  [切到 Safari]\n', options:{ fontFace:MONO, fontSize:11, color:INK2 }},
    { text:'      14:07:31  [複製 “func reconnect(attempt:)” 附近 12 行]\n', options:{ fontFace:MONO, fontSize:11, color:INK2 }},
    { text:'      14:11:02  [切回 Xcode · WebSocketClient.swift]\n\n', options:{ fontFace:MONO, fontSize:11, color:INK2 }},
    { text:'L1  ', options:{ fontFace:MONO, fontSize:11, bold:true, color:ATTN }},
    { text:'「使用者正在為 WebSocket 重連加入指數退避，\n      已查到參考實作，尚未套用」\n\n', options:{ fontFace:SANS, fontSize:12.5, color:INK }},
    { text:'L2  ', options:{ fontFace:MONO, fontSize:11, bold:true, color:ATTN }},
    { text:'「14:00–14:15 debug WebSocket 重連」', options:{ fontFace:SANS, fontSize:12.5, color:INK }},
  ];
  s.addText(script, { x:M+0.32, y:2.28, w:lw-0.64, h:2.95, isTextBox:true, margin:0,
    valign:'top', lineSpacing:19 });

  const rx=M+lw+0.4, rw=W-M-rx;
  const layers=[
    ['L0','模板','零模型、完全確定性'],
    ['L1','本地 3B','FoundationModels，推測意圖'],
    ['L2','段落摘要','滾動彙總'],
  ];
  layers.forEach((l,i)=>{
    const y=2.0+i*0.86;
    s.addShape(pres.ShapeType.roundRect,{ x:rx, y, w:0.62, h:0.62, rectRadius:0.06,
      fill:{color:ATTNS}, line:{type:'none'} });
    s.addText(l[0],{ x:rx, y, w:0.62, h:0.62, isTextBox:true, margin:0, align:'center',
      valign:'middle', fontFace:SANS, fontSize:15, bold:true, color:ATTN });
    s.addText(l[1],{ x:rx+0.82, y:y+0.03, w:rw-0.82, h:0.3, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:14, bold:true, color:INK });
    s.addText(l[2],{ x:rx+0.82, y:y+0.32, w:rw-0.82, h:0.28, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:12, color:MUTED });
  });
  s.addText('階梯會回報自己用了哪一層——關掉 Apple Intelligence 就掉回規則式，不中斷。',
    { x:rx, y:4.7, w:rw, h:0.62, isTextBox:true, margin:0, fontFace:SANS, fontSize:12.5,
      color:INK2, lineSpacing:19, valign:'top' });
  card(s, rx, 5.5, rw, 0.72, ATTNS);
  s.addText('L1 延遲　1373–2388ms',{ x:rx+0.24, y:5.5, w:rw-0.48, h:0.72, isTextBox:true,
    margin:0, valign:'middle', fontFace:SANS, fontSize:13.5, bold:true, color:'7A4707' });
  n(s,'你要它接手，它需要知道的不是畫面長什麼樣，是你為什麼走到這一步。\n\n左邊是真實的輸出格式：L0 是模板產的、完全確定性；L1 是本地 3B 推測意圖；L2 滾動彙總成段落。');
}

/* ============================ S7 四道閘 ============================ */
{
  const s = slide();
  eyebrow(s,'交棒快 · Cloud Takeover', M, 0.62);
  title(s,'四道閘', M, 0.94);
  sub(s,'模型回來的每個動作都是不可信提議。螢幕上出現的任何指令都可能是別人放的，所以防線必須在模型之外。',
    M, 1.72, 11.2, { fontSize:13.5 });
  const gates=[
    ['01','出境閘門','EgressGate','逐欄位掃描信封並遮罩；PIPL 命中就整包拒出，呼叫端只准走本地階，不 fallback 雲端。'],
    ['02','預算熔斷','LiteLLM Gateway','設 max_budget；路由不變式由 pytest 解析 config 斷言，不靠人記得。'],
    ['03','風險分級 + 人按','RiskClassifier','與模型推理無關的本地規則判 low／medium／high；high 在任何政策下都必須人按。'],
    ['04','沙箱執行','XPC + sbpl','雙向 code-signing 驗證 → sandbox-exec → posix_spawn argv 直呼。全程沒有一個 shell。'],
  ];
  const cw=(CW-0.66)/4, top=2.55;
  gates.forEach((g,i)=>{
    const x=M+i*(cw+0.22);
    card(s, x, top, cw, 2.72, i===3?ATTNS:SUNK);
    s.addText(g[0],{ x:x+0.26, y:top+0.24, w:cw-0.52, h:0.44, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:26, bold:true, color:ATTN });
    s.addText(g[1],{ x:x+0.26, y:top+0.76, w:cw-0.52, h:0.34, isTextBox:true, margin:0,
      fontFace:SERIF, fontSize:16, bold:true, color:INK });
    s.addText(g[2],{ x:x+0.26, y:top+1.12, w:cw-0.52, h:0.28, isTextBox:true, margin:0,
      fontFace:MONO, fontSize:10, color:MUTED });
    s.addText(g[3],{ x:x+0.26, y:top+1.5, w:cw-0.52, h:1.8, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:12, color:INK2, lineSpacing:19, valign:'top' });
  });
  card(s, M, 5.62, CW, 0.8, WHITE);
  s.addText('⌃⌥⌘.  kill-switch：作廢整個世代的授權——串流斷、HUD 進 aborted、後續 token 全失效。停的不是一個動作，是整批授權。',
    { x:M+0.3, y:5.62, w:CW-0.6, h:0.8, isTextBox:true, margin:0, valign:'middle',
      fontFace:SANS, fontSize:13, bold:true, color:INK2 });
  n(s,'四道閘任何一道都能單獨擋下來。重點在最後一段——動作是在另一個程序裡、在沙箱裡、用 argv 直呼執行的，全程沒有一個 shell。\n\n還有一個獨立的 kill-switch，作廢整個世代的授權，不是只停下一個動作。');
}

/* ============================ S8 進度（主秀）============================ */
{
  const s = slide();
  eyebrow(s,'進度', M, 0.5);
  s.addText([
    { text:'62', options:{ fontFace:SANS, fontSize:52, bold:true, color:INK }},
    { text:' / 66 ', options:{ fontFace:SANS, fontSize:26, color:MUTED }},
    { text:'   94%', options:{ fontFace:SANS, fontSize:26, bold:true, color:ATTN }},
  ], { x:M, y:0.78, w:5.2, h:0.86, isTextBox:true, margin:0, valign:'middle' });
  s.addText('原 58 步 TDD backlog（含 10.5／23.5 共 60 列），step 53「M5 真機驗收」做下去才發現前置的執行端根本不存在，展開成 53.1–53.7——所以總數是 66。',
    { x:5.6, y:0.8, w:W-M-5.6, h:0.82, isTextBox:true, margin:0, fontFace:SANS,
      fontSize:12, color:INK2, lineSpacing:18, valign:'middle' });

  // 里程碑燈號
  const ms=[['M0','擷取引擎','d','idle CPU 9%'],['M1','冷熱狀態機','w','待驗收'],
            ['M2','局部 OCR','d','吞吐 18%'],['M2.5','L0 劇本','d','時間機器'],
            ['M3','記憶系統','w','待驗收'],['M4','本地敘事','d','1373–2388ms'],
            ['M5','雲端交棒','p','執行端全通過'],['M6','隱私黑名單','w','待驗收']];
  const mw=(CW-0.49)/8, mt=1.86;
  ms.forEach((m,i)=>{
    const x=M+i*(mw+0.07);
    const fill = m[2]==='p'?ATTNS : (m[2]==='d'?DONES:WAITS);
    const fg   = m[2]==='p'?ATTN  : (m[2]==='d'?DONE :WAIT);
    s.addShape(pres.ShapeType.roundRect,{ x, y:mt, w:mw, h:1.06, rectRadius:0.05,
      fill:{color:fill}, line:{type:'none'} });
    s.addText(m[0],{ x:x+0.14, y:mt+0.1, w:mw-0.28, h:0.26, isTextBox:true, margin:0,
      fontFace:MONO, fontSize:11, bold:true, color:fg });
    s.addText(m[1],{ x:x+0.14, y:mt+0.36, w:mw-0.28, h:0.3, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:11.5, bold:true, color:INK });
    s.addText(m[3],{ x:x+0.14, y:mt+0.7, w:mw-0.28, h:0.26, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:9.5, color:fg });
  });

  // Phase tile rows
  const phases=[
    ['A  可跑骨架','step 1–10.5',11,11,0,0],
    ['B  智慧擷取引擎','step 11–24',13,15,0,1],
    ['C  局部 OCR','step 25–29',5,5,0,0],
    ['D  記憶系統','step 30–36',6,7,0,0],
    ['E  本地推理敘事','step 37–42',6,6,0,0],
    ['F  雲端交棒','step 43–53.7',17,17,0,0],
    ['G  隱私黑名單','step 54–58',4,5,0,0],
  ];
  const pt=3.22, sz=0.15, gap=0.045;
  phases.forEach((p,i)=>{
    const y=pt+i*0.42;
    s.addText(p[0],{ x:M, y:y-0.04, w:2.1, h:0.3, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:12.5, bold:true, color:INK, valign:'middle' });
    s.addText(p[1],{ x:M+2.15, y:y-0.04, w:1.25, h:0.3, isTextBox:true, margin:0,
      fontFace:MONO, fontSize:9, color:MUTED, valign:'middle' });
    const done=p[2], total=p[3], prog=p[4], defer=p[5];
    for(let k=0;k<total;k++){
      const x=M+3.5+k*(sz+gap);
      let col=WAITS;
      if(k<done) col=DONE;
      else if(k<done+prog) col=ATTN;
      else if(k>=total-defer) col=WAITS;
      tile(s, x, y+0.03, sz, col, k>=done+prog ? { line:{color:RULE,width:0.75} } : {});
    }
    s.addText(`${done} / ${total}`,{ x:11.0, y:y-0.04, w:1.0, h:0.3, isTextBox:true, margin:0,
      align:'right', fontFace:MONO, fontSize:10.5, color:MUTED, valign:'middle' });
  });

  card(s, M, 6.32, CW, 0.66, SUNK);
  s.addText([
    { text:'剩下四項全部只有真 Mac 能驗：', options:{ fontFace:SANS, fontSize:12.5, bold:true, color:INK }},
    { text:'23.5（延後優化）· 24（M1）· 36（M3）· 58（M6）　—　沒有任何「CI 能驗但還沒寫」的邏輯欠著。',
      options:{ fontFace:SANS, fontSize:12.5, color:INK2 }},
  ], { x:M+0.26, y:6.32, w:CW-0.52, h:0.66, isTextBox:true, margin:0, valign:'middle' });
  n(s,'94% 這個數字要小心解讀。剩下的四項全部是要真機、真權限、真 GPU 才能驗的東西——沒有任何一行「CI 能驗但還沒寫」的邏輯欠著。\n\n綠色是完成，琥珀色是進行中，空格是待驗收。');
}

/* ============================ S9 規模 ============================ */
{
  const s = slide();
  eyebrow(s,'規模', M, 0.62);
  title(s,'8,606 行程式碼，6,161 行測試', M, 0.94);
  const stats=[['8,606','Swift 原始碼 · 100 檔'],['6,161','測試 · 72 檔'],
               ['595','XCTest 案例'],['0.72','測試比']];
  const sw=(CW-0.6)/4;
  stats.forEach((st,i)=>{
    const x=M+i*(sw+0.2);
    card(s, x, 1.92, sw, 1.28, SUNK);
    s.addText(st[0],{ x:x+0.24, y:2.06, w:sw-0.48, h:0.6, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:32, bold:true, color:INK });
    s.addText(st[1],{ x:x+0.24, y:2.68, w:sw-0.48, h:0.32, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:11, color:MUTED });
  });
  const mods=[['ActionExecutor','19','1,789','HUD 閘門、風險、沙箱、UI 動作、undo'],
              ['CaptureEngine','31','1,784','擷取、tile、注意力、OCR、隱私遮罩'],
              ['app（含 XPC service）','16','2,461','menu bar、HUD 浮層、執行端'],
              ['ScriptNarrator','14','1,006','L0／L1／L2 三層劇本'],
              ['CloudRouter','10','858','打包、出境閘門、computer-use、SSE'],
              ['CoPartnerCore','4','472','共用型別、記憶體診斷純值層'],
              ['MemoryStore','5','174','三層記憶、向量檢索']];
  const hy=3.52;
  ['模組','檔數','行數','職責'].forEach((h,i)=>{
    const xs=[M, M+3.1, M+4.0, M+5.1], ws=[3.0,0.8,0.9,CW-4.48];
    s.addText(h,{ x:xs[i], y:hy, w:ws[i], h:0.28, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:10, bold:true, charSpacing:1.2, color:MUTED,
      align: i===1||i===2 ? 'right':'left' });
  });
  mods.forEach((m,i)=>{
    const y=hy+0.36+i*0.4;
    if(i%2===0) s.addShape(pres.ShapeType.rect,{ x:M-0.1, y:y-0.04, w:CW+0.2, h:0.38,
      fill:{color:SUNK}, line:{type:'none'} });
    s.addText(m[0],{ x:M, y, w:3.0, h:0.3, isTextBox:true, margin:0, fontFace:SANS,
      fontSize:12, bold:true, color:INK, valign:'middle' });
    s.addText(m[1],{ x:M+3.1, y, w:0.8, h:0.3, isTextBox:true, margin:0, align:'right',
      fontFace:MONO, fontSize:11, color:INK2, valign:'middle' });
    s.addText(m[2],{ x:M+4.0, y, w:0.9, h:0.3, isTextBox:true, margin:0, align:'right',
      fontFace:MONO, fontSize:11, color:INK2, valign:'middle' });
    s.addText(m[3],{ x:M+5.1, y, w:CW-4.48, h:0.3, isTextBox:true, margin:0, fontFace:SANS,
      fontSize:11.5, color:INK2, valign:'middle' });
  });
  s.addText('CI 三 job 全綠（macos-15）：swift · python · app（xcodegen + xcodebuild + XPC probe 型別檢查）',
    { x:M, y:6.62, w:CW, h:0.3, isTextBox:true, margin:0, fontFace:SANS, fontSize:11.5,
      color:MUTED });
  n(s,'測試比 0.72——每三行程式碼配兩行測試。這不是為了好看，是因為我沒有 Mac，測試是唯一能自主判定「這步做完了」的方式。下一頁講這件事。');
}

/* ============================ S10 方法論 ============================ */
{
  const s = slide();
  eyebrow(s,'方法論', M, 0.62);
  title(s,'沒有 Mac，怎麼寫 macOS app', M, 0.94);
  sub(s,'開發代理跑在 Linux 容器，沒有 Mac、沒有 GPU、沒有螢幕、沒有權限、沒有 Apple Intelligence。這六條是被逼出來的。',
    M, 1.72, 11.4, { fontSize:13.5 });
  const ps=[
    ['01','可注入後端','平台重活（Metal／SCK／vec0／FoundationModels／computer-use／XPC）全藏在 protocol 後，CI 用假後端驗邏輯。'],
    ['02','誠實佔位','沒接線的真後端一律 throw .notWired，絕不靜默假成功。假成功會讓「還沒接」這個訊號永遠消失。'],
    ['03','不變式寫進型別','ApprovalToken 的 init 是 internal，繞過閘門的呼叫路徑在編譯層面不存在；而且它不過 XPC 線。'],
    ['04','先無害，再有能力','XPC service 先做成沒有執行能力的骨架，驗簽補上後才翻開開關。'],
    ['05','build 綠 ≠ 真的編到了','canImport 為 false 時整檔靜默略過。在 #if／#else 兩側各放一個 #warning，看到黃字才算數。'],
    ['06','驗證方式比被驗的東西重要','沙箱只測「擋得住」會得到假通過——deny-default 下什麼都跑不起來。'],
  ];
  const cw=(CW-0.4)/2, top=2.5;
  ps.forEach((p,i)=>{
    const x=M+(i%2)*(cw+0.4), y=top+Math.floor(i/2)*1.42;
    s.addText(p[0],{ x, y, w:0.44, h:0.3, isTextBox:true, margin:0, fontFace:SANS,
      fontSize:13, bold:true, color:ATTN });
    s.addText(p[1],{ x:x+0.5, y:y-0.02, w:cw-0.5, h:0.32, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:14.5, bold:true, color:INK });
    s.addText(p[2],{ x:x+0.5, y:y+0.32, w:cw-0.5, h:0.92, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:12, color:INK2, lineSpacing:18, valign:'top' });
  });
  n(s,'這不是巧思，是被逼出來的。但逼出來的結果是——每一個平台依賴都變成一個明確的注入點，我永遠知道「哪裡還沒接真的」。\n\n94% 的工作是在沒有真機的情況下被驗證過的。');
}

/* ============================ S11 安全 ============================ */
{
  const s = slide();
  eyebrow(s,'安全', M, 0.62);
  title(s,'把不變式寫進型別系統', M, 0.94);
  sub(s,'間接 prompt injection 的防線不能是「我在 prompt 裡叫它不要聽壞人的話」。防線必須在模型之外。',
    M, 1.72, 11.4, { fontSize:13.5 });
  const rows=[
    ['ApprovalToken 的 init 是 internal','只有同模組的 HUD 狀態機能鑄造 → 「繞過確認閘門的呼叫路徑」在編譯層面不存在。'],
    ['ApprovalToken 不過 XPC 線','跨程序的值可以偽造，所以授權留在偽造不了的地方——主 app 內驗。'],
    ['ProposedAction 只有 argv: [String]','沒有整串 shell 欄位，型別層面消滅 metacharacter 注入面，executor 不經 sh -c。'],
    ['模型輸出＝不可信提議','每個動作過與模型推理無關的本地規則，加人工確認。防線不依賴 prompt。'],
  ];
  const top=2.5;
  rows.forEach((r,i)=>{
    const y=top+i*0.92;
    card(s, M, y, CW, 0.78, i%2===0?SUNK:WHITE);
    s.addText(r[0],{ x:M+0.3, y:y+0.06, w:4.6, h:0.66, isTextBox:true, margin:0,
      fontFace:MONO, fontSize:11.5, bold:true, color:ATTN, valign:'middle' });
    s.addText(r[1],{ x:M+5.1, y:y+0.06, w:CW-5.4, h:0.66, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:12.5, color:INK2, valign:'middle', lineSpacing:18 });
  });
  s.addText('十條可測不變式 I1–I10：繞不過閘門 · high 必人按 · 危險指令保守偏殺 · 無 shell 字串 · 路徑白名單解 symlink · 敏感不出境 · kill-switch 作廢整世代 · 動作迴圈熔斷 · 每提議落稽核 · gateway 路由不變式',
    { x:M, y:6.32, w:CW, h:0.62, isTextBox:true, margin:0, fontFace:SANS, fontSize:11.5,
      color:MUTED, lineSpacing:17, valign:'top' });
  n(s,'螢幕上出現的任何指令都是不可信的——那可能是別人放在網頁上騙模型的。所以防線必須在模型之外，而且最好是編譯器保證，不是靠紀律。');
}

/* ============================ S12 翻開執行開關（dark）============================ */
{
  const s = slide(true);
  eyebrow(s,'2026-08-20  ·  2026-09-03  ·  STEP 53.5 / 53.6-C', M, 0.62, ATTNL);
  s.addText('兩次「第一次」',{ x:M, y:0.94, w:CW, h:0.8, isTextBox:true, margin:0,
    fontFace:SERIF, fontSize:33, bold:true, color:WHITE });
  s.addText('翻開的那一行單獨成立一個 PR。理由很簡單：翻開執行能力若混在一大包程式碼裡，沒有人（包括作者）能真的審完。',
    { x:M, y:1.74, w:11.4, h:0.5, isTextBox:true, margin:0, fontFace:SANS, fontSize:13.5,
      color:'C9D2CF', lineSpacing:20 });
  const cw=(CW-0.4)/2, top=2.52;
  s.addShape(pres.ShapeType.roundRect,{ x:M, y:top, w:cw, h:3.0, rectRadius:0.05,
    fill:{color:'1B2E27'}, line:{type:'none'} });
  s.addShape(pres.ShapeType.roundRect,{ x:M+cw+0.4, y:top, w:cw, h:3.0, rectRadius:0.05,
    fill:{color:'2E2413'}, line:{type:'none'} });
  s.addText('允許',{ x:M+0.3, y:top+0.22, w:cw-0.6, h:0.34, isTextBox:true, margin:0,
    fontFace:SERIF, fontSize:18, bold:true, color:'6FBFA0' });
  s.addText('拒絕',{ x:M+cw+0.7, y:top+0.22, w:cw-0.6, h:0.34, isTextBox:true, margin:0,
    fontFace:SERIF, fontSize:18, bold:true, color:ATTNL });
  const allow=['只有 shell 一種動作',
    '只有固定表裡七個唯讀工具：cat ls head tail wc grep find',
    '只能寫沙箱工作目錄',
    '每個動作仍過本地風險分級 + HUD 人工確認'];
  const deny=['永遠不含 shell 本身',
    '網路全斷、家目錄關閉、秘密路徑另外 deny',
    '檔案動作明確拒絕；UI 執行端刻意不支援截圖',
    '解析不出的組合鍵一律 high——不知道它會做什麼，更該問人'];
  [[allow, M+0.3, 'D6E2E0'],[deny, M+cw+0.7, 'E4DCCC']].forEach(([list,x,col])=>{
    list.forEach((t,i)=>{
      const y=top+0.72+i*0.56;
      tile(s, x, y+0.08, 0.1, col==='D6E2E0'?'6FBFA0':ATTNL);
      s.addText(t,{ x:x+0.26, y:y-0.02, w:cw-0.56, h:0.52, isTextBox:true, margin:0,
        fontFace:SANS, fontSize:12, color:col, lineSpacing:18, valign:'top' });
    });
  });
  s.addText('第一次真執行刻意用本地合成提議，走完全相同的路徑——不繞過任何閘門，只是把提議來源從雲端換成本地，讓第一次真執行發生在完全受控的情況下。翻回 false 是出事時的第一個動作，只需改一行。',
    { x:M, y:5.78, w:CW, h:0.8, isTextBox:true, margin:0, fontFace:SANS, fontSize:12.5,
      color:'8B9793', lineSpacing:19, valign:'top' });
  n(s,'翻開執行能力那一行單獨成立一個 PR——這件事本身就是設計的一部分。\n\n還有一個細節：驗收判定是「stdout 裡有那串隨機標記」，不是 didExecute == true。因為沙箱擋掉讀取時 cat 照樣會結束、didExecute 照樣為真，stdout 卻是空的。');
}

/* ============================ S13 隱私 ============================ */
{
  const s = slide();
  eyebrow(s,'隱私', M, 0.62);
  title(s,'縱深五層', M, 0.94);
  const layers=[
    ['1','文字層','PIIMasker — 卡號／身分證／密碼欄在寫進劇本之前就遮','真機驗過','d'],
    ['2','tile 層','SensitiveTileMask — 敏感區不 OCR、不持久化','待 M6','w'],
    ['3','來源層','SCContentFilter 黑名單 — 黑名單 app 0 frame 進來','待 M6','w'],
    ['4','聚合層','注意力熱圖只存聚合權重，不存內容','完成','d'],
    ['5','出境層','EgressGate — PIPL 命中整包拒出，只准走本地階','待 M5 收尾','w'],
  ];
  const top=2.0;
  layers.forEach((l,i)=>{
    const y=top+i*0.8;
    card(s, M, y, CW, 0.66, i%2===0?SUNK:WHITE);
    s.addShape(pres.ShapeType.roundRect,{ x:M+0.22, y:y+0.13, w:0.4, h:0.4, rectRadius:0.05,
      fill:{color:ATTNS}, line:{type:'none'} });
    s.addText(l[0],{ x:M+0.22, y:y+0.13, w:0.4, h:0.4, isTextBox:true, margin:0, align:'center',
      valign:'middle', fontFace:SANS, fontSize:13, bold:true, color:ATTN });
    s.addText(l[1],{ x:M+0.82, y:y, w:1.5, h:0.66, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:13, bold:true, color:INK, valign:'middle' });
    s.addText(l[2],{ x:M+2.4, y:y, w:CW-4.3, h:0.66, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:12.5, color:INK2, valign:'middle' });
    pill(s, M+CW-1.5, y+0.2, 1.28, l[3], l[4]==='d'?DONE:WAIT, l[4]==='d'?DONES:WAITS);
  });
  s.addText('法遵：台灣 PDPA + 上海團隊的中國 PIPL 跨境條款。敏感命中時強制 local-only，不 fallback 雲端。\n刻意的「不做」：UI 執行端不支援截圖——截圖該由擷取管線產生並經出境閘門，在執行端偷截一張等於靜默拿掉整個出境設計。',
    { x:M, y:6.22, w:CW, h:0.8, isTextBox:true, margin:0, fontFace:SANS, fontSize:12,
      color:MUTED, lineSpacing:19, valign:'top' });
  n(s,'隱私不是一道牆，是五層。密碼欄在寫進劇本之前就遮掉了——不是存起來再過濾。\n\n最後那句「刻意的不做」我覺得最重要：截圖功能拿掉，是因為留著它就等於在出境閘門旁邊開一個後門。');
}

/* ============================ S14 真機 bug ============================ */
{
  const s = slide();
  eyebrow(s,'真機 dogfood', M, 0.62);
  title(s,'CI 永遠測不到的那種 bug', M, 0.94);
  const bugs=[
    ['FOCUS 狂刷','M2 · 同源共四類','終端機每輸出一個字就被判定換視窗。根因是焦點追蹤誤用 AX value（欄位內容）當視窗識別。','邏輯正確、測試也過——錯在真機餵給它的資料。'],
    ['OCR 截整螢幕','M2','混入選單列和其他 app 的文字，吞吐等同沒優化。','改依 AX 焦點框裁切 → 吞吐 18%。'],
    ['Vision bbox 左下原點','M2','與螢幕座標慣例相反，沿用會讓摘要上下顛倒。','型別強迫呼叫端明講慣例。'],
    ['稽核不誠實','M5','被閘門擋下的動作留下零痕跡；執行未成功記成已執行。','改成 attempt／executed／notExecuted／blocked 四態。'],
    ['sbpl 路徑陷阱','M5','給 /tmp/x 的規則對 /private/tmp/x 永遠不匹配，profile 看起來完全正常。','先 realpath，並補上路徑跳脫。'],
  ];
  const top=1.94;
  bugs.forEach((b,i)=>{
    const y=top+i*0.94;
    if(i===0) card(s, M, y-0.06, CW, 0.86, ATTNS);
    s.addText(b[0],{ x:M+0.2, y:y, w:2.5, h:0.3, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:14, bold:true, color:INK });
    s.addText(b[1],{ x:M+0.2, y:y+0.3, w:2.5, h:0.26, isTextBox:true, margin:0,
      fontFace:MONO, fontSize:9.5, color:MUTED });
    s.addText(b[2],{ x:M+2.9, y:y-0.02, w:5.4, h:0.62, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:12, color:INK2, lineSpacing:18, valign:'top' });
    s.addText(b[3],{ x:M+8.5, y:y-0.02, w:CW-8.5, h:0.62, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:12, bold:i===0, color:i===0?'7A4707':DONE,
      lineSpacing:18, valign:'top' });
  });
  n(s,'這五個沒有一個是 CI 抓得到的。第一個尤其可怕——所有測試都是綠的，因為測試餵的是乾淨資料。真機餵的不是。');
}

/* ============================ S15 記憶體診斷 ============================ */
{
  const s = slide();
  eyebrow(s,'STEP 53.7  ·  七輪', M, 0.62);
  title(s,'一場推翻了自己三次的診斷', M, 0.94);
  sub(s,'症狀：沒開觀察、只是讓 app 開著就會跳系統記憶體告警。這一句話就排除了原本兩個主要嫌疑——它們都只在觀察開始後才存在。',
    M, 1.72, 11.4, { fontSize:13.5 });

  card(s, M, 2.48, 5.5, 1.86, SUNK);
  s.addText([
    { text:'+151', options:{ fontFace:SANS, fontSize:30, bold:true, color:MUTED, strike:'sngStrike' }},
    { text:'  MB/hr', options:{ fontFace:SANS, fontSize:14, color:MUTED }},
    { text:'    →    ', options:{ fontFace:SANS, fontSize:20, color:MUTED }},
    { text:'+7', options:{ fontFace:SANS, fontSize:40, bold:true, color:DONE }},
    { text:'  MB/hr', options:{ fontFace:SANS, fontSize:14, color:DONE }},
  ],{ x:M+0.3, y:2.62, w:4.9, h:0.7, isTextBox:true, margin:0, valign:'middle' });
  s.addText('AsyncStream<TileEvent> 沒指定 buffering policy（無上限），唯一的消費者是 @MainActor 計數器。改成 .bufferingNewest(64)。',
    { x:M+0.3, y:3.34, w:4.9, h:0.9, isTextBox:true, margin:0, fontFace:SANS, fontSize:11.5,
      color:INK2, lineSpacing:17, valign:'top' });

  const rx=M+5.9, rw=W-M-rx;
  s.addText('診斷過程推翻的三個中途結論',{ x:rx, y:2.48, w:rw, h:0.3, isTextBox:true, margin:0,
    fontFace:SANS, fontSize:11, bold:true, charSpacing:1.2, color:MUTED });
  const wrong=[
    ['「持續成長」','一次性暖機被整體斜率攤成了成長率'],
    ['「還是在成長」','階段落差被攤成了成長率——斜率不該跨越狀態邊界'],
    ['「停止後不回落」','量測時機造成的假象。停止後 1–5 分鐘根本還沒開始掉，真正的落定點在 30 分鐘'],
  ];
  wrong.forEach((w2,i)=>{
    const y=2.88+i*0.72;
    s.addText(String(i+1),{ x:rx, y, w:0.3, h:0.28, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:12, bold:true, color:ATTN });
    s.addText(w2[0],{ x:rx+0.34, y:y-0.02, w:rw-0.34, h:0.28, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:12.5, bold:true, color:INK });
    s.addText(w2[1],{ x:rx+0.34, y:y+0.26, w:rw-0.34, h:0.5, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:11.5, color:INK2, lineSpacing:17, valign:'top' });
  });

  card(s, M, 5.22, CW, 0.9, ATTNS);
  s.addText('每一次都是同一種錯誤：一個看起來像資料的猜測，比「不知道」更糟。',
    { x:M+0.34, y:5.22, w:CW-0.68, h:0.9, isTextBox:true, margin:0, valign:'middle',
      fontFace:SERIF, fontSize:19, bold:true, color:'7A4707' });
  s.addText('附帶設計：刻意不用定時器取樣。要量的正是閒置路徑，在上面裝一個定時醒來的東西，等於在被觀察的對象裡加一個新的觀察者。改成每次打開選單取一個樣，背景成本恰好是零。',
    { x:M, y:6.34, w:CW, h:0.62, isTextBox:true, margin:0, fontFace:SANS, fontSize:12,
      color:MUTED, lineSpacing:19, valign:'top' });
  n(s,'這頁我最想講的不是那個 bug，是診斷過程。七輪裡我三次以為自己找到答案，三次都被下一份資料推翻。\n\n共通點是：我拿一個看起來像資料的東西（斜率）當結論，但那個斜率的算法本身有問題。');
}

/* ============================ S16 驗證方式 ============================ */
{
  const s = slide();
  eyebrow(s,'方法論', M, 0.62);
  title(s,'驗證方式比被驗的東西重要', M, 0.94);
  sub(s,'一個測不出東西的測試，比沒有測試更危險——因為它會讓你以為你驗過了。',
    M, 1.72, 11.4, { fontSize:13.5 });
  const cw=(CW-0.4)/2, top=2.5;
  card(s, M, top, cw, 2.7, SUNK);
  card(s, M+cw+0.4, top, cw, 2.7, DONES);
  s.addText('錯的驗法',{ x:M+0.3, y:top+0.24, w:cw-0.6, h:0.34, isTextBox:true, margin:0,
    fontFace:SERIF, fontSize:17, bold:true, color:MUTED });
  s.addText('對的驗法',{ x:M+cw+0.7, y:top+0.24, w:cw-0.6, h:0.34, isTextBox:true, margin:0,
    fontFace:SERIF, fontSize:17, bold:true, color:DONE });
  const bad=['只測「擋得住」','deny-default 之下什麼都跑不起來 → 全部通過','得到一個永遠會通過的測試'];
  const good=['成對驗證：正向基準 + 負向結果','負向結果依賴正向基準','基準沒過時全部標「無效」，而不是「通過」'];
  [[bad,M+0.3,INK2],[good,M+cw+0.7,INK]].forEach(([list,x,col])=>{
    list.forEach((t,i)=>{
      const y=top+0.78+i*0.6;
      tile(s, x, y+0.09, 0.11, col===INK?DONE:MUTED);
      s.addText(t,{ x:x+0.28, y:y-0.02, w:cw-0.58, h:0.56, isTextBox:true, margin:0,
        fontFace:SANS, fontSize:12.5, color:col, lineSpacing:18, valign:'top' });
    });
  });
  card(s, M, 5.5, CW, 0.86, WHITE);
  s.addText([
    { text:'./scripts/sandbox-verify.sh', options:{ fontFace:MONO, fontSize:13, bold:true, color:INK }},
    { text:'    →    8 項全綠  ·  0 失敗  ·  ', options:{ fontFace:SANS, fontSize:13, color:INK2 }},
    { text:'0 無效', options:{ fontFace:SANS, fontSize:13, bold:true, color:DONE }},
  ],{ x:M+0.34, y:5.5, w:CW-0.68, h:0.86, isTextBox:true, margin:0, valign:'middle' });
  s.addText('同一個原則的另一個例子：canImport 隔離的程式碼，build 綠不代表編到了。在 #if／#else 兩側各放一個 #warning，看到黃字才算數。',
    { x:M, y:6.52, w:CW, h:0.4, isTextBox:true, margin:0, fontFace:SANS, fontSize:12,
      color:MUTED, valign:'top' });
  n(s,'「0 無效」那一欄是重點。它代表正向基準真的跑起來了，所以負向結果才有意義。少了它，一個什麼都擋的 profile 會通過每一條負向測試。');
}

/* ============================ S17 算術上不可達 ============================ */
{
  const s = slide();
  eyebrow(s,'M4 · L1 敘事延遲', M, 0.62);
  title(s,'一個算術上不可達的目標', M, 0.94);
  const lw=6.9;
  s.addText([
    { text:'原訂目標  ', options:{ fontFace:SANS, fontSize:14, color:MUTED }},
    { text:'~300ms', options:{ fontFace:SANS, fontSize:30, bold:true, color:MUTED, strike:'sngStrike' }},
  ],{ x:M, y:1.96, w:lw, h:0.56, isTextBox:true, margin:0, valign:'middle' });
  const steps=[
    '端上 3B 逐 token 串行生成，延遲幾乎與輸出長度成正比。',
    '300ms 的預算只夠 12–15 個 token。',
    '塞不下 6 欄位結構化輸出裡的兩段散文加一個陣列。',
    '再壓要砍 inferredGoal 欄位——那是 L1 的全部價值。',
  ];
  steps.forEach((t,i)=>{
    const y=2.68+i*0.62;
    s.addText('↓',{ x:M, y, w:0.3, h:0.3, isTextBox:true, margin:0, fontFace:SANS,
      fontSize:13, color:ATTN, align:'center' });
    s.addText(t,{ x:M+0.36, y:y-0.02, w:lw-0.36, h:0.56, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:13, color:INK2, lineSpacing:19, valign:'top' });
  });
  card(s, M, 5.28, lw, 0.9, ATTNS);
  s.addText('這是輸出形狀與模型吞吐的算術，不是調校問題。',
    { x:M+0.3, y:5.28, w:lw-0.6, h:0.9, isTextBox:true, margin:0, valign:'middle',
      fontFace:SERIF, fontSize:17, bold:true, color:'7A4707' });

  const rx=M+lw+0.5, rw=W-M-rx;
  card(s, rx, 1.96, rw, 2.0, SUNK);
  s.addText('壓過一輪就到頭了',{ x:rx+0.28, y:2.12, w:rw-0.56, h:0.3, isTextBox:true, margin:0,
    fontFace:SANS, fontSize:11, bold:true, charSpacing:1.2, color:MUTED });
  s.addText([
    { text:'2659', options:{ fontFace:SANS, fontSize:26, bold:true, color:MUTED, strike:'sngStrike' }},
    { text:'  →  ', options:{ fontFace:SANS, fontSize:18, color:MUTED }},
    { text:'1373', options:{ fontFace:SANS, fontSize:34, bold:true, color:INK }},
    { text:' ms', options:{ fontFace:SANS, fontSize:14, color:MUTED }},
  ],{ x:rx+0.28, y:2.5, w:rw-0.56, h:0.66, isTextBox:true, margin:0, valign:'middle' });
  s.addText('靠 @Guide 字數上限 + 視窗縮減',{ x:rx+0.28, y:3.2, w:rw-0.56, h:0.5, isTextBox:true,
    margin:0, fontFace:SANS, fontSize:11.5, color:INK2, lineSpacing:17, valign:'top' });

  card(s, rx, 4.16, rw, 2.02, WHITE);
  s.addText('修訂後的標準',{ x:rx+0.28, y:4.32, w:rw-0.56, h:0.3, isTextBox:true, margin:0,
    fontFace:SANS, fontSize:11, bold:true, charSpacing:1.2, color:MUTED });
  s.addText('~2.5s',{ x:rx+0.28, y:4.62, w:rw-0.56, h:0.56, isTextBox:true, margin:0,
    fontFace:SANS, fontSize:34, bold:true, color:DONE });
  s.addText('實測 1373–2388ms。浮動是因為 @Guide 的字數上限模型只當參考、不嚴格遵守（設 20 字、實測輸出 35 字）。',
    { x:rx+0.28, y:5.22, w:rw-0.56, h:0.86, isTextBox:true, margin:0, fontFace:SANS,
      fontSize:11.5, color:INK2, lineSpacing:17, valign:'top' });
  n(s,'這頁想講的是怎麼對待一個訂錯的目標。不是硬調參數調到天亮，是算一次數學，然後帶著理由去改目標。\n\n使用者裁決維持資訊量——寧可慢一點，也不要失去 inferredGoal。');
}

/* ============================ S18 M5 卡在哪 ============================ */
{
  const s = slide();
  eyebrow(s,'M5 · step 53', M, 0.62);
  title(s,'現在卡在哪', M, 0.94);
  const cw=(CW-0.5)/2, top=2.0;
  card(s, M, top, cw, 4.3, DONES);
  s.addText('已完成（真機驗過）',{ x:M+0.3, y:top+0.26, w:cw-0.6, h:0.34, isTextBox:true,
    margin:0, fontFace:SERIF, fontSize:17, bold:true, color:DONE });
  const done=[
    ['53.1','XPC 骨架 — service pid ≠ app pid，刻意無執行能力'],
    ['53.2','雙向 code-signing 驗證 — 外部程序定址不到'],
    ['53.3','sandbox-exec profile — 成對驗證 8 項全綠'],
    ['53.5','第一次真的執行命令 — stdout 帶回對得上的 UUID（8／20）'],
    ['53.6','第一次真的動使用者的電腦 — HUD 確認後畫面捲動（9／3）'],
    ['53.7','記憶體洩漏定位並修復 — +151 → +7 MB/hr'],
  ];
  done.forEach((d,i)=>{
    const y=top+0.72+i*0.58;
    s.addText(d[0],{ x:M+0.3, y, w:0.75, h:0.28, isTextBox:true, margin:0,
      fontFace:MONO, fontSize:11, bold:true, color:DONE });
    s.addText(d[1],{ x:M+1.1, y:y-0.02, w:cw-1.4, h:0.66, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:12.5, color:INK2, lineSpacing:18, valign:'top' });
  });

  const rx=M+cw+0.5;
  card(s, rx, top, cw, 4.3, ATTNS);
  s.addText('還剩',{ x:rx+0.3, y:top+0.26, w:cw-0.6, h:0.34, isTextBox:true, margin:0,
    fontFace:SERIF, fontSize:17, bold:true, color:ATTN });
  const left=[
    ['1','接上真雲端 SSE 來源 — 執行端全通了，但提議還是本地合成的；目前解析鏈用假來源驗過'],
    ['2','對照 I1–I10 逐項勾：危險指令被攔／kill-switch 全鏈斷／越界寫入 deny／LiteLLM 預算熔斷'],
    ['3','接手品質 — 留個 open loop 按熱鍵，Claude 應接續而不是貼一堆說明文字'],
  ];
  left.forEach((d,i)=>{
    const y=top+0.8+i*0.85;
    s.addText(d[0],{ x:rx+0.3, y, w:0.3, h:0.28, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:12, bold:true, color:ATTN });
    s.addText(d[1],{ x:rx+0.68, y:y-0.02, w:cw-0.98, h:0.8, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:12.5, color:INK2, lineSpacing:18, valign:'top' });
  });
  s.addText('M5 之後：M3 真 vec0（8hr 磁碟量）→ M1 擷取 CPU 優化 + 影片驗收 → M6 隱私最終審查 → V1 收官 → V2 Listen 開工。',
    { x:M, y:6.52, w:CW, h:0.4, isTextBox:true, margin:0, fontFace:SANS, fontSize:12,
      color:MUTED, valign:'top' });
  n(s,'左邊六項都在真機上驗過了——執行端整條鏈是通的。\n\n右邊剩的其實只有一件事的兩面：提議的來源還是本地合成的，接上真雲端之後才輪得到驗「Claude 有沒有正確續寫」。')
}

/* ============================ S19 誠實清單 ============================ */
{
  const s = slide();
  eyebrow(s,'誠實清單', M, 0.62);
  title(s,'已知的風險與缺陷', M, 0.94);
  sub(s,'列出來不是為了免責，是因為知道哪裡不確定本身就是進度。前兩條是寫在設計文件裡、後來被真機推翻的假設。',
    M, 1.72, 11.4, { fontSize:13.5 });
  const risks=[
    ['XPC 買到的不是權限降級','原本假設 service 跑在低權 user——做不到。內嵌 XPC service 必然與主 app 同 uid（實測 euid 501）。真正的圍籬來自 sbpl。記為殘餘風險 R5。'],
    ['L1 會編故事','終端機標題被 3B 腦補成「與 CoPartner 進行視訊會議」——日誌裡沒有任何視訊訊號。指令已明寫禁止臆測，3B 壓不住。'],
    ['真 vec0 磁碟量未驗','盲寫風險低，但要裝 sqlite-vec 並跑滿 8 小時才知道磁碟量。step 36 專門驗這件事。'],
    ['擷取仍是固定 2fps','每幀 hash 全螢幕；DYNAMIC 狀態機已測但還沒拿來降頻。step 23.5 是刻意延後，不是遺漏。'],
    ['同 app 內換視窗仍記 FOCUS','只有 CI 測試蓋到，dogfood 沒驗到。下次開兩個終端機視窗切一下就能補驗。'],
    ['單人開發、V2+V3 約一年','緩解方式是每一版都設計成「該版結束即有完整可用產品」，不是半成品接力。'],
  ];
  const cw=(CW-0.4)/3, top=2.5;
  risks.forEach((r,i)=>{
    const x=M+(i%3)*(cw+0.2), y=top+Math.floor(i/3)*2.06;
    card(s, x, y, cw, 1.86, i<2?ATTNS:SUNK);
    s.addText(r[0],{ x:x+0.26, y:y+0.22, w:cw-0.52, h:0.56, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:13.5, bold:true, color:i<2?'7A4707':INK, lineSpacing:19, valign:'top' });
    s.addText(r[1],{ x:x+0.26, y:y+0.82, w:cw-0.52, h:0.9, isTextBox:true, margin:0,
      fontFace:SANS, fontSize:11.5, color:INK2, lineSpacing:17, valign:'top' });
  });
  n(s,'我把不確定的東西列出來，不是為了免責，是因為知道哪裡不確定本身就是進度。\n\n上面兩條（琥珀色）特別重要——那是我原本寫在設計文件裡、被真機實測推翻的假設。');
}

/* ============================ S20 收尾（dark）============================ */
{
  const s = slide(true);
  tileGrid(s, 10.6, 0.62, 4, 3, 0.34, 0.08, '20272A',
    (c,r)=> (c===1&&r===1)?ATTNL:null);
  eyebrow(s,'V1 → V4', M, 0.72, ATTNL);
  s.addText('它已經會看了。它已經會動了。',{ x:M, y:1.06, w:9.6, h:0.8, isTextBox:true,
    margin:0, fontFace:SERIF, fontSize:31, bold:true, color:WHITE });
  s.addText('接下來是讓它離開電腦。',{ x:M, y:1.82, w:9.6, h:0.4, isTextBox:true, margin:0,
    fontFace:SANS, fontSize:16, color:'8B9793' });

  const vers=[
    ['V1','CoPartner','桌面 ambient 助理：看螢幕、寫劇本、熱鍵交棒','→ 2026-12','0%',0,true],
    ['V2','Listen','全日音訊 → 生活劇本；訊息閘道讓互動隨身','2027-01 → 05','30%',0.30,false],
    ['V3','Agent','技能引擎、heartbeat 主動巡檢、手機／手錶衛星','2027-06 → 11','70%',0.70,false],
    ['V4','Omni','穿戴優先：眼鏡、墜飾、即時耳語協助','2028+','100%',1.0,false],
  ];
  const top=2.6;
  vers.forEach((v,i)=>{
    const y=top+i*0.78;
    if(v[6]) s.addShape(pres.ShapeType.roundRect,{ x:M-0.16, y:y-0.08, w:CW+0.32, h:0.68,
      rectRadius:0.05, fill:{color:'2E2413'}, line:{type:'none'} });
    s.addText(v[0],{ x:M, y:y, w:0.6, h:0.4, isTextBox:true, margin:0, fontFace:MONO,
      fontSize:12, bold:true, color:v[6]?ATTNL:'6C7A76', valign:'middle' });
    s.addText(v[1],{ x:M+0.66, y:y, w:1.5, h:0.4, isTextBox:true, margin:0, fontFace:SERIF,
      fontSize:16, bold:true, color:WHITE, valign:'middle' });
    s.addText(v[2],{ x:M+2.3, y:y, w:5.9, h:0.4, isTextBox:true, margin:0, fontFace:SANS,
      fontSize:12.5, color:'C9D2CF', valign:'middle' });
    s.addText(v[3],{ x:M+8.3, y:y, w:1.6, h:0.4, isTextBox:true, margin:0, fontFace:MONO,
      fontSize:10.5, color:'8B9793', valign:'middle' });
    // 跳出電腦的程度
    s.addShape(pres.ShapeType.roundRect,{ x:M+10.1, y:y+0.15, w:1.3, h:0.1, rectRadius:0.05,
      fill:{color:'2A3335'}, line:{type:'none'} });
    if(v[5]>0) s.addShape(pres.ShapeType.roundRect,{ x:M+10.1, y:y+0.15, w:1.3*v[5], h:0.1,
      rectRadius:0.05, fill:{color:ATTNL}, line:{type:'none'} });
    s.addText(v[4],{ x:M+11.5, y:y, w:0.6, h:0.4, isTextBox:true, margin:0, align:'right',
      fontFace:MONO, fontSize:10.5, color:'8B9793', valign:'middle' });
  });
  s.addText('右欄是「跳出電腦的程度」。貫穿每一版的架構是 Hub-and-Satellites：Mac mini 永遠是中樞，手機手錶眼鏡都是衛星——不存資料、不做重推理，所以「本地優先、敏感不出境」在每一版都成立。',
    { x:M, y:5.82, w:CW, h:0.6, isTextBox:true, margin:0, fontFace:SANS, fontSize:11.5,
      color:'6C7A76', lineSpacing:18, valign:'top' });
  s.addText('AI 助理的瓶頸不是模型有多聰明，是它知不知道你在幹嘛。',
    { x:M, y:6.5, w:CW, h:0.5, isTextBox:true, margin:0, fontFace:SERIF, fontSize:20,
      bold:true, color:ATTNL });
  n(s,'三句話收尾：它已經會看了——M0／M2／M2.5／M4 真機通過。它已經會動了——沙箱執行端建成、開關翻開。接下來是讓它離開電腦。\n\n最後一句：這個專案真正在賭的是一件事——AI 助理的瓶頸不是模型有多聰明，是它知不知道你在幹嘛。');
}

pres.writeFile({ fileName: process.argv[2] || 'CoPartner-進度全景.pptx' })
  .then(f => console.log('written:', f, '| slides:', notes.length));
