app [main!] {
	base64: "../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import pf.Cmd
import pf.OsStr
import pf.Random
import pf.Stderr
import pf.Stdout
import base64.Base64

usage =
	\\Compare this package against GNU coreutils (base64, basenc) and OpenSSL on
	\\random inputs, in both directions.
	\\
	\\Usage: diff/main.roc [--count INTEGER] [--seed INTEGER]
	\\
	\\  --count INTEGER  How many random inputs to check (default 300)
	\\  --seed INTEGER   Reproduce a run (default: fresh randomness)
	\\  --help           Show this message

Args : { count : U64, seed : [Fixed(U64), Fresh], help : Bool }

parse_args : List(Str), Args -> Try(Args, [BadArgs(Str)])
parse_args = |args, parsed|
	match args {
		[] => Ok(parsed)
		["--help", .. as rest] => parse_args(rest, { ..parsed, help: True })
		["--count", value, .. as rest] =>
			match U64.from_str(value) {
				Ok(count) => parse_args(rest, { ..parsed, count })
				Err(_) => Err(BadArgs("--count must be a non-negative integer, but got ${value}"))
			}
		["--seed", value, .. as rest] =>
			match U64.from_str(value) {
				Ok(seed) => parse_args(rest, { ..parsed, seed: Fixed(seed) })
				Err(_) => Err(BadArgs("--seed must be a non-negative integer, but got ${value}"))
			}
		[other, ..] => Err(BadArgs("Unknown or incomplete argument: ${other}"))
	}

## SplitMix64: the next state and a random number
next : U64 -> (U64, U64)
next = |state| {
	s = state.plus_wrap(0x9E3779B97F4A7C15)
	z1 = s.bitwise_xor(s.shr_zf_wrap(30)).times_wrap(0xBF58476D1CE4E5B9)
	z2 = z1.bitwise_xor(z1.shr_zf_wrap(27)).times_wrap(0x94D049BB133111EB)
	(s, z2.bitwise_xor(z2.shr_zf_wrap(31)))
}

## `count` random bytes
random_bytes : U64, U64 -> (U64, List(U8))
random_bytes = |state, count| {
	var $state = state
	var $bytes = List.with_capacity(count)
	for _ in List.from_iter((0.U64).until(count)) {
		(s, n) = next($state)
		$state = s
		$bytes = $bytes.append(n.to_u8_wrap())
	}
	($state, $bytes)
}

## Bytes a mutation may write: alphabet characters from both alphabets,
## padding, whitespace, and bytes outside any alphabet
mutation_bytes : List(U8)
mutation_bytes = "AZaz09+/-_=  \n\r\t!.~\u(e9)".to_utf8()

## Corrupt `text` by replacing, inserting, or deleting one byte, or by
## appending padding
mutate : U64, List(U8) -> (U64, List(U8))
mutate = |state, text| {
	(s1, a) = next(state)
	(s2, b) = next(s1)
	position = if (text.is_empty()) 0 else a % text.len()
	new_byte = match mutation_bytes.get(b % mutation_bytes.len()) {
		Ok(byte) => byte
		Err(OutOfBounds) => crash "b % len is always in bounds"
	}
	before = text.take_first(position)
	after = text.drop_first(position)
	mutated = match a.shr_zf_wrap(32) % 4 {
		0 => before.append(new_byte).concat(after.drop_first(1))
		1 => before.append(new_byte).concat(after)
		2 => before.concat(after.drop_first(1))
		_ => text.append('=')
	}
	(s2, mutated)
}

## What a reference tool did with its standard input
Verdict : [Accepted(List(U8)), Rejected]

## Run `program` with `input` on standard input. Exit code 0 is `Accepted` with
## its output; any other exit is `Rejected`.
run_tool! : Str, List(Str), List(U8) => Try(Verdict, [ToolFailed(Str)])
run_tool! = |program, args, input| {
	command = Str.join_with([program].concat(args), " ")
	output = Cmd.new(OsStr.from_str(program))
		.args(args.map(OsStr.from_str))
		.stdin(Bytes(input))
		.run!() ? |err| ToolFailed("${command}: ${Str.inspect(err)}")
	match output.status {
		Exited(0) => Ok(Accepted(output.stdout_bytes))
		_ => Ok(Rejected)
	}
}

## Run a tool that must succeed, dropping one trailing newline from its output
encode_tool! : Str, List(Str), List(U8) => Try(List(U8), [ToolFailed(Str)])
encode_tool! = |program, args, input|
	match run_tool!(program, args, input)? {
		Accepted(out) if out.last() == Ok('\n') => Ok(out.drop_last(1))
		Accepted(out) => Ok(out)
		Rejected => Err(ToolFailed("${program} ${Str.join_with(args, " ")} rejected ${Str.inspect(input)}"))
	}

## Ours and theirs, for one comparison that differed
Mismatch : { check : Str, input : List(U8), ours : Str, theirs : Str }

show : List(U8) -> Str
show = |bytes| Str.inspect(Str.from_utf8_lossy(bytes))

wrapped : U64 -> Base64.EncodeOptions
wrapped = |width| { ..Base64.default_encode, wrap: Wrap({ width, newline: Lf }) }

## Every comparison for one input. `mutated` is a corrupted encoding of it.
check_input! : List(U8), List(U8) => Try((U64, List(Mismatch)), [ToolFailed(Str)])
check_input! = |input, mutated| {
	var $checks = 0
	var $mismatches = []

	standard = Base64.encode_to_bytes_with(input, Base64.default_encode)
	url = Base64.encode_to_bytes_with(input, { ..Base64.default_encode, alphabet: UrlSafe })
	url_unpadded = Base64.encode_to_bytes_with(input, { ..Base64.default_encode, alphabet: UrlSafe, padding: Unpadded })

	# Encoding: our output against each tool's, byte for byte
	encodings = [
		("encode vs base64 -w0", standard, ("base64", ["-w0"])),
		("encode vs openssl base64 -A", standard, ("openssl", ["base64", "-A"])),
		("wrap 76 vs base64", Base64.encode_to_bytes_with(input, wrapped(76)), ("base64", [])),
		("wrap 64 vs openssl base64", Base64.encode_to_bytes_with(input, wrapped(64)), ("openssl", ["base64"])),
		("wrap 10 vs base64 -w10", Base64.encode_to_bytes_with(input, wrapped(10)), ("base64", ["-w10"])),
		("encode_url vs basenc --base64url", url, ("basenc", ["--base64url", "-w0"])),
	]
	for (check, ours, (program, args)) in encodings {
		theirs = encode_tool!(program, args, input)?
		$checks = $checks + 1
		if ours != theirs {
			$mismatches = $mismatches.append({ check, input, ours: show(ours), theirs: show(theirs) })
		}
	}

	# basenc has no unpadded mode, so strip its padding
	theirs_unpadded = encode_tool!("basenc", ["--base64url", "-w0"], input)?.drop_if(|c| c == '=')
	$checks = $checks + 1
	if url_unpadded != theirs_unpadded {
		$mismatches = $mismatches.append({ check: "encode_url_unpadded vs basenc, unpadded", input, ours: show(url_unpadded), theirs: show(theirs_unpadded) })
	}

	# Our decoder must read the tools' wrapped and unpadded output
	gnu_wrapped = encode_tool!("base64", [], input)?
	$checks = $checks + 1
	if Base64.decode_bytes_with(gnu_wrapped, { ..Base64.default_decode, whitespace: Ignore }) != Ok(input) {
		$mismatches = $mismatches.append({ check: "decode with whitespace: Ignore of base64 (wrapped)", input, ours: "did not decode to the input", theirs: show(gnu_wrapped) })
	}
	$checks = $checks + 1
	if Base64.decode_bytes_with(theirs_unpadded, { ..Base64.default_decode, alphabet: UrlSafe, padding: Forbidden }) != Ok(input) {
		$mismatches = $mismatches.append({ check: "decode_url_unpadded of basenc, unpadded", input, ours: "did not decode to the input", theirs: show(theirs_unpadded) })
	}

	# Decoding: each tool must decode our output back to the input
	decodings = [
		("base64 -d decodes encode", standard, ("base64", ["-d"])),
		("openssl base64 -d -A decodes encode", standard, ("openssl", ["base64", "-d", "-A"])),
		("basenc -d decodes encode_url", url, ("basenc", ["-d", "--base64url"])),
	]
	for (check, text, (program, args)) in decodings {
		$checks = $checks + 1
		theirs = match run_tool!(program, args, text)? {
			Accepted(out) if out == input => Same
			Accepted(out) => Differs(Str.inspect(out))
			Rejected => Differs("rejected")
		}
		match theirs {
			Same => {}
			Differs(shown) => {
				$mismatches = $mismatches.append({ check, input, ours: show(text), theirs: shown })
			}
		}
	}

	# Corrupted input: whatever our strict decoder accepts, GNU must decode the
	# same way. GNU is more lenient (it skips newlines and allows non-zero
	# trailing bits), so only this direction must hold.
	$checks = $checks + 1
	match Base64.decode_bytes_with(mutated, Base64.default_decode) {
		Ok(ours) => {
			theirs = match run_tool!("base64", ["-d"], mutated)? {
				Accepted(out) if out == ours => Same
				Accepted(out) => Differs(Str.inspect(out))
				Rejected => Differs("rejected")
			}
			match theirs {
				Same => {}
				Differs(shown) => {
					$mismatches = $mismatches.append({ check: "decode of corrupted text vs base64 -d", input: mutated, ours: Str.inspect(ours), theirs: shown })
				}
			}
		}
		Err(_) => {}
	}

	Ok(($checks, $mismatches))
}

## Fail unless `base64` and `basenc` are GNU coreutils, whose flags this uses
require_gnu! : Str => Try({}, [ToolFailed(Str)])
require_gnu! = |program| {
	version = match run_tool!(program, ["--version"], [])? {
		Accepted(out) => Str.from_utf8_lossy(out)
		Rejected => ""
	}
	if version.contains("GNU coreutils") {
		Ok({})
	} else {
		Err(ToolFailed("${program} is not GNU coreutils; run inside `devenv shell`"))
	}
}

run! = |os_args| {
	args = parse_args(os_args.map(OsStr.display), { count: 300, seed: Fresh, help: False })?
	if args.help {
		Stdout.line!(usage)?
		return Ok({})
	}
	require_gnu!("base64")?
	require_gnu!("basenc")?

	seed = match args.seed {
		Fixed(value) => value
		Fresh => Random.seed_u64!()?
	}

	var $state = seed
	var $checks = 0
	var $mismatches = []
	var $accepted = 0.U64
	for case in List.from_iter((0.U64).until(args.count)) {
		# Mostly short inputs, which cover every tail length, and some long ones
		# that cross several wrapped lines
		(s1, a) = next($state)
		len = if (case % 10 == 9) a % 2000 else a % 100
		(s2, input) = random_bytes(s1, len)
		(s3, mutated) = mutate(s2, Base64.encode_to_bytes_with(input, Base64.default_encode))
		$state = s3
		if Base64.decode_bytes_with(mutated, Base64.default_decode).is_ok() {
			$accepted = $accepted + 1
		}
		(checks, mismatches) = check_input!(input, mutated)?
		$checks = $checks + checks
		$mismatches = $mismatches.concat(mismatches)
	}

	for m in $mismatches.take_first(10) {
		Stderr.line!("${m.check}\n  input:  ${Str.inspect(m.input)}\n  ours:   ${m.ours}\n  theirs: ${m.theirs}")?
	}
	summary = "${args.count.to_str()} inputs, ${$checks.to_str()} comparisons, ${$mismatches.len().to_str()} mismatches; strict decoding accepted ${$accepted.to_str()} corrupted inputs (--seed ${seed.to_str()})"
	if $mismatches.is_empty() {
		Stdout.line!(summary)?
		Ok({})
	} else {
		Err(Mismatches(summary))
	}
}

main! : List(OsStr) => Try({}, _)
main! = |args|
	match run!(args) {
		Ok({}) => Ok({})
		Err(err) => {
			message = match err {
				BadArgs(msg) => "${msg}\n\n${usage}"
				ToolFailed(msg) => msg
				Mismatches(summary) => summary
				other => "Unexpected error: ${Str.inspect(other)}"
			}
			Stderr.line!(message)?
			Err(Exit(1))
		}
	}
