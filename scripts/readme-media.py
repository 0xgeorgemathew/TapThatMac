#!/usr/bin/env python3
"""Renders the README images in media/ from the window captures in media/captures/.

    python3 -I scripts/readme-media.py

The captures are real Tap That Mac windows, taken with `screencapture -o -l <window>`; this
script only frames them. Each image is an HTML page screenshotted by headless Chrome at 2x, so a
1x window capture placed at half its width lands on the page pixel for pixel.

Palette, from the Live graph: cyan is motion, violet is the light-tap impulse, gold is the
threshold a tap must cross. The hero's double-tap trace is drawn, not captured.
"""

import random
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MEDIA = ROOT / "media"
CAPTURES = MEDIA / "captures"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

FONTS = ("https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:"
         "opsz,wdth,wght@12..96,75..100,400..800&display=block")

BASE_CSS = """
:root { --abyss:#08131D; --deep:#0E2030; --ink:#EAF2F8; --muted:rgba(234,242,248,.62);
  --faint:rgba(234,242,248,.38); --rule:rgba(127,211,247,.12);
  --cyan:#7FD3F7; --violet:#B9A6FF; --gold:#E9B949; --rose:#FF6F86; }
* { margin:0; padding:0; box-sizing:border-box; }
html, body { background:transparent; }
body { position:relative; overflow:hidden; color:var(--ink);
  font:400 14px/1.45 -apple-system, "SF Pro Text", system-ui; -webkit-font-smoothing:antialiased; }
.stage { position:absolute; inset:0; border-radius:18px; overflow:hidden; background:var(--abyss);
  box-shadow: inset 0 0 0 1px rgba(127,211,247,.10); }
.grid { position:absolute; inset:0;
  background-image: linear-gradient(to right, var(--rule) 1px, transparent 1px),
                    linear-gradient(to bottom, var(--rule) 1px, transparent 1px);
  background-size: 44px 44px; background-position: -1px -1px;
  mask-image: radial-gradient(120% 90% at 70% 40%, #000 30%, transparent 85%); opacity:.55; }
.display { font-family:"Bricolage Grotesque", -apple-system, system-ui; font-variation-settings:"wdth" 80;
  font-weight:800; letter-spacing:-.035em; line-height:.9; }
.mono { font-family: ui-monospace, "SF Mono", Menlo, monospace; letter-spacing:.06em; text-transform:uppercase; }
.eyebrow { font: 600 10.5px/1 ui-monospace, "SF Mono", Menlo, monospace; letter-spacing:.14em;
  text-transform:uppercase; color:var(--cyan); }
.window { position:absolute; border-radius:11px; overflow:hidden;
  box-shadow: 0 0 0 .5px rgba(255,255,255,.18), 0 28px 60px rgba(0,0,0,.55), 0 6px 16px rgba(0,0,0,.35); }
.window img { display:block; }
.tag { display:inline-block; font:700 9.5px/1 ui-monospace, "SF Mono", Menlo, monospace; letter-spacing:.12em;
  padding:5px 7px 4px; border-radius:5px; text-transform:uppercase; }
.tag.ready { color:var(--cyan); box-shadow: inset 0 0 0 1px rgba(127,211,247,.45); }
.tag.alpha { color:#120B2A; background:var(--violet); }
.tag.exp { color:var(--gold); box-shadow: inset 0 0 0 1px rgba(233,185,73,.5); }
h2 { font-family:"Bricolage Grotesque", -apple-system, system-ui; font-variation-settings:"wdth" 85;
  font-weight:750; font-size:30px; letter-spacing:-.025em; line-height:1; }
"""


def run(cmd, **kw):
    subprocess.run(cmd, check=True, **kw)


def capture(name, body, width, height, work, css=""):
    page = work / f"{name}.html"
    page.write_text(f"<!doctype html><meta charset=utf-8><link rel=stylesheet href='{FONTS}'>"
                    f"<style>{BASE_CSS}{css}</style>"
                    f"<body style='width:{width}px;height:{height}px'>{body}</body>")
    out = MEDIA / f"{name}.png"
    run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=2",
         "--default-background-color=00000000", f"--window-size={width},{height}",
         "--virtual-time-budget=6000", f"--screenshot={out}", "--allow-file-access-from-files", page.as_uri()],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if shutil.which("pngquant"):
        subprocess.run(["pngquant", "--force", "--skip-if-larger", "--quality", "82-96", "--output", out, out],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"  {out.relative_to(ROOT)}")


