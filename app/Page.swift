// Page.swift: the panel's page, as it was in teacher.lua (the voice with the highlight comes from the reader of MANTRA_VOICE)
let PAGE_HTML = #"""
<!doctype html><html><head><meta charset="utf-8"><style>
  html,body{margin:0;height:100%;background:#0f1217;color:#f2f2f2;
    font:15px/1.4 -apple-system,Helvetica,sans-serif;-webkit-user-select:none;overflow:hidden}
  #wrap{display:flex;flex-direction:column;min-height:100%;padding:12px 14px;box-sizing:border-box}
  #top{display:flex;justify-content:space-between;align-items:center;gap:8px;font-size:11px;color:#8a8f99;letter-spacing:.06em}
  #ctl{display:flex;gap:6px;align-items:center}
  #ctl select,#ctl button{background:#1c222b;color:#c9d0da;border:1px solid #2a323f;border-radius:6px;font-size:11px;padding:2px 6px;cursor:pointer}
  #ctl button{min-width:40px}
  #say{flex:0 0 auto;overflow:visible;margin:8px 0 6px;font-size:16px;white-space:pre-wrap}
  #bar{margin-top:auto}
  #say.stopped{color:#e08a8a}
  #say.reply{color:#e9dcc0}
  #spoken{font-size:14px;line-height:1.45;color:#c9d0da;margin:0 0 6px;white-space:pre-wrap}
  #spoken:empty{display:none}
  #hint{font-size:13px;color:#b9c3d6;margin-bottom:6px;white-space:pre-wrap}
  #meter{display:none;height:8px;margin:0 0 8px;background:#1c222b;border-radius:4px;overflow:hidden}
  #meter i{display:block;height:100%;width:0;transition:width .08s linear;
    background:linear-gradient(90deg,#3fb862 0,#3fb862 60%,#e0c040 80%,#d04a3a 100%)}
  #bar{display:flex;align-items:center;gap:10px;margin-top:auto}
  button{border:0;border-radius:9px;color:#fff;font-size:14px;padding:9px 0;cursor:pointer}
  #stop{background:#b84040;width:78px}
  #mic{background:#3a4250;width:78px}
  #mic.listening{background:#d04a3a;animation:pulse 1.2s infinite}
  #mic.thinking{background:#8a6a2a}
  #cancel{background:#3a2323;color:#e08a8a;width:40px}
  @keyframes pulse{50%{opacity:.6}}
  #status{flex:1;font-size:12px;color:#9aa1ad;text-align:center}
  #next{background:#555c66;width:130px;font-size:16px}
  #next.on{background:#3fb862}
</style></head><body><div id="wrap">
  <div id="top"><span>@@HEAD@@</span><span id="ctl"><select id="voice" title="the voice"></select><button id="spd" title="reading speed">1.0×</button></span><span id="count"></span></div>
  <div id="say"></div>
  <div id="spoken"></div>
  <div id="hint"></div>
  <div id="meter"><i></i></div>
  <div id="bar">
    <button id="stop" onclick="send('stop')">STOP</button>
    <button id="mic" onclick="send('mic')">MIC</button>
    <button id="cancel" onclick="send('cancel')" title="C or Escape" hidden>✕</button>
    <span id="status"></span>
    <button id="next" onclick="send('next')">NEXT</button>
  </div>
</div><script>
  function send(m){ try{ window.webkit.messageHandlers.teacher.postMessage(m) }catch(e){} }
  function set(o){
    if (o.speed !== undefined && o.speed !== speed) setSpeed(o.speed, false);
    if (o.say !== undefined) document.getElementById('say').textContent = o.say;
    if (o.status !== undefined) document.getElementById('status').textContent = o.status;
    if (o.count !== undefined) document.getElementById('count').textContent = o.count;
    if (o.hint !== undefined) document.getElementById('hint').textContent = o.hint;
    if (o.nextOn !== undefined) document.getElementById('next').className = o.nextOn ? 'on' : '';
    if (o.mic !== undefined) {
      document.getElementById('mic').className = o.mic === 'idle' ? '' : o.mic;
      document.getElementById('meter').style.display = o.mic === 'listening' ? 'block' : 'none';
      document.getElementById('cancel').hidden = o.mic !== 'listening';
      if (o.mic !== 'listening') lvl(0);
    }
    document.getElementById('say').className = o.stopped ? 'stopped' : (o.reply ? 'reply' : '');
  }
  function lvl(v){ document.getElementById('meter').firstElementChild.style.width = (v * 100) + '%'; }
  /* THE BOX FITS THE TEXT (Marko, 7.9.2026: "the whole text must fit in the box, I don't want to
     scroll; the box should adapt to the text size"). After every change the page measures what it
     needs and tells Lua, which resizes the window. */
  let lastNeed = 0;
  function fit(){
    /* the content's own height, not the window's: the say/spoken/hint boxes by their scrollHeight
       (they stretch to fill), the rest by their box */
    let need = 24;
    for (const id of ['top','say','spoken','hint','meter','bar']){
      const el = document.getElementById(id); const cs = getComputedStyle(el);
      if (cs.display === 'none') continue;
      const h = (id === 'say' || id === 'spoken' || id === 'hint') ? el.scrollHeight : el.offsetHeight;
      const mt = id === 'bar' ? 8 : parseFloat(cs.marginTop || 0);      /* the bar's auto margin is the empty space */
      need += h + mt + parseFloat(cs.marginBottom || 0);
    }
    need = Math.ceil(need);
    if (Math.abs(need - lastNeed) < 4) return; lastNeed = need;
    send('size:' + need);
  }
  new ResizeObserver(() => fit()).observe(document.getElementById('wrap'));
  new MutationObserver(() => setTimeout(fit, 30)).observe(document.body, {subtree: true, childList: true, characterData: true, attributes: true});
  /* THE VOICE WITH THE HIGHLIGHT (Marko, 7.9.2026, through Talk: "the same algorithm is going to
     my teachers"). The system's reader (MANTRA_VOICE /reader.js) speaks the text into a box and
     lights the sentence and the word. Lua hears back whether it played, so teacher.py can fall
     back to afplay when the reader is not there. */
  function speak(text, where){
    const el = document.getElementById(where === 'say' ? 'say' : 'spoken');
    if (where !== 'say') el.textContent = text;
    if (!window.MantraReader){ send('voice:none'); return; }
    MantraReader.read(text, el, {speed: speed, onstart: () => send('voice:playing'), onend: () => send('voice:done')})
      .catch(e => send('voice:blocked ' + String(e).slice(0, 60)));
  }
  function hush(){ if (window.MantraReader) MantraReader.stop(); }
  /* READING SPEED and THE VOICE, in the window (Marko, 7.9.2026). The speed cycles and is
     remembered by Lua (panel.json); the voice list comes from the voice server, a change is the
     system's change (every app follows). */
  const SPEEDS = [0.8, 1.0, 1.2, 1.5, 2.0]; let speed = 1.0;
  function setSpeed(v, tell){ speed = v; document.getElementById('spd').textContent = v.toFixed(1) + '×'; if (tell) send('speed:' + v); }
  document.getElementById('spd').onclick = () => setSpeed(SPEEDS[(SPEEDS.indexOf(speed) + 1) % SPEEDS.length], true);
  async function voices(){
    const sel = document.getElementById('voice');
    try {
      const d = await (await fetch('http://127.0.0.1:8837/voices')).json();
      sel.innerHTML = '';
      for (const v of d.voices){ const o = document.createElement('option'); o.value = 'clone:' + v.name; o.textContent = v.name; sel.appendChild(o); }
      const b = document.createElement('option'); b.value = 'beatrice:'; b.textContent = 'Beatrice'; sel.appendChild(b);
      sel.value = d.current.engine === 'beatrice' ? 'beatrice:' : 'clone:' + d.current.voice;
      sel.onchange = async () => { const [engine, voice] = sel.value.split(':');
        await fetch('http://127.0.0.1:8837/current', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(voice ? {engine, voice} : {engine})}); };
    } catch (e) { sel.innerHTML = '<option>voice off</option>'; }
  }
  setTimeout(voices, 500);
  /* KEYS in the window: space talks and space stops (the MIC), N is NEXT, S is STOP, Escape hushes */
  document.addEventListener('keydown', e => {
    if (e.target && (e.target.tagName === 'SELECT' || e.target.tagName === 'INPUT')) return;
    if (e.code === 'Space'){ e.preventDefault(); send('mic'); }
    else if (e.code === 'KeyN'){ e.preventDefault(); send('next'); }
    else if (e.code === 'KeyS'){ e.preventDefault(); send('stop'); }
    else if (e.code === 'KeyC' || e.code === 'Escape'){ e.preventDefault(); send('cancel'); hush(); }   /* C and Escape: throw the recording away (Marko, 7.9.2026) */
  });
  send('ready');
</script><script src="http://127.0.0.1:8837/reader.js"></script></body></html>
"""#
