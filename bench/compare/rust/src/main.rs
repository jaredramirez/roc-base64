use base64::{engine::general_purpose::STANDARD, Engine};
use std::hint::black_box;
use std::time::Instant;

fn best(iters: usize, reps: usize, mut f: impl FnMut()) -> u128 {
    f();
    f(); // warm up
    (0..iters)
        .map(|_| {
            let start = Instant::now();
            for _ in 0..reps {
                f();
            }
            start.elapsed().as_nanos()
        })
        .min()
        .unwrap()
        / reps as u128
}

fn main() {
    let args: Vec<usize> = std::env::args().skip(1).map(|a| a.parse().unwrap()).collect();
    let (size, iters) = (args[0], args[1]);
    // Each sample times enough calls to cover 256 KiB, for timer resolution
    let reps = 262144usize.div_ceil(size.max(1));
    let data: Vec<u8> = (0..size).map(|i| ((i * 31 + 7) % 256) as u8).collect();
    let text = STANDARD.encode(&data);
    assert_eq!(STANDARD.decode(&text).unwrap(), data);
    let enc = best(iters, reps, || {
        black_box(STANDARD.encode(black_box(&data)));
    });
    let dec = best(iters, reps, || {
        black_box(STANDARD.decode(black_box(&text)).unwrap());
    });
    println!("{enc} {dec}");
}
