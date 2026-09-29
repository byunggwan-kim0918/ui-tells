#!/usr/bin/env node
/**
 * measure.mjs — 브라우저 실측 도구. 의존성 0개.
 *
 * audit.sh 는 코드를 읽고, 이 파일은 **렌더된 화면을 잰다.** SKILL.md 가 요구하는
 * 측정(§4 수집, §6.A 색상환 census, §8 검증) 중 코드가 없던 것들을 담았다.
 * 이게 없으면 쓰는 사람이 매번 CDP 드라이버를 다시 짜게 된다.
 *
 * 왜 Playwright 가 아닌가 — SKILL.md §9 는 새 의존성 설치를 중단 조건으로 잡는다.
 * 그래서 npm 설치 없이 **이미 있는 브라우저**(실 Chrome 또는 Playwright 캐시 Chromium)를
 * CDP 로 직접 몬다. Node 22+ 내장 WebSocket 만 쓴다.
 *
 * 사용:
 *   node measure.mjs recon <url...>            레퍼런스 실측 (타이포·색·radius·보더·모션·그림자)
 *   node measure.mjs shot <url...>             스크린샷 (--w 390,1024,1440 --theme light,dark)
 *   node measure.mjs census <url...>           색상환 census (§6.A)
 *   node measure.mjs contrast <url...>         텍스트 대비 실측 (AA 4.5:1 / UI 3:1)
 *   node measure.mjs overflow <url...>         가로 넘침의 진짜 원인 요소
 *   node measure.mjs fonts <url...>            실제 로드된 서체 (폴백 판별)
 *   node measure.mjs motion <url...>           선언된 transition/animation 과 실제 트리거 여부
 *   node measure.mjs icon <url...>             아이콘을 16·32·180px 로 래스터해 확대 비교
 *
 * 공통 옵션:
 *   --w 390,1440      뷰포트 폭 (기본 1440)
 *   --theme light,dark  prefers-color-scheme 에뮬레이션 (기본 light)
 *   --out <dir>       산출물 디렉터리 (기본 ./.design/measure)
 *   --wait <ms>       렌더 대기 (기본 1500)
 *   --full            전체 페이지 캡처
 *   --json            사람이 읽는 표 대신 JSON
 */

import { spawn, execSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, mkdirSync, existsSync, readdirSync } from 'node:fs';
import { tmpdir, homedir } from 'node:os';
import { join, dirname } from 'node:path';

/* ── 브라우저 찾기 ───────────────────────────────────────────────────
   SKILL.md §4 는 "번들 Chromium 보다 지문이 자연스러워 anti-bot 을 통과한다"는
   이유로 실 Chrome 을 우선한다. 순서를 그대로 지킨다. */
function findBrowser() {
  const candidates = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
    process.env.CHROME_PATH,
  ].filter(Boolean);
  for (const c of candidates) if (existsSync(c)) return c;

  // Playwright 캐시에 받아둔 브라우저가 있으면 설치 없이 쓴다
  const cache = join(homedir(), 'Library/Caches/ms-playwright');
  if (existsSync(cache)) {
    for (const d of readdirSync(cache)) {
      for (const rel of [
        'chrome-mac/Chromium.app/Contents/MacOS/Chromium',
        'chrome-mac-arm64/Chromium.app/Contents/MacOS/Chromium',
        'chrome-headless-shell-mac-arm64/chrome-headless-shell',
        'chrome-headless-shell-mac/chrome-headless-shell',
      ]) {
        const p = join(cache, d, rel);
        if (existsSync(p)) return p;
      }
    }
  }
  return null;
}

