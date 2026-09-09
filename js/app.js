/* Gnog Schedules v1 — private period & medication calendar. All data stays on this device. */
"use strict";

const VAPID_PUBLIC_KEY = "BNwow9ajpBeyM1n67mUt2-K-Q5BQ8oH_6U_zy1RoiV48AKGSqxxNtw1LGoMqpLxynfQUq7sKtoAY6v4pDfbfb0s";
const STORE_KEY = "gnog.v1";
const FLOWS = ["spotting", "light", "medium", "heavy"];
const FLOW_EMOJI = { spotting: "💧", light: "🩸", medium: "🩸🩸", heavy: "🩸🩸🩸" };
const MOODS = ["happy", "calm", "energetic", "anxious", "sad", "irritable", "tired", "cramps"];
const MOOD_EMOJI = { happy: "😊", calm: "😌", energetic: "⚡", anxious: "😟", sad: "😢", irritable: "😠", tired: "😴", cramps: "🤕" };

/* ---------- date utils (local-time safe) ---------- */
function fmt(d) {
  const p = (n) => String(n).padStart(2, "0");
  return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate());
}
function parse(s) {
  const [y, m, d] = s.split("-").map(Number);
  return new Date(y, m - 1, d);
}
function addDays(s, n) {
  const d = parse(s); d.setDate(d.getDate() + n); return fmt(d);
}
function diffDays(a, b) { // b - a in whole days
  return Math.round((parse(b) - parse(a)) / 86400000);
}
function todayStr() { return fmt(new Date()); }
function mod(n, m) { return ((n % m) + m) % m; }
function pretty(s) {
  return parse(s).toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short" });
}
function esc(s) {
  return String(s == null ? "" : s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

/* ---------- state ---------- */
function defaultState() {
  return {
    periodStarts: ["2026-09-07"],
    days: {},                       // "YYYY-MM-DD" -> {flow, moods:[], note}
    medGroups: [
      { id: "g-morning", name: "Morning", time: "08:00", meds: [
        { id: "m-prebiotic", name: "Prebiotic" },
        { id: "m-probiotic", name: "Probiotic" },
        { id: "m-iron", name: "Iron supplement" } ] },
      { id: "g-afternoon", name: "Afternoon", time: "13:30", meds: [
        { id: "m-liza", name: "Liza", packOnly: true },
        { id: "m-lexapro", name: "Lexapro" },
        { id: "m-abilify", name: "Abilify" } ] }
    ],
    taken: {},                      // "YYYY-MM-DD" -> {medId: true}
    packAnchor: "2026-09-12",        // day 1 of an active pack
    settings: { cycleLength: 28 }
  };
}
let S = load();
function load() {
  try {
    const raw = localStorage.getItem(STORE_KEY);
    if (!raw) return defaultState();
    const s = JSON.parse(raw);
    const d = defaultState();
    return Object.assign(d, s);
  } catch (e) { return defaultState(); }
}
function save() { localStorage.setItem(STORE_KEY, JSON.stringify(S)); }
function uid(p) { return p + "-" + Math.random().toString(36).slice(2, 8); }

/* ---------- pill pack logic ---------- */
// packAnchor = a "day 1 of active pills" date. Packs repeat every 28 days:
// idx 0..20 = active pill (day idx+1 of 21), idx 21..27 = placebo (day idx-20 of 7).
function packInfo(dateStr) {
  const idx = mod(diffDays(S.packAnchor, dateStr), 28);
  if (idx < 21) return { phase: "active", day: idx + 1, of: 21, idx };
  return { phase: "placebo", day: idx - 20, of: 7, idx };
}
function packPhaseLabel(dateStr) {
  const p = packInfo(dateStr);
  return p.phase === "active"
    ? "Pill day " + p.day + " of 21"
    : "Placebo day " + p.day + " of 7 — no Liza today";
}

/* ---------- cycle logic ---------- */
function avgCycleLength() {
  const ps = S.periodStarts.slice().sort();
  if (ps.length >= 2) {
    const gaps = [];
    for (let i = 1; i < ps.length; i++) gaps.push(diffDays(ps[i - 1], ps[i]));
    const recent = gaps.slice(-3);
    return Math.round(recent.reduce((a, b) => a + b, 0) / recent.length);
  }
  return S.settings.cycleLength || 28;
}
function lastPeriodStart() {
  const ps = S.periodStarts.slice().sort();
  return ps.length ? ps[ps.length - 1] : null;
}
function predictedNextPeriod() {
  const l = lastPeriodStart();
  return l ? addDays(l, avgCycleLength()) : null;
}
function periodDayNumber(dateStr) {
  // which day of the current bleed is dateStr? null if not in a bleed
  const ps = S.periodStarts.slice().sort();
  for (let i = ps.length - 1; i >= 0; i--) {
    const d = diffDays(ps[i], dateStr);
    if (d >= 0 && d < 8) {
      // confirm bleed continuity: flow logged on start, or within 7 days of start
      const startFlow = (S.days[ps[i]] || {}).flow;
      if (d === 0 || startFlow || S.days[dateStr]) return d + 1;
      if (d <= 6) return d + 1;
    }
    if (d < 0) continue;
    break;
  }
  return null;
}
function cyclePhase(dateStr) {
  const l = lastPeriodStart();
  if (!l) return "unknown";
  const d = mod(diffDays(l, dateStr), avgCycleLength());
  if (d < 7) return "menstrual";
  if (d < 14) return "follicular";
  if (d < 17) return "ovulation";
  return "luteal";
}

/* ---------- TODAY ---------- */
function medsFor(dateStr) {
  const p = packInfo(dateStr);
  const out = [];
  for (const g of S.medGroups) {
    const meds = g.meds.filter((m) => !(m.packOnly && p.phase === "placebo"));
    const skipped = g.meds.filter((m) => m.packOnly && p.phase === "placebo");
    out.push({ group: g, meds, skipped });
  }
  return out;
}
function streak() {
  // consecutive days (ending today, or yesterday if today isn't complete)
  // where every scheduled medication was marked taken
  let n = 0, d = todayStr();
  const sched0 = medsFor(d).flatMap((g) => g.meds);
  const tk0 = S.taken[d] || {};
  if (!(sched0.length && sched0.every((m) => tk0[m.id]))) d = addDays(d, -1);
  for (;;) {
    const s = medsFor(d).flatMap((g) => g.meds);
    const tk = S.taken[d] || {};
    if (s.length && s.every((m) => tk[m.id])) { n++; d = addDays(d, -1); }
    else break;
  }
  return n;
}
function renderToday() {
  const t = todayStr();
  document.getElementById("todayDate").textContent =
    parse(t).toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "long" });

  // hero card: pack progress ring + period status + streak
  const p = packInfo(t);
  const pdn = periodDayNumber(t);
  const next = predictedNextPeriod();
  let periodLine;
  if (pdn) periodLine = "🩸 Day " + pdn + " of your period";
  else if (next) {
    const n = diffDays(t, next);
    periodLine = "📅 Period expected " + (n === 0 ? "today" : n === 1 ? "tomorrow" : "in " + n + " days");
  } else periodLine = "📅 Log a period to see predictions";
  const frac = p.day / p.of;
  const CIRC = 2 * Math.PI * 44;
  const st = streak();
  document.getElementById("heroCard").innerHTML =
    '<div class="hero-ring" role="img" aria-label="' + esc(packPhaseLabel(t)) + '">' +
    '<svg width="104" height="104" viewBox="0 0 104 104">' +
    '<circle class="ring-bg" cx="52" cy="52" r="44" fill="none" stroke-width="9"/>' +
    '<circle class="ring-fg" cx="52" cy="52" r="44" fill="none" stroke-width="9" ' +
    'stroke-dasharray="' + CIRC.toFixed(1) + '" stroke-dashoffset="' + (CIRC * (1 - frac)).toFixed(1) + '"/>' +
    '</svg><div class="hero-center"><span class="hero-num">' + p.day + '</span>' +
    '<span class="hero-sub">of ' + p.of + '</span></div></div>' +
    '<div class="hero-info"><h2>' + (p.phase === "active" ? "Active pills" : "Placebo week") + '</h2>' +
    '<p>' + periodLine + '</p>' +
    '<p>' + (p.phase === "active" ? "💊 Pill day " + p.day + " of 21" : "💊 No Liza until the next pack") + '</p>' +
    (st > 0 ? '<span class="hero-streak">🔥 ' + st + '-day streak</span>' : '') + '</div>';

  // med lists
  const wrap = document.getElementById("medLists");
  const taken = S.taken[t] || {};
  wrap.innerHTML = "";
  for (const { group, meds, skipped } of medsFor(t)) {
    const box = document.createElement("div");
    box.className = "med-group";
    const done = meds.filter((m) => taken[m.id]).length;
    box.innerHTML = '<div class="med-group-head"><h2>' + esc(group.name) + "</h2>" +
      '<span class="med-time">' + esc(group.time) + " · " + done + "/" + meds.length + "</span></div>";
    for (const m of meds) {
      const b = document.createElement("button");
      b.className = "med-item" + (taken[m.id] ? " taken" : "");
      b.innerHTML = '<span class="check">' + (taken[m.id] ? "✓" : "") + "</span>" +
        '<span class="med-name">' + esc(m.name) + "</span>";
      b.onclick = () => toggleTaken(t, m.id);
      box.appendChild(b);
    }
    if (skipped.length) {
      const s = document.createElement("div");
      s.className = "med-skip";
      s.textContent = "⏸ " + skipped.map((m) => m.name).join(", ") + " skipped — placebo week";
      box.appendChild(s);
    }
    wrap.appendChild(box);
  }

  // log form
  renderChips();
  const day = S.days[t] || {};
  document.getElementById("dayNote").value = day.note || "";
  document.getElementById("savedHint").hidden = true;
}
function toggleTaken(dateStr, medId) {
  S.taken[dateStr] = S.taken[dateStr] || {};
  if (S.taken[dateStr][medId]) delete S.taken[dateStr][medId];
  else S.taken[dateStr][medId] = true;
  save(); renderToday();
}
let selFlow = null, selMoods = [];
function renderChips() {
  const t = todayStr();
  const day = S.days[t] || {};
  selFlow = day.flow || null;
  selMoods = (day.moods || []).slice();
  const fc = document.getElementById("flowChips");
  fc.innerHTML = "";
  for (const f of FLOWS) {
    const c = document.createElement("button");
    c.className = "chip" + (selFlow === f ? " on" : "");
    c.textContent = (FLOW_EMOJI[f] || "") + " " + f;
    c.onclick = () => { selFlow = selFlow === f ? null : f; renderChips(); };
    fc.appendChild(c);
  }
  const mc = document.getElementById("moodChips");
  mc.innerHTML = "";
  for (const m of MOODS) {
    const c = document.createElement("button");
    c.className = "chip" + (selMoods.includes(m) ? " on" : "");
    c.textContent = (MOOD_EMOJI[m] || "") + " " + m;
    c.onclick = () => {
      selMoods = selMoods.includes(m) ? selMoods.filter((x) => x !== m) : selMoods.concat(m);
      renderChips();
    };
    mc.appendChild(c);
  }
}
function saveDay() {
  const t = todayStr();
  const note = document.getElementById("dayNote").value.trim();
  const prev = S.days[t] || {};
  const isPeriodStart = selFlow && selFlow !== "spotting" && !prev.flow;
  S.days[t] = { flow: selFlow, moods: selMoods.slice(), note };
  if (isPeriodStart && !S.periodStarts.includes(t)) {
    // only auto-add if it's been a while since the last start (avoid dupes)
    const l = lastPeriodStart();
    if (!l || diffDays(l, t) > 10) S.periodStarts.push(t);
  }
  save();
  document.getElementById("savedHint").hidden = false;
  renderToday(); renderCalendar(); renderInsights();
}

