"""原创配乐合成：120 BPM / A 小调，节拍网格与视频镜头对齐。

python3 music.py out/music.wav
时间均为视频时间（秒）。镜头时间 = index.html 内部时间 - 2.9。
"""
import sys
import wave
import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve

SR = 48000
DUR = 43.8
N = int(SR * DUR)
BEAT = 0.5
OFF = 0.4                       # 第一拍；16.9/17.9/18.9 三个硬切、40.4 九宫格落定都在拍上
rng = np.random.default_rng(7)

def beat(k): return OFF + BEAT * k
def bar(b): return OFF + 2.0 * b

L = np.zeros(N); R = np.zeros(N)          # 干声总线
RV = np.zeros((2, N))                      # 混响发送
DUCK_SRC = []                              # 底鼓时刻，用于侧链

def add(sig, t, gain=1.0, pan=0.0, rev=0.0):
    i = int(round(t * SR))
    if i >= N or i + len(sig) <= 0: return
    s0 = max(0, -i); i0 = max(0, i); n = min(len(sig) - s0, N - i0)
    seg = sig[s0:s0 + n] * gain
    gl, gr = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    L[i0:i0 + n] += seg * gl; R[i0:i0 + n] += seg * gr
    if rev: RV[0, i0:i0 + n] += seg * gl * rev; RV[1, i0:i0 + n] += seg * gr * rev

def tt(d): return np.arange(int(d * SR)) / SR
def env_exp(d, tau, att=0.002):
    t = tt(d); return np.minimum(1, t / att) * np.exp(-t / tau)
def filt(x, kind, f, order=2):
    f = np.clip(np.atleast_1d(f) / (SR / 2), 1e-4, .999)
    wn = float(f[0]) if f.size == 1 else f
    return sosfilt(butter(order, wn, kind, output='sos'), x)
def saw(freq, t, phase=0.0): return 2 * ((freq * t + phase) % 1) - 1
def noise(d): return rng.uniform(-1, 1, int(d * SR))
def hz(note):  # MIDI
    return 440 * 2 ** ((note - 69) / 12)

# ---------- 乐器 ----------
def kick(t, g=1.0):
    d = 0.45; x = tt(d)
    f = 45 + 110 * np.exp(-x / 0.035)
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) * env_exp(d, 0.14, 0.001)
    s += filt(noise(d), 'highpass', 2500) * env_exp(d, 0.004) * 0.35
    add(np.tanh(s * 1.6), t, 0.52 * g)
    DUCK_SRC.append(t)

def clap(t, g=1.0):
    d = 0.3; n = filt(noise(d), 'bandpass', [900, 3200])
    e = np.zeros(int(d * SR))
    for k, o in enumerate([0, .011, .022]):
        i = int(o * SR); ev = env_exp(d, .009 if k < 2 else .12)[:len(e) - i]; e[i:i + len(ev)] += ev
    add(n * e, t, 0.62 * g, 0.0, rev=0.35)

def hat(t, open_=False, g=1.0, pan=0.25):
    d = 0.25 if open_ else 0.06
    s = filt(noise(d), 'highpass', 7500) * env_exp(d, 0.09 if open_ else 0.018)
    add(s, t, (0.34 if open_ else 0.24) * g, pan)

def snare(t, g=1.0):
    d = 0.22; x = tt(d)
    s = filt(noise(d), 'bandpass', [1200, 6000]) * env_exp(d, 0.06) + np.sin(2 * np.pi * 190 * x) * env_exp(d, 0.04) * .5
    add(s, t, 0.32 * g, 0.0, rev=0.25)

def crash(t, g=1.0, d=2.4):
    s = filt(noise(d), 'highpass', 4500) * env_exp(d, 0.7, 0.001)
    add(s, t, 0.22 * g, -0.2, rev=0.4); add(filt(noise(d), 'highpass', 5000) * env_exp(d, 0.65, 0.001), t, 0.2 * g, 0.3)

