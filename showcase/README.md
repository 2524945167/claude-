# GTA5 中文字体包安装器 · Showcase

安装器 v1.2.0 的展示视频，只展示菜单界面本身，没有字幕和标题文字。

- 成片：`out/gta5-installer-showcase.mp4`（1920×1080，60fps，43.8 秒，含配乐，内嵌封面）
- 封面：`out/cover.png`（1920×1080）
- 配乐：`out/music.m4a`（原创合成，120 BPM，A 小调，-14 LUFS）
- 界面按真实截图（1160×950）在 HTML 里逐像素还原，镜头推近时依旧清晰

## 镜头顺序

| 时间 | 内容 |
| --- | --- |
| 0–5s | 窗口从远处倾斜飞入，概览页检测项依次打勾，推近游戏状态卡 |
| 5–8s | 甩镜到「维护 / 还原原版」与底栏 |
| 8–13s | 侧栏切到「画面」，关闭「去雾」「夜晚补亮」，底栏计数 22 → 21 → 20 |
| 13–17s | 「水下视野」大角度俯视，单选切换 |
| 17–21s | 「贴图」「灯光与地图」「玩法」快切 |
| 21–28s | 「界面」取色器：拖色相、拖饱和度、点色板，横幅预览和 RGB/HEX 同步变化 |
| 28–31s | 「车流」滚转入镜，逐行悬停 |
| 31–37s | 「导入 kit」：拖入 .gtakit 文件，下摇到已有 kit 列表 |
| 37–44s | 点击「安装」，拉远成九宫格，展示全部页面后淡出 |

## 重新渲染

```bash
npm i -g playwright   # 或使用已安装的 Playwright + Chromium
node render.js --workers 4 --scale 2 --out out/gta5-installer-showcase.mp4
node stills.js /tmp/stills 3.5 20 30   # 导出指定时间点的静帧预览
```

- `app.js`：界面还原（页面数据、图标、颜色工具）
- `index.html`：镜头关键帧、光标路径、交互时间轴，`renderFrame(t)` 可任意定位
- `render.js`：逐帧截图 → ffmpeg 分段编码 → 无损拼接；`--scale 2` 为 2 倍超采样
- `music.py`：配乐合成（numpy + scipy），节拍网格从 0.4s 起，三个硬切和九宫格落定都在拍上；甩镜配 whoosh，点击配咔嗒声
- `cover.html` / `cover.js`：封面

## 配乐与合成

| 时间 | 段落 |
| --- | --- |
| 0–2.4s | 前奏：铺底 + 琶音 + 上升音效，窗口落定时低频冲击 |
| 2.4–16.4s | 律动 A：四拍底鼓、拍手、反拍镲、低音、和弦 |
| 16.4–32.4s | 律动 B：加入琶音主旋律，16.9 / 17.9 / 18.9 三个硬切配重音 |
| 32.4–36.4s | 收束：鼓组退出，只留铺底和琶音（拖入 kit） |
| 36.4–40.4s | 推进：军鼓滚奏加速 + 上升音效 |
| 40.4s– | 九宫格落定：重拍 + 长和弦，淡出 |

```bash
python3 music.py /tmp/music.wav
node cover.js out/cover.png
ffmpeg -i silent.mp4 -i /tmp/music.wav -i cover.jpg -map 0:v -map 1:a -map 2:v \
  -c:v:0 copy -c:v:1 mjpeg -disposition:v:1 attached_pic -c:a aac -b:a 320k -af volume=-0.6dB \
  -movflags +faststart out/gta5-installer-showcase.mp4
```
