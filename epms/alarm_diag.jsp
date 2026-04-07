<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<html>
<head>
    <title>Alarm Queue Diagnostics</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        :root{
            --bg:#f4f8fc;
            --card:#ffffff;
            --line:#d7e2ef;
            --text:#18324a;
            --muted:#66809a;
            --ok:#2e8b57;
            --warn:#d08a00;
            --bad:#c63d3d;
            --chip:#edf4fb;
            --shadow:0 16px 32px rgba(20,46,78,.08);
        }
        *{box-sizing:border-box}
        body{margin:0;font-family:"Segoe UI",Tahoma,sans-serif;background:linear-gradient(180deg,#f8fbff 0%,#edf4fb 100%);color:var(--text)}
        .page{max-width:1280px;margin:24px auto;padding:0 18px 24px}
        .head{display:flex;justify-content:space-between;align-items:flex-end;gap:16px;margin-bottom:18px}
        .head h1{margin:0;font-size:28px}
        .head p{margin:6px 0 0;color:var(--muted)}
        .toolbar{display:flex;gap:10px;align-items:center}
        .pill{display:inline-flex;align-items:center;gap:8px;padding:8px 12px;border-radius:999px;background:var(--chip);border:1px solid var(--line);font-size:12px;font-weight:700}
        .pill.ok{color:var(--ok)}
        .pill.warn{color:var(--warn)}
        .pill.bad{color:var(--bad)}
        .btn{display:inline-flex;align-items:center;justify-content:center;text-decoration:none;border:none;border-radius:10px;background:#2f6fde;color:#fff;font-weight:700;padding:10px 16px;cursor:pointer;box-shadow:0 10px 20px rgba(47,111,222,.2)}
        .grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px;margin-bottom:16px}
        .card{background:var(--card);border:1px solid var(--line);border-radius:18px;box-shadow:var(--shadow)}
        .metric{padding:18px}
        .metric .label{font-size:12px;color:var(--muted);margin-bottom:8px}
        .metric .value{font-size:28px;font-weight:800;letter-spacing:-.02em}
        .metric .sub{margin-top:8px;font-size:12px;color:var(--muted)}
        .section{padding:18px}
        .section h2{margin:0 0 12px;font-size:18px}
        .kv{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}
        .kv-item{padding:12px 14px;border:1px solid var(--line);border-radius:12px;background:#fbfdff}
        .kv-item .k{font-size:12px;color:var(--muted);margin-bottom:6px}
        .kv-item .v{font-size:16px;font-weight:700;word-break:break-word}
        .mono{font-family:Consolas,"Courier New",monospace}
        .footer{margin-top:18px;text-align:center;color:#6d8298;font-size:12px}
        .status-ok{color:var(--ok)}
        .status-watch{color:var(--warn)}
        .status-degraded{color:var(--bad)}
        @media (max-width:1024px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}.kv{grid-template-columns:1fr}}
        @media (max-width:640px){.head{flex-direction:column;align-items:flex-start}.grid{grid-template-columns:1fr}}
    </style>
</head>
<body>
<div class="page">
    <div class="head">
        <div>
            <h1>Alarm Diagnostics</h1>
            <p>알람 큐 압력, 캐시 상태, write-op 누적 현황을 실시간으로 확인합니다.</p>
        </div>
        <div class="toolbar">
            <div id="refreshInfo" class="pill">Last update: -</div>
            <button id="refreshBtn" class="btn" type="button">새로고침</button>
            <a class="back-btn" href="<%= request.getContextPath() %>/epms/epms_main.jsp" style="text-decoration:none;">EPMS 메인</a>
        </div>
    </div>

    <div class="grid">
        <div class="card metric">
            <div class="label">진단 상태</div>
            <div id="diagStatus" class="value">-</div>
            <div id="queueAdvice" class="sub">-</div>
        </div>
        <div class="card metric">
            <div class="label">Queue Pressure</div>
            <div id="queuePressureLevel" class="value">-</div>
            <div id="queueUtilizationPct" class="sub">-</div>
        </div>
        <div class="card metric">
            <div class="label">Queued Writes</div>
            <div id="queuedWriteOps" class="value">-</div>
            <div id="queueRemainingUntilFlush" class="sub">-</div>
        </div>
        <div class="card metric">
            <div class="label">High-water Mark</div>
            <div id="queuedWriteHighWaterMark" class="value">-</div>
            <div id="queueFlushThreshold" class="sub">-</div>
        </div>
    </div>

    <div class="card section" style="margin-bottom:16px;">
        <h2>Cache State</h2>
        <div class="kv">
            <div class="kv-item"><div class="k">AI Rule Cache</div><div id="aiRuleCacheSize" class="v mono">-</div></div>
            <div class="kv-item"><div class="k">AI Open State Cache</div><div id="aiOpenStateSize" class="v mono">-</div></div>
            <div class="kv-item"><div class="k">DI Event State Cache</div><div id="diEventStateSize" class="v mono">-</div></div>
            <div class="kv-item"><div class="k">DI Alarm State Cache</div><div id="diAlarmStateSize" class="v mono">-</div></div>
        </div>
    </div>

    <div class="card section">
        <h2>Queue Breakdown</h2>
        <div class="kv">
            <div class="kv-item"><div class="k">Open AI Alarms</div><div id="queuedOpenAiAlarms" class="v mono">-</div></div>
            <div class="kv-item"><div class="k">Clear AI Alarms</div><div id="queuedClearAiAlarms" class="v mono">-</div></div>
            <div class="kv-item"><div class="k">Open DI Events</div><div id="queuedOpenDiEvents" class="v mono">-</div></div>
            <div class="kv-item"><div class="k">Close DI Events</div><div id="queuedCloseDiEvents" class="v mono">-</div></div>
            <div class="kv-item"><div class="k">Open DI Alarms</div><div id="queuedOpenDiAlarms" class="v mono">-</div></div>
            <div class="kv-item"><div class="k">Clear DI Alarms</div><div id="queuedClearDiAlarms" class="v mono">-</div></div>
            <div class="kv-item"><div class="k">Warn Interval</div><div id="queueWarnIntervalMs" class="v mono">-</div></div>
            <div class="kv-item"><div class="k">Last Queue Warn</div><div id="lastQueueWarnAt" class="v mono">-</div></div>
        </div>
    </div>

    <div class="footer">© EPMS Dashboard | SNUT CNT</div>
</div>

<script>
const fields = [
  "diagStatus","queuePressureLevel","queuedWriteOps","queuedWriteHighWaterMark","queueFlushThreshold",
  "aiRuleCacheSize","aiOpenStateSize","diEventStateSize","diAlarmStateSize",
  "queuedOpenAiAlarms","queuedClearAiAlarms","queuedOpenDiEvents","queuedCloseDiEvents",
  "queuedOpenDiAlarms","queuedClearDiAlarms","queueWarnIntervalMs","lastQueueWarnAt"
];

function setText(id, value) {
  const el = document.getElementById(id);
  if (el) el.textContent = (value === null || value === undefined || value === "") ? "-" : String(value);
}

function applyStatusClass(el, value) {
  if (!el) return;
  el.classList.remove("status-ok","status-watch","status-degraded");
  if (value === "OK" || value === "NORMAL") el.classList.add("status-ok");
  else if (value === "WATCH" || value === "WARN") el.classList.add("status-watch");
  else if (value === "DEGRADED" || value === "HIGH") el.classList.add("status-degraded");
}

async function loadDiag() {
  const res = await fetch("<%= request.getContextPath() %>/api/alarm?action=diag", { cache: "no-store" });
  const data = await res.json();
  fields.forEach((id) => setText(id, data[id]));
  setText("queueAdvice", data.queueAdvice || "-");
  setText("queueUtilizationPct", "Utilization: " + (data.queueUtilizationPct ?? "-") + "% / Headroom: " + (data.queueHeadroomPct ?? "-") + "%");
  setText("queueRemainingUntilFlush", "Remaining until flush: " + (data.queueRemainingUntilFlush ?? "-"));
  document.getElementById("refreshInfo").textContent = "Last update: " + new Date().toLocaleString();
  applyStatusClass(document.getElementById("diagStatus"), data.diagStatus);
  applyStatusClass(document.getElementById("queuePressureLevel"), data.queuePressureLevel);
}

document.getElementById("refreshBtn").addEventListener("click", () => {
  loadDiag().catch((err) => alert("diag load failed: " + err));
});

loadDiag().catch((err) => alert("diag load failed: " + err));
setInterval(() => {
  loadDiag().catch(() => {});
}, 5000);
</script>
</body>
</html>
