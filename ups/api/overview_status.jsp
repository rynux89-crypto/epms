<%@ page import="epms.ups.*" %>
<%@ page contentType="application/json;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_json.jspf" %>
<%
request.setCharacterEncoding("UTF-8");
response.setHeader("Cache-Control", "no-store");
UpsOverviewPageModel overview = UpsOverviewPageService.build("1".equals(request.getParameter("include_inactive")));
StringBuilder json = new StringBuilder(4096);
json.append("{\"ok\":").append(overview.err == null ? "true" : "false");
if (overview.err != null) {
    json.append(",\"error\":\"").append(escJson(overview.err)).append("\"");
}
json.append(",\"summary\":{")
    .append("\"total\":").append(overview.items.size()).append(',')
    .append("\"normal\":").append(overview.normalCount).append(',')
    .append("\"alarm\":").append(overview.alarmCount).append(',')
    .append("\"comm\":").append(overview.commCount).append(',')
    .append("\"inactiveOrUnknown\":").append(overview.inactiveOrUnknownCount()).append(',')
    .append("\"includeInactive\":").append(overview.includeInactive ? "true" : "false")
    .append("},\"items\":[");
for (int i = 0; i < overview.items.size(); i++) {
    UpsOverviewItem item = overview.items.get(i);
    if (i > 0) json.append(',');
    json.append('{')
        .append("\"upsId\":\"").append(escJson(item.upsId)).append("\",")
        .append("\"statusClass\":\"").append(escJson(item.statusClass)).append("\",")
        .append("\"statusText\":\"").append(escJson(item.statusText)).append("\",")
        .append("\"enabledText\":\"").append(escJson(item.enabledText)).append("\",")
        .append("\"measuredAtText\":\"").append(escJson(item.measuredAtText)).append("\",")
        .append("\"loadText\":\"").append(escJson(item.loadText)).append("\",")
        .append("\"batteryText\":\"").append(escJson(item.batteryText)).append("\",")
        .append("\"outputVoltageText\":\"").append(escJson(item.outputVoltageText)).append("\",")
        .append("\"outputKwText\":\"").append(escJson(item.outputKwText)).append("\",")
        .append("\"outputKvaText\":\"").append(escJson(item.outputKvaText)).append("\",")
        .append("\"frequencyText\":\"").append(escJson(item.frequencyText)).append("\",")
        .append("\"operationModeText\":\"").append(escJson(item.operationModeText)).append("\",")
        .append("\"batteryTempText\":\"").append(escJson(item.batteryTempText)).append("\",")
        .append("\"remainingText\":\"").append(escJson(item.remainingText)).append("\",")
        .append("\"activeAlarmCount\":").append(item.activeAlarmCount)
        .append('}');
}
json.append("]}");
out.print(json.toString());
%>