/* ---------- CALENDAR ---------- */
let calCursor = null;
function renderCalendar() {
  if (!calCursor) { const d = new Date(); calCursor = new Date(d.getFullYear(), d.getMonth(), 1); }
  const y = calCursor.getFullYear(), m = calCursor.getMonth();
  document.getElementById("calTitle").textContent =
    calCursor.toLocaleDateString(undefined, { month: "long", year: "numeric" });
  const grid = document.getElementById("calGrid");
  grid.innerHTML = "";
  ["S", "M", "T", "W", "T", "F", "S"].forEach((d) => {
    const el = document.createElement("div"); el.className = "dow"; el.textContent = d; grid.appendChild(el);
  });
  const first = new Date(y, m, 1);
  const startOffset = first.getDay();
  const daysInMonth = new Date(y, m + 1, 0).getDate();
  const prevDays = new Date(y, m, 0).getDate();
  const next = predictedNextPeriod();
  const cells = [];
  for (let i = startOffset - 1; i >= 0; i--) cells.push({ d: new Date(y, m - 1, prevDays - i), dim: true });
  for (let d = 1; d <= daysInMonth; d++) cells.push({ d: new Date(y, m, d), dim: false });
  while (cells.length % 7) { const l = cells[cells.length - 1].d; cells.push({ d: new Date(l.getFullYear(), l.getMonth(), l.getDate() + 1), dim: true }); }
  const t = todayStr();
  for (const { d, dim } of cells) {
    const ds = fmt(d);
    const b = document.createElement("button");
    b.className = "day" + (dim ? " dim" : "") + (ds === t ? " today" : "") + (isPeriod ? " has-period" : "");
    const day = S.days[ds];
    const isPeriod = periodDayNumber(ds) !== null;
    const isPredicted = next && ds === next;
    let pips = "";
    if (isPeriod) pips += '<span class="dot period"></span>';
    else if (isPredicted) pips += '<span class="dot predicted"></span>';
    if (day && (day.moods || []).length) pips += '<span class="dot logged"></span>';
    b.innerHTML = d.getDate() + '<span class="pips">' + pips + "</span>";
    b.onclick = () => showDayDetail(ds);
    grid.appendChild(b);
  }
}
function showDayDetail(ds) {
  const box = document.getElementById("dayDetail");
  const day = S.days[ds] || {};
  const p = packInfo(ds);
  const taken = S.taken[ds] || {};
  const medNames = [];
  for (const g of S.medGroups)
    for (const med of g.meds) {
      if (med.packOnly && p.phase === "placebo") continue;
      medNames.push((taken[med.id] ? "✓ " : "○ ") + med.name);
    }
  box.hidden = false;
  const isStart = S.periodStarts.includes(ds);
  box.innerHTML = "<h3>" + pretty(ds) + "</h3>" +
    '<div class="kv"><span>Flow</span><span>' + (day.flow ? (FLOW_EMOJI[day.flow] || "") + " " + day.flow : "—") + "</span></div>" +
    '<div class="kv"><span>Mood</span><span>' + ((day.moods || []).map((x) => (MOOD_EMOJI[x] || "") + " " + x).join(", ") || "—") + "</span></div>" +
    '<div class="kv"><span>Pack</span><span>' + packPhaseLabel(ds) + "</span></div>" +
    '<div class="kv"><span>Medications</span><span>' + (medNames.join("<br>") || "—") + "</span></div>" +
    (day.note ? '<div class="kv"><span>Note</span><span>' + esc(day.note) + "</span></div>" : "") +
    '<div class="btn-row" style="margin-top:12px">' +
    (isStart
      ? '<button class="btn small" id="unmarkStartBtn">Remove period start</button>'
      : '<button class="btn small" id="markStartBtn">Mark as period start</button>') +
    "</div>";
  const markBtn = document.getElementById("markStartBtn");
  if (markBtn) markBtn.onclick = () => {
    S.periodStarts.push(ds); S.periodStarts.sort(); save();
    renderCalendar(); renderToday(); renderInsights(); showDayDetail(ds);
  };
  const unmarkBtn = document.getElementById("unmarkStartBtn");
  if (unmarkBtn) unmarkBtn.onclick = () => {
    S.periodStarts = S.periodStarts.filter((x) => x !== ds); save();
    renderCalendar(); renderToday(); renderInsights(); showDayDetail(ds);
  };
  box.scrollIntoView({ behavior: "smooth", block: "nearest" });
}

