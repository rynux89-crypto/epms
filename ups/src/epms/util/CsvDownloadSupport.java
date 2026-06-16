package epms.util;

import java.io.IOException;
import java.io.Writer;
import javax.servlet.http.HttpServletResponse;
import javax.servlet.jsp.JspWriter;

public final class CsvDownloadSupport {
    private CsvDownloadSupport() {
    }

    public static void begin(HttpServletResponse response, JspWriter out, String fileName) throws IOException {
        out.clear();
        response.reset();
        response.setCharacterEncoding("UTF-8");
        response.setContentType("text/csv;charset=UTF-8");
        response.setHeader("Content-Disposition", "attachment; filename=\"" + safeFileName(fileName) + "\"");
        out.print("\uFEFF");
    }

    public static void writeRow(Writer out, Object... values) throws IOException {
        for (int i = 0; i < values.length; i++) {
            if (i > 0) out.write(",");
            out.write(cell(values[i]));
        }
        out.write("\n");
    }

    public static String cell(Object value) {
        if (value == null) return "";
        String s = String.valueOf(value).replace("\r", " ").replace("\n", " ");
        if (s.startsWith("=") || s.startsWith("+") || s.startsWith("-") || s.startsWith("@")) {
            s = "'" + s;
        }
        if (s.indexOf(',') >= 0 || s.indexOf('"') >= 0) {
            s = "\"" + s.replace("\"", "\"\"") + "\"";
        }
        return s;
    }

    private static String safeFileName(String fileName) {
        if (fileName == null || fileName.trim().isEmpty()) return "download.csv";
        return fileName.replace("\\", "_").replace("/", "_").replace("\"", "");
    }
}