/* ── 최소 CDP 클라이언트 ────────────────────────────────────────── */
class Browser {
  static async launch({ port = 9222 + Math.floor(Math.random() * 400), profile } = {}) {
    const bin = findBrowser();
    if (!bin) {
      console.error(
        '브라우저를 찾지 못했습니다.\n' +
          '  · Chrome 을 설치하거나 CHROME_PATH 로 경로를 지정하세요.\n' +
          '  · 새 의존성 설치는 SKILL.md §9 의 중단 조건입니다 — 사용자에게 먼저 물으세요.'
      );
      process.exit(3);
    }
    const proc = spawn(
      bin,
      [
        `--remote-debugging-port=${port}`,
        `--user-data-dir=${profile || mkdtempSync(join(tmpdir(), 'measure-'))}`,
        '--headless=new',
        '--hide-scrollbars',
        '--no-first-run',
        '--no-default-browser-check',
        '--disable-backgrounding-occluded-windows',
        '--disable-renderer-backgrounding',
        '--force-device-scale-factor=2',
      ],
      { stdio: 'ignore' }
    );
    for (let i = 0; i < 160; i++) {
      try {
        if ((await fetch(`http://127.0.0.1:${port}/json/version`)).ok) break;
      } catch {}
      await new Promise((r) => setTimeout(r, 250));
    }
    const b = new Browser();
    b.proc = proc;
    b.port = port;
    b.bin = bin;
    return b;
  }

  async page() {
    const list = await (await fetch(`http://127.0.0.1:${this.port}/json/list`)).json();
    let t = list.find((x) => x.type === 'page');
    if (!t) t = await (await fetch(`http://127.0.0.1:${this.port}/json/new?about:blank`, { method: 'PUT' })).json();
    const ws = new WebSocket(t.webSocketDebuggerUrl);
    await new Promise((res, rej) => ((ws.onopen = res), (ws.onerror = rej)));
    return new Page(ws);
  }

  close() {
    try {
      this.proc.kill();
    } catch {}
  }
}

class Page {
  constructor(ws) {
    this.ws = ws;
    this.id = 0;
    this.pending = new Map();
    this.handlers = new Map();
    ws.onmessage = (ev) => {
      const m = JSON.parse(ev.data);
      if (m.id && this.pending.has(m.id)) {
        const { res, rej } = this.pending.get(m.id);
        this.pending.delete(m.id);
        m.error ? rej(new Error(JSON.stringify(m.error))) : res(m.result);
      } else if (m.method) (this.handlers.get(m.method) || []).forEach((f) => f(m.params));
    };
  }
  on(k, f) {
    if (!this.handlers.has(k)) this.handlers.set(k, []);
    this.handlers.get(k).push(f);
  }
  send(method, params = {}) {
    const id = ++this.id;
    this.ws.send(JSON.stringify({ id, method, params }));
    return new Promise((res, rej) => {
      this.pending.set(id, { res, rej });
      setTimeout(() => {
        if (this.pending.has(id)) (this.pending.delete(id), rej(new Error('timeout: ' + method)));
      }, 60000);
    });
  }
  viewport(width, height = Math.round(width * 0.7)) {
    return this.send('Emulation.setDeviceMetricsOverride', {
      width, height, deviceScaleFactor: 2, mobile: width < 500,
    });
  }
  theme(scheme) {
    return this.send('Emulation.setEmulatedMedia', {
      features: [{ name: 'prefers-color-scheme', value: scheme }],
    });
  }
  async goto(url, waitMs = 1500) {
    await this.send('Page.enable');
    const loaded = new Promise((r) => this.on('Page.loadEventFired', r));
    await this.send('Page.navigate', { url });
    await Promise.race([loaded, new Promise((r) => setTimeout(r, 25000))]);
    await new Promise((r) => setTimeout(r, waitMs));
    // SKILL.md §4: location.href 로 생존 확인 (리다이렉트·차단 감지)
    return this.eval('return location.href');
  }
  async eval(body) {
    const r = await this.send('Runtime.evaluate', {
      expression: `(()=>{${body}})()`,
      returnByValue: true,
      awaitPromise: true,
    });
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || 'eval error');
    return r.result.value;
  }
  async shot(path, full = false) {
    mkdirSync(dirname(path), { recursive: true });
    const r = await this.send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: full });
    writeFileSync(path, Buffer.from(r.data, 'base64'));
    return path;
  }
  close() {
    try {
      this.ws.close();
    } catch {}
  }
}

