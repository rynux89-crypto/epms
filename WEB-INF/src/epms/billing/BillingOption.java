package epms.billing;

public final class BillingOption {
    private final String value;
    private final String label;

    public BillingOption(String value, String label) {
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
