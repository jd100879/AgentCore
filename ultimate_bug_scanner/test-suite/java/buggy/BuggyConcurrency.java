import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class BuggyConcurrency {
    private static final ExecutorService EXEC = Executors.newFixedThreadPool(4);

    public void submitTasks() {
        for (int i = 0; i < 10; i++) {
            EXEC.submit(() -> {
                throw new RuntimeException("boom");
            });
        }
        // BUG: executor never shutdown
    }
}