/* ── 브라우저 안에서 도는 조각들 ──────────────────────────────── */

const SNIPPETS = {
  /* §6.A 색상환 census — "색을 정의한 뒤가 아니라 실제 데이터가 들어간 화면에서 센다" */
  census: `
    const hsl = (c) => {
      const m = c.match(/rgba?\\(([^)]+)\\)/); if (!m) return null;
      const p = m[1].split(',').map(Number);
      if (p.length > 3 && p[3] < 0.05) return null;
      const [r,g,b] = p.map(v => v/255);
      const mx = Math.max(r,g,b), mn = Math.min(r,g,b), d = mx-mn;
      let h = 0;
      if (d) { h = mx===r ? ((g-b)/d+6)%6 : mx===g ? (b-r)/d+2 : (r-g)/d+4; h *= 60; }
      const l = (mx+mn)/2;
      // HSL 채도는 흰색·검정 근처에서 분모(1-|2l-1|)가 0으로 가며 폭증한다.
      // rgb(251,250,247) 같은 종이색이 채도 33%로 잡혀 유채로 분류되는 원인이었다.
      // 그래서 절대 크로마(mx-mn)를 함께 본다.
      return {
        h: Math.round(h),
        s: Math.round((d ? d/(1-Math.abs(2*l-1)) : 0)*100),
        l: Math.round(l*100),
        chroma: d,
      };
    };
    const seen = new Map();
    for (const el of document.querySelectorAll('*')) {
      const r = el.getBoundingClientRect();
      if (!r.width || !r.height) continue;
      const area = Math.round(r.width * r.height);
      const cs = getComputedStyle(el);
      for (const prop of ['color','backgroundColor','borderTopColor']) {
        const v = hsl(cs[prop]); if (!v) continue;
        // 채도 12% 미만은 무채로 본다. 종이·잉크의 미세한 색조를 유채로 세면 census 가 무의미해진다
        // 채도와 절대 크로마를 모두 넘겨야 유채로 센다
        const key = v.s >= 12 && v.chroma >= 0.06 ? 'H' + (Math.round(v.h/15)*15) : 'gray';
        const cur = seen.get(key) || { count: 0, area: 0, samples: [] };
        cur.count++; cur.area += area;
        if (cur.samples.length < 3) cur.samples.push(cs[prop] + ' @' + prop + ' ' + el.tagName.toLowerCase());
        seen.set(key, cur);
      }
    }
    return [...seen.entries()].sort((a,b)=>b[1].area-a[1].area)
      .map(([k,v]) => ({ bucket: k, count: v.count, areaMpx: +(v.area/1e6).toFixed(2), sample: v.samples[0] }));
  `,

  /* 레퍼런스 실측 — DNA 7항목 중 기계로 잴 수 있는 것 */
  recon: `
    const gs = (e) => getComputedStyle(e);
    const out = {};
    const texts = [...document.querySelectorAll('h1,h2,h3,h4,p,span,div,a,button,td,th,li')].filter(e => {
      const hasText = [...e.childNodes].some(n => n.nodeType===3 && n.textContent.trim().length>1);
      const r = e.getBoundingClientRect();
      return hasText && r.width>0 && r.height>0 && gs(e).visibility!=='hidden';
    });
    const tb = new Map();
    for (const e of texts) {
      const s = gs(e);
      const k = [s.fontFamily.split(',')[0].replace(/["']/g,''), s.fontSize, s.fontWeight, s.lineHeight, s.letterSpacing].join(' | ');
      const c = tb.get(k) || { n:0, tags:new Set(), sample:'' };
      c.n++; c.tags.add(e.tagName.toLowerCase());
      if (!c.sample) c.sample = e.textContent.trim().slice(0,36);
      tb.set(k, c);
    }
    out.type = [...tb.entries()].sort((a,b)=>b[1].n-a[1].n).slice(0,14)
      .map(([k,v]) => ({ spec:k, n:v.n, tags:[...v.tags].join(','), sample:v.sample }));

    const rad = new Map(), bor = new Map(), sh = new Map(), mo = new Map();
    for (const e of document.querySelectorAll('*')) {
      const r = e.getBoundingClientRect(); if (r.width<20 || r.height<12) continue;
      const s = gs(e);
      if (s.borderTopLeftRadius !== '0px') rad.set(s.borderTopLeftRadius, (rad.get(s.borderTopLeftRadius)||0)+1);
      if (s.borderTopWidth !== '0px') { const k = s.borderTopWidth+' '+s.borderTopStyle; bor.set(k,(bor.get(k)||0)+1); }
      if (s.boxShadow && s.boxShadow !== 'none') { const k = s.boxShadow.slice(0,64); sh.set(k,(sh.get(k)||0)+1); }
      if (s.transitionDuration !== '0s') {
        const k = s.transitionProperty.slice(0,60)+' | '+s.transitionDuration+' | '+s.transitionTimingFunction;
        mo.set(k,(mo.get(k)||0)+1);
      }
    }
    const top = (m,n=8) => [...m.entries()].sort((a,b)=>b[1]-a[1]).slice(0,n);
    out.radius = top(rad); out.border = top(bor,5); out.shadow = top(sh,5); out.motion = top(mo);

    // 오버슈트 커브(제어점 >1)는 "스프링"이다. 있고 없고가 인상을 크게 가른다
    out.overshoot = [...mo.keys()].filter(k => /cubic-bezier\\(([^)]*)\\)/.test(k))
      .filter(k => (k.match(/cubic-bezier\\(([^)]*)\\)/)||[])[1]?.split(',').map(Number).some(v=>v>1||v<0));

    // 대문자 마이크로 라벨 (양수 자간) — 현행 제품 UI 의 흔한 관용구
    out.microLabels = texts.filter(e => {
      const s = gs(e);
      return s.textTransform === 'uppercase' && parseFloat(s.letterSpacing) > 0.3 && parseFloat(s.fontSize) <= 13;
    }).slice(0,6).map(e => { const s = gs(e); return e.textContent.trim().slice(0,20)+' ('+s.fontSize+'/'+s.fontWeight+' ls '+s.letterSpacing+')'; });

    const b = gs(document.body);
    out.body = { bg: b.backgroundColor, color: b.color, font: b.fontFamily.slice(0,64) };
    out.title = document.title;
    return out;
  `,

  /* 대비 실측 — 알파 배경은 하위 레이어와 합성 후 계산한다(안 하면 1.0 으로 잘못 나온다) */
  contrast: `
    const lum = (rgb) => {
      const [r,g,b] = rgb.map(v => { v/=255; return v<=0.04045 ? v/12.92 : Math.pow((v+0.055)/1.055, 2.4); });
      return 0.2126*r + 0.7152*g + 0.0722*b;
    };
    const parse = (c) => { const m = c.match(/rgba?\\(([^)]+)\\)/); return m ? m[1].split(',').map(Number) : null; };
    const over = (fg, bg) => fg.length>3 && fg[3]<1
      ? [0,1,2].map(i => fg[i]*fg[3] + bg[i]*(1-fg[3])) : fg.slice(0,3);
    const effBg = (el) => {
      let e = el;
      while (e) {
        const c = parse(getComputedStyle(e).backgroundColor);
        if (c && (c.length < 4 || c[3] > 0.95)) return c.slice(0,3);
        e = e.parentElement;
      }
      return [255,255,255];
    };
    const rows = [];
    for (const el of document.querySelectorAll('*')) {
      const hasText = [...el.childNodes].some(n => n.nodeType===3 && n.textContent.trim().length>1);
      if (!hasText) continue;
      const r = el.getBoundingClientRect(); if (!r.width || !r.height) continue;
      const s = getComputedStyle(el);
      const fg = parse(s.color); if (!fg) continue;
      const bg = effBg(el);
      const L1 = lum(over(fg,bg)), L2 = lum(bg);
      const ratio = (Math.max(L1,L2)+0.05)/(Math.min(L1,L2)+0.05);
      const px = parseFloat(s.fontSize), bold = parseInt(s.fontWeight,10) >= 700;
      const large = px >= 24 || (px >= 18.66 && bold);
      const need = large ? 3 : 4.5;
      rows.push({
        ratio: +ratio.toFixed(2), need, pass: ratio >= need,
        size: s.fontSize, weight: s.fontWeight,
        color: s.color, bg: 'rgb('+bg.join(',')+')',
        text: el.textContent.trim().slice(0,28),
      });
    }
    const seen = new Set();
    const uniq = rows.filter(r => { const k = r.color+'|'+r.bg+'|'+r.size; if (seen.has(k)) return false; seen.add(k); return true; });
    return uniq.sort((a,b)=>a.ratio-b.ratio);
  `,

  /* 가로 넘침 — 넓은 요소가 아니라 "축소되지 않는 조상"이 원인인 경우가 많다.
     grid/flex 자식의 기본 min-width:auto 가 overflow-x-auto 를 무력화한다 */
  overflow: `
    const W = document.documentElement.clientWidth;
    const total = document.documentElement.scrollWidth - W;
    const leaks = [];
    for (const el of document.querySelectorAll('body *')) {
      const b = el.getBoundingClientRect();
      if (b.right <= W + 1 && b.width <= W + 1) continue;
      let p = el.parentElement, scrollable = false;
      while (p && p !== document.body) {
        const ov = getComputedStyle(p).overflowX;
        if (ov === 'auto' || ov === 'scroll' || ov === 'hidden') { scrollable = true; break; }
        p = p.parentElement;
      }
      if (scrollable) continue;
      const par = el.parentElement;
      const ps = par ? getComputedStyle(par) : null;
      leaks.push({
        tag: el.tagName.toLowerCase(),
        cls: (el.className||'').toString().slice(0,60),
        width: Math.round(b.width), right: Math.round(b.right),
        // 이게 진짜 원인일 때가 많다
        parentDisplay: ps ? ps.display : null,
        parentMinWidth: ps ? ps.minWidth : null,
        hint: ps && /grid|flex/.test(ps.display) && ps.minWidth === 'auto'
          ? 'grid/flex 자식의 min-width:auto — 부모에 min-w-0 을 주면 해소될 수 있다' : null,
        text: (el.textContent||'').trim().slice(0,28),
      });
    }
    return { viewport: W, overflowPx: total, leakCount: leaks.length, leaks: leaks.slice(0,10) };
  `,

  /* 서체가 실제로 로드됐는지 — 폴백으로 렌더된 화면을 "확인됨"이라 하지 않는다(typography.md §5) */
  fonts: `
    const used = new Map();
    for (const el of document.querySelectorAll('h1,h2,h3,p,span,td,th,button,a,li')) {
      const r = el.getBoundingClientRect(); if (!r.width) continue;
      const f = getComputedStyle(el).fontFamily.split(',')[0].replace(/["']/g,'').trim();
      used.set(f, (used.get(f)||0)+1);
    }
    const loaded = [...document.fonts].map(f => f.family.replace(/["']/g,'') + ' ' + f.weight + ' ' + f.status);
    const declared = [...new Set([...document.fonts].map(f => f.family.replace(/["']/g,'')))];
    const rendered = [...used.entries()].sort((a,b)=>b[1]-a[1]);
    return {
      rendered,
      declared,
      // 렌더된 서체가 선언 목록에 없으면 폴백이다
      fallbackSuspects: rendered.filter(([f]) => !declared.includes(f)).map(([f,n]) => f+' ×'+n),
      loadedSample: loaded.slice(0,10),
    };
  `,

  /* 모션 — 선언은 됐는데 트리거가 없어 한 번도 재생되지 않는 것을 잡는다 */
  motion: `
    const decl = [];
    for (const el of document.querySelectorAll('*')) {
      const s = getComputedStyle(el);
      if (s.transitionDuration !== '0s') decl.push({
        kind: 'transition', prop: s.transitionProperty.slice(0,50),
        dur: s.transitionDuration, ease: s.transitionTimingFunction,
        cls: (el.className||'').toString().slice(0,44),
      });
      if (s.animationName !== 'none') decl.push({
        kind: 'animation', name: s.animationName, dur: s.animationDuration,
        ease: s.animationTimingFunction, iter: s.animationIterationCount,
        cls: (el.className||'').toString().slice(0,44),
      });
    }
    const keyframes = [...document.styleSheets].flatMap(ss => {
      try { return [...ss.cssRules].filter(r => r.type === CSSRule.KEYFRAMES_RULE).map(r => r.name); }
      catch { return []; }
    });
    const running = document.getAnimations ? document.getAnimations().length : null;
    return {
      declared: decl.length,
      keyframes: [...new Set(keyframes)],
      runningNow: running,
      // 같은 duration+easing 이 압도적이면 "하나의 효과를 전부에 복사"한 것이다(ai-tells §6)
      byEase: Object.entries(decl.reduce((a,d)=>{const k=d.dur+' '+d.ease;a[k]=(a[k]||0)+1;return a;},{}))
        .sort((a,b)=>b[1]-a[1]).slice(0,6),
      sample: decl.slice(0,8),
    };
  `,
};

