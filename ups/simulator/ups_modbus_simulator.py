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
import urllib.request
import webbrowser
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


SCENARIOS = {
    "normal",
    "battery",
    "bypass",
    "output_off",
    "maintenance_bypass",
    "battery_test",
    "epo",
    "battery_charging",
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
    "bypass": "바이패스 운전",
    "output_off": "출력 OFF",
    "maintenance_bypass": "유지보수 바이패스",
    "battery_test": "배터리 테스트",
    "epo": "EPO 동작",
    "battery_charging": "배터리 충전",
    "low_battery": "배터리 부족",
    "overload": "과부하",
    "input_fault": "입력 이상",
    "output_fault": "출력 이상",
    "bypass_fault": "바이패스 이상",
    "power_module_fault": "파워 모듈 이상",
    "critical": "중요 알람",
}

DEFAULT_BREAKERS = {
    "uib": True,
    "uob": True,
    "ssib": False,
    "bf2": False,
    "mbb": False,
    "bb": True,
}

SCENARIO_BREAKER_PROFILES = {
    "normal": DEFAULT_BREAKERS,
    "battery": {
        "uib": False,
        "uob": True,
        "ssib": False,
        "bf2": False,
        "mbb": False,
        "bb": True,
    },
    "battery_charging": DEFAULT_BREAKERS,
    "battery_test": DEFAULT_BREAKERS,
    "bypass": {
        "uib": True,
        "uob": True,
        "ssib": True,
        "bf2": True,
        "mbb": False,
        "bb": True,
    },
    "maintenance_bypass": {
        "uib": False,
        "uob": False,
        "ssib": False,
        "bf2": False,
        "mbb": True,
        "bb": False,
    },
    "output_off": {
        "uib": True,
        "uob": False,
        "ssib": False,
        "bf2": False,
        "mbb": False,
        "bb": True,
    },
    "epo": {
        "uib": False,
        "uob": False,
        "ssib": False,
        "bf2": False,
        "mbb": False,
        "bb": False,
    },
    "low_battery": {
        "uib": False,
        "uob": True,
        "ssib": False,
        "bf2": False,
        "mbb": False,
        "bb": True,
    },
}

ALARM_TESTS = [
    {"code": "UPS_MIN_RUNTIME", "group": "UPS", "label": "배터리 런타임 최소 이하", "severity": "CRITICAL", "metric": "ups_status_word", "bit": 1},
    {"code": "UPS_BATTERY_INOPERABLE", "group": "UPS", "label": "배터리 사용 불가", "severity": "CRITICAL", "metric": "ups_status_word", "bit": 9},
    {"code": "UPS_CRITICAL_ALARM_PRESENT", "group": "UPS", "label": "UPS 중요 알람 존재", "severity": "CRITICAL", "metric": "ups_status_word", "bit": 15},
    {"code": "BATTERY_CRITICAL", "group": "Battery", "label": "배터리 충전율 위험", "severity": "CRITICAL", "metric": "battery_charge_percent", "value": 5},
    {"code": "BATTERY_TEMP_HIGH", "group": "Battery", "label": "배터리 온도 높음", "severity": "WARNING", "metric": "battery_temperature", "value": 42.0},
    {"code": "BATTERY_HEALTH_ABNORMAL", "group": "Battery", "label": "배터리 상태 이상", "severity": "WARNING", "metric": "battery_health_status", "value": 3},
    {"code": "ENERGY_CHARGER_HIGH_TEMP_SHUTDOWN", "group": "Energy", "label": "고온으로 충전기 정지", "severity": "CRITICAL", "metric": "energy_storage_status", "bit": 5},
    {"code": "ENERGY_MIN_RUNTIME", "group": "Energy", "label": "배터리 런타임 부족", "severity": "CRITICAL", "metric": "energy_storage_status", "bit": 6},
    {"code": "ENERGY_BATTERY_VOLTAGE_MISMATCH", "group": "Energy", "label": "배터리 전압 설정 불일치", "severity": "CRITICAL", "metric": "energy_storage_status", "bit": 7},
    {"code": "ENERGY_BATTERY_POOR", "group": "Energy", "label": "배터리 상태 불량", "severity": "CRITICAL", "metric": "energy_storage_status", "bit": 9},
    {"code": "ENERGY_BATTERY_NOT_WORKING", "group": "Energy", "label": "배터리 동작 이상", "severity": "CRITICAL", "metric": "energy_storage_status", "bit": 14},
    {"code": "ENERGY_HIGH_TEMP_SHUTDOWN", "group": "Energy", "label": "배터리 고온 시스템 정지", "severity": "CRITICAL", "metric": "energy_storage_status_2", "bit": 0},
    {"code": "ENERGY_CONFIG_INCORRECT", "group": "Energy", "label": "배터리 설정 오류", "severity": "CRITICAL", "metric": "energy_storage_status_2", "bit": 1},
    {"code": "ENERGY_LOW_TEMP_CHARGER_SHUTDOWN", "group": "Energy", "label": "저온으로 충전기 정지", "severity": "CRITICAL", "metric": "energy_storage_status_2", "bit": 2},
    {"code": "GENERAL_EPO_ACTIVE", "group": "General", "label": "EPO 스위치 동작", "severity": "CRITICAL", "metric": "general_status", "bit": 0},
    {"code": "GENERAL_INVERTER_BYPASS_PHASE_MISMATCH", "group": "General", "label": "인버터/바이패스 위상 불일치", "severity": "CRITICAL", "metric": "general_status", "bit": 2},
    {"code": "GENERAL_SYSTEM_LOCKED_BYPASS", "group": "General", "label": "바이패스 운전 고정", "severity": "CRITICAL", "metric": "general_status_2", "bit": 9},
    {"code": "GENERAL_UNSUPPORTED_POWER_MODULE", "group": "General", "label": "미지원 파워 모듈", "severity": "CRITICAL", "metric": "general_status_2", "bit": 11},
    {"code": "GENERAL_UNSUPPORTED_SBS", "group": "General", "label": "미지원 정적 바이패스 모듈", "severity": "CRITICAL", "metric": "general_status_2", "bit": 12},
    {"code": "GENERAL_RATING_EXCEEDS_FRAME", "group": "General", "label": "정격 프레임 용량 초과", "severity": "CRITICAL", "metric": "general_status_2", "bit": 14},
    {"code": "GENERAL_NO_POWER_MODULE", "group": "General", "label": "파워 모듈 없음", "severity": "CRITICAL", "metric": "general_status_3", "bit": 2},
    {"code": "GENERAL_SURVEILLANCE_FAULT", "group": "General", "label": "UPS 감시 기능 고장", "severity": "CRITICAL", "metric": "general_status_3", "bit": 13},
    {"code": "GENERAL_MODEL_INCORRECT", "group": "General", "label": "UPS 모델 번호 오류", "severity": "CRITICAL", "metric": "general_status_4", "bit": 4},
    {"code": "INPUT_VOLTAGE_OUT", "group": "Input", "label": "입력 전압 범위 이탈", "severity": "CRITICAL", "metric": "input_status", "bit": 0},
    {"code": "INPUT_PHASE_SEQUENCE", "group": "Input", "label": "입력 상 회전 순서 이상", "severity": "CRITICAL", "metric": "input_status", "bit": 1},
    {"code": "INPUT_FREQ_OUT", "group": "Input", "label": "입력 주파수 범위 이탈", "severity": "CRITICAL", "metric": "input_status", "bit": 2},
    {"code": "INPUT_PHASE_MISSING", "group": "Input", "label": "입력 결상", "severity": "CRITICAL", "metric": "input_status", "bit": 3},
    {"code": "OUTPUT_VOLTAGE_OUT", "group": "Output", "label": "출력 전압 범위 이탈", "severity": "CRITICAL", "metric": "output_status", "bit": 0},
    {"code": "OUTPUT_FREQ_OUT", "group": "Output", "label": "출력 주파수 범위 이탈", "severity": "CRITICAL", "metric": "output_status", "bit": 1},
    {"code": "OUTPUT_OVERLOAD_SHORT", "group": "Output", "label": "UPS 과부하 또는 단락", "severity": "CRITICAL", "metric": "output_status", "bit": 2},
    {"code": "OUTPUT_OVERLOAD_HIGH_AMBIENT", "group": "Output", "label": "고온 UPS 과부하", "severity": "CRITICAL", "metric": "output_status", "bit": 3},
    {"code": "OUTPUT_LOAD_CRITICAL", "group": "Output", "label": "출력 부하율 위험", "severity": "CRITICAL", "metric": "output_load_total_percent", "value": 97},
    {"code": "BYPASS_VOLTAGE_OUT", "group": "Bypass", "label": "바이패스 전압 범위 이탈", "severity": "WARNING", "metric": "bypass_status", "bit": 0},
    {"code": "BYPASS_PHASE_SEQUENCE", "group": "Bypass", "label": "바이패스 상 회전 순서 이상", "severity": "WARNING", "metric": "bypass_status", "bit": 1},
    {"code": "BYPASS_FREQ_OUT", "group": "Bypass", "label": "바이패스 주파수 범위 이탈", "severity": "WARNING", "metric": "bypass_status", "bit": 2},
    {"code": "BYPASS_PHASE_MISSING", "group": "Bypass", "label": "바이패스 결상", "severity": "WARNING", "metric": "bypass_status", "bit": 3},
    {"code": "PARALLEL_REDUNDANCY_LOST", "group": "Parallel", "label": "병렬 이중화 상실", "severity": "CRITICAL", "metric": "parallel_status", "bit": 5},
    {"code": "POWER_MODULE_INOPERABLE", "group": "Power Module", "label": "파워 모듈 사용 불가", "severity": "CRITICAL", "metric": "power_module_status", "bit": 0},
    {"code": "POWER_MODULE_OVERHEATED", "group": "Power Module", "label": "파워 모듈 과열", "severity": "CRITICAL", "metric": "power_module_status", "bit": 2},
    {"code": "POWER_MODULE_FAN_INOPERABLE", "group": "Power Module", "label": "파워 모듈 팬 이상", "severity": "CRITICAL", "metric": "power_module_status", "bit": 7},
    {"code": "POWER_MODULE_SURVEILLANCE_FAULT", "group": "Power Module", "label": "파워 모듈 감시 고장", "severity": "CRITICAL", "metric": "power_module_status", "bit": 9},
    {"code": "POWER_MODULE_PMC_LOST_DISCONNECTED", "group": "Power Module", "label": "PMC 통신 끊김", "severity": "CRITICAL", "metric": "power_module_status", "bit": 10},
]

