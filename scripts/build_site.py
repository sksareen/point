# /// script
# requires-python = ">=3.10"
# dependencies = ["markdown>=3.5"]
# ///
"""Build the blog, RSS feed, and sitemap into site/.

    uv run scripts/build_site.py

Posts are Markdown files in blog/ with a front-matter block:

    ---
    title: How to show Claude Code exactly what you mean
    description: One or two sentences for search results and link previews.
    date: 2026-11-18
    slug: show-claude-code-what-you-mean   (optional; defaults to the file name)
    draft: true                            (optional; drafts are skipped)
    image: /blog-images/cover.png          (optional; cover and link-preview image)
    ---

Generated files are committed; Vercel serves site/ as static files.
"""

from __future__ import annotations

import datetime as dt
import html
import pathlib
import re
import shutil
from email.utils import format_datetime

import markdown

ROOT = pathlib.Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
POSTS_SRC = ROOT / "blog"
OUT = SITE / "blog"
BASE = "https://www.pointandtell.app"

# Pages outside the blog that belong in the sitemap.
STATIC_PAGES = [("index.html", "/"), ("roadmap.html", "/roadmap.html")]


def parse(path: pathlib.Path) -> dict | None:
    text = path.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    if not m:
        raise SystemExit(f"{path.name}: missing front matter")
    meta: dict = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            meta[k.strip()] = v.strip()
    if meta.get("draft", "").lower() == "true":
        return None
    for key in ("title", "description", "date"):
        if not meta.get(key):
            raise SystemExit(f"{path.name}: front matter needs {key}")
    meta["slug"] = meta.get("slug") or path.stem
    meta["date_obj"] = dt.date.fromisoformat(meta["date"])
    meta["body_md"] = m.group(2).strip() + "\n"
    meta["body_html"] = markdown.markdown(meta["body_md"], extensions=["fenced_code", "tables", "sane_lists"])
    meta["src"] = path
    return meta


THEME_HEAD = """<script>
  (function () {
    try {
      var t = localStorage.getItem("point-theme");
      if (t === "light" || t === "dark") document.documentElement.setAttribute("data-theme", t);
    } catch (e) {}
  })();
</script>"""

THEME_TAIL = """<script>
(function () {
  function currentTheme() {
    var t = document.documentElement.getAttribute("data-theme");
    if (t) return t;
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }
  function toggleTheme() {
    var next = currentTheme() === "dark" ? "light" : "dark";
    document.documentElement.setAttribute("data-theme", next);
    try { localStorage.setItem("point-theme", next); } catch (e) {}
  }
  document.getElementById("themeBtn").addEventListener("click", toggleTheme);
  window.addEventListener("keydown", function (e) {
    if ((e.metaKey || e.ctrlKey) && !e.shiftKey && !e.altKey && e.key.toLowerCase() === "i") {
      e.preventDefault();
      toggleTheme();
    }
  });
})();
</script>"""

STYLE = """<style>
  .post { max-width: 720px; padding-top: 32px; padding-bottom: 72px; }
  .post h1 { font-size: clamp(2rem, 5vw, 2.8rem); letter-spacing: -0.03em; line-height: 1.08; margin: 0 0 12px; }
  .post .meta { color: var(--muted); font-size: 0.95rem; margin: 0 0 36px; }
  .post img.cover { display: block; width: 100%; margin: -12px 0 32px; }
  .post h2 { font-size: 1.5rem; letter-spacing: -0.02em; margin: 44px 0 10px; }
  .post h3 { font-size: 1.15rem; margin: 32px 0 8px; }
  .post p, .post li { font-size: 1.08rem; }
  .post img, .post video { max-width: 100%; height: auto; border-radius: 12px; border: 1px solid var(--line); }
  .post pre { background: var(--term); color: var(--term-ink); padding: 14px 16px; border-radius: 10px; overflow-x: auto; font-size: 0.92rem; }
  .post blockquote { margin: 20px 0; padding: 4px 0 4px 18px; border-left: 3px solid var(--loop); color: var(--muted); }
  .post table { border-collapse: collapse; width: 100%; font-size: 0.98rem; }
  .post th, .post td { text-align: left; padding: 8px 10px; border-bottom: 1px solid var(--line); vertical-align: top; }
  .cta { margin-top: 48px; padding: 20px 22px; border: 1px solid var(--line); border-radius: 14px; background: var(--window); }
  .cta p { margin: 0 0 12px; }
  .cta a.btn { display: inline-block; background: var(--loop); color: #fff; font-weight: 700; text-decoration: none; padding: 10px 16px; border-radius: 999px; }
  .posts { list-style: none; padding: 0; margin: 24px 0 0; border-top: 1.5px solid var(--ink); }
  .posts li { padding: 20px 0; border-bottom: 1px solid var(--line); }
  .posts a { font-size: 1.25rem; font-weight: 700; text-decoration: none; }
  .posts a:hover { text-decoration: underline; }
  .posts p { margin: 4px 0 0; color: var(--muted); }
  .posts time { color: var(--muted); font-size: 0.9rem; }
</style>"""


def page(*, title: str, description: str, canonical: str, body: str, og_type: str = "website",
         extra_head: str = "", image: str = "/og.png") -> str:
    t, d = html.escape(title), html.escape(description)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{t}</title>
