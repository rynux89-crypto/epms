#!/usr/bin/env python3
"""
Schneider Easy UPS 3-Phase Modular Modbus TCP simulator.

Default endpoint:
  127.0.0.1:1502, unit id 1

Register addresses use the PDF "Absolute Starting Register Address (Decimal)"
values, matching the UPS monitor profile.
"""

from __future__ import annotations

import argparse
import json
import socket
import socketserver
import struct
import sys
import threading
import time
import urllib.parse
import webbrowser
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


SCENARIOS = {
    "normal",
    "battery",
    "low_battery",
    "overload",
    "input_fault",
    "output_fault",
    "bypass_fault",
    "power_module_fault",
    "critical",
}

SCENARIO_LABELS = {
    "normal": "정상",
    "battery": "배터리 운전",
    "low_battery": "배터리 부족",
    "overload": "과부하",
    "input_fault": "입력 이상",
    "output_fault": "출력 이상",
    "bypass_fault": "바이패스 이상",
    "power_module_fault": "파워 모듈 이상",
    "critical": "중요 알람",
}


def u16(value: int) -> int:
    return max(0, min(0xFFFF, int(value)))


def set_u32(regs: dict[int, int], address: int, value: int) -> None:
    value &= 0xFFFFFFFF
    regs[address] = (value >> 16) & 0xFFFF
    regs[address + 1] = value & 0xFFFF


def set_i32(regs: dict[int, int], address: int, value: int) -> None:
    if value < 0:
        value = (1 << 32) + value
    set_u32(regs, address, value)


def get_u32(regs: dict[int, int], address: int) -> int:
    return ((regs.get(address, 0) & 0xFFFF) << 16) | (regs.get(address + 1, 0) & 0xFFFF)


def get_i32(regs: dict[int, int], address: int) -> int:
    value = get_u32(regs, address)
    if value & 0x80000000:
        value -= 1 << 32
    return value


