// 安装器界面还原（坐标与截图 1160×950 一一对应，标题栏占 0–32px）
'use strict';

const ICONS = {
  gauge: '<path d="M4.5 17a7.5 7.5 0 1 1 15 0"/><path d="M12 14.5l3.2-3.6"/><circle cx="12" cy="15" r="1.2" fill="#fff" stroke="none"/>',
  sun: '<circle cx="12" cy="12" r="3.6"/><path d="M12 3v2.2M12 18.8V21M3 12h2.2M18.8 12H21M5.6 5.6l1.6 1.6M16.8 16.8l1.6 1.6M5.6 18.4l1.6-1.6M16.8 7.2l1.6-1.6"/>',
  waves: '<path d="M3 7.5c1.5-1.4 3-1.4 4.5 0s3 1.4 4.5 0 3-1.4 4.5 0 3 1.4 4.5 0"/><path d="M3 12c1.5-1.4 3-1.4 4.5 0s3 1.4 4.5 0 3-1.4 4.5 0 3 1.4 4.5 0"/><path d="M3 16.5c1.5-1.4 3-1.4 4.5 0s3 1.4 4.5 0 3-1.4 4.5 0 3 1.4 4.5 0"/>',
  image: '<rect x="3.5" y="4.5" width="17" height="15" rx="3"/><circle cx="9" cy="10" r="1.6"/><path d="M4.5 18l5-4.6 3.6 3.2 2.6-2.2 4 3.4"/>',
  bulb: '<path d="M9.5 17.5h5M10.3 20.5h3.4"/><path d="M12 3.5a5.8 5.8 0 0 0-3.4 10.5c.7.5 1 1.2 1 2v.5h4.8V16c0-.8.3-1.5 1-2A5.8 5.8 0 0 0 12 3.5z"/>',
  pad: '<path d="M7.5 8h9a4.5 4.5 0 0 1 4.5 4.5v.7a3 3 0 0 1-5.3 1.9L14.6 14H9.4l-1.1 1.1A3 3 0 0 1 3 13.2v-.7A4.5 4.5 0 0 1 7.5 8z"/><path d="M8 10.2v3.2M6.4 11.8h3.2"/><circle cx="15.6" cy="10.9" r=".9" fill="#fff" stroke="none"/><circle cx="17.4" cy="12.7" r=".9" fill="#fff" stroke="none"/>',
  sliders: '<path d="M4 7h4M12 7h8M4 12h10M18 12h2M4 17h2M10 17h10"/><circle cx="10" cy="7" r="2"/><circle cx="16" cy="12" r="2"/><circle cx="8" cy="17" r="2"/>',
  car: '<path d="M5 12.5l1.6-4.2A2 2 0 0 1 8.5 7h7a2 2 0 0 1 1.9 1.3l1.6 4.2"/><rect x="4" y="12.5" width="16" height="5" rx="1.8"/><path d="M6.5 17.5v1.5M17.5 17.5v1.5"/><circle cx="7.8" cy="15" r=".9" fill="#fff" stroke="none"/><circle cx="16.2" cy="15" r=".9" fill="#fff" stroke="none"/>',
  dl: '<path d="M12 4v10M8 10.2l4 4 4-4"/><path d="M4.5 15v2.5A2 2 0 0 0 6.5 19.5h11a2 2 0 0 0 2-2V15"/>',
};
const svg = (name, size, stroke = 2, color = '#fff') =>
  `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="${stroke}" stroke-linecap="round" stroke-linejoin="round">${ICONS[name]}</svg>`;

const PAGES = [
  { id: 'overview', name: '概览', icon: 'gauge', grad: ['#a2a2a8', '#66666b'] },
  { id: 'visual', name: '画面', icon: 'sun', grad: ['#4aa2ff', '#0a6edb'] },
  { id: 'water', name: '水下视野', icon: 'waves', grad: ['#66d1de', '#2a9db4'] },
  { id: 'tex', name: '贴图', icon: 'image', grad: ['#d47ef0', '#9a4ed5'] },
  { id: 'light', name: '灯光与地图', icon: 'bulb', grad: ['#ffbf4d', '#ff9500'] },
  { id: 'play', name: '玩法', icon: 'pad', grad: ['#68dd82', '#2db04d'] },
  { id: 'ui', name: '界面', icon: 'sliders', grad: ['#9490f8', '#5a57df'] },
  { id: 'traffic', name: '车流', icon: 'car', grad: ['#ff7464', '#f0372b'] },
  { id: 'kit', name: '导入 kit', icon: 'dl', grad: ['#c6a782', '#9c7e57'] },
];
const NAV_Y = PAGES.map((p, i) => (i < 8 ? 103 + 33 * i : 387));
const pageIndex = id => PAGES.findIndex(p => p.id === id);

