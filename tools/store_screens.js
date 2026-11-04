#!/usr/bin/env node
// Скриншоты для стора из веб-сборки (Playwright, headless Chromium).
//
//   env -u XDG_DATA_HOME tools/build_web.sh        # сначала собрать build/web
//   node tools/store_screens.js                      # все кадры в оба размера → docs/store/
//   node tools/store_screens.js --out /tmp/store --sizes 1290x2796 --shots home,dig
//
// Как устроено: поднимает python3 -m http.server на build/web, открывает страницу как телефон
// (CSS-вьюпорт 430x932 при DPR 3 = 1290x2796 физических, iPhone 6.7"; 414x736 при DPR 3 = 1242x2208,
// iPhone 5.5") с адресом ?shot=home, ждёт «нажмите, чтобы играть», стартует движок, затем для каждого
// кадра просит игру поставить сцену (RaskopkiQA.shot(id), scripts/qa/store_shots.gd) и ждёт
// RaskopkiShell.shotReady. Снимок — страница целиком: в режиме телефона игра занимает весь экран.
// Сейв игры при постановке не пишется (SaveSystem.readonly) и живёт только в этом профиле браузера.
//
// Результат: docs/store/<ширина>x<высота>_<кадр>.png. Рендер — SwiftShader (программный), поэтому
// кадры по цвету точны, а по скорости — нет; на время анимаций даётся запас.
'use strict';

const fs = require('fs');
const net = require('net');
const path = require('path');
const { spawn } = require('child_process');

function loadPlaywright() {
	const tries = [process.env.PW_MODULE, 'playwright', '/opt/node-tools/node_modules/playwright'];
	for (const t of tries) {
		if (!t) continue;
		try { return require(t); } catch (e) { /* пробуем дальше */ }
	}
	console.error('store_screens: нет модуля playwright (ищем PW_MODULE, playwright, /opt/node-tools)');
	process.exit(2);
}

// Размеры стора: физические пиксели = CSS × DPR. Телефонная раскладка оболочки включается,
// когда меньшая сторона CSS-вьюпорта ≤ 640 и указатель «грубый» (isMobile).
const SIZES = {
	'1290x2796': { css: [430, 932], dpr: 3 },   // iPhone 6.7" (App Store, обязательный размер)
	'1242x2208': { css: [414, 736], dpr: 3 },   // iPhone 5.5"
};
const SHOTS = ['home', 'dig', 'shop', 'museum', 'combat'];

function parseArgs(argv) {
	const o = {
		dir: path.resolve(__dirname, '..', 'build', 'web'),
		out: path.resolve(__dirname, '..', 'docs', 'store'),
		sizes: Object.keys(SIZES),
		shots: SHOTS,
		timeout: 180,
		settle: 1400,   // мс после готовности кадра: окна всплывают, копка замахивается
	};
	for (let i = 2; i < argv.length; i++) {
		const a = argv[i];
		const next = () => argv[++i];
		if (a === '--dir') o.dir = path.resolve(next());
		else if (a === '--out') o.out = path.resolve(next());
		else if (a === '--sizes') o.sizes = next().split(',');
		else if (a === '--shots') o.shots = next().split(',');
		else if (a === '--timeout') o.timeout = Number(next());
		else if (a === '--settle') o.settle = Number(next());
		else { console.error('store_screens: неизвестный аргумент ' + a); process.exit(2); }
	}
	for (const s of o.sizes) if (!SIZES[s]) { console.error('store_screens: неизвестный размер ' + s); process.exit(2); }
	for (const s of o.shots) if (!SHOTS.includes(s)) { console.error('store_screens: неизвестный кадр ' + s); process.exit(2); }
	return o;
}

function freePort() {
	return new Promise((resolve, reject) => {
		const s = net.createServer();
		s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => resolve(p)); });
		s.on('error', reject);
	});
}

