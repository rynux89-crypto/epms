package epms.util;

import java.util.Locale;

public final class AgentAnswerGuardSupport {
    private AgentAnswerGuardSupport() {
    }

    public static String sanitizeUngroundedJudgement(String answer, String dbContext) {
        String a = answer == null ? "" : answer;
        if (a.trim().isEmpty()) return a;
        String ctx = dbContext == null ? "" : dbContext;
        String low = a.toLowerCase(Locale.ROOT);
        boolean hasJudgement =
            low.contains("이상 징후") ||
            low.contains("이상징후") ||
            low.contains("발견되지 않았") ||
            low.contains("정상입니다") ||
            low.contains("문제 없습니다") ||
            low.contains("abnormal") ||
            low.contains("no anomaly");
        if (!hasJudgement) return a;

        String c = ctx.toLowerCase(Locale.ROOT);
        boolean grounded =
            c.contains("[frequency outlier]") ||
            c.contains("[power factor outlier]") ||
            c.contains("[harmonic exceed]") ||
            c.contains("[voltage unbalance top") ||
            c.contains("[latest alarms]") ||
            c.contains("[open alarms]") ||
            c.contains("[alarm count]");
        if (grounded) return a;

        String[] lines = a.split("\\r?\\n");
        StringBuilder out = new StringBuilder();
        for (String line : lines) {
            String l = line.toLowerCase(Locale.ROOT);
            boolean isJudgementLine =
                l.contains("이상 징후") ||
                l.contains("이상징후") ||
                l.contains("발견되지 않았") ||
                l.contains("정상입니다") ||
                l.contains("문제 없습니다") ||
                l.contains("abnormal") ||
                l.contains("no anomaly");
            if (isJudgementLine) continue;
            if (out.length() > 0) out.append('\n');
            out.append(line);
        }
        if (out.length() == 0) return "현재 제공된 값만으로는 이상 여부를 단정할 수 없습니다.";
        if (!out.toString().contains("이상 여부를 단정")) {
            out.append("\n\n현재 제공된 값만으로는 이상 여부를 단정할 수 없습니다.");
        }
        return out.toString();
    }
}
