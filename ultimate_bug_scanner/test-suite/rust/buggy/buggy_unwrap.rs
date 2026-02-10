use std::mem;
use std::sync::{Arc, Mutex};

fn compute(value: Option<i32>) -> i32 {
    // WARNING: unwrap without guard
    value.unwrap()
}

fn leak_memory() {
    let data = vec![1, 2, 3];
    unsafe {
        // CRITICAL: transmute arbitrary pointer
        let _: usize = mem::transmute(data);
    }
}

fn main() {
    let shared = Arc::new(Mutex::new(0));
    let clone = shared.clone();
    std::thread::spawn(move || {
        // WARNING: lock().unwrap() panic on poison
        let mut guard = clone.lock().unwrap();
        *guard += 1;
        panic!("boom");
    });

    println!("{}", compute(Some(1)));
    leak_memory();
}