/* ── 출력 ─────────────────────────────────────────────────────────── */
const C = { dim: '\x1b[2m', red: '\x1b[31m', yellow: '\x1b[33m', green: '\x1b[32m', off: '\x1b[0m' };
const args = process.argv.slice(3);
const flag = (name, def) => {
  const i = args.indexOf('--' + name);
  return i >= 0 ? args[i + 1] : def;
};
const has = (name) => args.includes('--' + name);
const urls = args.filter((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--') && !['full', 'json'].includes(args[i - 1].slice(2))));

const cmd = process.argv[2];
const OUT = flag('out', './.design/measure');
const WAIT = +flag('wait', 1500);
const WIDTHS = flag('w', '1440').split(',').map(Number);
const THEMES = flag('theme', 'light').split(',');
const JSON_OUT = has('json');

if (!cmd || !urls.length) {
  console.log(
    '사용: node measure.mjs <recon|shot|census|contrast|overflow|fonts|motion|icon> <url...> [옵션]\n' +
      '  --w 390,1440   --theme light,dark   --out <dir>   --wait <ms>   --full   --json'
  );
  process.exit(2);
}

const slug = (u) => u.replace(/^https?:\/\//, '').replace(/[^a-z0-9]/gi, '_').slice(0, 44) || 'page';

const browser = await Browser.launch();
const page = await browser.page();
console.log(`${C.dim}브라우저: ${browser.bin}${C.off}\n`);

let exitCode = 0;
const results = [];

for (const width of WIDTHS) {
  await page.viewport(width);
  for (const theme of THEMES) {
    await page.theme(theme);
    for (const url of urls) {
      const href = await page.goto(url, WAIT);
      const tag = `${width}px ${theme} ${url}`;
      console.log(`${'─'.repeat(64)}\n${tag}`);
      if (!href.replace(/\/$/, '').startsWith(url.replace(/\/$/, '').slice(0, 30))) {
        console.log(`${C.yellow}  생존확인: location.href = ${href} (리다이렉트됨)${C.off}`);
      }

      try {
        if (cmd === 'shot' || cmd === 'recon') {
          const f = join(OUT, `${width}-${theme}-${slug(url)}.png`);
          await page.shot(f, has('full'));
          console.log(`  스크린샷 ${f}`);
        }

        if (cmd === 'recon') {
          const r = await page.eval(SNIPPETS.recon);
          results.push({ url, width, theme, ...r });
          if (!JSON_OUT) {
            console.log(`  title: ${r.title}`);
            console.log(`  body : ${r.body.bg} / ${r.body.color} / ${r.body.font}`);
            console.log('\n  -- 타이포 (빈도순) --');
            r.type.forEach((t) => console.log(`    ${String(t.n).padStart(4)}x  ${t.spec}  "${t.sample}"`));
            console.log('\n  -- radius --', JSON.stringify(r.radius));
            console.log('  -- border --', JSON.stringify(r.border));
            console.log('  -- shadow --', JSON.stringify(r.shadow));
            console.log('\n  -- 모션 --');
            r.motion.forEach((m) => console.log(`    ${String(m[1]).padStart(4)}x  ${m[0]}`));
            console.log(`  오버슈트 커브: ${r.overshoot.length ? r.overshoot.join(' / ') : '없음'}`);
            console.log(`  대문자 마이크로 라벨: ${r.microLabels.length ? r.microLabels.join(' / ') : '없음'}`);
            const cen = await page.eval(SNIPPETS.census);
            console.log('\n  -- 색상환 census (면적순) --');
            cen.slice(0, 8).forEach((c) =>
              console.log(`    ${c.bucket.padEnd(6)} area=${String(c.areaMpx).padStart(7)}Mpx n=${String(c.count).padStart(4)}  ${c.sample || ''}`)
            );
          }
        }

        if (cmd === 'census') {
          const c = await page.eval(SNIPPETS.census);
          results.push({ url, theme, census: c });
          if (!JSON_OUT) {
            c.slice(0, 12).forEach((x) =>
              console.log(`  ${x.bucket.padEnd(6)} area=${String(x.areaMpx).padStart(7)}Mpx n=${String(x.count).padStart(4)}  ${x.sample || ''}`)
            );
            const chroma = c.filter((x) => x.bucket !== 'gray');
            if (chroma.length) {
              console.log(`\n  최빈 유채색: ${chroma[0].bucket} — 브랜드가 아니면 결함이다(§6.A①)`);
              const hs = chroma.map((x) => +x.bucket.slice(1)).sort((a, b) => a - b);
              const near = hs.filter((h, i) => i > 0 && h - hs[i - 1] <= 45);
              if (near.length) console.log(`  ${C.yellow}45° 이내 유채색 2개 이상 — 탁함의 원인이다(§6.A②)${C.off}`);
            }
          }
        }

        if (cmd === 'contrast') {
          const rows = await page.eval(SNIPPETS.contrast);
          const fail = rows.filter((r) => !r.pass);
          results.push({ url, theme, fail, total: rows.length });
          if (!JSON_OUT) {
            console.log(`  검사 ${rows.length}쌍 / 실패 ${fail.length}`);
            fail.slice(0, 12).forEach((r) =>
              console.log(`  ${C.red}FAIL${C.off} ${String(r.ratio).padStart(5)}:1 (필요 ${r.need}) ${r.size}/${r.weight} ${r.color} on ${r.bg}  "${r.text}"`)
            );
            if (!fail.length) console.log(`  ${C.green}모든 텍스트 쌍이 AA 통과${C.off}`);
          }
          if (fail.length) exitCode = 1;
        }

        if (cmd === 'overflow') {
          const o = await page.eval(SNIPPETS.overflow);
          results.push({ url, width, theme, ...o });
          if (!JSON_OUT) {
            console.log(`  뷰포트 ${o.viewport}px / 넘침 ${o.overflowPx}px / 원인 후보 ${o.leakCount}`);
            o.leaks.forEach((l) => {
              console.log(`  ${C.red}LEAK${C.off} <${l.tag}> w=${l.width} right=${l.right}  ${l.cls}`);
              if (l.hint) console.log(`       ${C.yellow}→ ${l.hint}${C.off}`);
            });
            if (!o.overflowPx) console.log(`  ${C.green}가로 넘침 없음${C.off}`);
          }
          if (o.overflowPx > 0) exitCode = 1;
        }

        if (cmd === 'fonts') {
          const f = await page.eval(SNIPPETS.fonts);
          results.push({ url, theme, ...f });
          if (!JSON_OUT) {
            console.log('  렌더된 서체:', f.rendered.map(([n, c]) => `${n} ×${c}`).join(', '));
            console.log('  선언된 서체:', f.declared.join(', ') || '(없음)');
            if (f.fallbackSuspects.length) {
              console.log(`  ${C.red}폴백 의심${C.off}: ${f.fallbackSuspects.join(', ')}`);
              console.log('  폴백으로 렌더된 화면을 "확인됨"이라 하지 않는다(typography.md §5)');
              exitCode = 1;
            } else console.log(`  ${C.green}선언한 서체로 렌더됨${C.off}`);
          }
        }

        if (cmd === 'motion') {
          const m = await page.eval(SNIPPETS.motion);
          results.push({ url, theme, ...m });
          if (!JSON_OUT) {
            console.log(`  선언 ${m.declared}곳 / 키프레임 ${m.keyframes.join(', ') || '없음'} / 지금 재생중 ${m.runningNow}`);
            console.log('  duration+easing 분포:');
            m.byEase.forEach(([k, n]) => console.log(`    ${String(n).padStart(4)}x  ${k}`));
            if (m.byEase.length === 1 && m.declared > 5)
              console.log(`  ${C.yellow}한 값만 나온다 — 하나의 효과를 전부에 복사한 것이다(ai-tells §6)${C.off}`);
            if (m.declared > 0 && m.runningNow === 0)
              console.log(`  ${C.yellow}선언은 있는데 재생중인 것이 0이다 — 트리거가 없는 모션인지 확인할 것${C.off}`);
          }
        }

        if (cmd === 'icon') {
          /* 아이콘은 최종 표시 치수로 래스터해서 본다. 큰 스크린샷은 증거가 아니다.
             rsvg-convert 가 없는 환경이 많아 브라우저로 대체한다 */
          const sizes = [16, 32, 180];
          const html =
            `<body style="margin:0;background:#888;font:12px system-ui;display:flex;gap:24px;padding:20px;align-items:flex-end">` +
            sizes
              .map(
                (s) =>
                  `<div><div style="color:#fff;margin-bottom:6px">@${s}</div>` +
                  `<img src="${url}" width="${s}" height="${s}" style="image-rendering:pixelated">` +
                  `<div style="margin-top:8px"><img src="${url}" style="image-rendering:pixelated;width:180px;height:180px"></div></div>`
              )
              .join('') +
            `</body>`;
          const f = join(OUT, `icon-${slug(url)}.html`);
          mkdirSync(dirname(f), { recursive: true });
          writeFileSync(f, html);
          await page.viewport(760, 320);
          await page.goto('file://' + join(process.cwd(), f).replace(/^\/+/, '/'), 800);
          const ok = await page.eval(`return [...document.images].every(i => i.naturalWidth > 0)`);
          const png = join(OUT, `icon-${slug(url)}.png`);
          await page.shot(png);
          console.log(`  ${ok ? C.green + '로드됨' + C.off : C.red + '로드 실패' + C.off}  →  ${png}`);
          console.log('  16px 에서 형태가 남는지 육안으로 판정할 것. 30px 미만에서 무너지면 단순형이 따로 필요하다');
          if (!ok) exitCode = 1;
        }
      } catch (e) {
        console.log(`  ${C.red}FAIL${C.off} ${String(e).slice(0, 180)}`);
        exitCode = 3;
      }
      console.log('');
    }
  }
}

if (JSON_OUT) console.log(JSON.stringify(results, null, 1));

page.close();
browser.close();
process.exit(exitCode);
