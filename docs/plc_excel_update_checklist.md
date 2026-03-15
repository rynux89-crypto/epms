# PLC Excel Update Checklist

1. Excel structure
- Check that the `PLC_IO_Address_AI` and `PLC_IO_Address_DI` sheet names are unchanged.
- Check that the base columns (`F1` to `F5`) still follow the expected layout.
- Check whether AI header tokens changed.
  - Examples: `IR` added/removed, `PV1~PI3` moved, `PST/PLT` added/removed.
- Check whether DI address/tag format changed.

2. Import preview
- Open [plc_excel_import.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/plc/plc_excel_import.jsp).
- Run `미리보기` with the latest Excel file.
- Check:
  - `ai_rows`
  - `di_map_rows`
  - `di_tag_rows`
  - `float_count_used`
  - `ai_rows_sample.metric_order`
  - `ai_match_sync.changed_count`
  - `ai_match_sync.missing_tokens`
  - `disable_summary`

3. AI mapping review
- Confirm that `metric_order` matches the Excel token order.
- Confirm that `float_count` matches the actual Excel address span.
- Confirm that no middle token is dropped.
  - Example: `IR`
- Confirm that `PV1~PI3` / `PI1~PI3` did not shift incorrectly.

4. Disable impact review
- Review:
  - `disable_summary.ai_disabled`
  - `disable_summary.di_map_disabled`
  - `disable_summary.di_tag_disabled`
- Check for unexpected protection/ELD tag removal.

5. Apply
- Apply in the same session after preview.
- Check recent execution history:
  - `upload_name`
  - `upload_source`
  - `exit=0`

6. DB mapping verification
- Check:
  - `plc_meter_map`
  - `plc_di_map`
  - `plc_di_tag_map`
  - `plc_ai_measurements_match`
- Confirm:
  - `start_address`
  - `float_count`
  - `metric_order`
  - `float_index` auto-sync result
  - missing token auto-registration if applicable

7. AI address spot-check
- Verify a few representative tokens:
  - `PF`
  - `H_VA_1`
  - `PV1`
  - `PI1`
- Compare Excel address vs DB-calculated address.

8. Read/write verification
- In [plc_write.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/plc/plc_write.jsp), verify representative token `reg1/reg2`.
- In [plc_status.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/plc/plc_status.jsp), verify polling status.

9. Insert verification
- Compare:
  - `plc_ai_samples`
  - `measurements`
  - `harmonic_measurements`
- For representative tokens, confirm `PLC 샘플값` and `최신 적재값` align.

10. Screen verification
- Review:
  - [ai_measurements_match.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/ai_measurements_match.jsp)
  - [ai_mapping.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/ai_mapping.jsp)
  - [di_mapping.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/di_mapping.jsp)

11. Alarm impact verification
- In [metric_catalog_manage.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/metric_catalog_manage.jsp), run:
  - `AI 지표 동기화`
  - `DI 지표 동기화`
- In [alarm_rule_manage.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/alarm_rule_manage.jsp), check `실제 판단 입력`.
- Review whether [alarm_api.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/alarm_api.jsp) behavior is affected.

12. History/log review
- Check [plc_excel_import_history.log](/c:/Tomcat%209.0/webapps/ROOT/logs/plc_excel_import_history.log).
- Confirm preview/apply file name, time, and exit status.