const iconTile = (p, size, radius, isz) =>
  `<div class="itile" style="width:${size}px;height:${size}px;border-radius:${radius}px;background:linear-gradient(180deg,${p.grad[0]},${p.grad[1]})">${svg(p.icon, isz, size > 30 ? 2 : 2.2)}</div>`;

const CHECK = '<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>';
const BLUECHECK = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#0a84ff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>';
const CHEV_R = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#8e8e93" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M9 5l7 7-7 7"/></svg>';
const CHEV_D = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#8e8e93" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 9l7 7 7-7"/></svg>';
const BADGE = '<span class="badge">已安装</span>';

const toggle = (key, on = true) => `<div class="tg" data-tg="${key}" style="--p:${on ? 1 : 0}"><i></i></div>`;
const row = (title, desc, right = '', badge = true, extra = '') =>
  `<div class="row" ${extra}><div class="rt">${title}${badge ? BADGE : ''}</div><div class="rd">${desc}</div>${right}</div>`;
const header = (p, sub, x) =>
  `<div class="phead" style="left:${x}px">${iconTile(p, 44, 11, 24)}<div class="ptitle">${p.name}</div><div class="psub">${sub}</div></div>`;
const scrollbar = (y0, y1) => `<div class="sbar" style="top:${y0}px;height:${y1 - y0}px"></div>`;

const HEX_ROW = (name, hex, key, open = false) =>
  `<div class="row sub" data-colorrow="${key}"><div class="rt">${name}</div><div class="hexr"><span class="hx">#${hex}</span><span class="dot" style="background:#${hex}"></span>${open ? CHEV_D : CHEV_R}</div></div>`;