/* ---------- PACK ---------- */
function renderPack() {
  const t = todayStr();
  const start = S.packAnchor;
  document.getElementById("packSummary").textContent =
    "This pack started " + pretty(start) + ". Today: " + packPhaseLabel(t) + ".";
  const grid = document.getElementById("packGrid");
  grid.innerHTML = "";
  for (let i = 0; i < 28; i++) {
    const ds = addDays(start, i);
    const p = packInfo(ds);
    const el = document.createElement("div");
    el.className = "pill" + (p.phase === "placebo" ? " placebo" : "") +
      (ds === t ? " today" : "") + (ds < t ? " past" : "");
    el.textContent = p.day;
    el.title = pretty(ds) + " — " + (p.phase === "active" ? "active pill " + p.day + "/21" : "placebo " + p.day + "/7");
    grid.appendChild(el);
  }
  document.getElementById("packAnchorInput").value = start;
  document.getElementById("syncCode").textContent = "PACK:" + start;
}
function savePack() {
  const v = document.getElementById("packAnchorInput").value;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) { alert("Please pick a valid date."); return; }
  S.packAnchor = v; save();
  renderPack(); renderToday();
  alert("Pack schedule saved. If you want reminders to stay in sync, send the code below to Muse.");
}

/* ---------- INSIGHTS ---------- */
function renderInsights() {
  const ps = S.periodStarts.slice().sort();
  const ch = document.getElementById("cycleHistory");
  if (ps.length === 0) {
    ch.innerHTML = '<p class="muted">No periods logged yet.</p>';
  } else {
    let html = "";
    for (let i = ps.length - 1; i >= 0; i--) {
      const gap = i > 0 ? diffDays(ps[i - 1], ps[i]) + " days" : "—";
      html += '<div class="stat-row"><span>Started ' + pretty(ps[i]) + "</span><span>" + gap + "</span></div>";
    }
    html += '<div class="stat-row"><span><strong>Average cycle</strong></span><span><strong>' + avgCycleLength() + " days</strong></span></div>";
    ch.innerHTML = html;
  }
  // moods by phase
  const counts = {};
  for (const ds of Object.keys(S.days)) {
    const ph = cyclePhase(ds);
    counts[ph] = counts[ph] || {};
    for (const m of (S.days[ds].moods || [])) counts[ph][m] = (counts[ph][m] || 0) + 1;
  }
  const mi = document.getElementById("moodInsights");
  const phases = ["menstrual", "follicular", "ovulation", "luteal"];
  let html = "";
  let any = false;
  for (const ph of phases) {
    const c = counts[ph] || {};
    const top = Object.entries(c).sort((a, b) => b[1] - a[1]).slice(0, 4);
    if (!top.length) continue;
    any = true;
    const max = top[0][1];
    html += '<h3 style="font-size:14px;margin:12px 0 4px;text-transform:capitalize;">' + ph + "</h3>";
    for (const [m, n] of top) {
      html += '<div class="bar-row"><span class="bar-label">' + (MOOD_EMOJI[m] || "") + " " + m + "</span>" +
        '<span class="bar-track"><span class="bar-fill" style="width:' + Math.round((n / max) * 100) + '%"></span></span>' +
        '<span class="bar-count">' + n + "</span></div>";
    }
  }
  mi.innerHTML = any ? html : '<p class="muted">Log some moods and patterns will show up here.</p>';
}

