# base64 from the Python standard library (implemented in C)
import base64, sys, time

size, iters = int(sys.argv[1]), int(sys.argv[2])
data = bytes((i * 31 + 7) % 256 for i in range(size))

def best(f):
    f(); f()  # warm up
    times = []
    for _ in range(iters):
        start = time.perf_counter_ns()
        f()
        times.append(time.perf_counter_ns() - start)
    return min(times)

text = base64.b64encode(data)
assert base64.b64decode(text, validate=True) == data
print(best(lambda: base64.b64encode(data)), best(lambda: base64.b64decode(text, validate=True)))
