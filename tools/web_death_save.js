#!/usr/bin/env node
// Веб-проверка «смерть доезжает до IndexedDB» (владелец, 27.10: «если после смерти быстро
// закрыть окно игры, то он появляется без штрафов на поверхности с последним лутом до спуска»).
//
//   tools/build_web.sh                                  # сначала собрать build/web
//   node tools/web_death_save.js                        # прогон, код возврата 0 — смерть в хранилище
//   node tools/web_death_save.js --dir сборка --out каталог --close tab|browser --close-after 0 --json отчёт.json
//
// Что делает (настоящая веб-сборка в Chromium, хранилище — профиль на диске):
//  1. Кладёт в IndexedDB страницы (там движок держит user://) сейв «последний автосейв перед
//     смертью»: 3000 монет, рюкзак с лутом, HP 2 и пустая сытость (голод убьёт за ~2 с),
//     сюжет и достижения пройдены (иначе награды достижений путают счёт монет).
//  2. Запускает игру, ждёт смерти: сборка с правкой сообщает о записи строкой консоли
//     «[raskopki] save: death» (SaveSystem.save_now); старая молчит — ждём 12 с и снимаем кадр.
//  3. Сразу (или через --close-after мс) закрывает вкладку, как игрок; --close browser — убивает
//     весь браузер (жёстче, чем бывает у игрока: хранилище браузера гибнет вместе со страницей).
//  4. Открывает игру заново (новая вкладка или тот же профиль) и читает save.json из IndexedDB —
//     ровно то, что поднимет игра; затем запускает игру и снимает кадр после загрузки.
// Итог: монеты 3000 → 2850 (плата 5%), рюкзак пуст — смерть записана; 3000 и лут — баг.
'use strict';

const fs = require('fs');
const os = require('os');
const net = require('net');
const path = require('path');
const { spawn } = require('child_process');

function loadPlaywright() {
	for (const t of [process.env.PW_MODULE, 'playwright', '/opt/node-tools/node_modules/playwright']) {
		if (!t) continue;
		try { return require(t); } catch (e) { /* пробуем дальше */ }
	}
	console.error('web_death_save: нет модуля playwright (ищем PW_MODULE, playwright, /opt/node-tools)');
	process.exit(2);
}

const ROOT = path.resolve(__dirname, '..');
const opt = { dir: path.join(ROOT, 'build', 'web'), out: path.join(ROOT, 'build', 'web_death_save'), closeAfter: 0, close: 'tab', json: '' };
for (let i = 2; i < process.argv.length; i++) {
	const a = process.argv[i];
	const next = () => process.argv[++i];
	if (a === '--dir') opt.dir = path.resolve(next());
	else if (a === '--out') opt.out = path.resolve(next());
	else if (a === '--close-after') opt.closeAfter = Number(next());
	else if (a === '--close') opt.close = next();   // tab — закрыть вкладку (браузер жив); browser — убить браузер целиком
	else if (a === '--json') opt.json = path.resolve(next());
	else { console.error('web_death_save: неизвестный аргумент ' + a); process.exit(2); }
}

const GL_ARGS = ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
	'--enable-webgl', '--autoplay-policy=no-user-gesture-required'];
const USER_DIR = '/userfs/godot/app_userdata/Раскопки на каникулах';   // user:// веб-сборки (имя проекта)
const COINS = 3000;
const FEE = Math.min(5000, Math.max(50, Math.floor(COINS * 0.05)));
const LOOT = { silver: 4, iron_ore: 7, coal: 12 };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function fixture() {
	const story = JSON.parse(fs.readFileSync(path.join(ROOT, 'data', 'story.json'), 'utf8'));
	const flags = {};
	for (const f of ['intro_seen', 'bars_introduced', 'gold_taken', 'foundation_broken', 'gold_sold', 'food_ordered']) flags[f] = true;
	for (const s of story.scenes) for (const e of (s.effects || [])) if (e.do === 'flag') flags[e.id] = true;
	const ach = {};
	for (const a of JSON.parse(fs.readFileSync(path.join(ROOT, 'data', 'achievements.json'), 'utf8')).achievements) ach[a.id] = 0;
	const save = {
		version: 2,
		survival: { hp: 2.0, stamina: 60, hunger: 0, is_alive: true },
		progression: { xp: 400, level: 4, skill_points_available: 0, skill_stages: {} },
		currency: { coins: COINS, dollars: 7 },
		inventory: LOOT,
		tool: { current_tool: 'shovel', rig_parked_x: -1, rig_parked_y: -1 },
		depth: { max_depth_reached: 120 },
		house: { tutorial_stage: 2, hatch_built: true, dopings_shop_unlocked: true },
		economy: { owned_tools: ['shovel'], owned_gear: ['backpack'], current_gear: 'backpack', workshop_visited: true },
		world_seed: 20261027,
		ext: { meta: { unlocked: true, ach } },
	};
	return {
		'save.json': JSON.stringify(save),
		'story.json': JSON.stringify({ version: 1, flags, seen: story.scenes.map((s) => s.id), queue: [] }),
	};
}