<meta name="description" content="{d}">
<link rel="canonical" href="{canonical}">
<meta property="og:title" content="{t}">
<meta property="og:description" content="{d}">
<meta property="og:type" content="{og_type}">
<meta property="og:url" content="{canonical}">
<meta property="og:image" content="{BASE}{image}">
<meta name="twitter:card" content="summary_large_image">
<link rel="alternate" type="application/rss+xml" title="Point blog" href="{BASE}/blog/feed.xml">
<link rel="icon" type="image/png" href="/icon.png">
<link rel="apple-touch-icon" href="/icon.png">
{THEME_HEAD}
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Caveat:wght@600&family=Schibsted+Grotesk:wght@400;500;700;800&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/style.css">
{STYLE}
{extra_head}
</head>
<body>
<header class="wrap nav">
  <a class="brand" href="/">
    <img src="/icon.png" alt="" width="28" height="28">
    Point
  </a>
  <nav class="nav-links" aria-label="Primary">
    <a href="/blog/">Blog</a>
    <a href="/roadmap.html">Roadmap</a>
    <a href="https://github.com/sksareen/point">GitHub</a>
    <button class="theme-btn" id="themeBtn" type="button" aria-label="Toggle dark mode (⌘I)" title="Toggle dark mode (⌘I)">◐</button>
  </nav>
</header>
<main class="wrap">
{body}
</main>
<footer>
  <div class="wrap">
    <span>Point is free and open source under the MIT license.</span>
    <a href="/blog/feed.xml">RSS</a>
  </div>
</footer>
{THEME_TAIL}
</body>
</html>
"""


CTA = """<div class="cta">
  <p><strong>Point</strong> is a free, open-source Mac app: hold a key, talk, and circle what you mean. Your agent gets your words plus a screenshot of exactly what you circled.</p>
  <a class="btn" href="https://github.com/sksareen/point/releases/latest/download/Point.dmg">Download free for Mac</a>
</div>"""


def human_date(d: dt.date) -> str:
    return f"{d.strftime('%B')} {d.day}, {d.year}"


def build() -> None:
    posts = sorted(
        (p for p in (parse(f) for f in sorted(POSTS_SRC.glob("*.md"))) if p),
        key=lambda p: p["date_obj"], reverse=True,
    )
    if OUT.exists():
        shutil.rmtree(OUT)

    if posts:
        OUT.mkdir(parents=True)
        for p in posts:
            url = f"{BASE}/blog/{p['slug']}.html"
            ld = (
                '<script type="application/ld+json">'
                + __import__("json").dumps({
                    "@context": "https://schema.org", "@type": "BlogPosting",
                    "headline": p["title"], "description": p["description"],
                    "datePublished": p["date"], "url": url,
                    "author": {"@type": "Person", "name": "Savar Sareen"},
                    "publisher": {"@type": "Organization", "name": "Point", "url": BASE},
                })
                + "</script>"
            )
            cover = (f'<img class="cover" src="{p["image"]}" alt="">\n' if p.get("image") else "")
            body = (f'<article class="post">\n<h1>{html.escape(p["title"])}</h1>\n'
                    f'<p class="meta"><time datetime="{p["date"]}">{human_date(p["date_obj"])}</time></p>\n'
                    f'{cover}{p["body_html"]}\n{CTA}\n</article>')
            (OUT / f"{p['slug']}.html").write_text(
                page(title=f"{p['title']} · Point", description=p["description"], canonical=url,
                     body=body, og_type="article", extra_head=ld,
                     image=p.get("image") or "/og.png"), encoding="utf-8")
            # Plain Markdown twin, for agents and llms.txt.
            (OUT / f"{p['slug']}.md").write_text(f"# {p['title']}\n\n{p['body_md']}", encoding="utf-8")

        items = "\n".join(
            f'  <li><time datetime="{p["date"]}">{human_date(p["date_obj"])}</time><br>'
            f'<a href="/blog/{p["slug"]}.html">{html.escape(p["title"])}</a>'
            f'<p>{html.escape(p["description"])}</p></li>' for p in posts)
        (OUT / "index.html").write_text(page(
            title="Point blog", canonical=f"{BASE}/blog/",
            description="Notes on building Point, and on showing AI agents exactly what you mean.",
            body=f'<section class="post"><h1>Blog</h1><p class="meta">Notes on building Point, and on showing AI agents exactly what you mean.</p>\n<ul class="posts">\n{items}\n</ul></section>'),
            encoding="utf-8")

        now = format_datetime(dt.datetime.now(dt.timezone.utc))
        rss_items = "\n".join(
            f"""    <item>
      <title>{html.escape(p['title'])}</title>
      <link>{BASE}/blog/{p['slug']}.html</link>
      <guid>{BASE}/blog/{p['slug']}.html</guid>
      <pubDate>{format_datetime(dt.datetime.combine(p['date_obj'], dt.time(16), dt.timezone.utc))}</pubDate>
      <description>{html.escape(p['description'])}</description>
    </item>""" for p in posts)
        (OUT / "feed.xml").write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Point blog</title>
    <link>{BASE}/blog/</link>
    <description>Notes on building Point, and on showing AI agents exactly what you mean.</description>
    <lastBuildDate>{now}</lastBuildDate>
{rss_items}
  </channel>
</rss>
""", encoding="utf-8")

    urls = [(f"{BASE}{path}", dt.date.fromtimestamp((SITE / f).stat().st_mtime).isoformat())
            for f, path in STATIC_PAGES]
    if posts:
        urls.append((f"{BASE}/blog/", posts[0]["date"]))
        urls += [(f"{BASE}/blog/{p['slug']}.html", p["date"]) for p in posts]
    body = "\n".join(f"  <url><loc>{u}</loc><lastmod>{d}</lastmod></url>" for u, d in urls)
    (SITE / "sitemap.xml").write_text(
        f'<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n{body}\n</urlset>\n',
        encoding="utf-8")
    print(f"{len(posts)} post(s); sitemap has {len(urls)} URL(s)")


if __name__ == "__main__":
    build()
