package epms.tenant;

public final class TenantOption {
    private final String value;
    private final String label;

    public TenantOption(String value, String label) {
        this.value = value;
        this.label = label;
    }

    public String getValue() {
        return value;
    }

    public String getLabel() {
        return label;
    }
}
