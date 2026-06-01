# UPS Modbus TCP Simulator

Schneider Easy UPS 3-Phase Modular Memory Map 기준의 간단한 Modbus TCP 시뮬레이터입니다.

## 실행

```bat
cd C:\Tomcat 9.0\webapps\ROOT\ups\simulator
start_simulator.bat
```

실행하면 제어 화면이 브라우저로 열립니다.

```text
http://127.0.0.1:1503
```

또는 직접 실행:

```bat
python ups_modbus_simulator.py --host 127.0.0.1 --port 1502 --control-port 1503 --scenario normal --open-browser
```

## UPS 등록값

UPS 등록 화면에서 아래 값으로 등록합니다.

- IP 주소: `127.0.0.1`
- Port: `1502`
- Unit ID: `1`
- 프로파일: `Schneider Easy UPS 3-Phase Modular`

SQL로 바로 등록하려면:

```bat
sqlcmd -S localhost -U <db_user> -P <db_password> -f 65001 -i register_simulator_device.sql
```

## 시나리오 변경

실행 중 제어 화면에서 버튼을 누르거나 콘솔에서 아래 명령을 입력하면 상태가 바로 바뀝니다.

- `normal`
- `battery`
- `low_battery`
- `overload`
- `input_fault`
- `output_fault`
- `bypass_fault`
- `power_module_fault`
- `critical`
- `status`
- `quit`

수집기는 5초마다 값을 읽으므로 시나리오 변경 후 몇 초 안에 모니터링 화면과 알람 화면에 반영됩니다.

## Mimic Diagram 테스트

제어 화면의 `차단기 테스트` 영역에서 아래 항목을 개별로 열고 닫을 수 있습니다.

- `UIB`
- `UOB`
- `SSIB`
- `BF2`
- `MBB`
- `BB`

버튼을 누르면 시뮬레이터의 Modbus 레지스터가 즉시 바뀌고, 수집 주기 이후 모니터링 화면의 mimic diagram 색상이 변경됩니다.