def impact(t, g=1.0):
    d = 2.2; x = tt(d)
    f = 30 + 60 * np.exp(-x / 0.12)
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(d, 0.7, 0.002)
    add(np.tanh(boom * 2), t, 0.3 * g, rev=0.2)
    add(filt(noise(d), 'lowpass', 900) * env_exp(d, 0.35), t, 0.35 * g, rev=0.5)

def bass(t, note, d=0.22, g=1.0, cut=900):
    x = tt(d); f = hz(note)
    s = saw(f, x) + saw(f * 1.006, x, .3)
    s = filt(s, 'lowpass', cut) * env_exp(d, d * 0.55, 0.004)
    s += np.sin(2 * np.pi * f * x) * env_exp(d, d * 0.8, 0.004) * 0.35
    add(np.tanh(s * 1.3), t, 0.21 * g)

def pad(t, notes, d, g=1.0, cut=1800, att=0.25):
    x = tt(d); s = np.zeros_like(x); s2 = np.zeros_like(x)
    for n in notes:
        for det, p in [(-0.11, -.6), (-0.04, .4), (0.0, 0), (0.05, -.3), (0.12, .7)]:
            f = hz(n + det)
            v = saw(f, x, rng.random())
            s += v * (1 - p) / 2; s2 += v * (1 + p) / 2
    e = np.minimum(1, x / att) * np.minimum(1, (d - x) / 0.35).clip(0)
    sl, sr = filt(s, 'lowpass', cut) * e, filt(s2, 'lowpass', cut) * e
    k = 0.11 * g / max(1, len(notes))
    add(sl, t, k, -1, rev=.4); add(sr, t, k, 1, rev=.4)

def pluck(t, note, g=1.0, pan=0.0, d=0.28, cut=3200):
    x = tt(d); f = hz(note)
    s = 0.6 * saw(f, x) + 0.4 * np.sign(np.sin(2 * np.pi * f * x))
    s = filt(s, 'lowpass', cut) * env_exp(d, 0.07, 0.002)
    add(s, t, 0.27 * g, pan, rev=0.45)

def stab(t, notes, g=1.0):
    for i, n in enumerate(notes):
        pluck(t, n, 0.9 * g, pan=(i - 1) * 0.4, d=0.35, cut=2600)

def riser(t0, t1, g=1.0):
    d = t1 - t0; x = tt(d); n = noise(d); out = np.zeros_like(x)
    blocks = 48; bl = len(x) // blocks + 1
    for b in range(blocks):
        a, z = b * bl, min(len(x), (b + 1) * bl)
        p = b / blocks; fc = 400 * (16 ** p)
        out[a:z] = filt(n[a:z], 'bandpass', [fc * .7, fc * 1.4])
    tone = saw(220 * 2 ** (x / d * 2), x) * 0.15
    e = (x / d) ** 2.2
    add((out + filt(tone, 'lowpass', 3000)) * e, t0, 0.32 * g, rev=0.5)

def whoosh(t0, t1, g=1.0):
    d = (t1 - t0) + 0.25; x = tt(d); n = noise(d); out = np.zeros_like(x)
    blocks = 24; bl = len(x) // blocks + 1
    for b in range(blocks):
        a, z = b * bl, min(len(x), (b + 1) * bl)
        p = b / blocks; fc = 700 + 2600 * np.sin(np.pi * min(1, p * 1.1))
        out[a:z] = filt(n[a:z], 'bandpass', [fc * .6, fc * 1.6])
    pk = (t1 - t0) * 0.55
    e = np.exp(-((x - pk) / (d * 0.28)) ** 2)
    half = len(x) // 2
    add(out[:half] * e[:half], t0, 0.16 * g, -0.5, rev=.25)
    add(out[half:] * e[half:], t0 + half / SR, 0.16 * g, 0.5, rev=.25)

def click(t, g=1.0):
    d = 0.05; x = tt(d)
    s = np.sin(2 * np.pi * 2400 * x) * env_exp(d, 0.006, 0.0005) + filt(noise(d), 'highpass', 4000) * env_exp(d, 0.003) * .5
    add(s, t, 0.12 * g, 0.15)

