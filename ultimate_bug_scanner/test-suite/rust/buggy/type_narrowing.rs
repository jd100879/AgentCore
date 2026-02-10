fn unwrap_after_guard() {
    let maybe_value: Option<&str> = if cfg!(feature = "missing") { None } else { Some("admin") };

    if let Some(name) = maybe_value {
        println!("welcome {}", name);
    }

    // Guard above does not exit, so this unwrap can still panic when None.
    println!("length = {}", maybe_value.unwrap().len());
}

fn result_then_expect() {
    let resp: Result<i32, &'static str> = Err("boom");

    if let Ok(num) = resp {
        println!("number {}", num);
    }

    // Expect after non-exiting guard.
    println!("value {}", resp.expect("expected ok"));
}

fn main() {
    unwrap_after_guard();
    result_then_expect();
}
