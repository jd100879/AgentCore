import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;

public class AsyncErrors {
    public static String loadUser() throws ExecutionException, InterruptedException {
        CompletableFuture<String> future = CompletableFuture.supplyAsync(() -> "user");
        return future.get();
    }

    public static void logChain() {
        CompletableFuture.supplyAsync(() -> "value")
            .thenApply(v -> v.toUpperCase())
            .thenAccept(System.out::println);
    }

    public static void main(String[] args) throws Exception {
        loadUser();
        logChain();
    }
}