# ---------- 编曲 ----------
CH = [  # (和弦音, 低音根音)
    ([57, 60, 64], 33),   # Am
    ([53, 57, 60], 29),   # F
    ([55, 60, 64], 36),   # C
    ([55, 59, 62], 31),   # G
]
ARP = [0, 1, 2, 3, 2, 1, 4, 3, 0, 1, 2, 3, 4, 5, 4, 2]

def chord_at(b): return CH[b % 4]
def arp_notes(notes): return [notes[0], notes[1], notes[2], notes[0] + 12, notes[1] + 12, notes[2] + 12]

# 0–0.4 预备 + 前奏 b0
riser(0.0, 2.4, 0.7)
pad(0.0, [57, 60, 64, 71], 2.4 + .3, 0.8, cut=900, att=0.6)
for k in range(16):
    t = bar(0) + k * 0.125
    if t < 0.4: continue
    pluck(t, arp_notes([57, 60, 64])[ARP[k] % 6] + 12, 0.55 * (k / 16 + .3), pan=0.3 * np.sin(k), cut=900 + 140 * k)
whoosh(0.0, 1.35, 1.2)
impact(1.35, 0.4)

def groove(b, B=False, kick_on=True, hats=True, stabs=True):
    notes, root = chord_at(b)
    t0 = bar(b)
    pad(t0, notes + [notes[0] + 12], 2.0, 0.75 if not B else 0.9, cut=1400 if not B else 2200)
    for k in range(4):
        tb = t0 + k * BEAT
        if kick_on: kick(tb)
        if k in (1, 3): clap(tb)
        if hats:
            hat(tb + .25, open_=True, pan=.3)
            hat(tb, g=.7, pan=-.35); hat(tb + .125, g=.5, pan=.4); hat(tb + .375, g=.55, pan=-.4)
        bass(tb + .25, root + 12 if (B and k % 2) else root, 0.22)
        if B: bass(tb + .375, root + 12, 0.1, 0.6)
    if stabs:
        stab(t0 + .75, notes, .7); stab(t0 + 1.75, notes, .6)
    if B:
        an = arp_notes(notes)
        for k in range(16):
            pluck(t0 + k * .125, an[ARP[k] % 6] + 12, .55, pan=0.45 * np.sin(k * 1.3), cut=2600)

for b in range(1, 8):            # 2.4–16.4 律动 A
    groove(b)
crash(bar(1), 1.1)
for k in range(4): snare(bar(7) + 1.5 + k * .125, 0.5 + k * .15)   # 进 B 前的小过门

for b in range(8, 16):           # 16.4–32.4 律动 B
    groove(b, B=True)
crash(bar(8))
for tcut in (16.9, 17.9, 18.9):  # 三个硬切
    crash(tcut, 0.6, 1.2); impact(tcut, 0.25)
crash(bar(12), 0.8)

for b in range(16, 18):          # 32.4–36.4 收束段（拖入 kit）
    notes, root = chord_at(b)
    pad(bar(b), notes + [notes[0] + 12, notes[2] + 12], 2.0, 1.0, cut=1000)
    an = arp_notes(notes)
    for k in range(16):
        t = bar(b) + k * .125
        pluck(t, an[ARP[k] % 6] + 12, .5, pan=.4 * np.sin(k), cut=1500)
        if k % 2 == 0: hat(t, g=.45)
    for k in range(4):
        bass(bar(b) + k * BEAT, root, .45, .7, cut=500)
impact(bar(16), 0.45)

for b in range(18, 20):          # 36.4–40.4 推进
    notes, root = chord_at(b)
    pad(bar(b), notes + [notes[0] + 12], 2.0, 1.0, cut=1200 + (b - 18) * 1400)
    for k in range(4):
        tb = bar(b) + k * BEAT
        if tb < 40.15: kick(tb, .85)
        bass(tb + .25, root, .2, .9)
        hat(tb + .25, open_=True, g=.8)
    # 军鼓滚奏：8 分 → 16 分 → 32 分
    step = .25 if b == 18 else .125
    t = bar(b)
    while t < bar(b) + 2.0 - 0.25 - 1e-9:
        snare(t, .35 + .65 * (t - bar(18)) / 4)
        t += step if t < bar(19) + 1.0 else .0625
