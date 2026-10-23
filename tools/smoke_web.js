#!/usr/bin/env node
// Дымовой тест веб-сборки в headless Chromium (Playwright).
//
//   tools/build_web.sh                       # сначала собрать build/web
//   node tools/smoke_web.js                  # прогон, отчёт в stdout, код возврата 0/1
//   node tools/smoke_web.js --out /tmp/smoke --viewport 448x960 [--no-fail] [--json отчёт.json]
//
// Что делает: поднимает `python3 -m http.server` на build/web, открывает
// страницу в Chromium с флагами программного WebGL, ждёт старта движка,
// пропускает интро, жмёт WASD (ходьба, копка вниз), снимает скриншоты и
// собирает: ошибки консоли, упавшие запросы, ответы >= 400, время загрузки,
// грубый FPS (счётчик requestAnimationFrame в странице). Результат — отчёт
// и код возврата: 0 — зелёное, 1 — провал проверки, 2 — не удалось запустить.
//
// FPS здесь — по SwiftShader (программный рендер), на реальном телефоне будет
// иначе: цифра нужна для сравнения «до/после», а не как абсолют.
//
// Про изоляцию: пресет Web собран без потоков (thread_support=false), поэтому
// заголовки COOP/COEP не нужны; тест проверяет, что игра стартует и без них.
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
	console.error('smoke_web: нет модуля playwright (ищем PW_MODULE, playwright, /opt/node-tools)');
	process.exit(2);
}

function parseArgs(argv) {
	const o = {
		dir: path.resolve(__dirname, '..', 'build', 'web'),
		out: path.resolve(__dirname, '..', 'build', 'smoke'),
		viewport: '448x960', // ровно ×2 от проектных 224×480: раскладка детерминирована
		timeout: 120,
		port: 0,
		keepGoing: false,
		json: '',
	};
	for (let i = 2; i < argv.length; i++) {
		const a = argv[i];
		const next = () => argv[++i];
		if (a === '--dir') o.dir = path.resolve(next());
		else if (a === '--out') o.out = path.resolve(next());
		else if (a === '--viewport') o.viewport = next();
		else if (a === '--timeout') o.timeout = Number(next());
		else if (a === '--port') o.port = Number(next());
		else if (a === '--json') o.json = path.resolve(next());
		else if (a === '--no-fail') o.keepGoing = true; // всегда код 0 (для сбора отчёта)
		else { console.error('smoke_web: неизвестный аргумент ' + a); process.exit(2); }
	}
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
		try {
			const r = await fetch(url);
			if (r.ok) return true;
		} catch (e) { /* сервер ещё не поднялся */ }
		await new Promise((r) => setTimeout(r, 150));
	}
	return false;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Шум, который не про нашу игру: драйвер программного GL и политика автозапуска звука.
