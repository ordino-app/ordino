"""Render the website's hero desktop (scattered windows -> Master + Stack -> undo) to docs/media/demo.gif and .mp4.

    python3 scripts/demo-gif.py

Needs Python Playwright with Chromium and ffmpeg. The animation is stepped frame by frame
(CSS transitions paused, currentTime set), so the result is the same on every run.
"""
import pathlib, shutil, subprocess, tempfile
from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "media"
FPS = 25
STEP = 1000 / FPS
MOVE_MS = 640 + 120  # longest transition (.win) plus the last window's delay

def capture(page, desk, hud_key, hud_text, frames_dir, start):
    """Screenshot the arrange transition, scattered -> arranged, with the HUD showing hud_key."""
    page.evaluate("""([k, t]) => {
        const d = document.querySelector('[data-desk]');
        d.querySelector('.hud .kbd').textContent = k;
        d.querySelector('.hud span:last-child').textContent = t;
        d.querySelector('.hud').style.transition = 'none';
        d.classList.add('is-scattered', 'is-hud');
        d.offsetWidth;
        d.classList.remove('is-scattered');
        document.getAnimations().forEach(a => a.pause());
    }""", [hud_key, hud_text])
    n, t = start, 0.0
    while t <= MOVE_MS + STEP:
        page.evaluate("ms => document.getAnimations().forEach(a => a.currentTime = ms)", t)
        desk.screenshot(path=str(frames_dir / f"{n:04d}.png"))
        n += 1
        t += STEP
    page.evaluate("() => document.getAnimations().forEach(a => a.finish())")
    return list(range(start, n))

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = pathlib.Path(tempfile.mkdtemp())
    raw, seq = tmp / "raw", tmp / "seq"
    raw.mkdir(); seq.mkdir()
    with sync_playwright() as p:
        b = p.chromium.launch()
        page = b.new_page(viewport={"width": 1280, "height": 900}, device_scale_factor=2, java_script_enabled=False)
        page.goto((ROOT / "web" / "index.html").as_uri())
        page.wait_for_load_state("networkidle")
        desk = page.locator("[data-desk]")
        page.evaluate("() => { const d = document.querySelector('[data-desk]'); d.classList.add('is-scattered'); d.classList.remove('is-hud'); }")
        desk.screenshot(path=str(raw / "scattered.png"))
        fwd = capture(page, desk, "⌥⌘A", "Master + Stack · 3 windows", raw, 0)
        page.evaluate("() => document.querySelector('[data-desk]').classList.remove('is-hud')")
        desk.screenshot(path=str(raw / "arranged.png"))
        und = capture(page, desk, "⌥⌘Z", "Undo", raw, 1000)
        b.close()

    # storyboard: messy desk -> press -> windows fly -> calm -> undo -> messy again (loops)
    f = lambda i: raw / f"{i:04d}.png"
    frames = []
    frames += [raw / "scattered.png"] * int(FPS * 1.2)
    frames += [f(fwd[0])] * int(FPS * 0.5)            # HUD appears before the windows move
    frames += [f(i) for i in fwd]
    frames += [f(fwd[-1])] * int(FPS * 0.8)
    frames += [raw / "arranged.png"] * int(FPS * 1.6)
    frames += [f(und[-1])] * int(FPS * 0.5)           # Undo HUD on the tidy desk
    frames += [f(i) for i in reversed(und)]
    frames += [f(und[0])] * int(FPS * 0.4)
    for i, src in enumerate(frames):
        shutil.copy(src, seq / f"{i:04d}.png")

    src = ["-framerate", str(FPS), "-i", str(seq / "%04d.png")]
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *src, "-vf",
                    "scale=880:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];"
                    "[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle",
                    "-loop", "0", str(OUT / "demo.gif")], check=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *src, "-vf", "scale=1760:-2:flags=lanczos",
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", "-movflags", "+faststart",
                    str(OUT / "demo.mp4")], check=True)
    shutil.rmtree(tmp)
    for name in ("demo.gif", "demo.mp4"):
        print(name, (OUT / name).stat().st_size // 1024, "KB")

if __name__ == "__main__":
    main()
