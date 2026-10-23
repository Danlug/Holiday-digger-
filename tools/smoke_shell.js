#!/usr/bin/env node
// Дымовая проверка веб-оболочки в headless Chromium: загрузка -> «нажмите» -> игра, телефон и десктоп,
// ландшафтная плашка, мультитач, окно ошибки, не скачался wasm, нет WebGL2. Снимает скриншоты — на них надо смотреть глазами.
//
//   python3 tools/build_web_shell.py && (экспорт и штамп, см. docs/BUILD.md)
//   cd build/web && python3 -m http.server 8000 &
//   node tools/smoke_shell.js http://localhost:8000/index.html /каталог/для/скриншотов [mobile,desktop,loadfail,nogl]
//
// Playwright берётся из /opt/node-tools (PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers). Код выхода 1 — были провалы.
let chromium;
try { ({ chromium } = require('playwright')); } catch (e) { ({ chromium } = require('/opt/node-tools/node_modules/playwright')); }
const fs = require('fs');
const path = require('path');

const url = process.argv[2] || 'http://localhost:8000/index.html';
const outDir = process.argv[3] || path.join(process.cwd(), 'shell_shots');
const only = (process.argv[4] || 'mobile,desktop,loadfail,nogl').split(',');
fs.mkdirSync(outDir, { recursive: true });

