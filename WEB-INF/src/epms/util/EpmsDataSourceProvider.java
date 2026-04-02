package epms.util;

import javax.naming.InitialContext;
import javax.naming.NamingException;
import javax.sql.DataSource;

public final class EpmsDataSourceProvider {
    private static final String DB_JNDI_NAME = "java:comp/env/jdbc/epms";
    private static final Object LOCK = new Object();
    private static volatile DataSource cachedDataSource = null;

    private EpmsDataSourceProvider() {
    }

    public static DataSource resolveDataSource() throws Exception {
        DataSource ds = cachedDataSource;
        if (ds != null) {
            return ds;
        }

        synchronized (LOCK) {
            if (cachedDataSource != null) {
                return cachedDataSource;
            }

            InitialContext ic = null;
            NamingException lastError = null;
            try {
                ic = new InitialContext();
                String[] names = new String[]{DB_JNDI_NAME, "jdbc/epms"};
                for (String name : names) {
                    try {
                        Object obj = ic.lookup(name);
                        if (obj instanceof DataSource) {
                            cachedDataSource = (DataSource) obj;
                            return cachedDataSource;
                        }
                    } catch (NamingException ne) {
                        lastError = ne;
                    }
                }
            } finally {
                try {
                    if (ic != null) {
                        ic.close();
                    }
                } catch (Exception ignore) {
                }
            }

            if (lastError != null) {
                throw lastError;
            }
            throw new NamingException("JNDI datasource not found: " + DB_JNDI_NAME);
        }
    }
}
