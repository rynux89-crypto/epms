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
    maxHeightVh: clamp(toInt(uiDefaultsRaw.maxHeightVh, 60), 40, 90),
    fontSizePx: clamp(toInt(uiDefaultsRaw.fontSizePx, 13), 12, 20),
  };

  function loadUiPrefs() {
    try {
      const raw = localStorage.getItem(UI_STORAGE_KEY);
      if (!raw) return null;
      const parsed = JSON.parse(raw);
      return {
        widthPx: clamp(toInt(parsed.widthPx, uiDefaults.widthPx), 300, 560),
        maxHeightVh: clamp(toInt(parsed.maxHeightVh, uiDefaults.maxHeightVh), 40, 90),
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
      width:var(--epms-chat-width, 360px); max-height:var(--epms-chat-max-height, 60vh);
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
    .epms-chat-footer{ padding:8px; border-top:1px solid #eceff3; display:flex; gap:6px; background:#f8fbff; }
    .epms-chat-footer input{ flex:1; padding:8px 10px; border:1px solid #c8d1db; border-radius:6px; font-size:var(--epms-chat-font-size, 13px); }
    .epms-chat-footer button{
      padding:8px 12px; background:#007acc; color:#fff; border:none; border-radius:6px; cursor:pointer;
      font-size:var(--epms-chat-font-size, 13px);
    }
    .epms-msg{
      margin:6px 0; padding:8px; border-radius:8px; max-width:88%;
      word-wrap:break-word; white-space:pre-wrap; line-height:1.4;
    }
    .epms-msg.user{ background:#e6f2ff; color:#1f2937; align-self:flex-end; }
    .epms-msg.bot{ background:#f3f4f6; color:#1f2937; align-self:flex-start; }
    .epms-context{
      font-size:11px; color:#64748b; margin-top:4px; padding-top:4px; border-top:1px solid #dbe2ea;
    }
    @media (max-width: 640px){
      .epms-chat-btn{ right:12px; bottom:12px; padding:10px 14px; }
      .epms-chat-modal{
        left:12px; right:12px; width:auto; bottom:64px; max-height:70vh;
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
      <span>EPMS 비서</span>
      <div class="epms-chat-tools">
        <button type="button" class="epms-chat-tool" id="epms-font-down" title="글자 작게">A-</button>
        <button type="button" class="epms-chat-tool" id="epms-font-up" title="글자 크게">A+</button>
        <button type="button" class="epms-chat-tool" id="epms-width-down" title="폭 줄이기">폭-</button>
        <button type="button" class="epms-chat-tool" id="epms-width-up" title="폭 넓히기">폭+</button>
        <button type="button" class="epms-chat-tool" id="epms-ui-reset" title="기본값 복원">초기화</button>
      </div>
      <button type="button" class="epms-chat-close" id="epms-close" aria-label="닫기">x</button>
    </div>
    <div class="epms-chat-body" id="epms-chat-body"></div>
    <div class="epms-chat-footer">
      <input id="epms-input" placeholder="질문을 입력하세요" />
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

  function appendMsg(text, who, context) {
    const body = document.getElementById("epms-chat-body");
    if (!body) return;
    const box = el("div", "epms-msg " + (who === "user" ? "user" : "bot"));
    if (who === "bot") box.innerHTML = formatText(text);
    else box.textContent = text;

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

  async function send(msg) {
    appendMsg(msg, "user");
    try {
      const res = await fetch("/epms/agent.jsp", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: msg }),
      });
      const json = await res.json();
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
