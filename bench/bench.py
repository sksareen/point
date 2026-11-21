# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Does a marked screenshot help a coding agent change the right element?

    uv run bench/bench.py shots      # render one marked screenshot per task
    uv run bench/bench.py describe   # a model writes two words-only requests per task
    uv run bench/bench.py run [N]    # run every task x condition N times (default 1)
    uv run bench/bench.py report     # summarize results/

The page in app/ is full of lookalike elements. Each task asks for a change to ONE
of them. Three ways of asking:

  vague      "Make this button green."                     (what you'd say while pointing, alone)
  short      a words-only request of at most 8 words, written by a model that saw the
             marked screenshot and was told no screenshot would be attached
  described  the same, with up to 25 words
  pointed    the vague sentence + [Screenshot: path] with a red loop on the target
             (exactly what Point pastes into a terminal)

A run is a HIT when the target changed and no lookalike did, judged from computed
styles in headless Chrome. See README.md for limits.
"""
from __future__ import annotations

import concurrent.futures as cf
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time

from PIL import Image, ImageDraw

HERE = pathlib.Path(__file__).resolve().parent
APP = HERE / "app"
SHOTS = HERE / "shots"
RESULTS = HERE / "results"
TASKS = json.loads((HERE / "tasks.json").read_text())
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
MODEL = "sonnet"
VIEW = (1440, 900)
LOOP = (255, 46, 64)
CONDITIONS = ("vague", "short", "described", "pointed")
FIND = "function __find(s){if(s.indexOf('text:')===0){var p=s.split(':');var tag=p[1];var txt=p.slice(2).join(':');return Array.prototype.find.call(document.querySelectorAll(tag),function(e){return e.textContent.indexOf(txt)>=0;})||null;}return document.querySelector(s);}"


def chrome(*args: str) -> str:
    r = subprocess.run([CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
                        f"--window-size={VIEW[0]},{VIEW[1]}", "--virtual-time-budget=2000", *args],
                       capture_output=True, text=True, timeout=90)
    return r.stdout


def with_script(src_dir: pathlib.Path, js: str) -> pathlib.Path:
    """Copy the app into a temp dir with a script appended to index.html."""
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="pointbench-"))
    shutil.copytree(src_dir, tmp / "app")
    page = tmp / "app" / "index.html"
    html = page.read_text()
    tag = f'<pre id="__out" hidden></pre><script>window.addEventListener("load",function(){{{js}}});</script>'
    html = html.replace("</body>", tag + "</body>") if "</body>" in html else html + tag
    page.write_text(html)
    return tmp


def read_out(dom: str):
    m = re.search(r'<pre id="__out"[^>]*>(.*?)</pre>', dom, re.S)
    if not m:
        return None
    import html as h
    return json.loads(h.unescape(m.group(1)))


def probe(app_dir: pathlib.Path) -> dict:
    """Probe value of every candidate of every task. A missing element reads 'MISSING'."""
    spec = [{"id": t["id"], "c": t["candidates"], "p": t["probe"]} for t in TASKS]
    js = (FIND + "var spec=" + json.dumps(spec) + ";var out={};spec.forEach(function(t){out[t.id]=t.c.map(function(s){"
          "var el=__find(s);if(!el)return'MISSING';try{return String(new Function('el','return '+t.p)(el));}"
          "catch(e){return'ERR';}});});document.getElementById('__out').textContent=JSON.stringify(out);")
    tmp = with_script(app_dir, js)
    try:
        return read_out(chrome("--dump-dom", f"file://{tmp}/app/index.html")) or {}
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def shots() -> None:
    """One marked screenshot per task: a 1440x900 view of the page with a red loop on the target.
    The page is rendered in one tall window (no scrolling) and cropped around the target."""
    SHOTS.mkdir(exist_ok=True)
    tall = 3000
    for t in TASKS:
        sel = t["candidates"][t["target"]]
        js = (FIND + "var el=__find(" + json.dumps(sel) + ");"
              "var r;if(el.children.length===0){var g=document.createRange();g.selectNodeContents(el);r=g.getBoundingClientRect();}"
              "else{r=el.getBoundingClientRect();}document.getElementById('__out').textContent="
              "JSON.stringify([r.left,r.top,r.width,r.height,document.documentElement.scrollHeight]);")
        tmp = with_script(APP, js)
        try:
            url = f"file://{tmp}/app/index.html"
            size = f"--window-size={VIEW[0]},{tall}"
            x, y, w, h, page_h = read_out(chrome(size, "--dump-dom", url))
            raw = tmp / "raw.png"
            chrome(size, f"--screenshot={raw}", url)
            img = Image.open(raw).convert("RGB")
            pad_x, pad_y = max(14, w * 0.12), max(12, h * 0.35)
            ImageDraw.Draw(img).ellipse([x - pad_x, y - pad_y, x + w + pad_x, y + h + pad_y], outline=LOOP, width=5)
            top = int(min(max(0, y + h / 2 - VIEW[1] / 2), max(0, min(page_h, img.height) - VIEW[1])))
            img.crop((0, top, VIEW[0], top + VIEW[1])).save(SHOTS / f"{t['id']}.png")
            print(f"{t['id']}: target at ({x:.0f},{y:.0f}) {w:.0f}x{h:.0f}")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


def claude(prompt: str, cwd: pathlib.Path, tools: str, add_dir: pathlib.Path | None = None) -> str:
    cmd = ["claude", "-p", prompt, "--safe-mode", "--model", MODEL, "--allowedTools", tools,
           "--no-session-persistence"]
    if add_dir:
        cmd += ["--add-dir", str(add_dir)]
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=300)
        return (r.stdout or "").strip() or (r.stderr or "").strip()
    except subprocess.TimeoutExpired:
        return "TIMEOUT"


DESCRIBE = """Look at the screenshot at {path}. One element has a red loop drawn around it.

You are a developer about to ask a coding agent for this change: "{say}"
The agent will NOT see the screenshot or the loop. Rewrite the request so the agent knows which
element you mean. Write it the way a busy developer types a quick message: one sentence, plain
words, at most {limit} words. Do not mention the screenshot or the loop. Reply with the sentence only."""


def describe() -> None:
    """Two words-only versions per task: 'short' (at most 8 words) and 'described' (at most 25)."""
    out = {"short": {}, "described": {}}
    def one(job):
        t, kind, limit = job
        tmp = pathlib.Path(tempfile.mkdtemp(prefix="pointbench-"))
        try:
            text = claude(DESCRIBE.format(path=SHOTS / f"{t['id']}.png", say=t["say"], limit=limit), tmp, "Read", SHOTS)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        return t["id"], kind, text.strip().strip('"')
    jobs = [(t, kind, limit) for t in TASKS for kind, limit in (("short", 8), ("described", 25))]
    with cf.ThreadPoolExecutor(6) as ex:
        for tid, kind, text in ex.map(one, jobs):
            out[kind][tid] = text
            print(f"{kind:10} {tid}: {text}")
    (HERE / "described.json").write_text(json.dumps(out, indent=2) + "\n")


def classify(task: dict, before: list, after: list) -> str:
    changed = [i for i, (b, a) in enumerate(zip(before, after)) if b != a]
    if not changed:
        return "no-change"
    if changed == [task["target"]]:
        return "hit"
    if task["target"] in changed:
        return "overbroad"
    return "wrong"


def run(repeats: int) -> None:
    described = json.loads((HERE / "described.json").read_text())
    baseline = probe(APP)
    RESULTS.mkdir(exist_ok=True)
    jobs = [(t, cond, n) for n in range(repeats) for t in TASKS for cond in CONDITIONS]

    def one(job):
        t, cond, n = job
        work = pathlib.Path(tempfile.mkdtemp(prefix="pointbench-"))
        shutil.copytree(APP, work / "site")
        if cond == "vague":
            prompt = t["say"]
        elif cond in ("short", "described"):
            prompt = described[cond][t["id"]]
        else:
            prompt = f"{t['say']}\n\n[Screenshot: {SHOTS / (t['id'] + '.png')}]"
        t0 = time.time()
        # Only the pointed condition may see the screenshots folder.
        reply = claude(prompt, work / "site", "Read,Edit,Write,Glob,Grep", SHOTS if cond == "pointed" else None)
        secs = round(time.time() - t0, 1)
        after = probe(work / "site").get(t["id"], [])
        outcome = classify(t, baseline[t["id"]], after) if after else "broken"
        shutil.rmtree(work, ignore_errors=True)
        rec = {"task": t["id"], "condition": cond, "run": n, "outcome": outcome, "seconds": secs,
               "prompt": prompt, "prompt_words": len(prompt.split("\n")[0].split()),
               "before": baseline[t["id"]], "after": after, "reply": reply[-600:]}
        print(f"{t['id']:16} {cond:10} run{n} -> {outcome} ({secs}s)", flush=True)
        return rec

    stamp = time.strftime("%Y%m%d-%H%M%S")
    with cf.ThreadPoolExecutor(6) as ex:
        recs = list(ex.map(one, jobs))
    path = RESULTS / f"run-{stamp}.json"
    path.write_text(json.dumps({"model": MODEL, "repeats": repeats, "records": recs}, indent=2) + "\n")
    print(f"saved {path}")
    report()


def report() -> None:
    recs = []
    for f in sorted(RESULTS.glob("run-*.json")):
        recs += json.loads(f.read_text())["records"]
    if not recs:
        print("no results yet")
        return
    print(f"\n{len(recs)} runs across {len({r['task'] for r in recs})} tasks\n")
    print(f"{'condition':11} {'hit':>4} {'wrong':>6} {'overbroad':>10} {'no-change':>10} {'broken':>7} {'total':>6} {'avg words':>10} {'avg secs':>9}")
    for cond in CONDITIONS:
        rs = [r for r in recs if r["condition"] == cond]
        c = lambda o: sum(1 for r in rs if r["outcome"] == o)
        words = sum(r["prompt_words"] for r in rs) / len(rs)
        secs = sum(r["seconds"] for r in rs) / len(rs)
        print(f"{cond:11} {c('hit'):>4} {c('wrong'):>6} {c('overbroad'):>10} {c('no-change'):>10} {c('broken'):>7} {len(rs):>6} {words:>10.1f} {secs:>9.1f}")
    print("\nper task (hits/runs):")
    for t in TASKS:
        row = []
        for cond in CONDITIONS:
            rs = [r for r in recs if r["condition"] == cond and r["task"] == t["id"]]
            row.append(f"{cond} {sum(r['outcome']=='hit' for r in rs)}/{len(rs)}")
        print(f"  {t['id']:16} " + "   ".join(row))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "report"
    if cmd == "shots": shots()
    elif cmd == "describe": describe()
    elif cmd == "run": run(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
    elif cmd == "probe": print(json.dumps(probe(APP), indent=1))
    else: report()