// Страница того же источника без движка: из неё пишем и читаем IndexedDB.
const BLANK = '__idb.html';

// Формат emscripten IDBFS: база = точка монтирования, хранилище FILE_DATA с индексом timestamp,
// каталоги {timestamp, mode}, файлы {timestamp, mode, contents}.
async function seed(page, files) {
	return page.evaluate(async ({ dir, files }) => {
		const db = await new Promise((res, rej) => {
			const r = indexedDB.open('/userfs', 21);
			r.onupgradeneeded = () => {
				const st = r.result.objectStoreNames.contains('FILE_DATA') ? r.transaction.objectStore('FILE_DATA')
					: r.result.createObjectStore('FILE_DATA');
				if (!st.indexNames.contains('timestamp')) st.createIndex('timestamp', 'timestamp', { unique: false });
			};
			r.onsuccess = () => res(r.result);
			r.onerror = () => rej(r.error);
		});
		const tx = db.transaction('FILE_DATA', 'readwrite');
		const st = tx.objectStore('FILE_DATA');
		const now = new Date();
		const parts = dir.split('/').filter(Boolean);
		for (let i = 2; i <= parts.length; i++) st.put({ timestamp: now, mode: 16893 }, '/' + parts.slice(0, i).join('/'));
		for (const [name, text] of Object.entries(files)) {
			const bytes = new TextEncoder().encode(text);
			st.put({ timestamp: now, mode: 33206, contents: new Int8Array(bytes.buffer) }, dir + '/' + name);
		}
		await new Promise((res, rej) => { tx.oncomplete = res; tx.onerror = () => rej(tx.error); });
		db.close();
		return true;
	}, { dir: USER_DIR, files });
}

