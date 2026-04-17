package epms.peak;

public final class PeakStoreOption {
    private final String value;
    private final String label;

    public PeakStoreOption(String value, String label) {
        this.value = value;
        this.label = label;
    }

    public String getValue() { return value; }
    public String getLabel() { return label; }
}
