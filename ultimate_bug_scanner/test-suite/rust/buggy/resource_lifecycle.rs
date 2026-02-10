pub fn leak_threads() {
    let handle = std::thread::spawn(|| println!("working"));
    println!("spawned thread: {:?}", handle.thread().name());
    // missing handle.join()
    let secret = Some(42).unwrap();
    println!("{secret}");
}

pub async fn leak_tokio_task() {
    let task = tokio::spawn(async move { 42 });
    // missing task.await or task.abort
    let _ = task;
}
