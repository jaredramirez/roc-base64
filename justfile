set positional-arguments

# List available commands.
default:
    @just --list

check:
    roc check package/main.roc
    roc check fuzz/main.roc
    roc check bench/main.roc
    roc check diff/main.roc
    roc check bench/compare/main.roc
    roc check bench/check.roc

test:
    roc test package/Base64.roc

fmt:
    roc fmt package fuzz bench diff

# Fail if any file needs formatting.
fmt-check:
    roc fmt --check package fuzz bench diff

docs:
    roc docs package/main.roc --output=generated-docs

# Check the fuzz examples, then explore for the given number of seconds.
fuzz seconds="30":
    mkdir -p fuzz-out/corpus
    roc build --fuzz fuzz/main.roc --output=fuzz-out/base64
    cd fuzz-out && ./base64 check && ./base64 explore corpus --time={{seconds}}

# Compare against GNU coreutils and OpenSSL on random inputs. See --help.
diff *args:
    roc diff/main.roc "$@"

# Time encoding and decoding SIZE bytes with the optimizing backend.
bench size="1048576" iterations="200":
    mkdir -p bench-out
    roc build --opt=speed bench/main.roc --output=bench-out/roc
    ./bench-out/roc {{size}} {{iterations}}

# Fail if the SIMD paths fall below 2x the speed of byte-at-a-time baselines.
perf-check:
    mkdir -p bench-out
    roc build --opt=speed bench/check.roc --output=bench-out/check
    ./bench-out/check

# Compare against Rust, Go, Zig, Node.js, and Python; prints a Markdown table.
bench-compare size="1048576" iterations="200":
    devenv --profile bench shell -- just _bench-compare {{size}} {{iterations}}

_bench-compare size iterations:
    mkdir -p bench-out
    roc build --opt=speed bench/main.roc --output=bench-out/roc
    cd bench/compare/rust && cargo build --release --quiet --target-dir ../../../bench-out/rust
    cd bench/compare/go && go build -o ../../../bench-out/go .
    zig build-exe -O ReleaseFast -lc bench/compare/zig/main.zig -femit-bin=bench-out/zig --cache-dir bench-out/zig-cache
    roc bench/compare/main.roc {{size}} {{iterations}}

# Bundle the package into dist/ for a release; prints the archive name.
bundle:
    rm -rf dist && mkdir -p dist
    cp LICENSE package/LICENSE
    cd package && roc bundle main.roc Base64.roc LICENSE --output-dir ../dist; status=$?; rm -f LICENSE; exit $status