async function waitHttp(url, ms) {
	const t0 = Date.now();
	while (Date.now() - t0 < ms) {
		try { const r = await fetch(url); if (r.ok) return true; } catch (e) { /* ещё не поднялся */ }
		await new Promise((r) => setTimeout(r, 150));
	}
	return false;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
	const opt = parseArgs(process.argv);
	const { chromium } = loadPlaywright();
	fs.mkdirSync(opt.out, { recursive: true });
	if (!fs.existsSync(path.join(opt.dir, 'index.html'))) {
		console.error(`store_screens: нет ${opt.dir}/index.html — сначала env -u XDG_DATA_HOME tools/build_web.sh`);
		process.exit(2);
	}
	const port = await freePort();
	const server = spawn('python3', ['-m', 'http.server', String(port), '--bind', '127.0.0.1', '--directory', opt.dir],
		{ stdio: 'ignore' });
	const base = `http://127.0.0.1:${port}/`;
	let browser = null;
	let failures = 0;
	const made = [];
	try {
		if (!await waitHttp(base + 'index.html', 8000)) throw new Error('http-сервер не поднялся');
		browser = await chromium.launch({
			args: [
				'--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
				'--ignore-gpu-blocklist', '--enable-webgl', '--autoplay-policy=no-user-gesture-required',
			],
		});
		for (const sizeKey of opt.sizes) {
			const size = SIZES[sizeKey];
			const ctx = await browser.newContext({
				viewport: { width: size.css[0], height: size.css[1] },
				deviceScaleFactor: size.dpr,
				isMobile: true,
				hasTouch: true,
			});
			const page = await ctx.newPage();
			const errors = [];
			page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
			page.on('console', (m) => {
				const t = m.text();
				if (/SCRIPT ERROR|Parse Error/.test(t)) errors.push(t);
			});

			console.log(`--- ${sizeKey} (css ${size.css.join('x')} @${size.dpr}x) ---`);
			await page.goto(base + 'index.html?shot=' + opt.shots[0], { waitUntil: 'domcontentloaded' });
			// Экран загрузки оболочки → «нажмите, чтобы играть» → старт движка.
			await page.waitForFunction(() => window.RaskopkiShell && window.RaskopkiShell.phase === 'ready',
				null, { timeout: opt.timeout * 1000 });
			await page.locator('#splash').click({ force: true });
			await page.waitForFunction(() => window.RaskopkiShell && window.RaskopkiShell.phase === 'running',
				null, { timeout: opt.timeout * 1000 });
			const phone = await page.evaluate(() => document.getElementById('frame').classList.contains('col') === false);
			if (!phone) console.warn('store_screens: оболочка не в телефонной раскладке — кадр будет колонкой');

			let first = true;
			for (const id of opt.shots) {
				const t0 = Date.now();
				if (!first) {
					await page.evaluate((sid) => { window.RaskopkiShell.shotReady = ''; window.RaskopkiQA.shot(sid); }, id);
				}
				first = false;
				try {
					await page.waitForFunction((sid) => window.RaskopkiShell && window.RaskopkiShell.shotReady === sid,
						id, { timeout: opt.timeout * 1000 });
				} catch (e) {
					console.log(`[FAIL] ${sizeKey} ${id}: игра не сообщила о готовности кадра`);
					failures++;
					continue;
				}
				await sleep(opt.settle);
				const file = path.join(opt.out, `${sizeKey}_${id}.png`);
				await page.screenshot({ path: file, fullPage: false });
				made.push(file);
				console.log(`[OK] ${sizeKey} ${id}  ${((Date.now() - t0) / 1000).toFixed(1)} с → ${path.relative(process.cwd(), file)}`);
			}
			if (errors.length) {
				console.log(`[FAIL] ${sizeKey}: ошибки скриптов в консоли: ` + errors.slice(0, 3).join(' | ').slice(0, 400));
				failures++;
			}
			await ctx.close();
		}
	} catch (e) {
		console.error('store_screens: ' + (e && e.message || e));
		failures++;
	} finally {
		if (browser) await browser.close().catch(() => {});
		server.kill();
	}
	console.log(`=== Итог: ${made.length} кадров, ${failures} провалов ===`);
	process.exit(failures ? 1 : 0);
})();
