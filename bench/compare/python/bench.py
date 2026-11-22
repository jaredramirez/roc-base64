# base64 from the Python standard library (implemented in C)
import base64, sys, time

size, iters = int(sys.argv[1]), int(sys.argv[2])
# Each sample times enough calls to cover 256 KiB, for timer resolution
reps = max(1, -(-262144 // size))
data = bytes((i * 31 + 7) % 256 for i in range(size))

def best(f):
    f(); f()  # warm up
    times = []
    for _ in range(iters):
        start = time.perf_counter_ns()
        for _ in range(reps):
            f()
        times.append(time.perf_counter_ns() - start)
    return min(times) // reps

text = base64.b64encode(data)
assert base64.b64decode(text, validate=True) == data
print(best(lambda: base64.b64encode(data)), best(lambda: base64.b64decode(text, validate=True)))
