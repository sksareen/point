// Receives feedback sent from the Point app and files it as an issue in a private GitHub repo.
//
// POST /api/feedback   (JSON)
//   message      string, required
//   email        string, optional
//   app_version  string     os_version  string     trigger_key  string
//   capture      optional { transcript, app, kind, created_at, engine, locale, audio_seconds, timings_ms }
//   screenshot   optional base64 JPEG (the app downsizes it), only if the user ticked the box
//
// Needs GITHUB_FEEDBACK_TOKEN in the Vercel project: a fine-grained token limited to the
// feedback repo, with Issues and Contents set to read and write.

const REPO = process.env.FEEDBACK_REPO || "sksareen/point-feedback";
const MAX_MESSAGE = 5000;
const MAX_SCREENSHOT_B64 = 3_500_000; // ~2.6 MB of image; Vercel caps a request body at 4.5 MB

const clip = (v, n) => (typeof v === "string" ? v.slice(0, n) : "");
// User text goes into fenced blocks so it can't @mention anyone or inject markup.
const fence = (text) => "````text\n" + String(text).replace(/````/g, "` ` ` `") + "\n````";

async function github(path, method, body) {
  const res = await fetch(`https://api.github.com/repos/${REPO}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${process.env.GITHUB_FEEDBACK_TOKEN}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "point-feedback",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`GitHub ${method} ${path}: ${res.status}`);
  return res.json();
}

module.exports = async (req, res) => {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "method_not_allowed" });
  }
  if (!process.env.GITHUB_FEEDBACK_TOKEN) {
    return res.status(503).json({ error: "not_configured" });
  }
  const body = req.body && typeof req.body === "object" ? req.body : null;
  // Only the app sends this header. It isn't a secret, it just keeps out drive-by form posts.
  if (!body || req.headers["x-point-client"] !== "point-app") {
    return res.status(400).json({ error: "bad_request" });
  }
  const message = clip(body.message, MAX_MESSAGE).trim();
  if (!message) return res.status(400).json({ error: "message_required" });

  const email = clip(body.email, 200).trim();
  const cap = body.capture && typeof body.capture === "object" ? body.capture : null;
  const id = Date.now().toString(36) + Math.random().toString(36).slice(2, 6);

  try {
    let shotLine = "";
    if (typeof body.screenshot === "string" && body.screenshot.length > 0) {
      if (body.screenshot.length > MAX_SCREENSHOT_B64 || !/^[A-Za-z0-9+/=]+$/.test(body.screenshot)) {
        return res.status(400).json({ error: "bad_screenshot" });
      }
      const path = `screenshots/${id}.jpg`;
      await github(`/contents/${path}`, "PUT", { message: `Screenshot for feedback ${id}`, content: body.screenshot });
      shotLine = `\n**Screenshot:** [${path}](https://github.com/${REPO}/blob/main/${path})\n`;
    }

    const lines = [
      fence(message),
      "",
      `**Point:** ${clip(body.app_version, 60) || "?"} · **macOS:** ${clip(body.os_version, 60) || "?"} · **Key:** ${clip(body.trigger_key, 40) || "?"}`,
    ];
    if (email) lines.push("", "**Reply to:**", fence(email));
    if (cap) {
      const t = cap.timings_ms && typeof cap.timings_ms === "object" ? cap.timings_ms : {};
      const timings = Object.entries(t)
        .filter(([k, v]) => /^[a-z_]{1,40}$/.test(k) && Number.isFinite(v))
        .map(([k, v]) => `${k}=${Math.round(v)}ms`)
        .join(" · ");
      lines.push(
        "",
        "### Attached capture",
        `**Kind:** ${clip(cap.kind, 30) || "?"} · **App:** ${clip(cap.app, 80).replace(/[^\w .\-]/g, "") || "?"} · **When:** ${clip(cap.created_at, 40).replace(/[^\dTZ:.\-+]/g, "") || "?"}`,
        `**Engine:** ${clip(cap.engine, 40).replace(/[^\w.\-]/g, "") || "?"} · **Locale:** ${clip(cap.locale, 20).replace(/[^\w\-]/g, "") || "?"} · **Audio:** ${Number.isFinite(cap.audio_seconds) ? cap.audio_seconds + "s" : "?"}`,
        timings ? `**Timings:** ${timings}` : "",
        "",
        "**What Point heard:**",
        fence(clip(cap.transcript, 4000) || "(nothing)"),
        shotLine
      );
    }

    const title = message.replace(/\s+/g, " ").replace(/[@#`<>\[\]]/g, "").slice(0, 70) || "Feedback";
    await github("/issues", "POST", { title, body: lines.filter((l) => l !== undefined).join("\n") });
    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error("feedback failed:", err.message);
    return res.status(502).json({ error: "upstream_failed" });
  }
};