/* ---------- SETTINGS: med editor ---------- */
function renderMedEditor() {
  const wrap = document.getElementById("medEditor");
  wrap.innerHTML = "";
  S.medGroups.forEach((g, gi) => {
    const card = document.createElement("div");
    card.className = "group-card";
    card.innerHTML = "<h3>Reminder group</h3>";
    const nameRow = document.createElement("div");
    nameRow.className = "time-row";
    nameRow.innerHTML = '<input class="text-input" data-g="' + gi + '" data-f="name" value="' + esc(g.name) + '" placeholder="Group name">' +
      '<input type="time" class="text-input" style="width:110px;flex:none;" data-g="' + gi + '" data-f="time" value="' + esc(g.time) + '">';
    card.appendChild(nameRow);
    g.meds.forEach((m, mi2) => {
      const row = document.createElement("div");
      row.className = "med-edit-row";
      row.innerHTML = '<input class="text-input" data-g="' + gi + '" data-m="' + mi2 + '" value="' + esc(m.name) + '" placeholder="Medication name">' +
        '<label class="small muted" title="Only on active pill days"><input type="checkbox" data-g="' + gi + '" data-p="' + mi2 + '"' + (m.packOnly ? " checked" : "") + "> pill-day only</label>" +
        '<button class="icon-btn" data-del-g="' + gi + '" data-del-m="' + mi2 + '" aria-label="Remove">✕</button>';
      card.appendChild(row);
    });
    const addRow = document.createElement("div");
    addRow.className = "btn-row";
    addRow.innerHTML = '<button class="btn small" data-add-med="' + gi + '">+ Add medication</button>' +
      '<button class="btn small" data-del-group="' + gi + '">Remove group</button>';
    card.appendChild(addRow);
    wrap.appendChild(card);
  });
  wrap.querySelectorAll("input[data-g]").forEach((inp) => {
    inp.onchange = () => {
      const gi = +inp.dataset.g;
      if (inp.dataset.m !== undefined) S.medGroups[gi].meds[+inp.dataset.m].name = inp.value;
      else if (inp.dataset.p !== undefined) S.medGroups[gi].meds[+inp.dataset.p].packOnly = inp.checked;
      else if (inp.dataset.f === "name") S.medGroups[gi].name = inp.value;
      else if (inp.dataset.f === "time") S.medGroups[gi].time = inp.value;
      save(); renderToday();
    };
  });
  wrap.querySelectorAll("[data-add-med]").forEach((b) => {
    b.onclick = () => { S.medGroups[+b.dataset.addMed].meds.push({ id: uid("m"), name: "New medication" }); save(); renderMedEditor(); renderToday(); };
  });
  wrap.querySelectorAll("[data-del-m]").forEach((b) => {
    b.onclick = () => {
      if (!confirm("Remove this medication?")) return;
      S.medGroups[+b.dataset.delG].meds.splice(+b.dataset.delM, 1); save(); renderMedEditor(); renderToday();
    };
  });
  wrap.querySelectorAll("[data-del-group]").forEach((b) => {
    b.onclick = () => {
      if (!confirm("Remove this whole reminder group?")) return;
      S.medGroups.splice(+b.dataset.delGroup, 1); save(); renderMedEditor(); renderToday();
    };
  });
}

