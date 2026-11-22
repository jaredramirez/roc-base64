app [main!] {
	base64: "../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import pf.Monotonic
import pf.Stderr
import pf.Stdout
import base64.Base64

## A performance regression check: each SIMD path must stay at least
## `min_speedup` times faster than a plain byte-at-a-time implementation
## written here, on 1 MiB, measured in the same process so the check works on
## any machine. A path that silently falls back to byte-at-a-time code runs at
## about 1x and fails. Run with `just perf-check`, which builds with
## --opt=speed.
min_speedup : U64
min_speedup = 2

size : U64
size = 1024 * 1024

iterations : U64
iterations = 60

standard_alphabet : List(U8)
standard_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".to_utf8()

url_safe_alphabet : List(U8)
url_safe_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".to_utf8()

main! = |_args| {
	bytes = List.from_iter((0.U64).until(size)).map(|i| (i * 31 + 7).to_u8_wrap())
	url = { ..Base64.default_encode, alphabet: UrlSafe }
	mime = { ..Base64.default_encode, wrap: Wrap({ width: 76, newline: CrLf }) }
	url_decode = { ..Base64.default_decode, alphabet: UrlSafe }
	mime_decode = { ..Base64.default_decode, whitespace: Ignore }

	standard_text = scalar_encode(bytes, standard_alphabet)
	url_text = scalar_encode(bytes, url_safe_alphabet)
	mime_text = scalar_wrap(standard_text, 76)
	standard_values = values_for(standard_alphabet)
	url_values = values_for(url_safe_alphabet)

	# The baselines must agree with the library before their times mean anything
	agree =
		Base64.encode_to_bytes_with(bytes, Base64.default_encode) == standard_text
			and Base64.encode_to_bytes_with(bytes, url) == url_text
			and Base64.encode_to_bytes_with(bytes, mime) == mime_text
			and scalar_decode(standard_text, standard_values) == bytes
			and scalar_decode(url_text, url_values) == bytes
			and scalar_decode(mime_text, standard_values) == bytes
			and Base64.decode_bytes_with(mime_text, mime_decode) == Ok(bytes)
	if !agree {
		Stderr.line!("the baselines disagree with the library")?
		return Err(Exit(1))
	}

	results = [
		(
			"encode standard",
			best!(|{}| Base64.encode_to_bytes_with(bytes, Base64.default_encode).len()),
			best!(|{}| scalar_encode(bytes, standard_alphabet).len()),
		),
		(
			"encode URL-safe",
			best!(|{}| Base64.encode_to_bytes_with(bytes, url).len()),
			best!(|{}| scalar_encode(bytes, url_safe_alphabet).len()),
		),
		(
			"encode MIME",
			best!(|{}| Base64.encode_to_bytes_with(bytes, mime).len()),
			best!(|{}| scalar_wrap(scalar_encode(bytes, standard_alphabet), 76).len()),
		),
		(
			"decode standard",
			best!(|{}| decoded_len(Base64.decode_bytes_with(standard_text, Base64.default_decode))),
			best!(|{}| scalar_decode(standard_text, standard_values).len()),
		),
		(
			"decode URL-safe",
			best!(|{}| decoded_len(Base64.decode_bytes_with(url_text, url_decode))),
			best!(|{}| scalar_decode(url_text, url_values).len()),
		),
		(
			"decode MIME",
			best!(|{}| decoded_len(Base64.decode_bytes_with(mime_text, mime_decode))),
			best!(|{}| scalar_decode(mime_text, standard_values).len()),
		),
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

## The fastest of [iterations] runs of `f`, in nanoseconds, after warming up
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

## A plain byte-at-a-time encoder, as fast as straightforward Roc allows
scalar_encode : List(U8), List(U8) -> List(U8)
scalar_encode = |bytes, alphabet| {
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

## Lines of `width` characters separated by CRLF, a byte at a time
scalar_wrap : List(U8), U64 -> List(U8)
scalar_wrap = |chars, width| {
	var $out = List.with_capacity(chars.len() + chars.len() / width * 2)
	var $column = 0
	for c in chars {
		if $column == width {
			$out = $out.append('\r').append('\n')
			$column = 0
		}
		$out = $out.append(c)
		$column = $column + 1
	}
	$out
}

## Each byte's 6-bit value in `alphabet`, or 64 for other bytes
values_for : List(U8) -> List(U8)
values_for = |alphabet|
	List.from_iter((0.U64).until(256)).map(
		|n| match alphabet.find_first_index(|c| c.to_u64() == n) {
			Ok(i) => i.to_u8_wrap()
			Err(NotFound) => 64
		},
	)

## A plain byte-at-a-time decoder that skips anything outside the alphabet
## (whitespace and padding included), as fast as straightforward Roc allows
scalar_decode : List(U8), List(U8) -> List(U8)
scalar_decode = |chars, values| {
	var $out = List.with_capacity(chars.len() / 4 * 3)
	var $acc = 0.U32
	var $count = 0.U8
	for c in chars {
		value = match values.get(c.to_u64()) {
			Ok(v) => v
			Err(OutOfBounds) => crash "a byte always indexes the 256 values"
		}
		if value < 64 {
			$acc = $acc.shl_wrap(6).bitwise_or(value.to_u32())
			$count = $count + 1
			if $count == 4 {
				$out = $out.append($acc.shr_zf_wrap(16).to_u8_wrap()).append($acc.shr_zf_wrap(8).to_u8_wrap()).append($acc.to_u8_wrap())
				$acc = 0
				$count = 0
			}
		}
	}
	if $count == 2 {
		$out = $out.append($acc.shr_zf_wrap(4).to_u8_wrap())
	} else if $count == 3 {
		$out = $out.append($acc.shr_zf_wrap(10).to_u8_wrap()).append($acc.shr_zf_wrap(2).to_u8_wrap())
	}
	$out
}