function pageHTML(id) {
  const P = PAGES[pageIndex(id)];
  switch (id) {
    case 'overview': return `
      <div class="ohead"><div class="bigicon">字</div><div class="otitle">GTA5 中文字体包</div><div class="osub">选装安装器 v1.2.0 · 适用于 GTA V 增强版 构建 1158</div></div>
      <div class="slabel" style="left:390px;top:156px">游戏</div>
      <div class="card" style="left:390px;top:181px">
        <div class="row ck"><span class="gck" data-ck="0">${CHECK}</span><div class="rt">游戏目录</div><div class="rd mono">E:\\SteamLibrary\\steamapps\\common\\Grand Theft Auto V Enhanced</div><div class="btn2">更改…</div></div>
        <div class="row ck"><span class="gck" data-ck="1">${CHECK}</span><div class="rt">游戏版本</div><div class="rd">构建 1158，已核对</div></div>
        <div class="row ck"><span class="gck" data-ck="2">${CHECK}</span><div class="rt">密钥文件</div><div class="rd">已找到，可以读写游戏文件</div></div>
        <div class="row ck"><span class="gck" data-ck="3">${CHECK}</span><div class="rt">原版备份</div><div class="rd">update.rpf 和 rpf.cache 已备份，可随时还原</div></div>
      </div>
      <div class="slabel" style="left:390px;top:443px">当前安装</div>
      <div class="card" style="left:390px;top:468px">
        <div class="row ck tall"><span class="gck" data-ck="4">${CHECK}</span><div class="rt">已安装 22 项功能</div><div class="rd wrap">中文字体包（必装）、VisualV 天气光照、VisualV 特效、去雾、夜晚补亮、夜间无云、清晰水下、NVE 天空与天气贴图、界面贴图、水面贴图、NVE 路灯、快速下云、移除爆炸震动、伤疤移除、按 E 拾取武器、跳过开场 logo、游戏中切换语言、战局中切换瞄准模式、经验条与武器轮盘颜色、玩家列表颜色、互动菜单横幅颜色、无车流无警力</div></div>
      </div>
      <div class="slabel" style="left:390px;top:608px">基础</div>
      <div class="card" style="left:390px;top:633px">
        <div class="row"><div class="rt">中文字体包（必装）${BADGE}<span class="badge gray">218 MB</span></div><div class="rd">中文字体、提示框排版、ESC 菜单时间字体、繁体弹药斜杠</div><div class="tg locked" style="--p:1"><i></i></div></div>
      </div>
      <div class="slabel" style="left:390px;top:718px">维护</div>
      <div class="card" style="left:390px;top:743px">
        <div class="row short"><div class="rt"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linejoin="round"><path d="M3.5 7.5a2 2 0 0 1 2-2h4l2 2.2h7a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/></svg>&nbsp;打开游戏目录</div></div>
        <div class="row" data-restore><div class="rt red"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#ff6961" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 5v5h5"/><path d="M5.2 15a7.5 7.5 0 1 0 .3-6.6L4 10"/></svg>&nbsp;还原原版…</div><div class="rd">移除所有已安装的功能</div></div>
      </div>
      ${scrollbar(36, 880)}`;
    case 'visual': return `${header(P, '5 项 · 已选 <span data-vsel>5</span> 项', 396)}
      <div class="card" style="left:396px;top:136px">
        ${row('VisualV 天气光照', '各天气的天空、光照和色调，含夜空噪点修复和车底不再死黑', toggle('v0'))}
        ${row('VisualV 特效', '滤镜修饰、暴风雪雾气、火焰、环境光遮蔽、镜头光晕、闪电', toggle('v1'))}
        ${row('去雾', '关闭雾和远景薄霾，含赌场金库隧道的雾', toggle('v2'))}
        ${row('夜晚补亮', '提高夜间环境光和曝光，月亮恢复原版亮度', toggle('v3'))}
        ${row('夜间无云', '晚上 9 点到早上 5 点天空无云', toggle('v4'))}
      </div>`;
    case 'water': return `${header(P, '3 项 · 单选', 396)}
      <div class="card" style="left:396px;top:136px">
        ${row('VisualV 水下', '雾从镜头前开始、深蓝色，偏暗偏写实', `<span class="rck" data-rck="w0">${BLUECHECK}</span>`, false, 'data-hov="w0"')}
        ${row('原版水下', '游戏原版的水下效果', `<span class="rck" data-rck="w1">${BLUECHECK}</span>`, false, 'data-hov="w1"')}
        ${row('清晰水下', '在原版基础上，雾从 25 米外开始、浓度降到 35%', `<span class="rck" data-rck="w2">${BLUECHECK}</span>`, true, 'data-hov="w2"')}
      </div>
      <div class="note" style="left:410px;top:322px">只能选择一项。</div>`;
    case 'tex': return `${header(P, '3 项 · 已选 3 项', 396)}
      <div class="card" style="left:396px;top:136px">
        ${row('NVE 天空与天气贴图', 'skydome.ytd、fxweather.ytd', toggle('t0'))}
        ${row('界面贴图', 'graphics.ytd', toggle('t1'))}
        ${row('水面贴图', 'water.ytd、graphics_pc.ytd', toggle('t2'))}
      </div>`;
    case 'light': return `${header(P, '1 项 · 已选 1 项', 396)}
      <div class="card" style="left:396px;top:136px">
        ${row('NVE 路灯', '白光路灯模型、灯具摆放和远景灯光', toggle('l0'))}
      </div>
      <div class="note" style="left:410px;top:204px">NVE 路面等大型功能以外部包单独下载，下载后把 .gtakit 文件拖进窗口即可导入。</div>`;
    case 'play': return `${header(P, '5 项 · 已选 5 项', 396)}
      <div class="card" style="left:396px;top:136px">
        ${row('快速下云', '去除下云动画', toggle('p0'), true, 'data-hov="p0"')}
        ${row('移除爆炸震动', '关闭爆炸引起的镜头震动', toggle('p1'), true, 'data-hov="p1"')}
        ${row('伤疤移除', '受伤痊愈后身上不留伤疤', toggle('p2'), true, 'data-hov="p2"')}
        ${row('按 E 拾取武器', '地上的武器需要按 E 才会捡起', toggle('p3'), true, 'data-hov="p3"')}
        ${row('跳过开场 logo', '启动时不播放 Rockstar 开场动画', toggle('p4'), true, 'data-hov="p4"')}
      </div>`;
    case 'ui': return `${header(P, '5 项 · 已选 5 项', 390)}
      <div class="card" style="left:390px;top:136px">
        ${row('游戏中切换语言', '在 设置 > 显示 里切换游戏语言', toggle('u0'))}
        ${row('战局中切换瞄准模式', '战局中可切换瞄准模式', toggle('u1'))}
        ${row('经验条与武器轮盘颜色', '自己填 RGB；默认武器轮盘青色、经验条原版蓝', toggle('u2'))}
        ${HEX_ROW('武器轮盘颜色', '4B8787', 'c0')}
        ${HEX_ROW('经验条（RP）颜色', '4B8787', 'c1')}
        ${row('玩家列表颜色', '线上玩家列表里默认蓝色的行改成自选颜色，组织、摩托帮等自带颜色的行不变', toggle('u3'))}
        ${HEX_ROW('颜色', '5C4080', 'c2')}
        ${row('互动菜单横幅颜色', 'M 键互动菜单顶部横幅图片换成自选颜色，保留原版渐变', toggle('u4'))}
        ${HEX_ROW('颜色', '8297AE', 'c3', true)}
        <div class="picker">
          <div class="pv"><div class="pvmenu"><div class="pvban"></div><div class="pvsel">${CHEV_R.replace('#8e8e93', '#222')}</div>${('<div class="pvrow">' + CHEV_R.replace('#8e8e93', '#777') + '</div>').repeat(4)}</div></div>
          <div class="pvreset"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#49a2fd" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M4 5v5h5"/><path d="M5.2 15a7.5 7.5 0 1 0 .3-6.6L4 10"/></svg> 恢复默认</div>
          <div class="sv"><div class="svw"></div><div class="svb"></div><div class="svk"></div></div>
          <div class="hue"><div class="huek"></div></div>
          <div class="sw">${['2d6eb9', 'e5484d', 'f76b15', 'f0be46', '30a46c', '0090ff', '5b5bd6', '8e4ec6', 'e93d82', 'ececec'].map((c, i) => `<span data-sw="${i}" style="background:#${c}"></span>`).join('')}<b></b></div>
          <div class="ins"><div class="in r"><em>R</em><span data-v="r">130</span></div><div class="in g"><em>G</em><span data-v="g">151</span></div><div class="in b"><em>B</em><span data-v="b">174</span></div><div class="in h"><em>#</em><span data-v="hex">8297AE</span></div></div>
        </div>
      </div>
      ${scrollbar(36, 866)}`;
    case 'traffic': return `${header(P, '4 项 · 单选', 396)}
      <div class="card" style="left:396px;top:136px">
        ${row('原版车流和警力', '不改车流和通缉', '', false, 'data-hov="c0"')}
        ${row('无车流（保留警力）', '路上不刷 NPC 车辆和停放车辆，通缉时照常派警', '', false, 'data-hov="c1"')}
        ${row('无车流无警力', '路上不刷 NPC 车辆，通缉时也不派警', `<span class="rck" style="opacity:1">${BLUECHECK}</span>`, true, 'data-hov="c2"')}
        ${row('三倍 NPC 车、十倍警车', 'NPC 车辆约 3 倍，派警 10 倍、间隔 2～5 秒，不刷行人', '', false, 'data-hov="c3"')}
      </div>
      <div class="note" style="left:410px;top:382px">只能选择一项。</div>`;
    case 'kit': {
      const kits = [['中文字体包（必装）', 'v2', '基础 · 218 MB'], ['VisualV 天气光照', 'v1', '画面 · 2.1 MB'], ['VisualV 特效', 'v2', '画面 · 2.2 MB'], ['去雾', 'v2', '画面 · 1 KB'], ['夜晚补亮', 'v1', '画面 · 1 KB'], ['夜间无云', 'v1', '画面 · 1 KB'], ['VisualV 水下', 'v1', '']];
      return `<div class="phead" style="left:390px">${iconTile(P, 44, 11, 24)}<div class="ptitle">导入 kit</div><div class="psub">新功能和更新以 .gtakit 单文件发布</div></div>
      <div class="drop" data-drop><div class="dropic">${svg('dl', 34, 2, '#0a84ff')}</div><div class="dropt">把 .gtakit 文件拖到这里</div><div class="drops">也可以拖到窗口的任意位置，导入前会先显示内容</div><div class="btn2 c">选择文件…</div></div>
      <div class="slabel" style="left:390px;top:366px">文件关联</div>
      <div class="card" style="left:390px;top:390px"><div class="row">${'<div class="rt">双击 .gtakit 文件时用本安装器打开</div>'}<div class="rd">只对当前 Windows 用户生效，随时可以关闭</div>${toggle('k0', false)}</div></div>
      <div class="slabel" style="left:390px;top:475px">已有的 kit</div><div class="slabel r" style="left:893px;width:100px;top:475px">27 个</div>
      <div class="card" style="left:390px;top:501px">${kits.map(k => `<div class="row"><div class="rt">${k[0]}<span class="badge gray">${k[1]}</span></div><div class="rd">${k[2]}</div></div>`).join('')}</div>
      ${scrollbar(36, 370)}`;
    }
  }
}

