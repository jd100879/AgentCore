use std::future::Future;
use std::pin::Pin;
use std::task::{Context, Poll};

async fn fetch_data() -> Result<String, &'static str> {
    Ok(String::from("data"))
}

async fn run() -> Result<(), &'static str> {
    match fetch_data().await {
        Ok(body) => println!("{}", body),
        Err(err) => {
            eprintln!("request failed: {err}");
            return Err(err);
        }
    }
    let handle = tokio::spawn(async move {
        if let Err(err) = fetch_data().await {
            eprintln!("background error: {err}");
        }
    });
    let _ = handle.await;
    Ok(())
}

fn main() {
    let _ = run();
}

mod tokio {
    use super::*;

    pub struct JoinHandle;

    impl Future for JoinHandle {
        type Output = Result<(), ()>;

        fn poll(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<Self::Output> {
            Poll::Ready(Ok(()))
        }
    }

    impl JoinHandle {
        pub fn abort(&self) {}
    }

    pub fn spawn<F>(_f: F) -> JoinHandle
    where
        F: Future<Output = ()> + Send + 'static,
    {
        JoinHandle
    }
}
