package epms.alarm;

import java.sql.Connection;
import java.util.Collections;
import java.util.List;

/**
 * Orchestration scaffold for high-volume alarm ingestion.
 *
 * <p>This class is intentionally conservative: it does not yet replace the JSP
 * runtime path, but it provides the service boundary for the next migration
 * step.</p>
 */
public final class AlarmIngestService {
    private final AlarmRuleCache ruleCache;
    private final AlarmStateCache stateCache;
    private final AlarmBatchWriter batchWriter;

    public AlarmIngestService(AlarmRuleCache ruleCache, AlarmStateCache stateCache, AlarmBatchWriter batchWriter) {
        this.ruleCache = ruleCache;
        this.stateCache = stateCache;
        this.batchWriter = batchWriter;
    }

    public List<AlarmRuleDef> loadAiRules(Connection conn) throws Exception {
        if (ruleCache == null) {
            return Collections.emptyList();
        }
        return ruleCache.getAiRules(conn);
    }

    public AlarmStateCache getStateCache() {
        return stateCache;
    }

    public AlarmBatchWriter getBatchWriter() {
        return batchWriter;
    }

    public void queue(AlarmWriteOp op) {
        if (batchWriter != null) {
            batchWriter.add(op);
        }
    }
}