def shot(name, x, y, w, h, scale=0.5):
    """A window capture cropped to (x, y, w, h) in capture pixels, shown at `scale`."""
    src = (CAPTURES / f"{name}.png").as_uri()
    return (f"<div style='width:{w * scale}px;height:{h * scale}px;overflow:hidden'>"
            f"<img src='{src}' style='width:auto;height:auto;zoom:{scale};margin:{-y}px 0 0 {-x}px'></div>")


def trace(width, baseline, taps, seed=7, jitter=3.2):
    """A motion trace as SVG path data: low noise, with a sharp decaying spike at each tap x."""
    rng = random.Random(seed)
    cyan, violet = [], []
    for x in range(0, width + 1, 2):
        noise = rng.uniform(-jitter, jitter) + rng.uniform(-jitter, jitter) * 0.5
        lift = 0.0
        for tap_x, height in taps:
            d = x - tap_x
            if -4 <= d < 0:
                lift = max(lift, height * (1 + d / 4) * 0.55)
            elif 0 <= d < 40:
                lift = max(lift, height * (0.82 ** d) * (1 if d % 4 < 2 else 0.55))
        cyan.append((x, baseline - abs(noise) - lift))
        violet.append((x, baseline + 2 - abs(noise) * 0.55 - lift * 0.86))

    def path(points):
        return "M" + " L".join(f"{x},{y:.1f}" for x, y in points)

    return path(cyan), path(violet)


# ── Images ────────────────────────────────────────────────────────────────────────────────────

def hero(work):
    w, h = 880, 520
    tap1, tap2 = 214, 284
    line, impulse = trace(w, 92, [(tap1, 78), (tap2, 72)])
    icon = (ROOT / "docs/assets/tapthatmac-app-icon.png").as_uri()
    body = f"""
<div class=stage>
  <div class=grid></div>
  <div class=glow></div>
  <div class="window fadeout" style="left:432px;top:40px">{shot("live", 0, 0, 1000, 760, 0.47)}</div>
  <div class=brand><img src='{icon}'><span>Tap That Mac</span><span class="tag ready">beta</span></div>
  <h1 class=display>Double&#8209;tap<br>your Mac.</h1>
  <p class=lede>Tap That Mac listens to the motion sensor inside your MacBook. Tap twice and it
    locks the screen, plays or pauses, or skips a track.</p>
  <svg class=trace width="{w}" height="130" viewBox="0 0 {w} 130">
    <defs><filter id="glow" x="-10%" y="-50%" width="120%" height="200%">
      <feGaussianBlur stdDeviation="2.4" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>
    <line x1="0" x2="{w}" y1="40" y2="40" stroke="#E9B949" stroke-width="1.4" stroke-dasharray="5 4"/>
    <text x="{w - 28}" y="32" text-anchor="end" class="svgmono" fill="#E9B949">THRESHOLD</text>
    <path d="{impulse}" fill="none" stroke="#B9A6FF" stroke-width="1.1" opacity=".75"/>
    <path d="{line}" fill="none" stroke="#7FD3F7" stroke-width="1.5" filter="url(#glow)"/>
    <text x="{tap1 + 2}" y="118" text-anchor="middle" class="svgmono" fill="#7FD3F7">TAP</text>
    <text x="{tap2 + 2}" y="118" text-anchor="middle" class="svgmono" fill="#7FD3F7">TAP</text>
    <text x="{tap2 + 40}" y="118" class="svgmono" fill="#EAF2F8">→ LOCK MAC</text>
  </svg>
</div>"""
    css = """
.glow { position:absolute; inset:0; background:
  radial-gradient(55% 60% at 78% 30%, rgba(127,211,247,.16), transparent 70%),
  radial-gradient(40% 50% at 12% 100%, rgba(185,166,255,.14), transparent 70%); }
.fadeout { -webkit-mask-image: linear-gradient(to bottom, #000 62%, transparent 96%); }
.brand { position:absolute; left:44px; top:40px; display:flex; align-items:center; gap:10px;
  font:650 15px -apple-system, system-ui; letter-spacing:-.01em; }
.brand img { width:30px; height:30px; filter: drop-shadow(0 4px 10px rgba(0,0,0,.4)); }
h1 { position:absolute; left:42px; top:104px; font-size:76px; width:440px; letter-spacing:-.01em;
  font-variation-settings:"wdth" 88, "opsz" 96; font-weight:780; }
.lede { position:absolute; left:44px; top:268px; width:330px; font-size:15px; line-height:1.5; color:var(--muted); }
.trace { position:absolute; left:0; top:372px; }
.svgmono { font: 600 10px ui-monospace, "SF Mono", Menlo, monospace; letter-spacing:.14em; }
"""
    capture("hero", body, w, h, work, css)


