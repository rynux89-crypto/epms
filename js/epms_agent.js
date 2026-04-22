(function () {
  const UI_STORAGE_KEY = "epms_chat_ui_prefs_v1";

  function clamp(n, min, max) {
    return Math.max(min, Math.min(max, n));
  }

  function toInt(v, defVal) {
    const n = parseInt(v, 10);
    return Number.isFinite(n) ? n : defVal;
  }

  const uiDefaultsRaw = window.EPMS_AGENT_UI_DEFAULTS || {};
  const uiDefaults = {
    widthPx: clamp(toInt(uiDefaultsRaw.widthPx, 360), 300, 560),
    maxHeightVh: 75,
    fontSizePx: clamp(toInt(uiDefaultsRaw.fontSizePx, 13), 12, 20),
  };

  function loadUiPrefs() {
    try {
      const raw = localStorage.getItem(UI_STORAGE_KEY);
      if (!raw) return null;
      const parsed = JSON.parse(raw);
      return {
        widthPx: clamp(toInt(parsed.widthPx, uiDefaults.widthPx), 300, 560),
        maxHeightVh: 75,
        fontSizePx: clamp(toInt(parsed.fontSizePx, uiDefaults.fontSizePx), 12, 20),
      };
    } catch (e) {
      return null;
    }
  }

  function saveUiPrefs(ui) {
    try {
      localStorage.setItem(UI_STORAGE_KEY, JSON.stringify(ui));
    } catch (e) {
      // ignore storage errors
    }
  }

  const ui = loadUiPrefs() || {
    widthPx: uiDefaults.widthPx,
    maxHeightVh: uiDefaults.maxHeightVh,
    fontSizePx: uiDefaults.fontSizePx,
  };

  function applyUi() {
    document.documentElement.style.setProperty("--epms-chat-width", ui.widthPx + "px");
    document.documentElement.style.setProperty("--epms-chat-max-height", ui.maxHeightVh + "vh");
    document.documentElement.style.setProperty("--epms-chat-font-size", ui.fontSizePx + "px");
  }

  applyUi();

  function el(tag, cls, text) {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text) node.textContent = text;
    return node;
  }

  const style = el("style");
  style.textContent = `
    .epms-chat-btn{
      position:fixed; right:20px; bottom:20px; z-index:9999;
      background:#007acc; color:#fff; border:none; border-radius:24px;
      padding:12px 16px; cursor:pointer; font-size:14px; font-weight:700;
      box-shadow:0 6px 16px rgba(0,0,0,.2);
    }
    .epms-chat-modal{
      position:fixed; right:20px; bottom:80px; z-index:9999;
      width:var(--epms-chat-width, 360px); height:var(--epms-chat-max-height, 75vh); max-height:75vh;
      display:flex; flex-direction:column;
      background:#fff; border:1px solid #d7dce2; border-radius:10px;
      box-shadow:0 10px 28px rgba(0,0,0,.24);
      overflow:hidden;
    }
    .epms-chat-header{
      padding:12px; border-bottom:1px solid #eceff3; font-weight:700;
      display:flex; justify-content:space-between; align-items:center;
      background:#f8fbff;
    }
    .epms-chat-close{
      border:none; background:transparent; cursor:pointer; font-size:18px; line-height:1;
      color:#334155;
    }
    .epms-chat-tools{ display:flex; gap:4px; align-items:center; }
    .epms-chat-tool{
      border:1px solid #c9d3df; background:#fff; color:#334155;
      border-radius:6px; font-size:11px; line-height:1; padding:5px 6px; cursor:pointer;
    }
    .epms-chat-body{
      padding:10px; overflow:auto; flex:1; font-size:var(--epms-chat-font-size, 13px); background:#fff;
      display:flex; flex-direction:column;
    }
    .epms-chat-footer{
      padding:8px; border-top:1px solid #eceff3; display:flex; gap:6px; background:#f8fbff;
    }
    .epms-chat-footer input{
      flex:1; padding:8px 10px; border:1px solid #c8d1db; border-radius:6px;
      font-size:var(--epms-chat-font-size, 13px);
    }
    .epms-chat-footer button{
      padding:8px 12px; background:#007acc; color:#fff; border:none; border-radius:6px; cursor:pointer;
      font-size:var(--epms-chat-font-size, 13px);
    }
    .epms-msg{
      margin:6px 0; padding:10px 12px; border-radius:12px; max-width:92%;
      word-wrap:break-word; white-space:pre-wrap; line-height:1;
      box-shadow:0 1px 2px rgba(15,23,42,.04);
    }
    .epms-msg.user{ background:#e6f2ff; color:#1f2937; align-self:flex-end; }
    .epms-msg.bot{ background:#f3f4f6; color:#1f2937; align-self:flex-start; }
    .epms-msg.bot.empty{
      background:#fff8e8; color:#5f4b1b; border:1px solid #f0d99a;
    }
    .epms-context{
      font-size:11px; color:#64748b; margin-top:4px; padding-top:4px; border-top:1px solid #dbe2ea;
    }
    .epms-samples{
      margin-top:2px; padding-top:2px; border-top:1px solid #dbe2ea;
    }
    .epms-samples-title{
      font-weight:700; color:#334155; margin-bottom:-6px;
      line-height:0.75;
    }
    .epms-samples ol{
      margin:-4px 0 0 0; padding-left:10px;
    }
    .epms-samples li{
      margin:0;
      line-height:0.5;
      padding:0;
    }
    @media (max-width: 640px){
      .epms-chat-btn{ right:12px; bottom:12px; padding:10px 14px; }
      .epms-chat-modal{
        left:12px; right:12px; width:auto; bottom:64px; height:75vh; max-height:75vh;
      }
      .epms-chat-tools{ display:none; }
    }
  `;
  document.head.appendChild(style);

  const btn = el("button", "epms-chat-btn", "EPMS Chat");
  document.body.appendChild(btn);

  const modal = el("div", "epms-chat-modal");
  modal.style.display = "none";
  modal.innerHTML = `
    <div class="epms-chat-header">
      <span>EPMS AI 비서</span>
      <div class="epms-chat-tools">
        <button type="button" class="epms-chat-tool" id="epms-font-down" title="글자 작게">A-</button>
        <button type="button" class="epms-chat-tool" id="epms-font-up" title="글자 크게">A+</button>
        <button type="button" class="epms-chat-tool" id="epms-width-down" title="폭 줄이기">-폭</button>
        <button type="button" class="epms-chat-tool" id="epms-width-up" title="폭 넓히기">+폭</button>
        <button type="button" class="epms-chat-tool" id="epms-ui-reset" title="기본값 복원">초기화</button>
      </div>
      <button type="button" class="epms-chat-close" id="epms-close" aria-label="닫기">x</button>
    </div>
    <div class="epms-chat-body" id="epms-chat-body" data-welcome-shown="true">
      <div class="epms-msg bot">무엇을 도와드릴까요? 아래 샘플 질문으로 바로 테스트해 보세요.

<div class="epms-samples">
  <div class="epms-samples-title">샘플 질문</div>
  <ol>
    <li>현재 알람 상태를 요약해줘</li>
    <li>알람이 가장 많은 계측기는 무엇이야?</li>
    <li>최근 알람 원인을 설명해줘</li>
    <li>전력품질 관점에서 현재 문제를 설명해줘</li>
    <li>주파수가 이상한 계측기를 보여줘</li>
    <li>전압 불평형이 큰 계측기를 찾아줘</li>
    <li>1번 계측기의 현재 상태를 알려줘</li>
    <li>1번 계측기의 이번 달 전력 사용량은 얼마야?</li>
    <li>전체 건물의 현재 전력 사용 현황을 요약해줘</li>
    <li>무효전력이 큰 계측기를 찾아주고 점검 포인트도 알려줘</li>
  </ol>
</div></div>
    </div>
    <div class="epms-chat-footer">
      <input id="epms-input" placeholder="질문을 입력해 주세요" />
      <button id="epms-send" type="button">Send</button>
    </div>
  `;
  document.body.appendChild(modal);

  function openModal() {
    modal.style.display = "flex";
    const input = document.getElementById("epms-input");
    if (input) input.focus();
  }

  function closeModal() {
    modal.style.display = "none";
  }

  btn.addEventListener("click", openModal);
  document.getElementById("epms-close").addEventListener("click", closeModal);
  document.getElementById("epms-font-down").addEventListener("click", () => {
    ui.fontSizePx = clamp(ui.fontSizePx - 1, 12, 20);
    applyUi();
    saveUiPrefs(ui);
  });
  document.getElementById("epms-font-up").addEventListener("click", () => {
    ui.fontSizePx = clamp(ui.fontSizePx + 1, 12, 20);
    applyUi();
    saveUiPrefs(ui);
  });
  document.getElementById("epms-width-down").addEventListener("click", () => {
    ui.widthPx = clamp(ui.widthPx - 20, 300, 560);
    applyUi();
    saveUiPrefs(ui);
  });
  document.getElementById("epms-width-up").addEventListener("click", () => {
    ui.widthPx = clamp(ui.widthPx + 20, 300, 560);
    applyUi();
    saveUiPrefs(ui);
  });
  document.getElementById("epms-ui-reset").addEventListener("click", () => {
    ui.widthPx = uiDefaults.widthPx;
    ui.maxHeightVh = uiDefaults.maxHeightVh;
    ui.fontSizePx = uiDefaults.fontSizePx;
    applyUi();
    saveUiPrefs(ui);
  });
  document.addEventListener("keydown", (ev) => {
    if (ev.key === "Escape") closeModal();
  });

  function formatText(text) {
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
      .replace(/`([^`]+)`/g, '<code style="background:#e5e7eb;padding:2px 4px;border-radius:3px">$1</code>')
      .replace(/```([\s\S]*?)```/g, '<div style="background:#1f2937;color:#f8fafc;padding:8px;border-radius:6px;overflow-x:auto;font-family:monospace;margin:4px 0">$1</div>');
  }

  function enrichCurrentStatusAnswer(text) {
    if (!text || text.indexOf("현재 상태") < 0) return text;
    if (text.indexOf("값 기준:") >= 0) return text;
    const guide = [
      "",
      "값 기준:",
      "- 전압: average_voltage 우선, 없으면 line_voltage_avg -> phase_voltage_avg -> voltage_ab",
      "- 전류: average_current",
      "- 역률: power_factor 우선, 없으면 power_factor_avg 또는 3상 평균",
      "- 유효전력: active_power_total",
      "- 무효전력: reactive_power_total",
      "- 주파수: frequency",
    ].join("\n");
    return text + "\n" + guide;
  }

  function enrichEmptyAnswer(text) {
    const normalized = String(text || "").trim();
    if (!normalized) return normalized;
    const emptyHints = [
      "데이터가 없습니다.",
      "조회 결과가 없습니다.",
      "찾지 못했습니다.",
      "없습니다."
    ];
    const matched = emptyHints.some((hint) => normalized.indexOf(hint) >= 0);
    if (!matched) return normalized;
    if (normalized.indexOf("다음 항목을 확인해 보세요") >= 0) return normalized;
    return normalized + "\n\n다음 항목을 확인해 보세요\n- 조회 기간에 실제 알람 데이터가 있는지\n- 계측기명 또는 범위 조건이 너무 좁지 않은지\n- 알람 로그 수집이 정상 동작 중인지";
  }

  function appendMsg(text, who, context) {
    const body = document.getElementById("epms-chat-body");
    if (!body) return;
    const box = el("div", "epms-msg " + (who === "user" ? "user" : "bot"));
    if (who === "bot") {
      const enriched = enrichEmptyAnswer(enrichCurrentStatusAnswer(text));
      box.innerHTML = formatText(enriched);
      if (enriched.indexOf("다음 항목을 확인해 보세요") >= 0) {
        box.classList.add("empty");
      }
    } else {
      box.textContent = text;
    }

    if (context) {
      const ctx = el("div", "epms-context", context);
      box.appendChild(ctx);
    }

    body.appendChild(box);
    body.scrollTop = body.scrollHeight;
  }

  function parseStreamingResponse(raw) {
    try {
      const lines = raw.split("\n").filter((line) => line.trim());
      let fullText = "";
      for (const line of lines) {
        try {
          const obj = JSON.parse(line);
          if (obj.response) fullText += obj.response;
        } catch (ignore) {
          // ignore malformed line
        }
      }
      return fullText.trim() || "응답이 비어 있습니다.";
    } catch (e) {
      return "응답 파싱 오류";
    }
  }

  function summarizeHtmlResponse(text) {
    const normalized = String(text || "").replace(/\s+/g, " ").trim();
    if (!normalized) return "빈 응답";
    const lowered = normalized.toLowerCase();
    if (lowered.indexOf("<!doctype") >= 0 || lowered.indexOf("<html") >= 0) {
      return "서버가 JSON 대신 HTML 페이지를 반환했습니다.";
    }
    return normalized.slice(0, 180);
  }

  async function parseJsonResponse(res) {
    const contentType = (res.headers.get("content-type") || "").toLowerCase();
    const raw = await res.text();

    if (!res.ok) {
      throw new Error("HTTP " + res.status + " " + summarizeHtmlResponse(raw));
    }

    if (contentType.indexOf("application/json") < 0) {
      throw new Error(summarizeHtmlResponse(raw));
    }

    try {
      return JSON.parse(raw);
    } catch (e) {
      throw new Error("JSON 파싱 실패: " + summarizeHtmlResponse(raw));
    }
  }

  async function send(msg) {
    appendMsg(msg, "user");
    try {
      const endpoint = window.EPMS_AGENT_ENDPOINT || "/api/agent";
      const res = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: msg }),
      });
      const json = await parseJsonResponse(res);
      if (json.error) {
        appendMsg("오류: " + json.error, "bot");
        return;
      }
      const cleanedText = parseStreamingResponse(json.provider_response || "");
      const dbContext = json.db_context || "";
      const dbContextUser = json.db_context_user || "";
      const isAdmin = json.is_admin === true;
      let contextText = null;
      if (isAdmin) {
        contextText = dbContext ? "DB Context: " + dbContext : (dbContextUser ? "DB Summary: " + dbContextUser : null);
      }
      appendMsg(cleanedText, "bot", contextText);
    } catch (e) {
      appendMsg("통신 오류: " + e.message, "bot");
    }
  }

  document.getElementById("epms-send").addEventListener("click", () => {
    const input = document.getElementById("epms-input");
    if (!input) return;
    const msg = input.value.trim();
    if (!msg) return;
    input.value = "";
    send(msg);
  });

  document.getElementById("epms-input").addEventListener("keydown", (ev) => {
    if (ev.key === "Enter") {
      ev.preventDefault();
      document.getElementById("epms-send").click();
    }
  });
})();