const BENIGN = [
	/GL Driver Message/i,
	/GPU stall due to ReadPixels/i,
	/AudioContext was not allowed to start/i,
	/Automatic fallback to software WebGL/i,
	/\[\.WebGL-/i,
	/favicon/i,
];
const isBenign = (t) => BENIGN.some((re) => re.test(t));

(async () => {
	const opt = parseArgs(process.argv);
	const { chromium } = loadPlaywright();
	const [vw, vh] = opt.viewport.split('x').map(Number);
	fs.mkdirSync(opt.out, { recursive: true });
	if (!fs.existsSync(path.join(opt.dir, 'index.html'))) {
		console.error(`smoke_web: нет ${opt.dir}/index.html — сначала tools/build_web.sh`);
		process.exit(2);
	}

	const port = opt.port || await freePort();
	const server = spawn('python3', ['-m', 'http.server', String(port), '--bind', '127.0.0.1', '--directory', opt.dir],
		{ stdio: 'ignore' });
	const base = `http://127.0.0.1:${port}/`;
	const checks = [];
	const check = (name, ok, detail = '') => {
		checks.push({ name, ok, detail });
		console.log(`[${ok ? 'OK' : 'FAIL'}] ${name}${detail ? '  ' + detail : ''}`);
	};
	let browser = null;
	const report = { base, viewport: opt.viewport, console: [], failed: [], bad: [], timings: {}, fps: {} };

	try {
		if (!await waitHttp(base + 'index.html', 8000)) {
			console.error('smoke_web: http-сервер не поднялся');
			process.exit(2);
		}
		browser = await chromium.launch({
			args: [
				'--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
				'--ignore-gpu-blocklist', '--enable-webgl', '--autoplay-policy=no-user-gesture-required',
			],
		});
		const ctx = await browser.newContext({ viewport: { width: vw, height: vh }, deviceScaleFactor: 1 });
		const page = await ctx.newPage();

		const errors = [];
		const warnings = [];
		page.on('console', (m) => {
			const t = m.type();
			const text = m.text();
			report.console.push({ type: t, text });
			// Godot-web шлёт в console.error и ошибки, и push_warning, и хвосты «at: …».
			// Предупреждения движка и игры считаем отдельно: они не валят прогон.
			if (/^WARNING:/.test(text)) { warnings.push(text); return; }
			if (/^\s+at:/.test(text)) return;
			if ((t === 'error' || /SCRIPT ERROR|Parse Error/.test(text)) && !isBenign(text)) errors.push(text);
		});
		page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
		page.on('requestfailed', (r) => report.failed.push(`${r.url()} — ${r.failure() && r.failure().errorText}`));
		const requested = [];
		page.on('response', (r) => {
			requested.push({ url: r.url(), status: r.status(), type: r.headers()['content-type'] || '' });
			if (r.status() >= 400 && !/favicon/.test(r.url())) report.bad.push(`${r.status()} ${r.url()}`);
		});

		// --- загрузка ---
		const t0 = Date.now();
		await page.goto(base + 'index.html', { waitUntil: 'domcontentloaded' });
		report.timings.domReadyMs = Date.now() - t0;
		let started = true;
		try {
			await page.waitForSelector('#status', { state: 'detached', timeout: opt.timeout * 1000 });
		} catch (e) { started = false; }
		report.timings.engineStartMs = Date.now() - t0;
		const notice = await page.evaluate(() => {
			const n = document.getElementById('status-notice');
			return n && n.style.display === 'block' ? n.textContent : '';
		}).catch(() => '');
		check('движок стартовал (оверлей загрузки снят)', started && !notice,
			notice ? 'уведомление: ' + notice.trim().slice(0, 200) : `${(report.timings.engineStartMs / 1000).toFixed(1)} с`);
		if (!started) throw new Error('движок не стартовал');

		const wasmReq = requested.find((r) => /\.wasm/.test(r.url));
		const pckReq = requested.find((r) => /\.pck/.test(r.url));
		check('wasm отдаётся как application/wasm', !!wasmReq && /application\/wasm/.test(wasmReq.type), wasmReq ? wasmReq.type : 'нет запроса');
		check('wasm и pck запрошены с меткой сборки ?v= (сброс кэша)',
			!!wasmReq && !!pckReq && /[?&]v=/.test(wasmReq.url) && /[?&]v=/.test(pckReq.url));

		const canvas = page.locator('#canvas');
		await page.waitForSelector('#canvas');
		const shot = async (name) => {
			const f = path.join(opt.out, name + '.png');
			await page.screenshot({ path: f });
			return f;
		};
		// Хеш кадра: «картинка изменилась» без разбора PNG.
		const frameSig = async () => {
			const buf = await canvas.screenshot();
			let h = 2166136261;
			for (let i = 0; i < buf.length; i += 7) { h ^= buf[i]; h = Math.imul(h, 16777619) >>> 0; }
			return { sig: h, size: buf.length };
		};

		await sleep(2500);
		await shot('01_boot');
		const boot = await frameSig();
		check('канвас не пустой (кадр нетривиальный по размеру PNG)', boot.size > 4000, `${boot.size} байт`);

		// FPS в покое (интро идёт сценой, но управление у игрока ещё нет).
		const fpsOf = (ms) => page.evaluate((span) => new Promise((resolve) => {
			let n = 0; let worst = 0; let last = performance.now(); const start = last;
			function tick(now) {
				n++; worst = Math.max(worst, now - last); last = now;
				if (now - start < span) requestAnimationFrame(tick);
				else resolve({ fps: n / ((now - start) / 1000), worstFrameMs: worst });
			}
			requestAnimationFrame(tick);
		}), ms);
		report.fps.intro = await fpsOf(3000);

		// --- интро: пропускаем кнопкой «Пропустить» (правый верхний угол, 64×20 проектных) ---
		const scale = vw / 224;
		const skipX = (224 - 72 + 32) * scale;
		const skipY = (8 + 10) * scale;
		for (let i = 0; i < 4; i++) {
			await page.mouse.click(skipX, skipY);
			await sleep(700);
		}
		await sleep(1500);
		await shot('02_after_intro');
		const afterIntro = await frameSig();

		// --- ходьба и копка ---
		await page.mouse.move(vw / 2, vh / 2);
		await canvas.focus().catch(() => {});
		const before = await frameSig();
		await page.keyboard.down('d');
		await sleep(1200);
		report.fps.walk = await fpsOf(2000);
		await page.keyboard.up('d');
		await shot('03_walked');
		const walked = await frameSig();
		await page.keyboard.down('a');
		await sleep(1200);
		await page.keyboard.up('a');

		await page.keyboard.down('s');
		await sleep(4000);
		await shot('04_digging');
		report.fps.dig = await fpsOf(2000);
		await page.keyboard.up('s');
		await sleep(600);
		await shot('05_after_dig');
		const dug = await frameSig();

		check('после интро и ввода картинка меняется (игра отзывается на клавиши)',
			walked.sig !== before.sig || dug.sig !== walked.sig || dug.sig !== afterIntro.sig);

		// Клик по экрану (тап/удержание мышью — эмуляция касания в игре).
		await page.mouse.move(vw / 2, vh * 0.8);
		await page.mouse.down();
		await sleep(800);
		await page.mouse.up();
		await shot('06_after_click');

		// Страница не должна «умереть»: ещё один кадр и жив ли rAF.
		const alive = await fpsOf(1000);
		check('страница отзывается в конце прогона (rAF идёт)', alive.fps > 0.5, `${alive.fps.toFixed(1)} fps`);

		check('нет ошибок консоли', errors.length === 0, errors.length ? errors.slice(0, 5).join(' | ').slice(0, 600) : '');
		check('нет упавших запросов', report.failed.length === 0, report.failed.slice(0, 3).join(' | '));
		check('нет ответов >= 400', report.bad.length === 0, report.bad.slice(0, 3).join(' | '));
		report.errors = errors;
		report.warnings = warnings;
		report.requests = requested.length;
	} catch (e) {
		check('прогон дошёл до конца без исключения', false, String(e && e.message || e).slice(0, 300));
	} finally {
		if (browser) await browser.close().catch(() => {});
		server.kill();
	}

	const failed = checks.filter((c) => !c.ok);
	console.log('\n--- отчёт ---');
	console.log(`загрузка: DOM ${report.timings.domReadyMs ?? '?'} мс, движок ${report.timings.engineStartMs ?? '?'} мс`);
	for (const k of Object.keys(report.fps)) {
		const f = report.fps[k];
		console.log(`FPS (${k}): ${f.fps.toFixed(1)}, худший кадр ${f.worstFrameMs.toFixed(0)} мс  [SwiftShader, не телефон]`);
	}
	console.log(`сообщений консоли: ${report.console.length}, предупреждений игры: ${(report.warnings || []).length}, упавших запросов: ${report.failed.length}`);
	for (const w of (report.warnings || []).slice(0, 10)) console.log('  ' + w.slice(0, 160));
	console.log(`скриншоты: ${opt.out}`);
	console.log(`=== Итог: ${checks.length} проверок, ${failed.length} провалов ===`);
	report.checks = checks;
	if (opt.json) fs.writeFileSync(opt.json, JSON.stringify(report, null, 1));
	fs.writeFileSync(path.join(opt.out, 'console.log'),
		report.console.map((c) => `[${c.type}] ${c.text}`).join('\n'));
	process.exit(failed.length && !opt.keepGoing ? 1 : 0);
})();
