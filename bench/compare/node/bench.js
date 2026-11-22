// Buffer's base64 from Node.js (implemented in C++)
const [size, iters] = process.argv.slice(2).map(Number);
// Each sample times enough calls to cover 256 KiB, for timer resolution
const reps = Math.max(1, Math.ceil(262144 / size));
const data = Buffer.alloc(size);
for (let i = 0; i < size; i++) data[i] = (i * 31 + 7) % 256;

function best(f) {
  f(); f(); // warm up
  let min = Infinity;
  for (let i = 0; i < iters; i++) {
    const start = process.hrtime.bigint();
    for (let r = 0; r < reps; r++) f();
    const ns = Number(process.hrtime.bigint() - start);
    if (ns < min) min = ns;
  }
  return Math.floor(min / reps);
}

const text = data.toString("base64");
if (!Buffer.from(text, "base64").equals(data)) throw new Error("round trip failed");
console.log(best(() => data.toString("base64")), best(() => Buffer.from(text, "base64")));
