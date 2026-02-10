import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

public class CleanService {
    private static final String API = "https://api.internal.local/users";

    public String readFile(String path) throws IOException {
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(
                        java.nio.file.Files.newInputStream(java.nio.file.Path.of(path)),
                        StandardCharsets.UTF_8))) {
            return reader.readLine();
        }
    }

    public void callApi() throws IOException {
        URL url = new URL(API);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setConnectTimeout(2000);
        conn.setReadTimeout(2000);
        conn.setRequestMethod("GET");
        conn.connect();
        conn.disconnect();
    }

    public void safeNullCheck(String value) {
        if (value != null && value.equals("test")) {
            System.out.println("ok");
        }
    }
}
