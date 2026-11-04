#!/usr/bin/env node
// Веб-проверка «закрыл игру под землёй — открыл там же» в headless Chromium (Playwright).
//
//   tools/build_web.sh
//   XDG_DATA_HOME=$PWD/.godot/xdg godot --headless --path . res://tests/test_save_position.tscn -- --seed-out /каталог/seed
//   node tools/smoke_save_position.js /каталог/seed /каталог/для/кадров [--close context|tab|background]
//
// Профиль браузера один на все заходы (IndexedDB переживает закрытие, как у игрока):
//   1. первый заход — движок заводит свою базу IDBFS, узнаём путь user:// в ней;
//   2. до старта движка кладём в базу сейв героя в шахте (онбординг пройден) → «нажмите» → игра;
//      герой висит над шахтой — жмём «вниз», он падает на дно, и СРАЗУ закрываем — без ожидания автосейва (раз в 60 с):
//        context    — закрыть контекст (браузер целиком, без единого события страницы), по умолчанию:
//                     место переживает это, только если уже записано («встал на новом месте», SaveHooks);
//        tab        — закрыть вкладку (pagehide), потом контекст;
//        background — увести вкладку в фон (visibilitychange → hidden), через 0.3 с убить браузер:
//                     так телефон выгружает свёрнутый браузер;
//   3. снова открываем: что лежит в базе (сейв при закрытии), и где герой после загрузки — его место из
//      следующей записи (скрываем страницу → игра сохраняется).
// Код выхода 0 — герой после перезапуска на той же глубине, что при закрытии, и она глубже исходной.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const net = require('net');
const { spawn } = require('child_process');
let chromium;
try { ({ chromium } = require('playwright')); } catch (e) { ({ chromium } = require('/opt/node-tools/node_modules/playwright')); }

const seedDir = process.argv[2];
const outDir = process.argv[3] || path.join(os.tmpdir(), 'savepos_shots');
const closeMode = process.argv.includes('--close') ? process.argv[process.argv.indexOf('--close') + 1] : 'context';
const webDir = path.resolve(__dirname, '..', 'build', 'web');
fs.mkdirSync(outDir, { recursive: true });
const GL = ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl'];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failures = 0;
function check(name, ok, extra) {
	console.log((ok ? '[OK] ' : '[FAIL] ') + name + (extra ? '  (' + extra + ')' : ''));
	if (!ok) { failures++; }
}
function freePort() {
	return new Promise((resolve) => { const s = net.createServer(); s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => resolve(p)); }); });
}

// --- IndexedDB движка (IDBFS: база '/userfs', хранилище FILE_DATA, ключ — полный путь) ---
const idbKeys = (page) => page.evaluate(() => new Promise((res) => {
	const r = indexedDB.open('/userfs');
	r.onupgradeneeded = (e) => e.target.transaction.abort();
	r.onerror = () => res([]);
	r.onsuccess = () => { const db = r.result; const q = db.transaction(['FILE_DATA']).objectStore('FILE_DATA').getAllKeys(); q.onsuccess = () => { db.close(); res(q.result); }; };
}));
const idbRead = (page, key) => page.evaluate((k) => new Promise((res) => {
	const r = indexedDB.open('/userfs');
	r.onsuccess = () => { const db = r.result; const q = db.transaction(['FILE_DATA']).objectStore('FILE_DATA').get(k); q.onsuccess = () => { db.close(); const v = q.result; res(v && v.contents ? new TextDecoder().decode(v.contents) : null); }; };
	r.onerror = () => res(null);
}), key);
const idbWrite = (page, files) => page.evaluate((list) => new Promise((res, rej) => {
	const r = indexedDB.open('/userfs');
	r.onsuccess = () => {
		const db = r.result; const tx = db.transaction(['FILE_DATA'], 'readwrite'); const st = tx.objectStore('FILE_DATA'); const now = new Date();
		for (const f of list) { st.put({ timestamp: now, mode: 33206, contents: new TextEncoder().encode(f.text) }, f.key); }
		tx.oncomplete = () => { db.close(); res(true); };
		tx.onerror = () => rej(tx.error);
	};
	r.onerror = () => rej(r.error);
}), files);

async function open(ctx) {
	const page = ctx.pages()[0] || await ctx.newPage();
	page.on('console', (m) => { const t = m.text(); if (/SCRIPT ERROR|Parse Error/.test(t)) { console.log('  консоль: ' + t.slice(0, 200)); } });
	return page;
}
const waitPhase = (page, want, ms) => page.waitForFunction((w) => document.documentElement.getAttribute('data-phase') === w, want, { timeout: ms || 120000 });
async function start(page) {
	await page.click('#splash');
	await waitPhase(page, 'running', 90000);
	await page.waitForFunction(() => getComputedStyle(document.getElementById('splash')).display === 'none', null, { timeout: 30000 });
}
// Каждая запись save_now (уход со страницы, «встал на новом месте») оставляет отметку в localStorage
// (живёт в профиле): где был герой. Автосейв (раз в 60 с) идёт мимо persistFile и отметки не ставит.
const markLeaves = (page) => page.evaluate(() => {
	const sh = window.RaskopkiShell; const orig = sh.persistFile;
	sh.persistFile = function (p, text) {
		try { if (/save\.json$/.test(p)) { const d = JSON.parse(text); localStorage.setItem('savepos_last', JSON.stringify({ spot: (d.ext || {}).hero_spot || null, at: Date.now() })); } } catch (e) {}
		return orig.call(sh, p, text);
	};
});
const spotOf = (text) => { try { return (JSON.parse(text).ext || {}).hero_spot || null; } catch (e) { return null; } };

