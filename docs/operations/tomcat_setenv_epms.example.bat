@echo off
rem Example only. Place equivalent settings in CATALINA_BASE\bin\setenv.bat
rem or in the Windows service JVM options, outside the webapp source tree.
rem
rem Required before using password="${EPMS_JNDI_DB_PASSWORD}" in META-INF\context.xml.

set "CATALINA_OPTS=%CATALINA_OPTS% -Dorg.apache.tomcat.util.digester.PROPERTY_SOURCE=org.apache.tomcat.util.digester.EnvironmentPropertySource"
