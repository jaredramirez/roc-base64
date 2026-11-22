app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import pf.Cmd
import pf.OsStr
import pf.Stderr
import pf.Stdout

## Usage: bench/compare/main.roc SIZE ITERATIONS
##
## Runs each language's benchmark, already built by `just bench-compare`, and
## prints a Markdown table of encode and decode throughput. Each benchmark
## prints its fastest encode and decode of SIZE bytes, in nanoseconds.
Entry : { name : Str, library : Str, program : Str, args : List(Str) }

entries : List(Entry)
entries = [
	{ name: "Roc", library: "roc-base64", program: "bench-out/roc", args: [] },
	{ name: "Rust", library: "base64 crate", program: "bench-out/rust/release/bench", args: [] },
	{ name: "Go", library: "encoding/base64", program: "bench-out/go", args: [] },
	{ name: "Zig", library: "std.base64", program: "bench-out/zig", args: [] },
	{ name: "Node.js", library: "Buffer", program: "node", args: ["bench/compare/node/bench.js"] },
	{ name: "Python", library: "base64 (C)", program: "python3", args: ["bench/compare/python/bench.py"] },
]

## Run one benchmark and parse its two timings
run_entry! : Entry, Str, Str => Try((U64, U64), [BenchFailed(Str)])
run_entry! = |entry, size, iterations| {
	args = entry.args.concat([size, iterations])
	output = Cmd.new(OsStr.from_str(entry.program))
		.args(args.map(OsStr.from_str))
		.run!() ? |err| BenchFailed("${entry.name}: ${Str.inspect(err)}")
	text = Str.from_utf8_lossy(output.stdout_bytes).trim()
	match (output.status, text.split_on(" ").map(U64.from_str)) {
		(Exited(0), [Ok(encode_ns), Ok(decode_ns)]) => Ok((encode_ns, decode_ns))
		_ => Err(BenchFailed("${entry.name} printed ${Str.inspect(text)}; stderr: ${Str.from_utf8_lossy(output.stderr_bytes)}"))
	}
}

## Throughput in MB/s (10^6 bytes per second) with no decimals; each
## benchmark reports time per call
mb_per_s : U64, U64 -> Str
mb_per_s = |bytes, ns| (bytes * 1000 / ns).to_str()

## Nanoseconds as microseconds with one decimal
micros : U64 -> Str
micros = |ns| {
	tenths = (ns + 50) / 100
	"${(tenths / 10).to_str()}.${(tenths % 10).to_str()}"
}

## Time per call in µs for large inputs, or in ns for small ones
time_unit : U64 -> (Str, (U64 -> Str))
time_unit = |size| if (size >= 16384) ("µs", micros) else ("ns", |ns| ns.to_str())

run! = |os_args|
	match os_args.map(OsStr.display) {
		[size_str, iterations_str] => {
			size = U64.from_str(size_str) ? |_| BenchFailed("SIZE must be an integer")
			(unit, show_time) = time_unit(size)
			var $rows = []
			for entry in entries {
				(encode_ns, decode_ns) = run_entry!(entry, size_str, iterations_str)?
				$rows = $rows.append(
					"| ${entry.name} | ${entry.library} | ${mb_per_s(size, encode_ns)} | ${show_time(encode_ns)} | ${mb_per_s(size, decode_ns)} | ${show_time(decode_ns)} |",
				)
			}
			header = [
				"| Language | Library | Encode MB/s | Encode ${unit} | Decode MB/s | Decode ${unit} |",
				"| --- | --- | ---: | ---: | ---: | ---: |",
			]
			Stdout.line!(Str.join_with(header.concat($rows), "\n"))?
			Ok({})
		}
		_ => Err(BenchFailed("Usage: bench/compare/main.roc SIZE ITERATIONS"))
	}

main! : List(OsStr) => Try({}, _)
main! = |args|
	match run!(args) {
		Ok({}) => Ok({})
		Err(BenchFailed(msg)) => {
			Stderr.line!(msg)?
			Err(Exit(1))
		}
		Err(other) => {
			Stderr.line!("Unexpected error: ${Str.inspect(other)}")?
			Err(Exit(1))
		}
	}
