# EPMS Admin Guard

Date: 2026-04-27

## Purpose

EPMS now has a small shared guard for high-risk JSP screens:

- `includes/epms_admin_guard.jspf`

The guard is intentionally opt-in at runtime. It only blocks requests when `EPMS_ADMIN_TOKEN` is configured in the Tomcat process environment.

## Protected Screens

The guard is included by:

- `epms/system/setup.jsp`
- `epms/system/data_retention_manage.jsp`
- `epms/system/alarm_rule_manage.jsp`
- `epms/system/metric_catalog_manage.jsp`
- `epms/system/meter_excel_import.jsp`
- `epms/plc/plc_write.jsp`
- `epms/plc/plc_excel_import.jsp`
- `epms/remote/tenant_store_excel_import.jsp`

## How It Works

If `EPMS_ADMIN_TOKEN` is not set:

- Existing behavior is preserved.
- The guard only adds basic response hardening headers.

If `EPMS_ADMIN_TOKEN` is set:

- Requests must already have session `role=ADMIN` or `isAdmin=true`, or
- Provide the token through `X-EPMS-ADMIN-TOKEN` header, or
- Provide the token once through `admin_token` request parameter.

When a valid token is provided, the guard marks the session as admin:

- `role=ADMIN`
- `isAdmin=true`

This matches the existing admin-session convention already used by the Agent API.

## Recommended Use

Set the token on the Tomcat service account:

```powershell
$env:EPMS_ADMIN_TOKEN = "<long random token>"
```

Then open a protected screen once with:

```text
/epms/system/setup.jsp?admin_token=<long random token>
```

After that, the current session can use protected screens without repeating the token.

## Follow-Up

This guard is a transitional safety layer. Long term, EPMS should use a real login flow, role-based authorization, and per-form CSRF tokens.

## Verification

Verified in the current runtime:

- With `EPMS_ADMIN_TOKEN` unset, protected screens keep existing behavior and return `HTTP 200`.
- The guarded JSP include checks for `EPMS_ADMIN_TOKEN`, `X-EPMS-ADMIN-TOKEN`, and `admin_token`.

Still to verify after a Tomcat restart with `EPMS_ADMIN_TOKEN` configured:

- Protected screens without a session or token return `HTTP 403`.
- A request with `?admin_token=<token>` creates an admin session.
- Subsequent protected-screen requests in the same session work without repeating the token.
