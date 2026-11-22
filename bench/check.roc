app [main!] {
	base64: "../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import pf.Monotonic
import pf.Stderr
import pf.Stdout
import base64.Base64

## A performance regression check: the SIMD paths must stay at least
## `min_speedup` times faster than byte-at-a-time baselines on 1 MiB, measured
## in the same process so the check works on any machine. Run with
## `just perf-check`, which builds with --opt=speed.
##
## - Encoding is compared with [scalar_encode], a plain loop written here.
## - Decoding is compared with the library's own byte-at-a-time decoder,
##   which it uses for the whole input when the first chunk has whitespace.
min_speedup : U64
min_speedup = 2

size : U64
size = 1024 * 1024

iterations : U64
iterations = 60

main! = |_args| {
	bytes = List.from_iter((0.U64).until(size)).map(|i| (i * 31 + 7).to_u8_wrap())
	text = Base64.encode_to_bytes_with(bytes, Base64.default_encode)
	lenient = { ..Base64.default_decode, whitespace: Ignore }
	# A leading space sends the whole input down the byte-at-a-time path
	spaced = [' '].concat(text)
	if scalar_encode(bytes) != text or Base64.decode_bytes_with(spaced, lenient) != Ok(bytes) {
		Stderr.line!("the baselines disagree with the library")?
		return Err(Exit(1))
	}

	encode_simd = best!(|{}| Base64.encode_to_bytes_with(bytes, Base64.default_encode).len())
	encode_scalar = best!(|{}| scalar_encode(bytes).len())
	decode_simd = best!(|{}| decoded_len(Base64.decode_bytes_with(text, lenient)))
	decode_scalar = best!(|{}| decoded_len(Base64.decode_bytes_with(spaced, lenient)))

	results = [
		("encode", encode_simd, encode_scalar),
		("decode", decode_simd, decode_scalar),
	]
	var $failed = False
	for (name, simd, scalar) in results {
		# Speedup in tenths, to print one decimal
		tenths = scalar * 10 / simd
		verdict = if (tenths >= min_speedup * 10) "ok" else "TOO SLOW"
		Stdout.line!("${name}: SIMD ${(simd / 1000).to_str()} µs, byte at a time ${(scalar / 1000).to_str()} µs, ${(tenths / 10).to_str()}.${(tenths % 10).to_str()}x faster (need ${min_speedup.to_str()}x) ${verdict}")?
		if tenths < min_speedup * 10 {
			$failed = True
		}
	}
	if $failed {
		Err(Exit(1))
	} else {
		Ok({})
	}
}

decoded_len : Try(List(U8), _) -> U64
decoded_len = |result|
	match result {
		Ok(decoded) => decoded.len()
		Err(_) => 0
	}

## The fastest of [iterations] runs of `f`, in nanoseconds
best! : ({} -> U64) => U64
best! = |f| {
	_warm1 = f({})
	_warm2 = f({})
	_warm3 = f({})
	var $min = 0xFFFF_FFFF_FFFF_FFFF.U64
	for _ in List.from_iter((0.U64).until(iterations)) {
		start = Monotonic.now!()
		len = f({})
		ns = start.elapsed!().to_nanos()
		if len == 0 {
			crash "a run produced no output"
		}
		if ns < $min {
			$min = ns
		}
	}
	$min
}

alphabet : List(U8)
alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".to_utf8()

## A plain byte-at-a-time encoder, as fast as straightforward Roc allows
scalar_encode : List(U8) -> List(U8)
scalar_encode = |bytes| {
	at = |n, shift|
		match alphabet.get(n.shr_zf_wrap(shift).bitwise_and(63).to_u64()) {
			Ok(c) => c
			Err(OutOfBounds) => crash "six bits always index the alphabet"
		}
	var $out = List.with_capacity((bytes.len() + 2) / 3 * 4)
	var $acc = 0.U32
	var $count = 0.U8
	for byte in bytes {
		$acc = $acc.shl_wrap(8).bitwise_or(byte.to_u32())
		$count = $count + 1
		if $count == 3 {
			$out = $out.append(at($acc, 18)).append(at($acc, 12)).append(at($acc, 6)).append(at($acc, 0))
			$acc = 0
			$count = 0
		}
	}
	if $count == 1 {
		n = $acc.shl_wrap(16)
		$out = $out.append(at(n, 18)).append(at(n, 12)).append('=').append('=')
	} else if $count == 2 {
		n = $acc.shl_wrap(8)
		$out = $out.append(at(n, 18)).append(at(n, 12)).append(at(n, 6)).append('=')
	}
	$out
}
