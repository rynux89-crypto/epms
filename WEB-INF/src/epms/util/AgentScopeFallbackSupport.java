package epms.util;

import java.util.HashSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class AgentScopeFallbackSupport {
    private AgentScopeFallbackSupport() {
    }

    public static String extractMeterScopeToken(String userMessage) {
        return extractScopedAreaTokenFallback(userMessage);
    }

    public static boolean shouldTreatAsGlobalMeterCount(String userMessage, String scopeToken) {
        String m = normalizeForIntent(userMessage);
        boolean asksCount =
            m.contains("계측기수") || m.contains("미터수") || m.contains("metercount")
                || m.contains("총계측기") || m.contains("전체계측기")
                || m.contains("지금계측기의수") || m.contains("현재계측기의수")
                || m.contains("계측기의수") || m.contains("계측기몇개")
                || m.contains("계측기개수") || m.contains("계측기갯수")
                || m.contains("시스템의계측기수") || m.contains("이시스템의계측기수")
                || m.contains("현재시스템의계측기수") || m.contains("지금이시스템의계측기수");
        boolean onlyGenericScope = isGenericGlobalCountScope(scopeToken, new String[] {
            "계측기", "미터", "meter", "시스템", "이시스템", "현재시스템", "지금", "현재"
        });
        boolean hasSpecificScope =
            m.contains("동관") || m.contains("서관") || m.contains("남관") || m.contains("북관")
                || m.contains("건물") || m.contains("패널") || m.contains("panel")
                || m.contains("용도") || m.contains("사용처");
        return asksCount && onlyGenericScope && !hasSpecificScope;
    }

    public static boolean shouldTreatAsGlobalPanelCount(String userMessage, String scopeToken) {
        String m = normalizeForIntent(userMessage);
        boolean asksCount =
            m.contains("패널수") || m.contains("panelcount")
                || m.contains("총패널") || m.contains("전체패널")
                || m.contains("지금패널의수") || m.contains("현재패널의수")
                || m.contains("패널의수") || m.contains("패널몇개")
                || m.contains("패널개수") || m.contains("패널갯수")
                || m.contains("시스템의패널수") || m.contains("이시스템의패널수")
                || m.contains("현재시스템의패널수") || m.contains("지금이시스템의패널수");
        boolean onlyGenericScope = isGenericGlobalCountScope(scopeToken, new String[] {
            "패널", "panel", "판넬", "시스템", "이시스템", "현재시스템", "지금", "현재"
        });
        boolean hasSpecificScope =
            m.contains("동관") || m.contains("서관") || m.contains("남관") || m.contains("북관")
                || m.contains("건물") || m.contains("용도") || m.contains("사용처");
        return asksCount && onlyGenericScope && !hasSpecificScope;
    }

    public static String extractScopedAreaTokenFallback(String userMessage) {
        String raw = EpmsWebUtil.trimToNull(userMessage);
        if (raw == null) return null;
        String aliasMatched = AgentMetadataLookupSupport.findBuildingAliasFromDb(raw);
        if (aliasMatched != null) return aliasMatched;
        String dbMatched = AgentMetadataLookupSupport.findBuildingNameFromDb(raw);
        if (dbMatched != null) return dbMatched;

        Matcher possessive = Pattern.compile("([가-힣A-Za-z0-9_\\-]{2,20})\\s*의").matcher(raw);
        while (possessive.find()) {
            String token = EpmsWebUtil.trimToNull(possessive.group(1));
            if (token == null) continue;
            String n = normalizeForIntent(token);
            if (n.length() < 2) continue;
            if ("이번달".equals(n) || "금월".equals(n) || "전체".equals(n) || "전력".equals(n) || "사용량".equals(n)) continue;
            return token;
        }

        Matcher bare = Pattern.compile("([가-힣A-Za-z0-9_\\-]{2,20})\\s*(관련|전체|전력|사용량)").matcher(raw);
        if (bare.find()) {
            String token = EpmsWebUtil.trimToNull(bare.group(1));
            if (token != null && normalizeForIntent(token).length() >= 2) return token;
        }
        return null;
    }

    public static String extractUsageTokenFallback(String userMessage) {
        String raw = EpmsWebUtil.trimToNull(userMessage);
        if (raw == null) return null;
        String aliasMatched = AgentMetadataLookupSupport.findUsageAliasFromDb(raw);
        if (aliasMatched != null) return aliasMatched;
        String dbMatched = AgentMetadataLookupSupport.findUsageTypeFromDb(raw);
        if (dbMatched != null) return dbMatched;

        String norm = normalizeForIntent(raw);
        if (norm.contains("동력")) return "전열";
        if (norm.contains("조명")) return "전등";
        if (norm.contains("비상전원")) return "비상";
        if (norm.contains("무정전")) return "UPS";
        if (norm.contains("발전기")) return "Generator";

        Matcher m1 = Pattern.compile("([가-힣A-Za-z0-9_\\-]{2,20})\\s*용도").matcher(raw);
        if (m1.find()) {
            String token = EpmsWebUtil.trimToNull(m1.group(1));
            if (token != null && normalizeForIntent(token).length() >= 2) return token;
        }
        Matcher m2 = Pattern.compile("용도\\s*([가-힣A-Za-z0-9_\\-]{2,20})").matcher(raw);
        if (m2.find()) {
            String token = EpmsWebUtil.trimToNull(m2.group(1));
            if (token != null && normalizeForIntent(token).length() >= 2) return token;
        }
        return null;
    }

    private static boolean isGenericGlobalCountScope(String scopeToken, String[] genericTokens) {
        String scope = EpmsWebUtil.trimToNull(scopeToken);
        if (scope == null) return true;
        HashSet<String> allowed = new HashSet<String>();
        for (String genericToken : genericTokens) {
            allowed.add(genericToken);
        }
        String[] parts = scope.split("\\s*(?:,|/|\\\\|의|관련|\\s+)\\s*");
        boolean sawToken = false;
        for (String part : parts) {
            String n = normalizeForIntent(part);
            if (n == null || n.isEmpty()) continue;
            sawToken = true;
            if (!allowed.contains(n)) return false;
        }
        return true;
    }

    private static String normalizeForIntent(String text) {
        if (text == null) return "";
        return text.toLowerCase(java.util.Locale.ROOT).replaceAll("\\s+", "");
    }
}
