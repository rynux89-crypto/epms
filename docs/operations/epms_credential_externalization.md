# EPMS Credential Externalization

Date: 2026-04-27

## Purpose

EPMS currently supports database connection through Tomcat JNDI first and a direct JDBC fallback second.

The direct fallback now prefers environment variables over `WEB-INF/config.toml`, so local files no longer need to contain the database password when the process environment is configured.

## Direct JDBC Fallback Environment Variables

Set these on the Tomcat service account or startup environment:

```powershell
$env:EPMS_DB_SERVER = "localhost:1433"
$env:EPMS_DB_NAME = "EPMS"
$env:EPMS_DB_USER = "sa"
$env:EPMS_DB_PASSWORD = "<set outside source tree>"
$env:EPMS_DB_ENCRYPT = "true"
$env:EPMS_DB_TRUST_SERVER_CERTIFICATE = "true"
```

Use JDBC host syntax for `EPMS_DB_SERVER`: `host:port`.
`sqlcmd` accepts `host,port`, but Microsoft JDBC treats `localhost,1433` as a literal host name unless the application normalizes it.

Resolution order for direct fallback:

1. Environment variables above
2. `WEB-INF/config.toml`

JNDI is still attempted first through `java:comp/env/jdbc/epms`.

## Recommended Next Cleanup

Completed in this workspace:

- `WEB-INF/config.toml` keeps the direct fallback password blank.
- Backup and aggregate scripts no longer default to the legacy local password.
- Existing generated aggregate `.cmd` wrappers no longer embed a password argument.
- PLC import fallback no longer embeds legacy SQL authentication credentials.

Remaining runtime item:

- `META-INF/context.xml` still contains the active Tomcat JNDI password. Do not blank this file until the Tomcat service has an external JNDI secret strategy in place, otherwise existing JSP pages that use JNDI first will lose DB connectivity.

## Tomcat JNDI Externalization Option

The installed Tomcat 9.0.106 documentation describes XML property replacement through `org.apache.tomcat.util.digester.PROPERTY_SOURCE`.
To read `${...}` values from process environment variables, enable `org.apache.tomcat.util.digester.EnvironmentPropertySource` before Tomcat starts.

Example `setenv.bat` entry outside this webapp source tree:

```bat
set "CATALINA_OPTS=%CATALINA_OPTS% -Dorg.apache.tomcat.util.digester.PROPERTY_SOURCE=org.apache.tomcat.util.digester.EnvironmentPropertySource"
```

After the Tomcat service account has `EPMS_JNDI_DB_PASSWORD` set, the JNDI resource can be changed from:

the literal legacy password value

to:

```xml
password="${EPMS_JNDI_DB_PASSWORD}"
```

Apply that change together with a Tomcat restart and verify `/epms/system/setup.jsp` immediately after startup.

Recommended production cleanup:

1. Move the Tomcat JNDI password out of `META-INF/context.xml` using the site-approved Tomcat secret mechanism.
2. Keep `WEB-INF/config.toml` password blank on deployed systems.
3. Set `EPMS_DB_PASSWORD` for scripts and direct fallback jobs.
4. Rotate the current database password if the repository has been copied outside the deployment host.