ALARM_TEST_BY_CODE = {item["code"]: item for item in ALARM_TESTS}

MANUAL_FIELDS = {
    "output_frequency_hz": {"min": 45.0, "max": 65.0},
    "input_voltage_l1n": {"min": 0.0, "max": 400.0},
    "input_voltage_l2n": {"min": 0.0, "max": 400.0},
    "input_voltage_l3n": {"min": 0.0, "max": 400.0},
    "input_voltage_l12": {"min": 0.0, "max": 600.0},
    "input_voltage_l23": {"min": 0.0, "max": 600.0},
    "input_voltage_l31": {"min": 0.0, "max": 600.0},
    "output_voltage_l12": {"min": 0.0, "max": 600.0},
    "output_voltage_l23": {"min": 0.0, "max": 600.0},
    "output_voltage_l31": {"min": 0.0, "max": 600.0},
    "output_current_l1": {"min": 0.0, "max": 1000.0},
    "output_current_l2": {"min": 0.0, "max": 1000.0},
    "output_current_l3": {"min": 0.0, "max": 1000.0},
    "output_load_percent": {"min": 0.0, "max": 150.0},
    "output_power_kw": {"min": 0.0, "max": 10000.0},
    "output_apparent_total_kva": {"min": 0.0, "max": 10000.0},
    "output_pf_l1": {"min": 0.0, "max": 1.0},
    "output_pf_l2": {"min": 0.0, "max": 1.0},
    "output_pf_l3": {"min": 0.0, "max": 1.0},
    "battery_voltage": {"min": 0.0, "max": 1000.0},
    "battery_current": {"min": -1000.0, "max": 1000.0},
    "battery_charge_percent": {"min": 0.0, "max": 100.0},
    "battery_temperature_c": {"min": -40.0, "max": 100.0},
    "remaining_minutes": {"min": 0.0, "max": 1440.0},
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
    breakers: dict[str, bool] = field(default_factory=lambda: dict(DEFAULT_BREAKERS))
    active_alarm_tests: set[str] = field(default_factory=set)
    manual_values: dict[str, float] = field(default_factory=dict)

    def set_scenario(self, scenario: str) -> None:
        if scenario not in SCENARIOS:
            raise ValueError(f"unknown scenario: {scenario}")
        with self.lock:
            self.scenario = scenario
            profile = SCENARIO_BREAKER_PROFILES.get(scenario, DEFAULT_BREAKERS)
            self.breakers.update(profile)

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
            self.breakers.update(DEFAULT_BREAKERS)

    def get_breakers(self) -> dict[str, bool]:
        with self.lock:
            return dict(self.breakers)

    def set_alarm_test(self, code: str, active: bool) -> None:
        key = code.strip().upper()
        if key not in ALARM_TEST_BY_CODE:
            raise ValueError(f"unknown alarm test: {code}")
        with self.lock:
            if active:
                self.active_alarm_tests.add(key)
            else:
                self.active_alarm_tests.discard(key)

    def reset_alarm_tests(self) -> None:
        with self.lock:
            self.active_alarm_tests.clear()

    def get_alarm_tests(self) -> set[str]:
        with self.lock:
            return set(self.active_alarm_tests)

    def set_manual_values(self, values: dict[str, float]) -> None:
        cleaned: dict[str, float] = {}
        for key, raw in values.items():
            if key not in MANUAL_FIELDS:
                raise ValueError(f"unknown manual field: {key}")
            try:
                value = float(raw)
            except (TypeError, ValueError):
                raise ValueError(f"invalid value for {key}: {raw}")
            limits = MANUAL_FIELDS[key]
            value = max(float(limits["min"]), min(float(limits["max"]), value))
            cleaned[key] = value
        with self.lock:
            self.manual_values.update(cleaned)

    def reset_manual_values(self) -> None:
        with self.lock:
            self.manual_values.clear()

    def get_manual_values(self) -> dict[str, float]:
        with self.lock:
            return dict(self.manual_values)

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
            "input_voltage_l1n": regs.get(4097, 0),
            "input_voltage_l2n": regs.get(4098, 0),
            "input_voltage_l3n": regs.get(4099, 0),
            "input_voltage_l12": regs.get(4100, 0),
            "input_voltage_l23": regs.get(4101, 0),
            "input_voltage_l31": regs.get(4102, 0),
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
            "ups_operation_mode_code": (
                6 if scenario in ("output_off", "epo", "output_fault")
                else 7 if scenario == "battery_test"
                else 5 if scenario in ("bypass", "maintenance_bypass")
                else 4 if scenario in ("battery", "low_battery", "input_fault")
                else 2
            ),
            "system_operation_mode_code": (
                6 if scenario in ("output_off", "epo", "output_fault")
                else 8 if scenario == "maintenance_bypass"
                else 5 if scenario == "bypass"
                else 2
            ),
            "ups_status_word": regs.get(1, 0),
            "input_status": regs.get(11, 0),
            "output_status": regs.get(12, 0),
            "power_module_status": regs.get(14, 0),
            "bypass_status": regs.get(2, 0),
            "energy_storage_status": regs.get(3, 0),
            "energy_storage_status_2": regs.get(4, 0),
            "general_status": regs.get(5, 0),
            "general_status_2": regs.get(6, 0),
            "general_status_3": regs.get(7, 0),
            "general_status_4": regs.get(8, 0),
            "parallel_status": regs.get(13, 0),
            "battery_health_status": regs.get(4880, 0),
            "active_alarm_tests": sorted(self.get_alarm_tests()),
            "manual_values": self.get_manual_values(),
        }

    def registers(self) -> dict[int, int]:
        scenario = self.get_scenario()
        wave = 0

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
        input_voltage_l1n = 220
        input_voltage_l2n = 221
        input_voltage_l3n = 219
        input_voltage_l12 = 380
        input_voltage_l23 = 381
        input_voltage_l31 = 379
        output_voltage_l12 = 380
        output_voltage_l23 = 381
        output_voltage_l31 = 379
        output_frequency_hz = 60.0
        output_current_l1 = 38
        output_current_l2 = 37
        output_current_l3 = 39
        output_power_total = 40
        output_power_l1 = 13
        output_power_l2 = 13
        output_power_l3 = 14
        output_kva_total = 43
        output_kva_l1 = 14
        output_kva_l2 = 14
        output_kva_l3 = 15
        battery_charge = 96
        battery_current = 4
        remaining_seconds = 7200
        battery_health = 1
        battery_temperature = 28.5
        ups_mode = 2
        system_mode = 2

        if scenario == "battery":
            ups_status |= 1 << 0
            energy_status |= 1 << 4
            battery_current = -35
            remaining_seconds = 2700
            battery_charge = 72
            ups_mode = 4
        elif scenario == "bypass":
            ups_mode = 5
            system_mode = 5
        elif scenario == "output_off":
            ups_mode = 6
            system_mode = 6
            output_load = 0
            output_voltage_l12 = output_voltage_l23 = output_voltage_l31 = 0
            output_frequency_hz = 0.0
            output_current_l1 = output_current_l2 = output_current_l3 = 0
            output_power_total = output_power_l1 = output_power_l2 = output_power_l3 = 0
            output_kva_total = output_kva_l1 = output_kva_l2 = output_kva_l3 = 0
            battery_current = 0
        elif scenario == "maintenance_bypass":
            ups_mode = 5
            system_mode = 8
        elif scenario == "battery_test":
            ups_mode = 7
            battery_current = -12
            remaining_seconds = 5400
            battery_charge = 88
        elif scenario == "epo":
            ups_status |= 1 << 15
            general_status |= 1 << 0
            output_status |= 1 << 0
            ups_mode = 6
            system_mode = 6
            output_load = 0
            output_voltage_l12 = output_voltage_l23 = output_voltage_l31 = 0
            output_frequency_hz = 0.0
            output_current_l1 = output_current_l2 = output_current_l3 = 0
            output_power_total = output_power_l1 = output_power_l2 = output_power_l3 = 0
            output_kva_total = output_kva_l1 = output_kva_l2 = output_kva_l3 = 0
        elif scenario == "battery_charging":
            battery_current = 25
            battery_charge = 88
            remaining_seconds = 7200
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
            input_voltage_l1n = input_voltage_l2n = input_voltage_l3n = 0
            input_voltage_l12 = input_voltage_l23 = input_voltage_l31 = 0
            battery_current = -32
            remaining_seconds = 3600
            battery_charge = min(battery_charge, 86)
            ups_mode = 4
            system_mode = 4
        elif scenario == "output_fault":
            ups_status |= 1 << 15
            output_status |= (1 << 0) | (1 << 1)
            ups_mode = 6
            system_mode = 6
            output_load = 0
            output_voltage_l12 = output_voltage_l23 = output_voltage_l31 = 0
            output_frequency_hz = 0.0
            output_current_l1 = output_current_l2 = output_current_l3 = 0
            output_power_total = output_power_l1 = output_power_l2 = output_power_l3 = 0
            output_kva_total = output_kva_l1 = output_kva_l2 = output_kva_l3 = 0
            battery_current = 0
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

        status_values = {
            "ups_status_word": ups_status,
            "bypass_status": bypass_status,
            "energy_storage_status": energy_status,
            "energy_storage_status_2": energy_status_2,
            "general_status": general_status,
            "general_status_2": general_status_2,
            "general_status_3": general_status_3,
            "general_status_4": general_status_4,
            "input_status": input_status,
            "output_status": output_status,
            "parallel_status": parallel_status,
            "power_module_status": power_module_status,
        }
        for code in self.get_alarm_tests():
            test = ALARM_TEST_BY_CODE.get(code)
            if not test:
                continue
            metric = str(test["metric"])
            if "bit" in test:
                status_values[metric] = status_values.get(metric, 0) | (1 << int(test["bit"]))
            elif metric == "battery_charge_percent":
                battery_charge = min(battery_charge, int(test["value"]))
            elif metric == "battery_temperature":
                battery_temperature = max(battery_temperature, float(test["value"]))
            elif metric == "battery_health_status":
                battery_health = max(battery_health, int(test["value"]))
            elif metric == "output_load_total_percent":
                output_load = max(output_load, int(test["value"]))

        manual_values = self.get_manual_values()
        if "output_load_percent" in manual_values:
            output_load = manual_values["output_load_percent"]
        if "battery_charge_percent" in manual_values:
            battery_charge = int(round(manual_values["battery_charge_percent"]))
        if "battery_temperature_c" in manual_values:
            battery_temperature = manual_values["battery_temperature_c"]
        if "battery_current" in manual_values:
            battery_current = int(round(manual_values["battery_current"]))
        if "remaining_minutes" in manual_values:
            remaining_seconds = int(round(manual_values["remaining_minutes"] * 60))

        ups_status = status_values["ups_status_word"]
        bypass_status = status_values["bypass_status"]
        energy_status = status_values["energy_storage_status"]
        energy_status_2 = status_values["energy_storage_status_2"]
        general_status = status_values["general_status"]
        general_status_2 = status_values["general_status_2"]
        general_status_3 = status_values["general_status_3"]
        general_status_4 = status_values["general_status_4"]
        input_status = status_values["input_status"]
        output_status = status_values["output_status"]
        parallel_status = status_values["parallel_status"]
        power_module_status = status_values["power_module_status"]

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

        # Input.
        regs[4097] = u16(input_voltage_l1n)
        regs[4098] = u16(input_voltage_l2n)
        regs[4099] = u16(input_voltage_l3n)
        regs[4100] = u16(input_voltage_l12)
        regs[4101] = u16(input_voltage_l23)
        regs[4102] = u16(input_voltage_l31)

        # Output.
        regs[4608] = u16(round(output_frequency_hz * 10))
        regs[4609] = 220
        regs[4610] = 221
        regs[4611] = 219
        regs[4612] = u16(output_voltage_l12 + wave)
        regs[4613] = u16(output_voltage_l23)
        regs[4614] = u16(output_voltage_l31)
        regs[4615] = u16(output_current_l1 + max(wave, 0))
        regs[4616] = u16(output_current_l2)
        regs[4617] = u16(output_current_l3)
        regs[4618] = u16(output_power_l1)
        regs[4619] = u16(output_power_l2)
        regs[4620] = u16(output_power_l3)
        regs[4621] = u16(output_kva_l1)
        regs[4622] = u16(output_kva_l2)
        regs[4623] = u16(output_kva_l3)
        regs[4624] = u16(output_load * 10)
        regs[4625] = u16((output_load - 1) * 10)
        regs[4626] = u16((output_load + 1) * 10)
        regs[4627] = u16(output_power_total)
        regs[4628] = 96
        regs[4629] = 95
        regs[4630] = 97
        regs[4631] = u16(output_kva_total)
        regs[4632] = u16(output_load * 10)

        # Battery.
        regs[4864] = int(round(battery_temperature * 10))
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

        if "output_frequency_hz" in manual_values:
            regs[4608] = u16(round(manual_values["output_frequency_hz"] * 10))
        for key, address in {
            "input_voltage_l1n": 4097,
            "input_voltage_l2n": 4098,
            "input_voltage_l3n": 4099,
            "input_voltage_l12": 4100,
            "input_voltage_l23": 4101,
            "input_voltage_l31": 4102,
            "output_voltage_l12": 4612,
            "output_voltage_l23": 4613,
            "output_voltage_l31": 4614,
            "output_current_l1": 4615,
            "output_current_l2": 4616,
            "output_current_l3": 4617,
            "output_power_kw": 4627,
            "output_apparent_total_kva": 4631,
            "battery_voltage": 4865,
        }.items():
            if key in manual_values:
                regs[address] = u16(round(manual_values[key]))
        for key, address in {
            "output_pf_l1": 4628,
            "output_pf_l2": 4629,
            "output_pf_l3": 4630,
        }.items():
            if key in manual_values:
                regs[address] = u16(round(manual_values[key] * 100))

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
            if parsed.path == "/api/alarm-test":
                self._post_alarm_test()
                return
            if parsed.path == "/api/reset-alarm-tests":
                self.server.state.reset_alarm_tests()  # type: ignore[attr-defined]
                self._json({"ok": True, **self.server.state.snapshot()})  # type: ignore[attr-defined]
                return
            if parsed.path == "/api/manual-values":
                self._post_manual_values()
                return
            if parsed.path == "/api/reset-manual-values":
                self.server.state.reset_manual_values()  # type: ignore[attr-defined]
                self._json({"ok": True, **self.server.state.snapshot()})  # type: ignore[attr-defined]
                return
            if parsed.path == "/api/shutdown":
                self._json({"ok": True})
                self.server.stop_event.set()  # type: ignore[attr-defined]
                return
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(length).decode("utf-8") if length else ""
        data = urllib.parse.parse_qs(raw)
        scenario = (data.get("scenario", [""])[0] or "").strip()
        try:
            before = self.server.state.get_scenario()  # type: ignore[attr-defined]
            self.server.state.set_scenario(scenario)  # type: ignore[attr-defined]
        except ValueError as exc:
            self._json({"ok": False, "error": str(exc)}, status=400)
            return
        # A repeated click is still useful during simulator testing, so record it
        # as a current-state event instead of dropping it as "no change".
        self._send_scenario_event("" if before == scenario else before, scenario)
        self._json({"ok": True, **self.server.state.snapshot()})  # type: ignore[attr-defined]

    def _post_breaker(self) -> None:
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(length).decode("utf-8") if length else ""
        data = urllib.parse.parse_qs(raw)
        name = (data.get("name", [""])[0] or "").strip()
        closed_raw = (data.get("closed", [""])[0] or "").strip().lower()
        closed = closed_raw in ("1", "true", "yes", "closed", "on")
        try:
            before = bool(self.server.state.get_breakers().get(name, False))  # type: ignore[attr-defined]
            self.server.state.set_breaker(name, closed)  # type: ignore[attr-defined]
        except ValueError as exc:
            self._json({"ok": False, "error": str(exc)}, status=400)
            return
        self._send_breaker_event(name, before, closed)
        self._json({"ok": True, **self.server.state.snapshot()})  # type: ignore[attr-defined]

    def _post_alarm_test(self) -> None:
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(length).decode("utf-8") if length else ""
        data = urllib.parse.parse_qs(raw)
        code = (data.get("code", [""])[0] or "").strip()
        active_raw = (data.get("active", [""])[0] or "").strip().lower()
        active = active_raw in ("1", "true", "yes", "active", "on")
        try:
            self.server.state.set_alarm_test(code, active)  # type: ignore[attr-defined]
        except ValueError as exc:
            self._json({"ok": False, "error": str(exc)}, status=400)
            return
        self._send_alarm_test(code, active)
        self._json({"ok": True, **self.server.state.snapshot()})  # type: ignore[attr-defined]

    def _post_manual_values(self) -> None:
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(length).decode("utf-8") if length else ""
        data = urllib.parse.parse_qs(raw)
        values: dict[str, float] = {}
        for key in MANUAL_FIELDS:
            if key not in data:
                continue
            raw_value = (data.get(key, [""])[0] or "").strip()
            if raw_value == "":
                continue
            try:
                values[key] = float(raw_value)
            except ValueError:
                self._json({"ok": False, "error": f"invalid value for {key}"}, status=400)
                return
        try:
            self.server.state.set_manual_values(values)  # type: ignore[attr-defined]
        except ValueError as exc:
            self._json({"ok": False, "error": str(exc)}, status=400)
            return
        self._json({"ok": True, **self.server.state.snapshot()})  # type: ignore[attr-defined]

    def _send_breaker_event(self, name: str, before: bool, after: bool) -> None:
        if before == after:
            return
        params = urllib.parse.urlencode({
            "name": name,
            "before": "closed" if before else "open",
            "after": "closed" if after else "open",
        })
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:8080/ups/api/simulator_breaker_event.jsp?{params}", timeout=0.5) as resp:
                resp.read(256)
        except Exception:
            pass

    def _send_scenario_event(self, before: str, after: str) -> None:
        if before == after:
            return
        params = urllib.parse.urlencode({"before": before, "after": after})
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:8080/ups/api/simulator_scenario_event.jsp?{params}", timeout=0.5) as resp:
                resp.read(256)
        except Exception:
            pass

    def _send_alarm_test(self, code: str, active: bool) -> None:
        params = urllib.parse.urlencode({"code": code, "active": "1" if active else "0"})
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:8080/ups/api/simulator_alarm_test.jsp?{params}", timeout=0.5) as resp:
                resp.read(256)
        except Exception:
            pass

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
            for name in ["normal", "battery", "battery_charging", "bypass", "maintenance_bypass", "output_off", "battery_test", "epo", "low_battery", "overload", "input_fault", "output_fault", "bypass_fault", "power_module_fault", "critical"]
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
.wrap {{ width:min(100%, 1800px); margin:0 auto; padding:18px 22px; }}
.top {{ display:flex; justify-content:space-between; gap:16px; align-items:flex-start; margin-bottom:18px; }}
h1 {{ margin:0 0 6px; font-size:28px; }}
.muted {{ color:#64748b; font-size:13px; }}
.top-actions {{ display:flex; align-items:center; justify-content:flex-end; gap:8px; flex-wrap:wrap; }}
.badge {{ display:inline-flex; align-items:center; min-height:34px; padding:6px 12px; border-radius:999px; background:#fff; border:1px solid #d7e1ec; font-weight:700; }}
.sim-control {{ border:1px solid #cbd8e6; border-radius:6px; background:#fff; color:#172033; min-height:34px; padding:7px 12px; font-weight:800; cursor:pointer; text-decoration:none; display:inline-flex; align-items:center; }}
.sim-control.running {{ background:#ecfdf3; border-color:#86efac; color:#166534; cursor:default; }}
.sim-control.stop {{ background:#dc2626; border-color:#dc2626; color:#fff; }}
.sim-control.manage {{ background:#eff6ff; border-color:#bfdbfe; color:#1d4ed8; }}
.panel {{ background:#fff; border:1px solid #d7e1ec; border-radius:8px; padding:16px; }}
.panel + .panel {{ margin-top:12px; }}
.scenario-breaker-row {{ display:grid; grid-template-columns:minmax(0, 1.45fr) minmax(520px, 1fr); gap:12px; margin-top:12px; align-items:start; }}
.scenario-breaker-row .panel {{ margin-top:0; height:100%; }}
.scenario-breaker-row + .panel {{ margin-top:12px; }}
.status-panel {{ margin-bottom:0; padding:12px; }}
.status-panel h2 {{ margin:0 0 8px; font-size:18px; }}
.status-summary {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(138px,1fr)); gap:6px; }}
.status-card {{ border:1px solid #d7e1ec; border-radius:6px; background:#f8fafc; padding:7px 8px; min-width:0; }}
.status-card strong {{ display:block; margin-bottom:3px; color:#0f172a; font-size:11px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }}
.status-value {{ font:800 14px Consolas,monospace; color:#1267b1; }}
.status-dec {{ margin-left:4px; color:#475569; font:700 10px Consolas,monospace; }}
.status-bits {{ margin-top:3px; color:#64748b; font-size:10px; line-height:1.25; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }}
.status-bits b {{ color:#b91c1c; }}
.section-head {{ display:flex; justify-content:space-between; align-items:center; gap:12px; min-height:36px; margin-bottom:12px; }}
.section-head h2 {{ margin:0; }}
.scenario-grid {{ display:grid; grid-template-columns:repeat(auto-fill,150px); gap:10px; justify-content:start; }}
button.scenario {{ border:1px solid #cbd8e6; border-radius:8px; background:#f8fafc; color:#172033; padding:9px 10px; text-align:center; cursor:pointer; min-height:58px; width:100%; display:flex; flex-direction:column; justify-content:center; align-items:center; }}
button.scenario strong {{ display:block; font-size:14px; margin-bottom:3px; }}
button.scenario span {{ color:#64748b; font-size:12px; }}
button.scenario.active {{ border-color:#1267b1; background:#eaf4ff; box-shadow:inset 0 0 0 1px #1267b1; }}
.breaker-grid {{ display:grid; grid-template-columns:repeat(auto-fill,150px); gap:10px; justify-content:start; margin-top:0; }}
button.breaker {{ border:1px solid #cbd8e6; border-radius:8px; background:#fff; color:#172033; padding:9px 10px; cursor:pointer; text-align:center; min-height:58px; width:100%; display:flex; flex-direction:column; justify-content:center; align-items:center; }}
button.breaker strong {{ display:block; font-size:14px; margin-bottom:3px; }}
button.breaker span {{ display:block; font-size:12px; color:#64748b; }}
button.breaker.closed {{ border-color:#169b45; background:#ecfdf3; }}
button.breaker.open {{ border-color:#9ca3af; background:#f8fafc; }}
.alarm-test-grid {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(165px,1fr)); gap:8px; }}
.alarm-group {{ grid-column:1/-1; margin-top:8px; padding:8px 0 2px; border-bottom:2px solid #d7e1ec; font-size:13px; color:#334155; font-weight:800; }}
button.alarm-test {{ border:1px solid #cbd8e6; border-radius:8px; background:#fff; color:#172033; padding:10px; cursor:pointer; text-align:left; min-height:66px; }}
button.alarm-test strong {{ display:block; font-size:14px; margin-bottom:5px; }}
button.alarm-test span {{ display:block; color:#64748b; font-size:12px; }}
button.alarm-test.active {{ border-color:#dc2626; background:#fff1f2; box-shadow:inset 0 0 0 1px #dc2626; }}
.sev-critical {{ color:#b91c1c; font-weight:800; }}
.sev-warning {{ color:#b45309; font-weight:800; }}
button.reset {{ margin-top:10px; border:1px solid #cbd8e6; border-radius:6px; background:#fff; padding:8px 10px; cursor:pointer; }}
.section-head button.reset {{ margin-top:0; flex:0 0 auto; }}
.metrics {{ display:grid; grid-template-columns:repeat(6,minmax(205px,1fr)); gap:10px; align-items:start; overflow-x:auto; padding-bottom:2px; }}
.metric-group {{ border:1px solid #d7e1ec; border-radius:8px; background:#fbfdff; padding:10px; min-width:0; }}
.metric-section-title {{ margin:0 0 4px; padding:0 0 6px; border-bottom:2px solid #cbd8e6; color:#334155; font-size:13px; font-weight:800; text-transform:uppercase; letter-spacing:.04em; }}
.metric-section-title:first-child {{ margin-top:0; }}
.row {{ display:flex; justify-content:space-between; gap:8px; padding:8px 0; border-bottom:1px solid #edf2f7; font-size:13px; min-width:0; }}
.row > span:first-child {{ min-width:0; flex:1 1 auto; overflow:visible; white-space:normal; line-height:1.25; word-break:keep-all; }}
.row:last-child {{ border-bottom:none; }}
.row strong {{ color:#0f172a; }}
.row.editable {{ align-items:center; }}
.metric-edit {{ width:74px; border:1px solid #cbd8e6; border-radius:6px; padding:6px 7px; text-align:right; font:700 13px Consolas,monospace; color:#0f172a; background:#fff; }}
.metric-edit:focus {{ border-color:#1267b1; outline:none; box-shadow:0 0 0 2px rgba(18,103,177,.12); }}
.metric-edit.dirty {{ border-color:#f59e0b; background:#fffbeb; }}
.metric-unit {{ min-width:28px; color:#64748b; font-size:12px; }}
.metric-control {{ display:flex; align-items:center; gap:4px; flex:0 0 auto; }}
.metric-help {{ margin:0 0 10px; color:#64748b; font-size:12px; line-height:1.45; }}
.status-word {{ font-family:Consolas,monospace; }}
.links {{ display:flex; gap:8px; flex-wrap:wrap; margin-top:14px; }}
.links a {{ color:#1267b1; text-decoration:none; border:1px solid #cbd8e6; border-radius:6px; padding:7px 10px; background:#fff; font-size:13px; }}
@media (max-width: 1100px) {{ .scenario-breaker-row {{ grid-template-columns:1fr; }} }}
@media (max-width: 1300px) {{ .metrics {{ grid-template-columns:repeat(3,minmax(240px,1fr)); }} }}
@media (max-width: 860px) {{ .wrap {{ padding:14px; }} .top {{ display:block; }} .top-actions {{ justify-content:flex-start; margin-top:12px; }} .panel {{ margin-bottom:14px; }} .panel + .panel {{ margin-top:0; }} .scenario-breaker-row {{ margin-top:0; gap:0; }} .scenario-breaker-row + .panel {{ margin-top:0; }} .metrics {{ grid-template-columns:1fr; }} }}
</style>
</head>
<body>
<div class="wrap">
  <div class="top">
    <div>
      <h1>UPS Simulator Control</h1>
      <div class="muted">Modbus TCP 127.0.0.1:1502 / Control UI 127.0.0.1:1503</div>
    </div>
    <div class="top-actions">
      <span class="sim-control running">실행 중</span>
      <button class="sim-control stop" id="stopSimulator" type="button">시뮬레이터 정지</button>
      <a class="sim-control manage" href="http://127.0.0.1:8080/ups/simulator/index.jsp" target="_blank">실행/정지 화면</a>
      <div class="badge" id="current">...</div>
    </div>
  </div>
  <div class="panel status-panel">
    <h2>Status Word</h2>
    <div class="status-summary" id="statusSummary"></div>
  </div>
  <div class="scenario-breaker-row">
    <div class="panel">
      <div class="section-head">
        <h2>시나리오</h2>
        <span></span>
      </div>
      <div class="scenario-grid">{scenarios}</div>
    </div>
    <div class="panel">
      <div class="section-head">
        <h2>차단기 테스트</h2>
        <button class="reset" id="resetBreakers" type="button">차단기 기본값 복원</button>
      </div>
      <div class="breaker-grid" id="breakers"></div>
    </div>
  </div>
  <div class="panel">
    <div class="section-head">
      <h2>현재 값</h2>
      <button class="reset" id="resetManualValues" type="button">현재 값 입력 초기화</button>
    </div>
    <p class="metric-help">입력 가능한 값은 변경 후 Enter 또는 포커스 이동 시 시뮬레이터에 즉시 반영됩니다.</p>
    <div class="metrics" id="metrics"></div>
  </div>
  <div class="panel">
    <div class="section-head">
      <h2>세부 알람 테스트</h2>
      <button class="reset" id="resetAlarmTests" type="button">세부 알람 전체 해제</button>
    </div>
    <div class="alarm-test-grid" id="alarmTests"></div>
    <div class="links">
      <a href="http://localhost:8080/ups/monitoring/ups_status.jsp" target="_blank">실시간 상태</a>
      <a href="http://localhost:8080/ups/alarm/alarm_view.jsp" target="_blank">알람 화면</a>
      <a href="http://localhost:8080/ups/alarm/event_view.jsp" target="_blank">이벤트 화면</a>
      <a href="http://localhost:8080/ups/monitoring/phasor_diagram.jsp" target="_blank">Phasor Diagram</a>
      <a href="http://localhost:8080/ups/system/ups_register.jsp" target="_blank">UPS 등록</a>
    </div>
  </div>
</div>
<script>
const labels = {json.dumps(SCENARIO_LABELS, ensure_ascii=False)};
const alarmTests = {json.dumps(ALARM_TESTS, ensure_ascii=False)};
const editableMetrics = {json.dumps(sorted(MANUAL_FIELDS.keys()), ensure_ascii=False)};
const editableMetricSet = new Set(editableMetrics);
const metricNames = {{
  output_frequency_hz:'출력 주파수',
  input_voltage_l1n:'입력 전압 L1-N',
  input_voltage_l2n:'입력 전압 L2-N',
  input_voltage_l3n:'입력 전압 L3-N',
  input_voltage_l12:'입력 전압 L1-2',
  input_voltage_l23:'입력 전압 L2-3',
  input_voltage_l31:'입력 전압 L3-1',
  output_voltage_l12:'출력 전압 L1-2',
  output_voltage_l23:'출력 전압 L2-3',
  output_voltage_l31:'출력 전압 L3-1',
  output_current_l1:'출력 전류 L1',
  output_current_l2:'출력 전류 L2',
  output_current_l3:'출력 전류 L3',
  output_load_percent:'부하율',
  output_power_kw:'출력 전력',
  output_apparent_total_kva:'피상 전력',
  output_pf_l1:'역률 L1',
  output_pf_l2:'역률 L2',
  output_pf_l3:'역률 L3',
  battery_voltage:'배터리 전압',
  battery_current:'배터리 전류',
  battery_charge_percent:'배터리 충전율',
  battery_temperature_c:'배터리 온도',
  remaining_minutes:'남은 시간',
  ups_status_word:'UPS Status',
  bypass_status:'Bypass Status',
  energy_storage_status:'Energy Storage 1',
  energy_storage_status_2:'Energy Storage 2',
  general_status:'General Status 1',
  general_status_2:'General Status 2',
  general_status_3:'General Status 3',
  general_status_4:'General Status 4',
  input_status:'Input Status',
  output_status:'Output Status',
  parallel_status:'Parallel Status',
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
const metricGroups = [
  ['Frequency', ['output_frequency_hz']],
  ['Input Voltage', ['input_voltage_l1n', 'input_voltage_l2n', 'input_voltage_l3n', 'input_voltage_l12', 'input_voltage_l23', 'input_voltage_l31']],
  ['Output Voltage', ['output_voltage_l12', 'output_voltage_l23', 'output_voltage_l31']],
  ['Current / Load', ['output_current_l1', 'output_current_l2', 'output_current_l3', 'output_load_percent', 'output_power_kw', 'output_apparent_total_kva']],
  ['Power Factor', ['output_pf_l1', 'output_pf_l2', 'output_pf_l3']],
  ['Battery', ['battery_voltage', 'battery_current', 'battery_charge_percent', 'battery_temperature_c', 'remaining_minutes']]
];
const statusMetricKeys = [
  'ups_status_word',
  'input_status',
  'output_status',
  'bypass_status',
  'energy_storage_status',
  'energy_storage_status_2',
  'general_status',
  'general_status_2',
  'general_status_3',
  'general_status_4',
  'parallel_status',
  'power_module_status'
];
const metricUnits = {{
  output_frequency_hz:'Hz',
  input_voltage_l1n:'V',
  input_voltage_l2n:'V',
  input_voltage_l3n:'V',
  input_voltage_l12:'V',
  input_voltage_l23:'V',
  input_voltage_l31:'V',
  output_voltage_l12:'V',
  output_voltage_l23:'V',
  output_voltage_l31:'V',
  output_current_l1:'A',
  output_current_l2:'A',
  output_current_l3:'A',
  output_load_percent:'%',
  output_power_kw:'kW',
  output_apparent_total_kva:'kVA',
  output_pf_l1:'',
  output_pf_l2:'',
  output_pf_l3:'',
  battery_voltage:'V',
  battery_current:'A',
  battery_charge_percent:'%',
  battery_temperature_c:'℃',
  remaining_minutes:'min'
}};
function fmt(k, v) {{
  if (k.includes('status') || k === 'ups_status_word') return '0x' + Number(v).toString(16).toUpperCase().padStart(4, '0');
  if (k.includes('frequency')) return Number(v).toFixed(1) + ' Hz';
  if (k.includes('voltage')) return Number(v).toFixed(0) + ' V';
  if (k.includes('current')) return Number(v).toFixed(0) + ' A';
  if (k.includes('load') || k.includes('charge')) return Number(v).toFixed(1).replace('.0','') + ' %';
  if (k.includes('temperature')) return Number(v).toFixed(1) + ' ℃';
  if (k.includes('pf')) return Number(v).toFixed(2);
  return v;
}}
function inputValue(k, v) {{
  const n = Number(v || 0);
  if (k.includes('pf')) return n.toFixed(2);
  if (k.includes('frequency') || k.includes('temperature') || k.includes('load') || k.includes('charge') || k === 'remaining_minutes') return n.toFixed(1).replace('.0','');
  return n.toFixed(0);
}}
function renderMetricRow(k, s) {{
  if (!editableMetricSet.has(k)) {{
    return `<div class="row"><span>${{metricNames[k]}}</span><strong class="${{k.includes('status') ? 'status-word' : ''}}">${{fmt(k, s[k])}}</strong></div>`;
  }}
  const focused = document.activeElement && document.activeElement.dataset && document.activeElement.dataset.metric === k;
  const currentValue = focused ? document.activeElement.value : inputValue(k, s[k]);
  return `<div class="row editable"><span>${{metricNames[k]}}</span><span class="metric-control"><input class="metric-edit" type="number" step="0.1" data-metric="${{k}}" value="${{currentValue}}"><span class="metric-unit">${{metricUnits[k] || ''}}</span></span></div>`;
}}
function activeBits(value) {{
  const n = Number(value || 0);
  const bits = [];
  for (let i = 0; i < 16; i++) {{
    if (n & (1 << i)) bits.push(i);
  }}
  return bits;
}}
function renderStatusSummary(s) {{
  document.getElementById('statusSummary').innerHTML = statusMetricKeys.map(k => {{
    const n = Number(s[k] || 0);
    const hex = '0x' + n.toString(16).toUpperCase().padStart(4, '0');
    const bits = activeBits(n);
    const bitText = bits.length ? `<b>ON bit</b> ${{bits.join(', ')}}` : 'ON bit 없음';
    return `<div class="status-card"><strong>${{metricNames[k]}}</strong><span class="status-value">${{hex}}</span><span class="status-dec">${{n}}</span><div class="status-bits">${{bitText}}</div></div>`;
  }}).join('');
}}
async function refresh() {{
  const r = await fetch('/api/status', {{cache:'no-store'}});
  const s = await r.json();
  document.getElementById('current').textContent = labels[s.scenario] + ' / ' + s.scenario;
  renderStatusSummary(s);
  document.querySelectorAll('.scenario').forEach(b => b.classList.toggle('active', b.dataset.scenario === s.scenario));
  document.getElementById('breakers').innerHTML = Object.keys(breakerNames).map(k => {{
    const closed = !!s.breakers[k];
    return `<button class="breaker ${{closed ? 'closed' : 'open'}}" data-breaker="${{k}}" data-closed="${{closed ? '1' : '0'}}"><strong>${{breakerNames[k]}}</strong><span>${{closed ? 'Closed' : 'Open'}}</span></button>`;
  }}).join('');
  document.querySelectorAll('.breaker').forEach(b => b.addEventListener('click', () => setBreaker(b.dataset.breaker, b.dataset.closed !== '1')));
  const activeAlarmTests = new Set(s.active_alarm_tests || []);
  let lastGroup = '';
  document.getElementById('alarmTests').innerHTML = alarmTests.map(t => {{
    const group = t.group || '';
    const heading = group !== lastGroup ? (lastGroup = group, `<div class="alarm-group">${{group}}</div>`) : '';
    const active = activeAlarmTests.has(t.code);
    const sev = String(t.severity || '').toLowerCase();
    return heading + `<button class="alarm-test ${{active ? 'active' : ''}}" data-code="${{t.code}}" data-active="${{active ? '1' : '0'}}"><strong>${{t.label}}</strong><span class="sev-${{sev}}">${{t.severity}}</span><span>${{t.code}}</span></button>`;
  }}).join('');
  document.querySelectorAll('.alarm-test').forEach(b => b.addEventListener('click', () => setAlarmTest(b.dataset.code, b.dataset.active !== '1')));
  const editingMetric = document.activeElement && document.activeElement.classList && document.activeElement.classList.contains('metric-edit');
  if (!editingMetric) {{
    document.getElementById('metrics').innerHTML = metricGroups.map(group =>
      `<div class="metric-group"><div class="metric-section-title">${{group[0]}}</div>` +
      group[1].map(k => renderMetricRow(k, s)).join('') +
      `</div>`
    ).join('');
    document.querySelectorAll('.metric-edit').forEach(input => {{
      input.addEventListener('input', () => input.classList.add('dirty'));
      input.addEventListener('keydown', event => {{
        if (event.key === 'Enter') {{
          event.preventDefault();
          saveManualValue(input);
        }}
      }});
      input.addEventListener('change', () => saveManualValue(input));
      input.addEventListener('blur', () => {{
        if (input.classList.contains('dirty')) saveManualValue(input);
      }});
    }});
  }}
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
async function setAlarmTest(code, active) {{
  await fetch('/api/alarm-test', {{
    method:'POST',
    headers:{{'Content-Type':'application/x-www-form-urlencoded'}},
    body:new URLSearchParams({{code:code, active:active ? '1' : '0'}})
  }});
  refresh();
}}
async function saveManualValue(input) {{
  const key = input.dataset.metric;
  const value = input.value;
  input.classList.remove('dirty');
  await fetch('/api/manual-values', {{
    method:'POST',
    headers:{{'Content-Type':'application/x-www-form-urlencoded'}},
    body:new URLSearchParams({{[key]:value}})
  }});
  refresh();
}}
document.querySelectorAll('.scenario').forEach(b => b.addEventListener('click', () => setScenario(b.dataset.scenario)));
document.getElementById('resetBreakers').addEventListener('click', async () => {{
  await fetch('/api/reset-breakers', {{method:'POST'}});
  refresh();
}});
document.getElementById('resetAlarmTests').addEventListener('click', async () => {{
  await fetch('/api/reset-alarm-tests', {{method:'POST'}});
  refresh();
}});
document.getElementById('resetManualValues').addEventListener('click', async () => {{
  await fetch('/api/reset-manual-values', {{method:'POST'}});
  refresh();
}});
document.getElementById('stopSimulator').addEventListener('click', async () => {{
  if (!confirm('시뮬레이터를 정지할까요?')) return;
  await fetch('/api/shutdown', {{method:'POST'}});
  setTimeout(() => {{
    location.href = 'http://127.0.0.1:8080/ups/simulator/index.jsp';
  }}, 500);
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
    def __init__(self, server_address: tuple[str, int], state: SimulatorState, stop_event: threading.Event):
        super().__init__(server_address, ControlHandler)
        self.state = state
        self.stop_event = stop_event


def console_loop(state: SimulatorState, server: ThreadedTcpServer) -> None:
    print("Commands: normal, battery, battery_charging, bypass, maintenance_bypass,")
    print("          output_off, battery_test, epo, low_battery, overload, input_fault,")
    print("          output_fault, bypass_fault, power_module_fault, critical, status, quit")
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
    stop_event = threading.Event()
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
            control_server = ControlServer((args.control_host, args.control_port), state, stop_event)
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
            while not stop_event.is_set():
                time.sleep(0.2)
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
