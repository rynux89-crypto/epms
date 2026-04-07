package epms.util;

public final class AgentDirectResultHelper {
    private AgentDirectResultHelper() {
    }

    public static AgentRuntimeModels.DirectAnswerResult simple(String dbContext, String userContext, String fallback) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = AgentDirectAnswerHelper.chooseUserContextAnswer(userContext, fallback);
        return result;
    }

    public static AgentRuntimeModels.DirectAnswerResult panelLatest(String dbContext, String userContext) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = AgentDirectAnswerHelper.buildPanelLatestStatusAnswer(dbContext, userContext);
        return result;
    }
}