@dataclass
class SimulatorState:
    scenario: str = "normal"
    started_at: float = field(default_factory=time.time)
    lock: threading.Lock = field(default_factory=threading.Lock)
    breakers: dict[str, bool] = field(default_factory=lambda: {
        "uib": True,
        "uob": True,
        "ssib": False,
        "bf2": False,
        "mbb": False,
        "bb": True,
    })

    def set_scenario(self, scenario: str) -> None:
        if scenario not in SCENARIOS:
            raise ValueError(f"unknown scenario: {scenario}")
        with self.lock:
            self.scenario = scenario

    def get_scenario(self) -> str:
        with self.lock:
            return self.scenario

    def set_breaker(self, name: str, closed: bool) -> None:
        key = name.strip().lower()
        if key not in self.breakers:
            raise ValueError(f"unknown breaker: {name}")
        with self.lock:
            self.breakers[key] = closed

    def reset_breakers(self) -> None:
        with self.lock:
            self.breakers.update({
                "uib": True,
                "uob": True,
                "ssib": False,
                "bf2": False,
                "mbb": False,
                "bb": True,
            })

    def get_breakers(self) -> dict[str, bool]:
        with self.lock:
            return dict(self.breakers)

    def snapshot(self) -> dict[str, object]:
        regs = self.registers()
        scenario = self.get_scenario()
        breakers = self.get_breakers()
        return {
            "scenario": scenario,
            "label": SCENARIO_LABELS.get(scenario, scenario),
            "breakers": breakers,
            "uptime_seconds": int(time.time() - self.started_at),
            "output_frequency_hz": regs.get(4608, 0) / 10,
            "output_voltage_l12": regs.get(4612, 0),
            "output_voltage_l23": regs.get(4613, 0),
            "output_voltage_l31": regs.get(4614, 0),
            "output_current_l1": regs.get(4615, 0),
            "output_current_l2": regs.get(4616, 0),
            "output_current_l3": regs.get(4617, 0),
            "output_load_percent": regs.get(4632, 0) / 10,
            "output_power_kw": regs.get(4627, 0),
            "output_power_l1_kw": regs.get(4618, 0),
            "output_power_l2_kw": regs.get(4619, 0),
            "output_power_l3_kw": regs.get(4620, 0),
            "output_apparent_total_kva": regs.get(4631, 0),
            "output_apparent_l1_kva": regs.get(4621, 0),
            "output_apparent_l2_kva": regs.get(4622, 0),
            "output_apparent_l3_kva": regs.get(4623, 0),
            "output_pf_l1": regs.get(4628, 0) / 100,
            "output_pf_l2": regs.get(4629, 0) / 100,
            "output_pf_l3": regs.get(4630, 0) / 100,
            "battery_voltage": regs.get(4865, 0),
            "battery_current": get_i32(regs, 4866),
            "battery_charge_percent": regs.get(4871, 0),
            "battery_temperature_c": regs.get(4864, 0) / 10,
            "remaining_minutes": get_u32(regs, 4872) / 60,
            "ups_operation_mode_code": 4 if scenario in ("battery", "low_battery") else 2,
            "system_operation_mode_code": 2,
            "ups_status_word": regs.get(1, 0),
            "input_status": regs.get(11, 0),
            "output_status": regs.get(12, 0),
            "power_module_status": regs.get(14, 0),
        }

    def registers(self) -> dict[int, int]:
        scenario = self.get_scenario()
        elapsed = time.time() - self.started_at
        wave = int((elapsed % 10) - 5)

        regs: dict[int, int] = {}
        breakers = self.get_breakers()

        ups_status = 0
        bypass_status = 0
        energy_status = 0
        energy_status_2 = 0
        general_status = 0
        general_status_2 = 0
        general_status_3 = 0
        general_status_4 = 0
        input_status = 0
        output_status = 0
        parallel_status = 0
        power_module_status = 0

        output_load = 43
        battery_charge = 96
        battery_current = 4
        remaining_seconds = 7200
        battery_health = 1
        ups_mode = 2
        system_mode = 2

        if scenario == "battery":
            ups_status |= 1 << 0
            energy_status |= 1 << 4
            battery_current = -35
            remaining_seconds = 2700
            battery_charge = 72
            ups_mode = 4
        elif scenario == "low_battery":
            ups_status |= (1 << 0) | (1 << 1) | (1 << 14)
            energy_status |= (1 << 4) | (1 << 6) | (1 << 12)
            battery_current = -48
            remaining_seconds = 420
            battery_charge = 8
            ups_mode = 4
        elif scenario == "overload":
            ups_status |= 1 << 14
            output_status |= (1 << 2) | (1 << 5)
            output_load = 97
        elif scenario == "input_fault":
            ups_status |= 1 << 14
            input_status |= (1 << 0) | (1 << 2)
        elif scenario == "output_fault":
            ups_status |= 1 << 15
            output_status |= (1 << 0) | (1 << 1)
        elif scenario == "bypass_fault":
            ups_status |= 1 << 14
            bypass_status |= (1 << 0) | (1 << 2)
        elif scenario == "power_module_fault":
            ups_status |= 1 << 15
            power_module_status |= (1 << 0) | (1 << 2) | (1 << 7)
        elif scenario == "critical":
            ups_status |= (1 << 1) | (1 << 9) | (1 << 15)
            energy_status |= (1 << 6) | (1 << 9) | (1 << 14)
            general_status |= 1 << 0
            output_status |= (1 << 2) | (1 << 5)
            power_module_status |= 1 << 0
            output_load = 101
            battery_charge = 5
            battery_health = 3

        # Status registers.
        regs[1] = ups_status
        regs[2] = bypass_status
        regs[3] = energy_status
        regs[4] = energy_status_2
        regs[5] = general_status
        regs[6] = general_status_2
        regs[7] = general_status_3
        regs[8] = general_status_4
        regs[11] = input_status
        regs[12] = output_status
        regs[13] = parallel_status
        regs[14] = power_module_status
        switchgear = 0
        if breakers.get("uib", False):
            switchgear |= 1 << 0
        if breakers.get("ssib", False):
            switchgear |= 1 << 1
        if breakers.get("uob", False):
            switchgear |= 1 << 3
        if breakers.get("bf2", False):
            switchgear |= 1 << 4
        if breakers.get("mbb", False):
            switchgear |= 1 << 10
        regs[17] = switchgear

        # Input.
        regs[4096] = 600
        regs[4097] = 220 + wave
        regs[4098] = 221
        regs[4099] = 219
        regs[4100] = 380 + wave
        regs[4101] = 381
        regs[4102] = 379
        regs[4103] = 42
        regs[4104] = 41
        regs[4105] = 43
        regs[4106] = 14
        regs[4107] = 14
        regs[4108] = 15
        regs[4115] = 43
        regs[4116] = 46

        # Bypass.
        regs[4352] = 600
        regs[4353] = 220
        regs[4354] = 221
        regs[4355] = 219
        regs[4371] = 0

        # Output.
        regs[4608] = 600
        regs[4609] = 220
        regs[4610] = 221
        regs[4611] = 219
        regs[4612] = 380 + wave
        regs[4613] = 381
        regs[4614] = 379
        regs[4615] = 38 + max(wave, 0)
        regs[4616] = 37
        regs[4617] = 39
        regs[4618] = 13
        regs[4619] = 13
        regs[4620] = 14
        regs[4621] = 14
        regs[4622] = 14
        regs[4623] = 15
        regs[4624] = u16(output_load * 10)
        regs[4625] = u16((output_load - 1) * 10)
        regs[4626] = u16((output_load + 1) * 10)
        regs[4627] = 40
        regs[4628] = 96
        regs[4629] = 95
        regs[4630] = 97
        regs[4631] = 43
        regs[4632] = u16(output_load * 10)

        # Battery.
        regs[4864] = 285
        regs[4865] = 540
        set_i32(regs, 4866, battery_current)
        regs[4868] = abs(battery_current) * 2
        set_u32(regs, 4869, 3600)
        regs[4871] = battery_charge
        set_u32(regs, 4872, remaining_seconds)
        regs[4874] = 2
        regs[4875] = 1
        regs[4876] = 1 if breakers.get("bb", False) else 0
        regs[4880] = battery_health
        regs[4881] = 420

        # Parallel/system.
        regs[4902] = regs[4631]
        regs[4903] = regs[4632]
        regs[4904] = regs[4627]
        regs[5376] = 245
        regs[5377] = switchgear
        set_u32(regs, 5378, ups_mode)
        regs[5380] = system_mode
        regs[5381] = 1
        regs[5382] = switchgear
        regs[8201] = 100
        regs[8202] = 100
        regs[8210] = 1

        return regs