async function readSave(page) {
	return page.evaluate(async (dir) => {
		const db = await new Promise((res, rej) => { const r = indexedDB.open('/userfs'); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
		if (!db.objectStoreNames.contains('FILE_DATA')) { db.close(); return null; }
		const st = db.transaction('FILE_DATA').objectStore('FILE_DATA');
		const v = await new Promise((res) => { const r = st.get(dir + '/save.json'); r.onsuccess = () => res(r.result); r.onerror = () => res(null); });
		db.close();
		if (!v || !v.contents) return null;
		return JSON.parse(new TextDecoder().decode(new Uint8Array(v.contents.buffer, v.contents.byteOffset, v.contents.byteLength)));
	}, USER_DIR);
}

// Ключи базы user:// — проверка, что штатный перенос движка (кэш шейдеров и прочее) не сломан.
async function listKeys(page) {
	return page.evaluate(async () => {
		const db = await new Promise((res, rej) => { const r = indexedDB.open('/userfs'); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
		if (!db.objectStoreNames.contains('FILE_DATA')) { db.close(); return []; }
		const keys = await new Promise((res) => { const r = db.transaction('FILE_DATA').objectStore('FILE_DATA').getAllKeys(); r.onsuccess = () => res(r.result); });
		db.close();
		return keys;
	});
}

async function startGame(page, base) {
	await page.goto(base + 'index.html', { waitUntil: 'domcontentloaded' });
	await page.waitForFunction(() => document.documentElement.getAttribute('data-phase') === 'ready', null, { timeout: 180000 });
	await page.click('#splash');
	await page.waitForFunction(() => document.documentElement.getAttribute('data-phase') === 'running', null, { timeout: 180000 });
}

function freePort() {
	return new Promise((resolve, reject) => {
		const s = net.createServer();
		s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => resolve(p)); });
		s.on('error', reject);
	});
}

(async () => {
	const { chromium } = loadPlaywright();
	if (!fs.existsSync(path.join(opt.dir, 'index.html'))) {
		console.error(`web_death_save: нет ${opt.dir}/index.html — сначала tools/build_web.sh`);
		process.exit(2);
	}
	fs.mkdirSync(opt.out, { recursive: true });
	const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'raskopki-death-'));
	const port = await freePort();
	const server = spawn('python3', ['-m', 'http.server', String(port), '--bind', '127.0.0.1', '--directory', opt.dir], { stdio: 'ignore' });
	const base = `http://127.0.0.1:${port}/`;
	const report = { dir: opt.dir, close: opt.close, closeAfterMs: opt.closeAfter, console: [] };
	const launch = async () => {
		const ctx = await chromium.launchPersistentContext(profile, { viewport: { width: 448, height: 960 }, args: GL_ARGS });
		await ctx.route(base + BLANK, (r) => r.fulfill({ status: 200, contentType: 'text/html', body: '<!doctype html><title>idb</title>' }));
		const page = ctx.pages()[0] || await ctx.newPage();
		page.on('console', (m) => report.console.push(`[${m.type()}] ${m.text()}`));
		return { ctx, page };
	};
	let code = 2;
	try {
		for (let i = 0; i < 50; i++) { try { if ((await fetch(base + 'index.html')).ok) break; } catch (e) { /* ждём сервер */ } await sleep(150); }

		// --- 1. сейв перед смертью ---
		let { ctx, page } = await launch();
		await page.goto(base + BLANK);
		await seed(page, fixture());
		const seeded = await readSave(page);
		console.log(`[..] в хранилище до игры: монет ${seeded.currency.coins}, рюкзак ${JSON.stringify(seeded.inventory)}`);

		// --- 2. игра и смерть ---
		// Сборка с правкой пишет в консоль «[raskopki] save: death» в той же задаче JS, где кладёт
		// сейв в IndexedDB; событие консоли приходит без ожидания главного потока страницы (опрос через
		// page.evaluate ждал бы его секундами — программный WebGL), и браузер закрывается следом.
		let logged = null;
		const deathLog = new Promise((resolve) => page.on('console', (m) => {
			const t = m.text();
			if (!logged && /^\[raskopki\] save: (death|respawn)/.test(t)) { logged = { text: t, at: Date.now() }; resolve(); }
		}));
		await startGame(page, base);
		const t0 = Date.now();
		await Promise.race([deathLog, sleep(12000)]);
		if (logged) {
			report.deathSavedMs = logged.at - t0;
			console.log(`[..] «${logged.text}» через ${(report.deathSavedMs / 1000).toFixed(1)} с после старта`);
		} else {
			console.log('[..] сборка не сообщает о записи (старая) — смерть по расчёту: HP 2, голод 1 HP/с; ждали 12 с');
		}
		// без page.evaluate: он ждёт главный поток страницы и растянул бы задержку на сотни мс
		if (opt.closeAfter > 0) await sleep(opt.closeAfter);
		// Кадр перед закрытием — доказательство смерти (окно смерти); снимок тянет закрытие на доли
		// секунды, поэтому при «закрыть сразу» после записи его не снимаем.
		if (!logged || opt.closeAfter >= 1000) await page.screenshot({ path: path.join(opt.out, 'before_close.png') });
		const what = opt.close === 'browser' ? 'браузер убит' : 'вкладка закрыта';
		if (opt.close === 'browser') await ctx.close();
		else await page.close();
		console.log(`[..] ${what} ${opt.closeAfter > 0 ? `через ${opt.closeAfter} мс` : 'сразу'} после ${logged ? 'записи смерти' : 'расчётной смерти'}`);

		// --- 3. тот же профиль заново ---
		if (opt.close === 'browser') ({ ctx, page } = await launch());
		else { page = await ctx.newPage(); page.on('console', (m) => report.console.push(`[${m.type()}] ${m.text()}`)); }
		await page.goto(base + BLANK);
		const after = await readSave(page);
		const coins = after ? after.currency.coins : -1;
		const inv = after ? after.inventory : null;
		const alive = after ? after.survival.is_alive : null;
		report.after = after ? { coins, inventory: inv, survival: after.survival, saved_at_utc: after.saved_at_utc } : null;
		console.log(`[..] в хранилище после перезапуска: монет ${coins}, рюкзак ${JSON.stringify(inv)}, жив ${alive}`);
		const keys = await listKeys(page);
		report.engineFiles = keys.filter((k) => /shader_cache\//.test(k)).length;
		console.log(`[..] записей движка (кэш шейдеров) в хранилище: ${report.engineFiles} — штатный перенос жив`);
		await startGame(page, base);
		await sleep(1200);
		// звонок бабушки (сюжет после старта) прячет HUD — пропускаем кнопкой ⏭ в правом верхнем углу
		for (let i = 0; i < 2; i++) { await page.mouse.click(448 - 45, 27); await sleep(400); }
		await page.screenshot({ path: path.join(opt.out, 'after_reopen.png') });
		await ctx.close();

		const lootGone = inv && Object.keys(inv).length === 0;
		const fined = coins === COINS - FEE;
		const fixed = lootGone && fined && alive === true;
		const bug = coins === COINS && inv && Object.keys(inv).length > 0;
		console.log(fixed ? `[OK] смерть записана: плата ${FEE} (${COINS} → ${coins}), рюкзак пуст, герой воскрес`
			: bug ? `[БАГ] смерти в хранилище нет: ${COINS} монет и лут до смерти — повторный вход отменил смерть`
				: '[??] неожиданное состояние сейва (см. --json)');
		report.verdict = fixed ? 'fixed' : bug ? 'bug' : 'unexpected';
		code = fixed ? 0 : 1;
	} catch (e) {
		console.error('web_death_save: ' + (e && e.stack || e));
		report.error = String(e && e.message || e);
	} finally {
		server.kill();
		fs.rmSync(profile, { recursive: true, force: true });
	}
	if (opt.json) fs.writeFileSync(opt.json, JSON.stringify(report, null, 1));
	fs.writeFileSync(path.join(opt.out, 'console.log'), report.console.join('\n'));
	console.log(`снимок: ${path.join(opt.out, 'after_reopen.png')}`);
	process.exit(code);
})();