const GL_ARGS = ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl'];
let failures = 0;
function check(name, ok, extra) {
	console.log((ok ? 'OK    ' : 'ПРОВАЛ') + ' ' + name + (extra ? '  (' + extra + ')' : ''));
	if (!ok) { failures++; }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function open(browser, opts) {
	const ctx = await browser.newContext(opts);
	const page = await ctx.newPage();
	const log = { errors: [], pageErrors: [], bad: [], urls: [] };
	page.on('console', (m) => {
		const t = m.text();
		// предупреждения самой игры (push_warning) и сообщения драйвера — не ошибки оболочки
		if (m.type() === 'error' && !/^WARNING|^\s+at:|GL Driver|Failed to load resource.*404/.test(t)) { log.errors.push(t.slice(0, 200)); }
	});
	page.on('pageerror', (e) => log.pageErrors.push(e.message.slice(0, 200)));
	page.on('response', (r) => { log.urls.push(r.url()); if (r.status() >= 400) { log.bad.push(r.status() + ' ' + r.url()); } });
	return { ctx, page, log };
}
const phase = (page) => page.evaluate(() => document.documentElement.getAttribute('data-phase'));
async function waitPhase(page, want, timeout) {
	await page.waitForFunction((w) => document.documentElement.getAttribute('data-phase') === w, want, { timeout: timeout || 120000 });
}
const snap = (page, name) => page.screenshot({ path: path.join(outDir, name + '.png') });

async function checkStamp(log) {
	const wasm = log.urls.filter((u) => /index\.wasm/.test(u));
	const pck = log.urls.filter((u) => /index\.pck/.test(u));
	const js = log.urls.filter((u) => /index\.js/.test(u));
	const stamped = (list) => list.length > 0 && list.every((u) => /[?&]v=/.test(u));
	check('штамп сборки: index.js/wasm/pck запрошены с ?v=', stamped(wasm) && stamped(pck) && stamped(js),
		[js[0], wasm[0], pck[0]].map((u) => (u || '-').replace(/^.*\//, '')).join(' '));
}

async function mobile(browser) {
	console.log('--- телефон 390x844, dpr 3');
	const { ctx, page, log } = await open(browser, { viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, hasTouch: true, isMobile: true });
	const cdp = await ctx.newCDPSession(page);
	await cdp.send('Network.enable');
	await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 20, downloadThroughput: 9 * 1024 * 1024, uploadThroughput: 1024 * 1024 });
	await page.goto(url);
	await waitPhase(page, 'loading', 20000);
	await page.waitForFunction(() => parseInt(document.getElementById('pct').textContent, 10) >= 30, null, { timeout: 60000 });
	const pctMid = await page.evaluate(() => document.getElementById('pct').textContent);
	await snap(page, 'mobile_1_loading');
	check('число процентов растёт по реальному прогрессу', parseInt(pctMid, 10) >= 30 && parseInt(pctMid, 10) < 100, pctMid + '%');
	await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1 });
	await waitPhase(page, 'ready', 120000);
	await sleep(900); // подсказка «нажмите» плавно проявляется
	await snap(page, 'mobile_2_ready');
	const geo = await page.evaluate(() => {
		const f = document.getElementById('frame').getBoundingClientRect(), c = document.getElementById('canvas');
		return { fw: f.width, fh: f.height, cw: c.width, ch: c.height, vw: innerWidth, vh: innerHeight };
	});
	check('телефон: игра заполняет экран', Math.abs(geo.fw - 390) < 1 && geo.fh > 800, JSON.stringify(geo));
	check('холст = размер кадра x dpr (без мыла)', Math.abs(geo.cw - geo.fw * 3) <= 1 && Math.abs(geo.ch - geo.fh * 3) <= 1);
	const meta = await page.evaluate(() => ({
		vp: document.querySelector('meta[name=viewport]').content,
		manifest: !!document.querySelector('link[rel=manifest]'),
		overscroll: getComputedStyle(document.body).overscrollBehaviorY,
		touchAction: getComputedStyle(document.getElementById('canvas')).touchAction,
		callout: getComputedStyle(document.body).webkitTouchCallout,
	}));
	check('viewport-fit=cover и запрет масштаба', /viewport-fit=cover/.test(meta.vp) && /user-scalable=no/.test(meta.vp));
	check('touch-action:none на холсте, overscroll выключен', meta.touchAction === 'none' && meta.overscroll === 'none');
	await page.tap('#splash');
	await waitPhase(page, 'running', 90000);
	await page.waitForFunction(() => getComputedStyle(document.getElementById('splash')).display === 'none', null, { timeout: 30000 });
	await sleep(4000);
	await snap(page, 'mobile_3_game');
	const audio = await page.evaluate(() => window.RaskopkiShell.audioStates());
	check('звук: контекст движка создан в жесте и работает', audio.length >= 1 && audio.every((s) => s === 'running'), JSON.stringify(audio));
	console.log('справка: полный экран после нажатия — ' + (await page.evaluate(() => !!document.fullscreenElement)));
	// мультитач: два пальца должны дойти до холста оба
	await page.evaluate(() => {
		window.__touch = { max: 0, prevented: 0 };
		document.getElementById('canvas').addEventListener('touchstart', (e) => {
			window.__touch.max = Math.max(window.__touch.max, e.touches.length);
			if (e.defaultPrevented) { window.__touch.prevented++; }
		});
	});
	await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 60, y: 700, id: 1 }] });
	await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 60, y: 700, id: 1 }, { x: 320, y: 700, id: 2 }] });
	await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
	const touch = await page.evaluate(() => window.__touch);
	check('мультитач: на холст приходят два касания сразу', touch.max === 2, JSON.stringify(touch));
	const ctxMenu = await page.evaluate(() => {
		const e = new MouseEvent('contextmenu', { cancelable: true, bubbles: true });
		document.getElementById('canvas').dispatchEvent(e);
		return e.defaultPrevented;
	});
	check('контекстное меню по долгому нажатию подавлено', ctxMenu === true);
	await checkStamp(log);
	await page.setViewportSize({ width: 844, height: 390 });
	await sleep(700);
	await snap(page, 'mobile_4_landscape');
	const rot = await page.evaluate(() => getComputedStyle(document.getElementById('rotate')).display);
	check('ландшафт на телефоне: плашка «поверни телефон»', rot === 'flex', rot);
	await page.setViewportSize({ width: 390, height: 844 });
	await sleep(500);
	const rot2 = await page.evaluate(() => getComputedStyle(document.getElementById('rotate')).display);
	check('портрет: плашка скрыта', rot2 === 'none', rot2);
	check('консоль без ошибок (телефон)', log.errors.length === 0 && log.pageErrors.length === 0, log.errors.concat(log.pageErrors).join(' | '));
	check('нет 404 (телефон)', log.bad.length === 0, log.bad.join(' | '));
	await page.evaluate(() => window.dispatchEvent(new ErrorEvent('error', { message: 'RuntimeError: unreachable' })));
	await sleep(500);
	await snap(page, 'mobile_5_crash');
	const ph = await phase(page);
	const reloadVisible = await page.evaluate(() => !document.getElementById('reload').hidden);
	check('падение движка: окно с кнопкой «Перезагрузить»', ph === 'fail' && reloadVisible, ph);
	await ctx.close();
}

