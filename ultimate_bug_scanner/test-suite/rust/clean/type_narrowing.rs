fn unwrap_after_guard_clean(opt: Option<&str>) -> Option<usize> {
    let value = opt?;
    Some(value.len())
}

fn result_expect_clean(resp: Result<i32, &'static str>) -> i32 {
    if let Ok(num) = resp {
        return num;
    }

    0
}

fn main() {
    println!("{:?}", unwrap_after_guard_clean(Some("ok")));
    println!("{:?}", result_expect_clean(Ok(42)));
}
