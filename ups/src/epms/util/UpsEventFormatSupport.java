package epms.util;

public final class UpsEventFormatSupport {
    private UpsEventFormatSupport() {
    }

    public static String displayEventMessage(Object value) {
        if (value == null) return "";
        return String.valueOf(value)
            .replace("\uCC28\uB2E8\uAE30 ", "")
            .replace("\uCC28\uB2E8\uAE30", "")
            .replace("\uF9E1\u2464\uB5D2\u6E72?", "")
            .replace("\uF9E1\u2464\uB5D2\u6E72?,", "")
            .trim();
    }
}
