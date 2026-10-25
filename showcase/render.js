// 渲染：node render.js [--fps 60] [--workers 4] [--scale 2] [--from 0] [--to DURATION] [--out out/showcase.mp4]
// 逐帧调用 renderFrame(t) 截图，多进程分段编码后无损拼接
const { chromium } = require('playwright');
const { spawn, execFileSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const arg = (k, d) => { const i = process.argv.indexOf('--' + k); return i > 0 ? process.argv[i + 1] : d; };
const FPS = +arg('fps', 60), WORKERS = +arg('workers', 4), SCALE = +arg('scale', 2);
const OUT = path.resolve(arg('out', path.join(__dirname, 'out', 'showcase.mp4')));
const tmp = fs.mkdtempSync(path.join(require('os').tmpdir(), 'showcase-'));

async function worker(w, f0, f1) {
  const seg = path.join(tmp, `seg${w}.mp4`);
  const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
    '-vf', SCALE !== 1 ? 'scale=1920:1080:flags=lanczos' : 'null',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '14', '-pix_fmt', 'yuv420p', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709', '-r', String(FPS), seg],
  { stdio: ['pipe', 'inherit', 'inherit'] });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: SCALE });
  page.on('pageerror', e => console.error('pageerror', e.message));
  await page.goto('file://' + path.join(__dirname, 'index.html'));
  await page.evaluate(() => window.ready);
  const t0 = Date.now();
  for (let f = f0; f < f1; f++) {
    await page.evaluate(t => window.renderFrame(t), f / FPS);
    const buf = await page.screenshot({ type: 'jpeg', quality: 94 });
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
    if ((f - f0) % 120 === 0) console.log(`[w${w}] ${f - f0}/${f1 - f0}  ${((f - f0) / ((Date.now() - t0) / 1000 + 1e-9)).toFixed(1)} fps`);
  }
  await browser.close();
  ff.stdin.end();
  await new Promise((res, rej) => ff.on('close', c => (c ? rej(new Error('ffmpeg ' + c)) : res())));
  return seg;
}

(async () => {
  const DURATION = 43.8;
  const from = Math.round(+arg('from', 0) * FPS), to = Math.round(+arg('to', DURATION) * FPS);
  const n = to - from, per = Math.ceil(n / WORKERS);
  const segs = await Promise.all([...Array(WORKERS)].map((_, w) => worker(w, from + w * per, Math.min(to, from + (w + 1) * per))));
  const list = path.join(tmp, 'list.txt');
  fs.writeFileSync(list, segs.map(s => `file '${s}'`).join('\n'));
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', list, '-c', 'copy', '-movflags', '+faststart', OUT]);
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log('done ->', OUT);
})();
