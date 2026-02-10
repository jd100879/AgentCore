use std::sync::{Arc, Mutex};
use std::thread;

fn worker(counter: Arc<Mutex<u32>>) {
    let mut guard = counter.lock().expect("lock poisoned");
    *guard += 1;
}

fn main() {
    let counter = Arc::new(Mutex::new(0));
    let mut handles = Vec::new();

    for _ in 0..4 {
        let clone = Arc::clone(&counter);
        handles.push(thread::spawn(move || worker(clone)));
    }

    for h in handles {
        h.join().expect("thread failed");
    }

    println!("count={}", counter.lock().unwrap());
}