class ModbusHandler(socketserver.BaseRequestHandler):
    def handle(self) -> None:
        state: SimulatorState = self.server.state  # type: ignore[attr-defined]
        while True:
            header = self._read_exact(7)
            if not header:
                return
            tx_id, proto_id, length, unit_id = struct.unpack(">HHHB", header)
            body = self._read_exact(length - 1)
            if not body:
                return
            fn = body[0]
            if fn not in (3, 4) or len(body) < 5:
                self._exception(tx_id, proto_id, unit_id, fn, 1)
                continue
            start, count = struct.unpack(">HH", body[1:5])
            if count < 1 or count > 125:
                self._exception(tx_id, proto_id, unit_id, fn, 3)
                continue
            regs = state.registers()
            payload = bytearray([fn, count * 2])
            for address in range(start, start + count):
                payload.extend(struct.pack(">H", regs.get(address, 0)))
            self._response(tx_id, proto_id, unit_id, payload)

    def _read_exact(self, length: int) -> bytes:
        data = bytearray()
        while len(data) < length:
            chunk = self.request.recv(length - len(data))
            if not chunk:
                return b""
            data.extend(chunk)
        return bytes(data)

    def _response(self, tx_id: int, proto_id: int, unit_id: int, payload: bytes | bytearray) -> None:
        header = struct.pack(">HHHB", tx_id, proto_id, len(payload) + 1, unit_id)
        self.request.sendall(header + bytes(payload))

    def _exception(self, tx_id: int, proto_id: int, unit_id: int, fn: int, code: int) -> None:
        self._response(tx_id, proto_id, unit_id, bytes([fn | 0x80, code]))


class ThreadedTcpServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, server_address: tuple[str, int], handler, state: SimulatorState):
        super().__init__(server_address, handler)
        self.state = state