function makeApp(onlyPages) {
  const ids = onlyPages || PAGES.map(p => p.id);
  const el = document.createElement('div');
  el.className = 'win';
  el.innerHTML = `
    <div class="tb"><div class="tbi">字</div><div class="tbt">GTA5 中文字体包</div>
      <div class="ctl" style="left:1036px"><svg width="12" height="12"><path d="M1 6.5h10" stroke="#20262e" stroke-width="1"/></svg></div>
      <div class="ctl" style="left:1082px"><svg width="12" height="12"><rect x="1.5" y="1.5" width="9" height="9" rx="1.5" fill="none" stroke="#20262e" stroke-width="1"/></svg></div>
      <div class="ctl" style="left:1127px"><svg width="12" height="12"><path d="M1.5 1.5l9 9M10.5 1.5l-9 9" stroke="#20262e" stroke-width="1"/></svg></div>
    </div>
    <div class="side">
      <div class="search"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#a1a1a6" stroke-width="2.4" stroke-linecap="round"><circle cx="10.5" cy="10.5" r="6.5"/><path d="M15.5 15.5L20 20"/></svg><span>搜索功能</span></div>
      <div class="navsel"></div>
      ${PAGES.map((p, i) => `<div class="nav" style="top:${NAV_Y[i] - 16 - 32}px">${iconTile(p, 22, 6, 13)}<span>${p.name}</span></div>`).join('')}
      <div class="sdiv"></div>
      <div class="sfoot">安装器 v1.2.0 · 构建 1158</div>
    </div>
    <div class="mainclip"><div class="pages">${ids.map(id => `<div class="page" data-page="${id}">${pageHTML(id)}</div>`).join('')}</div></div>
    <div class="foot">
      <div class="fl"><div class="fa"><b data-f1>已选 22 项</b><span data-f2>与当前安装相同</span></div><div class="fb"><b data-f1b></b><span data-f2b></span></div></div>
      <div class="link" data-link>恢复推荐</div><div class="pbtn" data-btn>重新安装</div>
    </div>
    <div class="overlay"></div>`;
  const q = s => el.querySelector(s);
  const qa = s => [...el.querySelectorAll(s)];
  return { el, q, qa };
}

// 颜色工具
function hsv2rgb(h, s, v) {
  h = ((h % 360) + 360) % 360;
  const c = v * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = v - c;
  let r, g, b;
  if (h < 60) [r, g, b] = [c, x, 0]; else if (h < 120) [r, g, b] = [x, c, 0];
  else if (h < 180) [r, g, b] = [0, c, x]; else if (h < 240) [r, g, b] = [0, x, c];
  else if (h < 300) [r, g, b] = [x, 0, c]; else [r, g, b] = [c, 0, x];
  return [r, g, b].map(u => Math.round((u + m) * 255));
}
function hex2hsv(hex) {
  const n = parseInt(hex, 16), r = (n >> 16) / 255, g = ((n >> 8) & 255) / 255, b = (n & 255) / 255;
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
  let h = 0;
  if (d) h = mx === r ? 60 * (((g - b) / d) % 6) : mx === g ? 60 * ((b - r) / d + 2) : 60 * ((r - g) / d + 4);
  return [(h + 360) % 360, mx ? d / mx : 0, mx];
}
const toHex = rgb => rgb.map(u => u.toString(16).padStart(2, '0')).join('').toUpperCase();
