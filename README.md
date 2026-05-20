# EPMS (Electric Power Monitoring System)

EPMS??Tomcat 9, JSP/Servlet, SQL Server 湲곕컲???꾨젰 愿由??쒖뒪?쒖엯?덈떎. ?꾨젰 ?덉쭏, ?먮꼫吏 ?ъ슜?? ?뚮엺/?대깽?? PLC/Modbus, ?먭꺽寃移? ?쇳겕 愿由? ?꾩냼諛곗텧?? ?댁쁺 Agent 湲곕뒫???쒓났?⑸땲??

## 二쇱슂 吏꾩엯??
- 硫붿씤 ?붾㈃: `/epms/epms_main.jsp`
- 珥덇린 ?ㅼ젙: `/epms/system/setup.jsp`
- Agent 愿由? `/epms/agent/agent_manage.jsp`
- Alarm API: `/api/alarm`
- Modbus API: `/api/modbus`
- Agent API: `/api/agent`

## ?붾㈃ 援ъ꽦

- `epms/monitoring/`: 怨꾩륫湲??곹깭, ?듯빀 ?덉쭏, ?섏씠?, ?대깽?? ?뚮엺
- `epms/quality/`: ?꾩븬/?꾨쪟 遺덊룊?? 蹂?숈쑉, 二쇳뙆?? 怨좎“??遺꾩꽍
- `epms/energy/`: ?먮꼫吏 ?꾪솴, ?곸꽭 遺꾩꽍, Sankey, 吏묎퀎, ?꾩냼諛곗텧??- `epms/remote/`: 留ㅼ옣, 怨꾩륫湲?留ㅽ븨, ?먭꺽寃移? ?뺤궛
- `epms/peak/`: ?쇳겕 ?꾪솴 諛??뺤콉 愿由?- `epms/plc/`: PLC ?깅줉, ?곹깭, ?곌린, ?묒? import, AI/DI 留ㅽ븨
- `epms/system/`: ?ㅼ젙, 怨꾩륫湲? ?몃━, ?뚮엺 洹쒖튃, ?곗씠??蹂댁〈, 移댄깉濡쒓렇

## Java ?⑦궎吏

- `WEB-INF/src/epms/alarm`: ?뚮엺 API 諛?泥섎━
- `WEB-INF/src/epms/plc`: Modbus/PLC ?고???- `WEB-INF/src/epms/tenant`: 留ㅼ옣/怨꾩륫湲?留ㅽ븨
- `WEB-INF/src/epms/billing`: ?먭꺽寃移??뺤궛
- `WEB-INF/src/epms/peak`: ?쇳겕 ?뺤콉/??쒕낫??- `WEB-INF/src/epms/carbon`: ?꾩냼諛곗텧??愿由?- `WEB-INF/src/epms/agent`, `WEB-INF/src/epms/util/Agent*`: Agent API? ?묐떟 泥섎━

## DB ?곌껐

湲곕낯 ?곌껐? Tomcat JNDI `java:comp/env/jdbc/epms`瑜?癒쇱? ?ъ슜?⑸땲?? JNDI瑜?李얠? 紐삵븯硫??쇰? JSP fallback 寃쎈줈?먯꽌 `WEB-INF/config.toml` ?먮뒗 ?섍꼍蹂?섎? ?ъ슜?⑸땲??

Direct JDBC fallback ?섍꼍蹂??

```powershell
$env:EPMS_DB_SERVER = "localhost:1433"
$env:EPMS_DB_NAME = "EPMS"
$env:EPMS_DB_USER = "sa"
$env:EPMS_DB_PASSWORD = "<set outside source tree>"
$env:EPMS_DB_ENCRYPT = "true"
$env:EPMS_DB_TRUST_SERVER_CERTIFICATE = "true"
```

二쇱쓽:

- `sqlcmd`??`localhost,1433` ?뺤떇???ъ슜?⑸땲??
- Microsoft JDBC??`localhost:1433` ?뺤떇???ъ슜?⑸땲??
- EPMS direct fallback? `host,port` ?낅젰??`host:port`濡?蹂댁젙?⑸땲??

## ?댁쁺 臾몄꽌

- `docs/architecture/epms_code_design_analysis_2026-04-27.md`
- `docs/operations/epms_credential_externalization.md`
- `docs/operations/epms_admin_guard.md`
- `docs/operations/epms_smoke_test_2026-04-27.md`

## ?ㅻえ???뚯뒪??湲곗?

理쒓렐 ?뺤씤??二쇱슂 URL:

- `/epms/system/setup.jsp`
- `/epms/epms_main.jsp`
- `/epms/monitoring/meter_status.jsp?meter_id=0`
- `/epms/plc/plc_status.jsp`
- `/epms/monitoring/alarm_view.jsp`
- `/epms/energy/energy_overview.jsp`