class ControlHandler(BaseHTTPRequestHandler):
    server_version = "UpsSimulatorControl/1.0"

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path in ("", "/"):
            self._html()
            return
        if parsed.path == "/api/status":
            self._json(self.server.state.snapshot())  # type: ignore[attr-defined]
            return
        self.send_error(404)

    def do_POST(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/api/scenario":
            if parsed.path == "/api/breaker":
                self._post_breaker()
                return
            if parsed.path == "/api/reset-breakers":
                self.server.state.reset_breakers()  # type: ignore[attr-defined]
                self._json({"ok": True, **self.server.state.snapshot()})  # type: ignore[attr-defined]
                return
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(length).decode("utf-8") if length else ""
        data = urllib.parse.parse_qs(raw)
        scenario = (data.get("scenario", [""])[0] or "").strip()
        try:
            self.server.state.set_scenario(scenario)  # type: ignore[attr-defined]
        except ValueError as exc:
            self._json({"ok": False, "error": str(exc)}, status=400)
            return
        self._json({"ok": True, **self.server.state.snapshot()})  # type: ignore[attr-defined]

    def _post_breaker(self) -> None:
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(length).decode("utf-8") if length else ""
        data = urllib.parse.parse_qs(raw)
        name = (data.get("name", [""])[0] or "").strip()
        closed_raw = (data.get("closed", [""])[0] or "").strip().lower()
        closed = closed_raw in ("1", "true", "yes", "closed", "on")
        try:
            self.server.state.set_breaker(name, closed)  # type: ignore[attr-defined]
        except ValueError as exc:
            self._json({"ok": False, "error": str(exc)}, status=400)
            return
        self._json({"ok": True, **self.server.state.snapshot()})  # type: ignore[attr-defined]

    def log_message(self, fmt: str, *args: object) -> None:
        return

    def _json(self, payload: dict[str, object], status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _html(self) -> None:
        scenarios = "\n".join(
            f'<button class="scenario" data-scenario="{name}"><strong>{SCENARIO_LABELS[name]}</strong><span>{name}</span></button>'
            for name in ["normal", "battery", "low_battery", "overload", "input_fault", "output_fault", "bypass_fault", "power_module_fault", "critical"]
        )
        body = f"""<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>UPS Simulator Control</title>
<style>
* {{ box-sizing:border-box; }}
body {{ margin:0; font-family:"Segoe UI","Noto Sans KR",Arial,sans-serif; background:#eef2f6; color:#172033; }}
.wrap {{ max-width:1120px; margin:0 auto; padding:24px; }}
.top {{ display:flex; justify-content:space-between; gap:16px; align-items:flex-start; margin-bottom:18px; }}
h1 {{ margin:0 0 6px; font-size:28px; }}
.muted {{ color:#64748b; font-size:13px; }}
.badge {{ display:inline-flex; align-items:center; min-height:34px; padding:6px 12px; border-radius:999px; background:#fff; border:1px solid #d7e1ec; font-weight:700; }}
.grid {{ display:grid; grid-template-columns:1fr 340px; gap:16px; align-items:start; }}
.panel {{ background:#fff; border:1px solid #d7e1ec; border-radius:8px; padding:16px; }}
.scenario-grid {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(170px,1fr)); gap:10px; }}
button.scenario {{ border:1px solid #cbd8e6; border-radius:8px; background:#f8fafc; color:#172033; padding:14px; text-align:left; cursor:pointer; min-height:74px; }}
button.scenario strong {{ display:block; font-size:16px; margin-bottom:5px; }}
button.scenario span {{ color:#64748b; font-size:12px; }}
button.scenario.active {{ border-color:#1267b1; background:#eaf4ff; box-shadow:inset 0 0 0 1px #1267b1; }}
.breaker-grid {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(110px,1fr)); gap:8px; margin-top:12px; }}
button.breaker {{ border:1px solid #cbd8e6; border-radius:8px; background:#fff; color:#172033; padding:10px; cursor:pointer; text-align:center; }}
button.breaker strong {{ display:block; font-size:15px; margin-bottom:4px; }}
button.breaker span {{ display:block; font-size:12px; color:#64748b; }}
button.breaker.closed {{ border-color:#169b45; background:#ecfdf3; }}
button.breaker.open {{ border-color:#9ca3af; background:#f8fafc; }}
button.reset {{ margin-top:10px; border:1px solid #cbd8e6; border-radius:6px; background:#fff; padding:8px 10px; cursor:pointer; }}
.metrics {{ display:grid; gap:8px; }}
.row {{ display:flex; justify-content:space-between; gap:12px; padding:9px 0; border-bottom:1px solid #edf2f7; font-size:14px; }}
.row:last-child {{ border-bottom:none; }}
.row strong {{ color:#0f172a; }}
.status-word {{ font-family:Consolas,monospace; }}
.links {{ display:flex; gap:8px; flex-wrap:wrap; margin-top:14px; }}
.links a {{ color:#1267b1; text-decoration:none; border:1px solid #cbd8e6; border-radius:6px; padding:7px 10px; background:#fff; font-size:13px; }}
@media (max-width: 860px) {{ .top,.grid {{ display:block; }} .panel {{ margin-bottom:14px; }} }}
</style>
</head>
<body>
<div class="wrap">
  <div class="top">
    <div>
      <h1>UPS Simulator Control</h1>
      <div class="muted">Modbus TCP 127.0.0.1:1502 / Control UI 127.0.0.1:1503</div>
    </div>
    <div class="badge" id="current">...</div>
  </div>
  <div class="grid">
    <div class="panel">
      <h2>시나리오</h2>
      <div class="scenario-grid">{scenarios}</div>
      <h2>차단기 테스트</h2>
      <div class="breaker-grid" id="breakers"></div>
      <button class="reset" id="resetBreakers" type="button">차단기 기본값 복원</button>
      <div class="links">
        <a href="http://localhost:8080/ups/monitoring/ups_status.jsp" target="_blank">실시간 상태</a>
        <a href="http://localhost:8080/ups/monitoring/phasor_diagram.jsp" target="_blank">Phasor Diagram</a>
        <a href="http://localhost:8080/ups/alarm/alarm_view.jsp" target="_blank">알람 화면</a>
        <a href="http://localhost:8080/ups/system/ups_register.jsp" target="_blank">UPS 등록</a>
      </div>
    </div>
    <div class="panel">
      <h2>현재 값</h2>
      <div class="metrics" id="metrics"></div>
    </div>
  </div>
</div>
<script>
const labels = {json.dumps(SCENARIO_LABELS, ensure_ascii=False)};
const metricNames = {{
  output_frequency_hz:'출력 주파수',
  output_voltage_l12:'출력 전압 L1-2',
  output_voltage_l23:'출력 전압 L2-3',
  output_voltage_l31:'출력 전압 L3-1',
  output_current_l1:'출력 전류 L1',
  output_current_l2:'출력 전류 L2',
  output_current_l3:'출력 전류 L3',
  output_load_percent:'부하율',
  output_pf_l1:'역률 L1',
  battery_charge_percent:'배터리 충전율',
  battery_temperature_c:'배터리 온도',
  ups_status_word:'UPS Status',
  input_status:'Input Status',
  output_status:'Output Status',
  power_module_status:'Power Module Status'
}};
const breakerNames = {{
  uib:'UIB',
  uob:'UOB',
  ssib:'SSIB',
  bf2:'BF2',
  mbb:'MBB',
  bb:'BB'
}};
function fmt(k, v) {{
  if (k.endsWith('_status') || k === 'ups_status_word') return '0x' + Number(v).toString(16).toUpperCase().padStart(4, '0');
  if (k.includes('frequency')) return Number(v).toFixed(1) + ' Hz';
  if (k.includes('voltage')) return Number(v).toFixed(0) + ' V';
  if (k.includes('current')) return Number(v).toFixed(0) + ' A';
  if (k.includes('load') || k.includes('charge')) return Number(v).toFixed(1).replace('.0','') + ' %';
  if (k.includes('temperature')) return Number(v).toFixed(1) + ' ℃';
  if (k.includes('pf')) return Number(v).toFixed(2);
  return v;
}}
async function refresh() {{
  const r = await fetch('/api/status', {{cache:'no-store'}});
  const s = await r.json();
  document.getElementById('current').textContent = labels[s.scenario] + ' / ' + s.scenario;
  document.querySelectorAll('.scenario').forEach(b => b.classList.toggle('active', b.dataset.scenario === s.scenario));
  document.getElementById('breakers').innerHTML = Object.keys(breakerNames).map(k => {{
    const closed = !!s.breakers[k];
    return `<button class="breaker ${{closed ? 'closed' : 'open'}}" data-breaker="${{k}}" data-closed="${{closed ? '1' : '0'}}"><strong>${{breakerNames[k]}}</strong><span>${{closed ? 'Closed' : 'Open'}}</span></button>`;
  }}).join('');
  document.querySelectorAll('.breaker').forEach(b => b.addEventListener('click', () => setBreaker(b.dataset.breaker, b.dataset.closed !== '1')));
  document.getElementById('metrics').innerHTML = Object.keys(metricNames).map(k =>
    `<div class="row"><span>${{metricNames[k]}}</span><strong class="${{k.includes('status') ? 'status-word' : ''}}">${{fmt(k, s[k])}}</strong></div>`
  ).join('');
}}
async function setScenario(name) {{
  await fetch('/api/scenario', {{
    method:'POST',
    headers:{{'Content-Type':'application/x-www-form-urlencoded'}},
    body:new URLSearchParams({{scenario:name}})
  }});
  refresh();
}}
async function setBreaker(name, closed) {{
  await fetch('/api/breaker', {{
    method:'POST',
    headers:{{'Content-Type':'application/x-www-form-urlencoded'}},
    body:new URLSearchParams({{name:name, closed:closed ? '1' : '0'}})
  }});
  refresh();
}}
document.querySelectorAll('.scenario').forEach(b => b.addEventListener('click', () => setScenario(b.dataset.scenario)));
document.getElementById('resetBreakers').addEventListener('click', async () => {{
  await fetch('/api/reset-breakers', {{method:'POST'}});
  refresh();
}});
refresh();
setInterval(refresh, 2000);
</script>
</body>
</html>"""
        payload = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)


class ControlServer(ThreadingHTTPServer):
    def __init__(self, server_address: tuple[str, int], state: SimulatorState):
        super().__init__(server_address, ControlHandler)
        self.state = state


def console_loop(state: SimulatorState, server: ThreadedTcpServer) -> None:
    print("Commands: normal, battery, low_battery, overload, input_fault, output_fault,")
    print("          bypass_fault, power_module_fault, critical, status, quit")
    while True:
        try:
            cmd = input("ups-sim> ").strip()
        except EOFError:
            return
        if not cmd:
            continue
        if cmd in ("quit", "exit"):
            server.shutdown()
            return
        if cmd == "status":
            print(f"scenario={state.get_scenario()}")
            continue
        try:
            state.set_scenario(cmd)
            print(f"scenario changed to {cmd}")
        except ValueError as exc:
            print(exc)


def main() -> int:
    parser = argparse.ArgumentParser(description="Schneider UPS Modbus TCP simulator")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=1502)
    parser.add_argument("--control-host", default="127.0.0.1")
    parser.add_argument("--control-port", type=int, default=1503)
    parser.add_argument("--scenario", choices=sorted(SCENARIOS), default="normal")
    parser.add_argument("--no-control", action="store_true", help="disable browser control UI")
    parser.add_argument("--no-console", action="store_true", help="run without interactive scenario commands")
    parser.add_argument("--open-browser", action="store_true", help="open the control UI in the default browser")
    args = parser.parse_args()

    state = SimulatorState(scenario=args.scenario)
    control_server = None
    try:
        server = ThreadedTcpServer((args.host, args.port), ModbusHandler, state)
    except OSError as exc:
        print(f"failed to bind {args.host}:{args.port}: {exc}", file=sys.stderr)
        return 1

    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    print(f"UPS Modbus simulator listening on {args.host}:{args.port}, scenario={args.scenario}")
    print("Register profile: Schneider Easy UPS 3-Phase Modular")

    if not args.no_control:
        try:
            control_server = ControlServer((args.control_host, args.control_port), state)
        except OSError as exc:
            print(f"failed to bind control UI {args.control_host}:{args.control_port}: {exc}", file=sys.stderr)
        else:
            control_thread = threading.Thread(target=control_server.serve_forever, daemon=True)
            control_thread.start()
            control_url = f"http://{args.control_host}:{args.control_port}/"
            print(f"Control UI: {control_url}")
            if args.open_browser:
                webbrowser.open(control_url)

    try:
        if args.no_console:
            while True:
                time.sleep(1)
        else:
            console_loop(state, server)
    except KeyboardInterrupt:
        pass
    finally:
        server.shutdown()
        server.server_close()
        if control_server:
            control_server.shutdown()
            control_server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