/* ---------- SETTINGS: export / import ---------- */
function download(name, text, type) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([text], { type }));
  a.download = name; a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 5000);
}
function exportJSON() { download("ggnog-schedules-backup.json", JSON.stringify(S, null, 2), "application/json"); }
function exportCSV() {
  const rows = [["date", "flow", "moods", "note", "pack_phase", "pack_day", "meds_taken"]];
  const dates = new Set([...Object.keys(S.days), ...Object.keys(S.taken), ...S.periodStarts]);
  for (const ds of [...dates].sort()) {
    const d = S.days[ds] || {};
    const p = packInfo(ds);
    rows.push([ds, d.flow || "", (d.moods || []).join("|"), '"' + (d.note || "").replace(/"/g, '""') + '"',
      p.phase, p.day, Object.keys(S.taken[ds] || {}).join("|")]);
  }
  download("ggnog-schedules.csv", rows.map((r) => r.join(",")).join("\n"), "text/csv");
}
function importFile(ev) {
  const f = ev.target.files[0];
  if (!f) return;
  const r = new FileReader();
  r.onload = () => {
    try {
      const s = JSON.parse(r.result);
      if (!s.medGroups || !s.packAnchor) throw new Error("bad file");
      if (!confirm("Replace all data with this backup?")) return;
      S = s; save();
      renderAll();
      alert("Backup restored.");
    } catch (e) { alert("Could not read that file."); }
  };
  r.readAsText(f);
  ev.target.value = "";
}

/* ---------- PUSH ---------- */
function urlB64ToU8(s) {
  const pad = "=".repeat((4 - (s.length % 4)) % 4);
  const b64 = (s + pad).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(b64);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}
function u8ToB64(u8) {
  let s = "";
  for (const b of u8) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
async function enablePush() {
  const status = document.getElementById("pushStatus");
  try {
    if (!("serviceWorker" in navigator) || !("PushManager" in window)) {
      status.textContent = "Push isn't supported in this browser.";
      return;
    }
    const reg = await navigator.serviceWorker.ready;
    const perm = await Notification.requestPermission();
    if (perm !== "granted") { status.textContent = "Notifications were blocked. Allow them in Settings to get reminders."; return; }
    let sub = await reg.pushManager.getSubscription();
    if (!sub) sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: urlB64ToU8(VAPID_PUBLIC_KEY) });
    const j = sub.toJSON();
    const code = "GNOGPUSH:" + u8ToB64(new TextEncoder().encode(JSON.stringify(j)));
    document.getElementById("pushCode").value = code;
    document.getElementById("pushCodeWrap").hidden = false;
    status.innerHTML = "✅ <strong>Ready.</strong> Copy the code below and send it to Muse in chat — that's the whole setup.";
  } catch (e) {
    status.textContent = "Something went wrong: " + e.message;
  }
}

