package epms.billing;

import java.util.ArrayList;
import java.util.List;

public final class BillingPrecheckResult {
    private final List<String> errors = new ArrayList<>();
    private final List<String> warnings = new ArrayList<>();

    public List<String> getErrors() {
        return errors;
    }

    public List<String> getWarnings() {
        return warnings;
    }

    public boolean hasErrors() {
        return !errors.isEmpty();
    }

    public void addError(String message) {
        if (message != null && !message.trim().isEmpty()) {
            errors.add(message.trim());
        }
    }

    public void addWarning(String message) {
        if (message != null && !message.trim().isEmpty()) {
            warnings.add(message.trim());
        }
    }

    public String summarizeErrors() {
        return String.join(" / ", errors);
    }
}