riser(bar(18), 40.4, 1.0)

# 40.4 九宫格落定：重拍 + 长和弦
kick(40.4, 1.2); impact(40.4, 1.0); crash(40.4, 1.4, 3.2)
pad(40.4, [57, 60, 64, 71, 76], 3.4, 1.4, cut=3200, att=.02)
bass(40.4, 33, 2.2, .8, cut=300)
an = [57, 64, 69, 71, 72, 76]
for k, n in enumerate(an * 2):
    pluck(40.4 + k * .125, n + 12, .5 * (1 - k / 14), pan=.5 * np.sin(k * 2), cut=3000)

# ---------- 音效：甩镜 whoosh / 点击 ----------
WHIPS = [(4.75, 5.5), (7.75, 8.15), (10.85, 11.3), (12.0, 12.75), (13.45, 13.95), (14.95, 15.6), (16.65, 17.2),
         (24.1, 24.65), (25.05, 25.7), (29.95, 30.7), (31.25, 31.55), (31.75, 32.55), (34.4, 34.85), (35.2, 35.8),
         (37.5, 38.25), (40.6, 41.0), (41.85, 43.35)]
for a, b in WHIPS:
    whoosh(a - 2.9, b - 2.9, 1.4 if b - a > 1 else 1.0)
for c in [12.0, 13.3, 14.3, 16.6, 17.6, 18.3, 24.95, 28.3, 28.9, 31.6, 35.1, 41.7]:
    click(c - 2.9)
add(np.sin(2 * np.pi * 180 * tt(.25)) * env_exp(.25, .06), 37.15 - 2.9, .25, rev=.3)   # 文件落下

# ---------- 混音 ----------
# 侧链：底鼓压低其余声部（对整体做轻微泵感）
duck = np.ones(N)
for t in DUCK_SRC:
    i = int(t * SR); d = int(.28 * SR)
    seg = 1 - 0.38 * np.exp(-np.arange(d) / (0.07 * SR))
    j = min(N, i + d); duck[i:j] = np.minimum(duck[i:j], seg[:j - i])
# 混响：合成的指数衰减噪声脉冲
irl = int(1.8 * SR); xi = np.arange(irl) / SR
ir = [filt(rng.standard_normal(irl), 'lowpass', 6000) * np.exp(-xi / 0.45) for _ in range(2)]
wl = fftconvolve(RV[0], ir[0])[:N]; wr = fftconvolve(RV[1], ir[1])[:N]
wl /= np.max(np.abs(wl)) + 1e-9; wr /= np.max(np.abs(wr)) + 1e-9
mix = np.stack([L + wl * 0.12 * np.max(np.abs(L)), R + wr * 0.12 * np.max(np.abs(R))])
mix *= duck * 0.15 + 0.85
mix = filt(mix[0], 'highpass', 36), filt(mix[1], 'highpass', 36)
mix = np.stack(mix)
mix = mix - 0.4 * np.stack([filt(m, 'lowpass', 110) for m in mix])   # 低架衰减约 -4 dB
# 淡入淡出 + 柔和限幅 + 归一化到 -1.5 dBFS
fade = np.ones(N)
fi = int(0.05 * SR); fade[:fi] = np.linspace(0, 1, fi)
fo0 = int(42.6 * SR); fade[fo0:] = np.linspace(1, 0, N - fo0) ** 1.5
mix *= fade
mix = np.tanh(mix / np.max(np.abs(mix)) * 1.8)
mix *= 10 ** (-1.5 / 20) / np.max(np.abs(mix))

out = sys.argv[1] if len(sys.argv) > 1 else 'out/music.wav'
pcm = (mix.T * 32767).astype('<i2')
with wave.open(out, 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
print('wrote', out, f'{DUR}s')