def actions(work):
    w, h = 880, 440
    rows = [
        ("Lock Mac", "ready", "Works"),
        ("Play / Pause", "ready", "Works"),
        ("Next Track", "ready", "Works"),
        ("Previous Track", "ready", "Works"),
        ("Ring: every action on one wheel", "alpha", "Pre-alpha"),
        ("ChatGPT controls", "exp", "Experimental"),
    ]
    items = "".join(f"<li><span>{name}</span><span class='tag {kind}'>{label}</span></li>" for name, kind, label in rows)
    body = f"""
<div class=stage>
  <div class=grid></div>
  <div class="window" style="left:36px;top:36px">{shot("actions", 0, 0, 1000, 548, 0.46)}</div>
  <div class=col>
    <div class=eyebrow>A double-tap can</div>
    <ul>{items}</ul>
    <p>Pick one in <b>Actions</b>. Lock Mac and Play / Pause show a quick ring animation before they run.</p>
  </div>
</div>"""
    css = """
.col { position:absolute; left:532px; top:52px; width:312px; }
ul { list-style:none; margin-top:16px; }
li { display:flex; justify-content:space-between; align-items:center; gap:12px; padding:11px 0;
  border-top:1px solid rgba(234,242,248,.09); font-size:14px; }
li:last-child { border-bottom:1px solid rgba(234,242,248,.09); }
.col p { margin-top:18px; font-size:12.5px; color:var(--muted); }
.col b { color:var(--ink); font-weight:600; }
"""
    capture("actions", body, w, h, work, css)


def ring(work):
    w, h = 880, 420
    play = (CAPTURES / "ring-play.png").as_uri()
    lock = (CAPTURES / "ring-lock.png").as_uri()
    body = f"""
<div class="stage desk">
  <div class=grid></div>
  <div class=stamp><span class="tag alpha">Pre-alpha</span><span>Expect missed and extra taps while the ring is tuned.</span></div>
  <img class="ring r1" src='{play}'>
  <div class=step style="left:350px"><div class=mono>Tap · Tap</div><div class=arrow>→</div><div class=note>each tap moves one step clockwise</div></div>
  <img class="ring r2" src='{lock}'>
  <div class=step style="left:738px;text-align:left"><div class=mono>Double&#8209;tap</div><div class=note>runs the highlighted action</div></div>
  <div class=opens><span class=mono>Double&#8209;tap</span> opens the ring</div>
</div>"""
    css = """
.desk { background:
  radial-gradient(45% 60% at 26% 55%, rgba(127,211,247,.13), transparent 70%),
  radial-gradient(45% 60% at 70% 55%, rgba(185,166,255,.12), transparent 70%), var(--abyss); }
.stamp { position:absolute; left:36px; top:30px; display:flex; align-items:center; gap:12px;
  font-size:13px; color:var(--muted); }
.ring { position:absolute; top:84px; width:250px; height:250px;
  filter: drop-shadow(0 24px 40px rgba(0,0,0,.55)); }
.r1 { left:84px; } .r2 { left:470px; }
.step { position:absolute; top:168px; width:110px; text-align:center; }
.step .mono { font:700 11px ui-monospace, "SF Mono", Menlo, monospace; letter-spacing:.14em; color:var(--violet); }
.step .arrow { font-size:26px; color:var(--violet); line-height:1.1; }
.step .note { font-size:12px; color:var(--muted); margin-top:4px; }
.opens { position:absolute; left:84px; top:352px; width:250px; text-align:center; font-size:12px; color:var(--muted); }
.opens .mono { font:700 11px ui-monospace, "SF Mono", Menlo, monospace; letter-spacing:.14em; color:var(--cyan); margin-right:4px; }
"""
    capture("ring", body, w, h, work, css)