/* ---------- tabs & init ---------- */
function showTab(name) {
  document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("active", t.dataset.tab === name));
  document.querySelectorAll(".view").forEach((v) => { v.hidden = v.dataset.view !== name; });
  if (name === "today") renderToday();
  if (name === "calendar") renderCalendar();
  if (name === "pack") renderPack();
  if (name === "insights") renderInsights();
  if (name === "settings") { renderMedEditor(); }
  window.scrollTo(0, 0);
}
function renderAll() { renderToday(); renderCalendar(); renderPack(); renderInsights(); renderMedEditor(); }

document.addEventListener("DOMContentLoaded", () => {
  if ("serviceWorker" in navigator) navigator.serviceWorker.register("sw.js").catch(() => {});
  document.querySelectorAll(".tab").forEach((t) => { t.onclick = () => showTab(t.dataset.tab); });
  document.getElementById("saveDayBtn").onclick = saveDay;
  document.getElementById("calPrev").onclick = () => { calCursor.setMonth(calCursor.getMonth() - 1); renderCalendar(); };
  document.getElementById("calNext").onclick = () => { calCursor.setMonth(calCursor.getMonth() + 1); renderCalendar(); };
  document.getElementById("savePackBtn").onclick = savePack;
  document.getElementById("packTodayBtn").onclick = () => { document.getElementById("packAnchorInput").value = todayStr(); };
  document.getElementById("packShiftBack").onclick = () => {
    const v = document.getElementById("packAnchorInput").value || S.packAnchor;
    document.getElementById("packAnchorInput").value = addDays(v, -1);
  };
  document.getElementById("packShiftFwd").onclick = () => {
    const v = document.getElementById("packAnchorInput").value || S.packAnchor;
    document.getElementById("packAnchorInput").value = addDays(v, 1);
  };
  document.getElementById("copySyncBtn").onclick = () => {
    navigator.clipboard.writeText(document.getElementById("syncCode").textContent).catch(() => {});
  };
  document.getElementById("enablePushBtn").onclick = enablePush;
  document.getElementById("copyPushBtn").onclick = () => {
    const ta = document.getElementById("pushCode");
    ta.select();
    try { document.execCommand("copy"); } catch (e) {}
    navigator.clipboard.writeText(ta.value).catch(() => {});
  };
  document.getElementById("addGroupBtn").onclick = () => {
    S.medGroups.push({ id: uid("g"), name: "New group", time: "09:00", meds: [] });
    save(); renderMedEditor(); renderToday();
  };
  document.getElementById("exportJsonBtn").onclick = exportJSON;
  document.getElementById("exportCsvBtn").onclick = exportCSV;
  document.getElementById("importFile").onchange = importFile;
  renderAll();
});