(async () => {
	if (!seedDir || !fs.existsSync(path.join(seedDir, 'save.json'))) { console.error('нет seed: ' + seedDir); process.exit(2); }
	const seedSave = fs.readFileSync(path.join(seedDir, 'save.json'), 'utf8');
	const seedStory = fs.readFileSync(path.join(seedDir, 'story.json'), 'utf8');
	const seedSpot = spotOf(seedSave);
	const port = await freePort();
	const server = spawn('python3', ['-m', 'http.server', String(port), '--bind', '127.0.0.1', '--directory', webDir], { stdio: 'ignore' });
	await sleep(800);
	const url = `http://127.0.0.1:${port}/index.html`;
	const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'savepos_profile_'));
	const launch = () => chromium.launchPersistentContext(profile, { args: GL, viewport: { width: 448, height: 960 }, deviceScaleFactor: 1 });
	try {
		// 1. Первый заход: движок заводит базу; находим каталог user:// по story.json.
		let ctx = await launch();
		let page = await open(ctx);
		await page.goto(url);
		await waitPhase(page, 'ready');
		await start(page);
		await sleep(6000);
		const keys = await idbKeys(page);
		const storyKey = keys.find((k) => /\/story\.json$/.test(k));
		check('движок завёл базу IDBFS и положил туда сюжет', !!storyKey, keys.slice(0, 6).join(', '));
		await ctx.close();
		if (!storyKey) { throw new Error('нет каталога user:// в IndexedDB'); }
		const userDir = storyKey.replace(/\/story\.json$/, '');
		console.log('user:// в браузере: ' + userDir);

		// 2. Сейв героя в шахте → игра → копает вниз → контекст закрыт сразу. Кладём сейв со страницы того же
		// адреса, но без движка: движок читает базу в init(), ещё до «нажмите», и затёр бы подложенное своим.
		ctx = await launch();
		page = await open(ctx);
		await page.goto(url.replace('index.html', 'version.json'));
		await idbWrite(page, [{ key: userDir + '/save.json', text: seedSave }, { key: userDir + '/story.json', text: seedStory }]);
		await page.goto(url);
		await waitPhase(page, 'ready');
		await start(page);
		await markLeaves(page);
		const t0 = Date.now();
		await sleep(3000);
		await page.screenshot({ path: path.join(outDir, '1_loaded_seed.png') });
		await page.mouse.click(385, 228);   // окно дня (ежедневная награда) — крестик
		await sleep(800);
		await page.screenshot({ path: path.join(outDir, '1b_popup_closed.png') });
		await page.mouse.move(224, 480);
		await page.locator('#canvas').focus().catch(() => {});
		// герой висит над шахтой: «вниз» снимает висение — падает на дно (программный рендер медленный: ждём)
		await page.keyboard.down('s');
		await sleep(600);
		await page.keyboard.up('s');
		await sleep(9000);   // падение ~4 с при 5–8 кадрах/с программного рендера и секунда простоя на дне
		await page.screenshot({ path: path.join(outDir, '2_dug_down.png') });
		console.log(`от загрузки до закрытия ${((Date.now() - t0) / 1000).toFixed(1)} с — автосейв (раз в 60 с) не успел; закрытие: ${closeMode}`);
		if (closeMode === 'tab') {
			await page.close({ runBeforeUnload: true });
			await sleep(500);   // браузер после закрытия вкладки живёт дальше; мгновенное убийство — режим context
		} else if (closeMode === 'background') {
			const other = await ctx.newPage();
			await other.bringToFront();
			await page.evaluate(() => {   // headless не прячет фоновую вкладку сам — объявляем это, как браузер телефона
				Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' });
				document.dispatchEvent(new Event('visibilitychange'));
			});
			await sleep(300);
		}
		await ctx.close();   // сразу: никаких ожиданий записи

		// 3. Снова открыли.
		ctx = await launch();
		page = await open(ctx);
		await page.goto(url);
		await waitPhase(page, 'ready');
		const atClose = spotOf(await idbRead(page, userDir + '/save.json'));
		const mark = await page.evaluate(() => localStorage.getItem('savepos_last'));
		console.log('сейв в базе после закрытия: ' + JSON.stringify(atClose) + ', отметка save_now: ' + mark + ', исходно: ' + JSON.stringify(seedSpot));
		check('запись save_now (уход со страницы или «встал на новом месте») дошла до базы — отметка есть', !!mark);
		check('в базе после закрытия — место глубже исходного (записан спуск, не автосейв)',
			!!atClose && !!seedSpot && atClose.y > seedSpot.y, JSON.stringify(atClose));
		await start(page);
		await markLeaves(page);
		await sleep(3000);
		await page.mouse.click(385, 228);   // окно дня — крестик
		await sleep(800);
		await page.screenshot({ path: path.join(outDir, '3_reopened.png') });
		// где герой после загрузки: просим игру записаться (как при уходе со страницы) и читаем место
		await page.evaluate(() => {
			Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' });
			document.dispatchEvent(new Event('visibilitychange'));
		});
		await sleep(800);
		const after = JSON.parse(await page.evaluate(() => localStorage.getItem('savepos_last')) || '{}').spot;
		console.log('место после перезапуска: ' + JSON.stringify(after));
		check('после перезапуска герой не дома, а там же: та же клетка, что при закрытии',
			!!after && !!atClose && after.x === atClose.x && after.y === atClose.y, JSON.stringify(after));
		await ctx.close();
	} catch (e) {
		check('прогон дошёл до конца', false, String(e && e.message || e).slice(0, 300));
	} finally {
		server.kill();
	}
	console.log(`кадры: ${outDir}`);
	console.log(`=== Итог: ${failures} провалов ===`);
	process.exit(failures ? 1 : 0);
})();