def live(work):
    w, h = 880, 560
    legend = [
        ("cyan", "Motion", "Everything the sensor feels: taps, typing, a bumped desk."),
        ("violet", "Light-tap impulse", "The sharp start of a tap, picked out of the motion."),
        ("gold", "Threshold", "A tap has to rise above it. Drag it, or choose Set for light taps."),
    ]
    items = "".join(f"<li><i class='{c}'></i><div><b>{t}</b><span>{d}</span></div></li>" for c, t, d in legend)
    body = f"""
<div class=stage>
  <div class=grid></div>
  <div class="window" style="left:36px;top:36px">{shot("live", 0, 0, 1000, 976, 0.5)}</div>
  <div class=col>
    <div class=eyebrow>Live, at 800 Hz</div>
    <ul>{items}</ul>
    <div class=modes>
      <div class=mode><b>Active</b><span>runs your action</span></div>
      <div class=mode><b>Test</b><span>shows what would run</span></div>
      <div class=mode><b>Paused</b><span>stops listening</span></div>
    </div>
  </div>
</div>"""
    css = """
.col { position:absolute; left:576px; top:58px; width:270px; }
ul { list-style:none; margin-top:18px; }
li { display:flex; gap:14px; padding:13px 0; border-top:1px solid rgba(234,242,248,.09); }
li i { flex:none; width:22px; height:3px; margin-top:8px; border-radius:2px; }
li i.cyan { background:var(--cyan); box-shadow:0 0 8px rgba(127,211,247,.7); }
li i.violet { background:var(--violet); }
li i.gold { background:repeating-linear-gradient(90deg, var(--gold) 0 5px, transparent 5px 8px); }
li b { display:block; font-weight:600; font-size:14px; }
li span { display:block; font-size:12.5px; color:var(--muted); margin-top:2px; }
.modes { margin-top:22px; display:grid; gap:0; border-top:1px solid rgba(234,242,248,.09); padding-top:16px; }
.mode { display:flex; justify-content:space-between; font-size:12.5px; padding:5px 0; }
.mode b { font-weight:600; } .mode span { color:var(--muted); }
"""
    capture("live", body, w, h, work, css)


def calibrate(work):
    w, h = 880, 440
    steps = [
        "Everyday desk activity: typing, leaning, moving things",
        "Leg and table movement",
        "Light taps and knocks, one at a time",
        "The same, in pairs",
        "A fresh round that checks the new settings",
    ]
    items = "".join(f"<li><span class=n>{i}</span><span>{s}</span></li>" for i, s in enumerate(steps, 1))
    body = f"""
<div class=stage>
  <div class=grid></div>
  <div class="window" style="left:36px;top:36px">{shot("calibrate", 0, 0, 1000, 736, 0.5)}</div>
  <div class=col>
    <div class=eyebrow>About two minutes</div>
    <ol>{items}</ol>
    <p>Only a profile that passes the check is applied. Nothing leaves your Mac.</p>
  </div>
</div>"""
    css = """
.col { position:absolute; left:576px; top:60px; width:270px; }
ol { list-style:none; margin-top:18px; }
li { display:flex; gap:12px; padding:10px 0; border-top:1px solid rgba(234,242,248,.09); font-size:13.5px; }
li:last-child { border-bottom:1px solid rgba(234,242,248,.09); }
.n { flex:none; width:16px; font:600 12px ui-monospace, "SF Mono", Menlo, monospace; color:var(--cyan); padding-top:1px; }
.col p { margin-top:16px; font-size:12.5px; color:var(--muted); }
"""
    capture("calibrate", body, w, h, work, css)


