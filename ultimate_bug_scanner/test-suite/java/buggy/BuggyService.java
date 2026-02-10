import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.net.HttpURLConnection;
import java.net.URL;

public class BuggyService {
    private static final String API = "http://api.internal.local/users"; // no TLS

    public String readFile(String path) throws IOException {
        BufferedReader reader = new BufferedReader(new FileReader(path)); // no try-with-resources
        return reader.readLine();
    }

    public void callApi() throws IOException {
        URL url = new URL(API);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("GET");
        conn.connect(); // no timeouts, can hang forever
    }

    @SuppressWarnings("deprecation")
    public void dangerousThread(Thread t) {
        t.stop(); // deprecated
        System.runFinalizersOnExit(true); // banned API
    }

    public void unguardedNull(String value) {
        if (value.equals("test")) { // possible NPE
            System.out.println("ok");
        }
    }
}
