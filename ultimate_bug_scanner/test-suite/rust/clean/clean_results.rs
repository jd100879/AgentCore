use std::sync::{Arc, Mutex};

fn main() -> Result<(), String> {
    let shared = Arc::new(Mutex::new(0));
    {
        let mut guard = shared.lock().map_err(|e| e.to_string())?;
        *guard += 1;
    }
    let value = shared.lock().map_err(|e| e.to_string())?;
    println!("value: {}", *value);
    Ok(())
}