def terminal(work):
    w, h = 880, 470
    rows = [
        ("c", "✓", "Checked this Mac", "macOS 27.0.1 · Apple M3 Pro"),
        ("c", "✓", "Found the motion sensor", "built-in accelerometer"),
        ("c", "✓", "Found Tap That Mac 0.1.0-beta.1", "released Oct 20 · 3.5 MB"),
        ("c", "✓", "Downloaded", "3.5 MB"),
        ("c", "✓", "Verified the download", "SHA-256 matches"),
        ("c", "✓", "Installed", "/Applications/Tap That Mac.app"),
        ("c", "✓", "Opened Tap That Mac", ""),
    ]
    lines = "".join(f"<div><span class={k}>{g}</span>  <span class=lbl>{l}</span><span class=dim>{d}</span></div>"
                    for k, g, l, d in rows)
    body = f"""
<div class=stage>
  <div class=term>
    <div class=bar><i></i><i></i><i></i><span>Terminal — zsh</span></div>
    <pre><span class=dim>$</span> curl -fsSL https://raw.githubusercontent.com/0xgeorgemathew/TapThatMac/main/install.sh | bash

<span class=c>        ▅       ▅</span>
<span class=c>        █       █</span>
<span class=g>┄┄┄┄┄┄┄┄</span><span class=c>█</span><span class=g>┄┄┄┄┄┄┄</span><span class=c>█</span><span class=g>┄┄┄┄┄┄┄┄</span>    <b>Tap That Mac</b>
<span class="c dimc">▁▂▁▁▂▃▅▆</span><span class=c>█</span><span class="c dimc">▅▂▁▂▃▆▇</span><span class=c>█</span><span class="c dimc">▄▂▁▁▂▁▁▂</span>    <span class=dim>Double-tap your Mac.</span>

{lines}
<b>Tap That Mac is open. Three things left:</b>

<span class=c>1</span>  Allow Accessibility, so a double-tap can run an action.
<span class=c>2</span>  Allow Input Monitoring, so taps while you type are ignored.
<span class=c>3</span>  In Actions, choose what a double-tap does. Lock Mac is a good first pick.</pre>
  </div>
</div>"""
    css = """
.stage { background: radial-gradient(60% 80% at 80% 0%, rgba(127,211,247,.12), transparent 70%), var(--abyss); }
.term { position:absolute; left:36px; top:30px; right:36px; bottom:30px; border-radius:11px; overflow:hidden;
  background:#0B0F14; box-shadow: 0 0 0 .5px rgba(255,255,255,.16), 0 28px 60px rgba(0,0,0,.55); }
.bar { height:30px; display:flex; align-items:center; gap:8px; padding:0 12px; background:#151A21;
  border-bottom:1px solid rgba(255,255,255,.06); }
.bar i { width:11px; height:11px; border-radius:50%; background:#FF5F57; }
.bar i:nth-child(2) { background:#FEBC2E; } .bar i:nth-child(3) { background:#28C840; }
.bar span { margin-left:auto; margin-right:auto; font-size:11.5px; color:rgba(234,242,248,.5); transform:translateX(-24px); }
pre { padding:14px 18px; font:12px/1.5 ui-monospace, "SF Mono", Menlo, monospace; color:#E6EDF3; white-space:pre; }
pre div { display:block; }
.lbl { display:inline-block; width:34ch; }
.c { color:var(--cyan); } .g { color:var(--gold); } .dim { color:rgba(230,237,243,.5); } .dimc { opacity:.55; }
b { font-weight:700; }
"""
    capture("terminal", body, w, h, work, css)


def main():
    if not Path(CHROME).exists():
        sys.exit("Google Chrome is needed to render the README images.")
    missing = [n for n in ("live", "actions", "ring-play", "ring-lock", "calibrate") if not (CAPTURES / f"{n}.png").exists()]
    if missing:
        sys.exit(f"Missing window captures in media/captures/: {', '.join(missing)}")
    only = set(sys.argv[1:])
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        for render in (hero, actions, ring, live, calibrate, terminal):
            if not only or render.__name__ in only:
                render(work)


if __name__ == "__main__":
    main()
