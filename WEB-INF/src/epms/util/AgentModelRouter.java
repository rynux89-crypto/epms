package epms.util;

import java.util.Locale;

public final class AgentModelRouter {
    private AgentModelRouter() {
    }

    public enum Route {
        GENERAL,
        AI,
        PQ,
        ALARM
    }

    public static Route detectRoute(String userMessage) {
        String m = normalize(userMessage);
        if (m.isEmpty()) {
            return Route.GENERAL;
        }

        boolean hasAi =
            containsAny(m,
                "예지보전", "고장예측", "부하예측", "이상탐지", "이상진단",
                "모델", "학습", "훈련", "평가", "피처", "feature",
                "데이터셋", "dataset", "predictive", "forecast", "anomaly",
                "autoencoder", "lstm", "transformer", "xgboost", "randomforest");

        boolean hasPq =
            containsAny(m,
                "전력품질", "pq", "thd", "고조파", "harmonic", "sag", "swell",
                "flicker", "불평형", "불균형", "주파수변동", "ieee519",
                "리액터", "콘덴서", "콘덴서뱅크", "필터", "역률");

        boolean hasAlarm =
            containsAny(m,
                "알람", "경보", "이벤트", "트립", "trip", "과전압", "저전압",
                "과전류", "지락", "단락", "ups", "변압기경보", "차단기",
                "fault", "alarm", "event");

        if (hasPq) {
            return Route.PQ;
        }
        if (hasAlarm) {
            return Route.ALARM;
        }
        if (hasAi) {
            return Route.AI;
        }
        return Route.GENERAL;
    }

    public static String routeModel(String userMessage, String defaultModel, String aiModel, String pqModel, String alarmModel) {
        Route route = detectRoute(userMessage);
        switch (route) {
            case AI:
                return firstNonBlank(aiModel, defaultModel);
            case PQ:
                return firstNonBlank(pqModel, defaultModel);
            case ALARM:
                return firstNonBlank(alarmModel, defaultModel);
            default:
                return defaultModel;
        }
    }

    private static boolean containsAny(String value, String... needles) {
        if (value == null || needles == null) {
            return false;
        }
        for (String needle : needles) {
            if (needle != null && !needle.isEmpty() && value.contains(needle)) {
                return true;
            }
        }
        return false;
    }

    private static String firstNonBlank(String first, String fallback) {
        String trimmedFirst = EpmsWebUtil.trimToNull(first);
        if (trimmedFirst != null) {
            return trimmedFirst;
        }
        return EpmsWebUtil.trimToNull(fallback);
    }

    private static String normalize(String s) {
        if (s == null) {
            return "";
        }
        return s.toLowerCase(Locale.ROOT).replaceAll("\\s+", "");
    }
}
