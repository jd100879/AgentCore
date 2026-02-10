use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

fn main() {
    let shared = Arc::new(Mutex::new(0));
    for _ in 0..4 {
        let clone = Arc::clone(&shared);
        thread::spawn(move || {
            let mut guard = clone.lock().unwrap();
            *guard += 1;
            panic!("poison");
        });
    }
    thread::sleep(Duration::from_millis(10));
    println!("{}", shared.lock().unwrap());
}
