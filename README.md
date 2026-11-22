# roc-base64

Base64 encoding and decoding for [Roc](https://www.roc-lang.org), following
[RFC 4648](https://www.rfc-editor.org/rfc/rfc4648):

- the standard (`+/`) and URL and filename safe (`-_`) alphabets
- padded and unpadded output, and decoding that requires, forbids, or accepts
  either
- MIME style line wrapping, and decoding that skips whitespace
- strict decoding by default, rejecting non-canonical input, with errors that
  say what is wrong and where
- encoding that never fails, to a `Str` or to bytes
- SIMD encoding and decoding, faster than Rust, Go, and Zig's standard choices on large inputs

Written for the Roc 0.1.0_RC1 compiler.

## Usage

Add the package to your app header, using the URL from the
[latest release](../../releases/latest):

```roc
app [main!] {
	pf: platform "...",
	base64: "https://github.com/<owner>/roc-base64/releases/download/<version>/<hash>.tar.zst",
}

import base64.Base64
```

```roc
Base64.encode("foobar".to_utf8()) # "Zm9vYmFy"
Base64.decode("Zm9vYmFy") # Ok("foobar".to_utf8())

Base64.encode_url([251, 255, 254]) # "-__-"
Base64.encode_url_unpadded([251, 255]) # "-_8", as in JSON Web Tokens
Base64.encode_mime(bytes) # lines of 76 characters separated by CRLF

Base64.decode("Zm9vYg") # Err(InvalidBase64({ index: 6, problem: MissingPadding }))
Base64.decode("Zh==") # Err(InvalidBase64({ index: 1, problem: NonZeroTrailingBits }))
```

Anything else is a record of options away. Start from `default_encode` or
`default_decode` and change what you need:

```roc
Base64.encode_with(bytes, { ..Base64.default_encode, padding: Unpadded, wrap: Wrap({ width: 64, newline: Lf }) })
Base64.decode_with(text, { ..Base64.default_decode, alphabet: UrlSafe, padding: Optional, whitespace: Ignore })
```

| Function | Alphabet | Padding | Lines |
| --- | --- | --- | --- |
| `encode` / `decode` | standard | required | none |
| `encode_url` / `decode_url` | URL safe | required | none |
| `encode_url_unpadded` / `decode_url_unpadded` | URL safe | none | none |
| `encode_mime` / `decode_mime` | standard | required | 76, CRLF / whitespace skipped |

`encode_to_bytes_with` and `decode_bytes_with` work on ASCII bytes instead of
`Str`, and `encoded_len` gives the exact output length for an input length.

Decoding errors are `InvalidBase64({ index, problem })`, where `index` is the
byte offset in the input (its length for problems at the end) and `problem` is
one of `InvalidByte(byte)`, `InvalidLength`, `MissingPadding`,
`UnexpectedPadding`, `DataAfterPadding`, or `NonZeroTrailingBits`.

## Performance

Encoding and decoding use SIMD (Roc's `U8x16` vectors, which lower to NEON on
ARM and SSE on x86-64) for 12 input bytes or 16 characters at a time, following
Wojciech Muła and Daniel Lemire, ["Faster Base64 Encoding and Decoding using
AVX2 Instructions"](https://arxiv.org/abs/1704.00605). Decoding drops to a
byte-at-a-time loop from the first chunk that holds anything but alphabet
characters, such as padding, whitespace, or an error, so error positions stay
exact.

Compared with the standard or most popular base64 in other languages, using
the standard alphabet. Each figure is the fastest of 200 samples, after two
warm-up runs, and includes allocating the output.

**1 MiB**

| Language | Library | Encode MB/s | Encode µs | Decode MB/s | Decode µs |
| --- | --- | ---: | ---: | ---: | ---: |
| Roc | roc-base64 | 10512 | 99.8 | 10276 | 102.0 |
| Rust | base64 crate | 4575 | 229.2 | 4544 | 230.8 |
| Go | encoding/base64 | 3133 | 334.7 | 4282 | 244.9 |
| Zig | std.base64 | 5754 | 182.2 | 4747 | 220.9 |
| Node.js | Buffer | 27654 | 37.9 | 14513 | 72.3 |
| Python | base64 (C) | 1345 | 779.3 | 1149 | 911.9 |

**64 bytes**, where the fixed cost of each call dominates

| Language | Library | Encode MB/s | Encode ns | Decode MB/s | Decode ns |
| --- | --- | ---: | ---: | ---: | ---: |
| Roc | roc-base64 | 2370 | 27 | 1600 | 40 |
| Rust | base64 crate | 2666 | 24 | 2782 | 23 |
| Go | encoding/base64 | 1882 | 34 | 2285 | 28 |
| Zig | std.base64 | 3555 | 18 | 3368 | 19 |
| Node.js | Buffer | 1882 | 34 | 1142 | 56 |
| Python | base64 (C) | 640 | 100 | 421 | 152 |

Measured on an Apple M5 Pro with Roc 0.1.0_RC1 (`--opt=speed`), Rust 1.98.1
with base64 0.22.1, Go 1.26.8, Zig 0.16.0 (`ReleaseFast`), Node.js 24.21.0, and
Python 3.14.7. MB/s is 10^6 bytes of input (encoding) or output (decoding) per
second; small inputs time batches of calls covering 256 KiB. Roc figures vary
by about 10% between runs. Node.js uses
[simdutf](https://github.com/simdutf/simdutf), which processes 64 bytes at a
time with interleaving loads that Roc does not expose; Rust, Go, Zig, and
Python are scalar. roc-base64 also checks canonical encoding while decoding,
and Python's figures use `b64decode(validate=True)` so that it rejects invalid
input too.

`encode` returns a `Str`, which checks that its bytes are UTF-8. Encoding to
bytes with `encode_to_bytes_with` skips that check and is about 15% faster on
large inputs.

Run `just bench-compare [SIZE] [ITERATIONS]` to reproduce the tables. It
enters the `bench` devenv profile, which adds the other toolchains, then builds
and runs the programs in `bench/compare/`.

## Development

Development requires [Nix](https://nixos.org/download/) and
[devenv 2.x](https://devenv.sh/getting-started/). The environment pins
Roc 0.1.0_RC1 and devenv modules v2.1.2; `devenv.lock` pins the Nix inputs.

```sh
devenv shell
just check
just test
just fuzz 30   # check the fuzz examples, then explore for 30 seconds
just diff      # compare against GNU coreutils and OpenSSL on random inputs
just bench     # time encoding and decoding 1 MiB
just perf-check  # fail if SIMD falls below 2x the byte-at-a-time speed
just docs      # generate API docs in generated-docs/
```

With direnv installed, `direnv allow` activates the same environment
automatically. `devenv test` runs the checks, tests, and a formatting check.

The tests include the RFC 4648 vectors, vectors checked against Python's
`base64` module, and round trips of every byte value with every combination of
options. To guard the SIMD paths, they compare encoding and decoding with a
plain reference implementation at every length up to 100 and around larger
chunk boundaries, place every byte value in every lane of a chunk, and check
that a bad byte at any position of a long input is reported at that position.

`just perf-check` guards against slowdowns the tests cannot see, such as a
SIMD path that silently falls back to the byte-at-a-time loop: it fails unless
SIMD encoding and decoding are at least twice as fast as byte-at-a-time
baselines measured in the same process. CI runs it on every push. The [roc-fuzz](https://github.com/lukewilliamboswell/roc-fuzz) target
checks round trips, `encoded_len`, and that strict decoding accepts only
canonical encodings.

`just diff` checks the package against independent implementations, which
devenv provides so they behave the same on every platform. For each random
input it compares our encoding byte for byte with `base64` (unwrapped and
wrapped at 76 and 10), `openssl base64` (unwrapped and wrapped at 64), and
`basenc --base64url` (padded and unpadded). It checks that `base64 -d`,
`openssl base64 -d` and `basenc -d` decode our output back to the input. Then
it corrupts the encoding and checks that whatever our strict decoder still
accepts, `base64 -d` decodes the same way. Pass `--count` for more inputs and
`--seed` to reproduce a run; CI runs 2000 inputs.

## Releasing

Push a version tag. The release workflow runs the tests, bundles `package/`
with `just bundle`, and attaches the archive to a GitHub release whose notes
give the package URL.

## Layout

- `package/`: the package (`main.roc` and `Base64.roc`, with its tests)
- `fuzz/main.roc`: the fuzz target
- `diff/main.roc`: the differential test against coreutils and OpenSSL
- `bench/main.roc`: the benchmark
- `bench/check.roc`: the performance regression check
- `bench/compare/`: the same benchmark in other languages, and the runner
  that tabulates them