async function desktop(browser) {
	console.log('--- десктоп 1280x800, dpr 1');
	const { ctx, page, log } = await open(browser, { viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1 });
	await page.goto(url);
	await waitPhase(page, 'ready', 120000);
	await sleep(900);
	await snap(page, 'desktop_1_ready');
	const g = await page.evaluate(() => {
		const f = document.getElementById('frame').getBoundingClientRect();
		return { w: f.width, h: f.height, x: f.left, rot: getComputedStyle(document.getElementById('rotate')).display };
	});
	check('десктоп: колонка 224:480 по центру', Math.abs(g.w / g.h - 224 / 480) < 0.004 && Math.abs(g.x + g.w / 2 - 640) < 1, JSON.stringify(g));
	check('десктоп: плашки «поверни» нет', g.rot === 'none');
	await page.setViewportSize({ width: 1920, height: 1080 });
	await sleep(400);
	const g2 = await page.evaluate(() => { const f = document.getElementById('frame').getBoundingClientRect(); return { w: f.width, h: f.height }; });
	check('1920x1080: целый множитель x2 (448x960)', g2.w === 448 && g2.h === 960, JSON.stringify(g2));
	await snap(page, 'desktop_1b_1080');
	await page.setViewportSize({ width: 1280, height: 800 });
	await sleep(300);
	await page.click('#splash');
	await waitPhase(page, 'running', 90000);
	await page.waitForFunction(() => getComputedStyle(document.getElementById('splash')).display === 'none', null, { timeout: 30000 });
	await sleep(4000);
	await snap(page, 'desktop_2_game');
	await checkStamp(log);
	check('консоль без ошибок (десктоп)', log.errors.length === 0 && log.pageErrors.length === 0, log.errors.concat(log.pageErrors).join(' | '));
	check('нет 404 (десктоп)', log.bad.length === 0, log.bad.join(' | '));
	await ctx.close();
}

async function loadfail(browser) {
	console.log('--- не скачался wasm');
	const { ctx, page } = await open(browser, { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, hasTouch: true, isMobile: true });
	await page.route('**/index.wasm*', (route) => route.abort());
	await page.goto(url);
	await waitPhase(page, 'fail', 60000);
	await sleep(300);
	await snap(page, 'loadfail');
	const t = await page.evaluate(() => document.getElementById('failTitle').textContent + ' / ' + !document.getElementById('reload').hidden);
	check('ошибка загрузки: сообщение и кнопка «Перезагрузить»', /Не загрузилось \/ true/.test(t), t);
	await ctx.close();
}

async function nogl() {
	console.log('--- без WebGL');
	const browser = await chromium.launch({ args: ['--disable-gpu', '--disable-webgl', '--disable-webgl2', '--disable-3d-apis'] });
	const { ctx, page } = await open(browser, { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, hasTouch: true, isMobile: true });
	await page.goto(url);
	await waitPhase(page, 'fail', 30000);
	await sleep(300);
	await snap(page, 'nogl');
	const t = await page.evaluate(() => document.getElementById('failTitle').textContent + ' / ' + document.getElementById('failText').textContent);
	check('нет WebGL2: понятное сообщение', /графики/i.test(t), t.slice(0, 60));
	await ctx.close();
	await browser.close();
}

(async () => {
	const browser = await chromium.launch({ args: GL_ARGS });
	try {
		if (only.includes('mobile')) { await mobile(browser); }
		if (only.includes('desktop')) { await desktop(browser); }
		if (only.includes('loadfail')) { await loadfail(browser); }
	} finally {
		await browser.close();
	}
	if (only.includes('nogl')) { await nogl(); }
	console.log(failures ? ('Провалов: ' + failures) : 'Все проверки прошли');
	process.exit(failures ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
