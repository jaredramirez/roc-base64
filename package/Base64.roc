## Base64 encoding and decoding as described in
## [RFC 4648](https://www.rfc-editor.org/rfc/rfc4648), with the standard and
## URL and filename safe alphabets, padded and unpadded output, and MIME style
## line wrapping ([RFC 2045](https://www.rfc-editor.org/rfc/rfc2045#section-6.8)).
##
## Encoding never fails. Decoding is strict by default: it rejects characters
## outside the alphabet, misplaced or missing padding, and non-canonical input
## whose unused trailing bits are not zero, and it says where the problem is.
##
## ```roc
## Base64.encode("foobar".to_utf8()) == "Zm9vYmFy"
## Base64.decode("Zm9vYmFy") == Ok("foobar".to_utf8())
## Base64.encode_url_unpadded([251, 255]) == "-_8"
## ```
Base64 := [].{

	## Which 64 characters stand for the six-bit values. `Standard` ends in `+`
	## and `/` ([RFC 4648 section 4](https://www.rfc-editor.org/rfc/rfc4648#section-4));
	## `UrlSafe` ends in `-` and `_` instead, so the output can go in URLs and
	## file names unescaped ([section 5](https://www.rfc-editor.org/rfc/rfc4648#section-5)).
	Alphabet : [Standard, UrlSafe]

	## Whether encoding fills out the last group of four characters with `=`.
	EncodePadding : [Padded, Unpadded]

	## Which padding decoding accepts. `Required` needs exactly the padding an
	## encoder would add, `Forbidden` rejects any `=`, and `Optional` accepts
	## either complete padding or none, but never partial padding.
	DecodePadding : [Required, Forbidden, Optional]

	## Whether encoding breaks the output into lines of at most `width`
	## characters. There is no newline after the last line. A `width` of 0
	## means no wrapping.
	LineWrap : [NoWrap, Wrap({ width : U64, newline : [Lf, CrLf] })]

	## How to encode. See [default_encode] for a starting point.
	EncodeOptions : { alphabet : Alphabet, padding : EncodePadding, wrap : LineWrap }

	## How to decode. `whitespace: Ignore` skips spaces, tabs, carriage returns,
	## line feeds, vertical tabs, and form feeds anywhere in the input.
	## `trailing_bits: Allow` accepts non-canonical input such as `Zh==`, whose
	## unused bits are not zero, and decodes it as if they were. See
	## [default_decode] for a starting point.
	DecodeOptions : {
		alphabet : Alphabet,
		padding : DecodePadding,
		whitespace : [Reject, Ignore],
		trailing_bits : [Reject, Allow],
	}

	## What is wrong with the input at the reported index.
	##
	## - `InvalidByte(byte)`: `byte` is not in the alphabet (or is whitespace
	##   that is not being ignored)
	## - `InvalidLength`: the input ends with a single character left over,
	##   which cannot stand for a whole byte
	## - `MissingPadding`: the input ends without the padding it needs
	## - `UnexpectedPadding`: an `=` where padding is not allowed
	## - `DataAfterPadding`: a character from the alphabet after padding
	## - `NonZeroTrailingBits`: the last character has unused bits set
	Problem : [
		InvalidByte(U8),
		InvalidLength,
		MissingPadding,
		UnexpectedPadding,
		DataAfterPadding,
		NonZeroTrailingBits,
	]

	## A decoding failure. `index` counts bytes from the start of the input.
	## `InvalidLength` and `MissingPadding`, found at the end of the input,
	## report its length; `NonZeroTrailingBits` reports the last character.
	DecodeErr : [InvalidBase64({ index : U64, problem : Problem })]

	## The standard alphabet, padded, without line breaks.
	default_encode : EncodeOptions
	default_encode = { alphabet: Standard, padding: Padded, wrap: NoWrap }

	## The standard alphabet, padding required, no whitespace, canonical input
	## only.
	default_decode : DecodeOptions
	default_decode = { alphabet: Standard, padding: Required, whitespace: Reject, trailing_bits: Reject }

	## Standard padded base64.
	##
	## ```roc
	## Base64.encode("foob".to_utf8()) == "Zm9vYg=="
	## ```
	encode : List(U8) -> Str
	encode = |bytes| encode_with(bytes, default_encode)

	## Decode standard padded base64.
	##
	## ```roc
	## Base64.decode("Zm9vYg==") == Ok("foob".to_utf8())
	## Base64.decode("Zm9vYg") == Err(InvalidBase64({ index: 6, problem: MissingPadding }))
	## ```
	decode : Str -> Try(List(U8), DecodeErr)
	decode = |text| decode_with(text, default_decode)

	## URL and filename safe base64, padded.
	encode_url : List(U8) -> Str
	encode_url = |bytes| encode_with(bytes, { ..default_encode, alphabet: UrlSafe })

	## Decode URL and filename safe base64 with padding.
	decode_url : Str -> Try(List(U8), DecodeErr)
	decode_url = |text| decode_with(text, { ..default_decode, alphabet: UrlSafe })

	## URL and filename safe base64 without padding, as used by JSON Web Tokens.
	encode_url_unpadded : List(U8) -> Str
	encode_url_unpadded = |bytes| encode_with(bytes, { ..default_encode, alphabet: UrlSafe, padding: Unpadded })

	## Decode URL and filename safe base64 without padding.
	decode_url_unpadded : Str -> Try(List(U8), DecodeErr)
	decode_url_unpadded = |text| decode_with(text, { ..default_decode, alphabet: UrlSafe, padding: Forbidden })

	## MIME base64: the standard alphabet, padded, in lines of at most 76
	## characters separated by CRLF.
	encode_mime : List(U8) -> Str
	encode_mime = |bytes| encode_with(bytes, { ..default_encode, wrap: Wrap({ width: 76, newline: CrLf }) })

	## Decode MIME base64, skipping line breaks and other whitespace.
	decode_mime : Str -> Try(List(U8), DecodeErr)
	decode_mime = |text| decode_with(text, { ..default_decode, whitespace: Ignore })

	## Encode with the given options.
	##
	## ```roc
	## Base64.encode_with([251, 255], { ..Base64.default_encode, padding: Unpadded }) == "+/8"
	## ```
	encode_with : List(U8), EncodeOptions -> Str
	encode_with = |bytes, options|
		# The output is ASCII by construction, so no bytes are ever replaced
		Str.from_utf8_lossy(encode_to_bytes_with(bytes, options))

	## Decode with the given options.
	decode_with : Str, DecodeOptions -> Try(List(U8), DecodeErr)
	decode_with = |text, options| decode_bytes_with(text.to_utf8(), options)

	## Encode to ASCII bytes instead of a `Str`.
	encode_to_bytes_with : List(U8), EncodeOptions -> List(U8)
	encode_to_bytes_with = |bytes, options| {
		alphabet = options.alphabet
		len = bytes.len()
		var $out = List.with_capacity(encoded_len(len, options))

		# 12 bytes at a time with SIMD, while 16 can be loaded
		offsets = match alphabet {
			Standard => standard_offsets
			UrlSafe => url_safe_offsets
		}
		var $start = 0
		while $start + 16 <= len {
			$out = encode12(load16(bytes, $start), offsets).append_to($out)
			$start = $start + 12
		}

		var $acc = 0.U32
		var $count = 0.U8
		for byte in bytes.drop_first($start) {
			$acc = $acc.shl_wrap(8).bitwise_or(byte.to_u32())
			$count = $count + 1
			if $count == 3 {
				$out = $out
					.append(char($acc, 18, alphabet))
					.append(char($acc, 12, alphabet))
					.append(char($acc, 6, alphabet))
					.append(char($acc, 0, alphabet))
				$acc = 0
				$count = 0
			}
		}
		padded = match options.padding {
			Padded => True
			Unpadded => False
		}
		if $count == 1 {
			n = $acc.shl_wrap(16)
			$out = $out.append(char(n, 18, alphabet)).append(char(n, 12, alphabet))
			if padded {
				$out = $out.append('=').append('=')
			}
		} else if $count == 2 {
			n = $acc.shl_wrap(8)
			$out = $out.append(char(n, 18, alphabet)).append(char(n, 12, alphabet)).append(char(n, 6, alphabet))
			if padded {
				$out = $out.append('=')
			}
		}
		match options.wrap {
			Wrap({ width, newline }) if width > 0 and $out.len() > width => wrap_lines($out, width, newline)
			_ => $out
		}
	}

	## Decode ASCII bytes instead of a `Str`.
	decode_bytes_with : List(U8), DecodeOptions -> Try(List(U8), DecodeErr)
	decode_bytes_with = |chars, options| {
		len = chars.len()
		# Room for every SIMD chunk's 16 lanes before the last 4 are dropped
		var $out = List.with_capacity(len / 4 * 3 + 16)
		tables = match options.alphabet {
			Standard => standard_tables
			UrlSafe => url_safe_tables
		}
		values = match options.alphabet {
			Standard => standard_values
			UrlSafe => url_safe_values
		}
		ignore_whitespace = match options.whitespace {
			Ignore => True
			Reject => False
		}
		var $acc = 0.U32
		var $data = 0.U64
		var $pads = 0.U64
		var $last_data = 0.U64
		var $index = 0.U64
		var $failure = None

		# Clean input is decoded entirely by [decode_chunks]
		(clean_out, clean_end) = decode_chunks(chars, 0, $out, tables)
		$out = clean_out
		$index = clean_end
		$data = $index

		while $index < len {
			# Between groups, go back to SIMD. When a chunk holds anything but
			# alphabet characters (padding, whitespace, or an error), keep the
			# groups before it and handle the rest a character at a time.
			# Between groups, go back to SIMD
			if $pads == 0 and $data % 4 == 0 {
				(resumed_out, resumed_end) = decode_chunks(chars, $index, $out, tables)
				$data = $data + (resumed_end - $index)
				$out = resumed_out
				$index = resumed_end
				if $index >= len {
					break
				}
			}

			# Otherwise, one character at a time
			c = match chars.get($index) {
				Ok(byte) => byte
				Err(OutOfBounds) => crash "the loop keeps index below len"
			}
			value = match values.get(c.to_u64()) {
				Ok(v) => v
				Err(OutOfBounds) => crash "a byte is always within the 256 table entries"
			}
			if value < 64 {
				if $pads > 0 {
					$failure = Failed(DataAfterPadding)
					break
				}
				$acc = $acc.shl_wrap(6).bitwise_or(value.to_u32())
				$data = $data + 1
				$last_data = $index
				if $data % 4 == 0 {
					$out = $out.append(byte_at($acc, 16)).append(byte_at($acc, 8)).append(byte_at($acc, 0))
					$acc = 0
				}
			} else if c == '=' {
				if padding_fits(options.padding, $data % 4, $pads) {
					$pads = $pads + 1
				} else {
					$failure = Failed(UnexpectedPadding)
					break
				}
			} else if !(ignore_whitespace and is_whitespace(c)) {
				$failure = Failed(InvalidByte(c))
				break
			}
			$index = $index + 1
		}
		match $failure {
			Failed(problem) => return Err(InvalidBase64({ index: $index, problem }))
			None => {}
		}

		end = chars.len()
		leftover = $data % 4
		if leftover == 1 {
			return Err(InvalidBase64({ index: end, problem: InvalidLength }))
		}
		needed = match leftover {
			2 => 2
			3 => 1
			_ => 0
		}
		padding_ok =
			$pads == needed
				or (
					$pads == 0 and match options.padding {
						Required => False
						Forbidden | Optional => True
					}
				)
		if !padding_ok {
			return Err(InvalidBase64({ index: end, problem: MissingPadding }))
		}

		(tail, unused) = match leftover {
			2 => ([byte_at($acc, 4)], $acc.bitwise_and(0xF))
			3 => ([byte_at($acc, 10), byte_at($acc, 2)], $acc.bitwise_and(0x3))
			_ => ([], 0)
		}
		trailing_ok = match options.trailing_bits {
			Allow => True
			Reject => unused == 0
		}
		if trailing_ok {
			Ok($out.concat(tail))
		} else {
			Err(InvalidBase64({ index: $last_data, problem: NonZeroTrailingBits }))
		}
	}

	## How many bytes encoding `byte_count` bytes produces, including padding
	## and newlines. Crashes if the result does not fit in a `U64`, which
	## takes more than 13 exabytes of input.
	encoded_len : U64, EncodeOptions -> U64
	encoded_len = |byte_count, options| {
		leftover = byte_count % 3
		tail = match (options.padding, leftover) {
			(_, 0) => 0
			(Padded, _) => 4
			(Unpadded, _) => leftover + 1
		}
		chars = byte_count / 3 * 4 + tail
		match options.wrap {
			Wrap({ width, newline }) if width > 0 and chars > 0 => chars + (chars - 1) / width * newline_len(newline)
			_ => chars
		}
	}
}

# Everything below is private to this module

## Read 16 bytes at `start`, which the caller has checked are there
load16 : List(U8), U64 -> U8x16
load16 = |bytes, start|
	match U8x16.load(bytes, start) {
		Ok(v) => v
		Err(OutOfBounds) => crash "load16 needs start + 16 <= len"
	}

## A vector from a list of exactly 16 lanes
vector : List(U8) -> U8x16
vector = |lanes|
	match U8x16.from_list(lanes) {
		Ok(v) => v
		Err(WrongLength) => crash "vector needs exactly 16 lanes"
	}

## Encode the first 12 bytes of `input` as 16 characters (Wojciech Muła
## and Daniel Lemire, "Faster Base64 Encoding and Decoding using AVX2
## Instructions", 2018, with 16-byte vectors)
encode12 : U8x16, U8x16 -> U8x16
encode12 = |input, offsets| {
	# Each group of 3 bytes [a, b, c] becomes the 32-bit lane [b, a, c, b],
	# so every 6-bit value sits within one 16-bit half
	shuffled = input.table_lookup(encode_shuffle).to_u16x8_bits()
	# Move each half's two values into the low 6 bits of their own bytes
	hi = shuffled.bitwise_and(splat32(0x0FC0FC00)).times_high(splat32(0x04000040))
	lo = shuffled.bitwise_and(splat32(0x003F03F0)).times_wrap(splat32(0x01000010))
	values = hi.bitwise_or(lo).to_u8x16_bits()
	# Map 0..63 to the alphabet by adding an offset per range: 0..25 use
	# index 13, 26..51 index 0, 52..61 indices 1..10, and 62 and 63 indices
	# 11 and 12
	reduced = values.minus_saturated(U8x16.splat(51))
	upper = values.lt_lanes(U8x16.splat(26)).bitwise_and(U8x16.splat(13))
	values.plus_wrap(offsets.table_lookup(reduced.bitwise_or(upper)))
}

encode_shuffle : U8x16
encode_shuffle = vector([1, 0, 2, 1, 4, 3, 5, 4, 7, 6, 8, 7, 10, 9, 11, 10])

## The characters for 62 and 63
special_chars : Base64.Alphabet -> (U8, U8)
special_chars = |alphabet|
	match alphabet {
		Standard => ('+', '/')
		UrlSafe => ('-', '_')
	}

## Decode 16 characters into 12 bytes, in the first 12 lanes of `bytes`.
## `valid` says whether every character is in the alphabet. When one is not,
## the bytes of the groups before the first invalid character, which
## [valid_groups] counts, are still correct. Uses
## the nibble lookups of Wojciech Muła and Daniel Lemire, "Faster Base64
## Encoding and Decoding using AVX2 Instructions", 2018.
decode16 : U8x16, DecodeTables -> { bytes : U8x16, valid : Bool }
decode16 = |input, tables| {
	hi = input.shr_zf_wrap(4)
	valid = valid_lanes(input, tables).all_lanes_set()

	# Each character plus the offset for its high nibble gives its value;
	# the character for 63 shares a nibble, so it uses slot nibble + 8
	is63 = input.eq_lanes(U8x16.splat(tables.c63))
	values = input.plus_wrap(tables.offsets.table_lookup(hi.bitwise_or(is63.bitwise_and(U8x16.splat(8)))))

	# Join each pair of values into 12 bits, then each pair of those into
	# the 24 bits of a group, and gather the 3 bytes of each group
	pairs = values.dot_pairs_saturated(decode_pair_weights).to_u8x16_bits().to_u32x4_bits()
	groups = pairs.bitwise_and(U32x4.splat(0xFFFF)).shl_wrap(12).bitwise_or(pairs.shr_zf_wrap(16))
	{ bytes: groups.to_u8x16_bits().table_lookup(decode_shuffle), valid }
}

## Decode `chars` from `start` 16 at a time with SIMD, appending to `out`,
## until a chunk holds anything but alphabet characters (padding, whitespace,
## or an error) or fewer than 16 are left. The groups before the first such
## character are kept. Returns the output and where decoding stopped, which
## is always a whole number of groups after `start`.
decode_chunks : List(U8), U64, List(U8), DecodeTables -> (List(U8), U64)
decode_chunks = |chars, start, out, tables| {
	var $out = out
	var $index = start
	zero = U8x16.splat(0)
	# 64 characters make 48 bytes, packed into three whole vectors so that
	# every append is a full 16 bytes
	while $index + 64 <= chars.len() {
		a = decode16(load16(chars, $index), tables)
		b = decode16(load16(chars, $index + 16), tables)
		c = decode16(load16(chars, $index + 32), tables)
		d = decode16(load16(chars, $index + 48), tables)
		if !(a.valid and b.valid and c.valid and d.valid) {
			break
		}
		$out = a.bytes
			.bitwise_or(zero.concat_shift_bytes(b.bytes, 4))
			.append_to($out)
		$out = b.bytes
			.concat_shift_bytes(zero, 4)
			.bitwise_or(zero.concat_shift_bytes(c.bytes, 8))
			.append_to($out)
		$out = c.bytes
			.concat_shift_bytes(zero, 8)
			.bitwise_or(zero.concat_shift_bytes(d.bytes, 12))
			.append_to($out)
		$index = $index + 64
	}
	while $index + 16 <= chars.len() {
		decoded = decode16(load16(chars, $index), tables)
		if !decoded.valid {
			break
		}
		$out = decoded.bytes.append_to($out).drop_last(4)
		$index = $index + 16
	}
	# Keep the whole groups of the chunk that stopped the loop
	if $index + 16 <= chars.len() {
		input = load16(chars, $index)
		groups = valid_groups(input, tables)
		if groups > 0 {
			$out = decode16(input, tables).bytes.append_to($out).drop_last(16 - groups * 3)
			$index = $index + groups * 4
		}
	}
	($out, $index)
}

## All ones in the lanes whose characters are in the alphabet
valid_lanes : U8x16, DecodeTables -> U8x16
valid_lanes = |input, tables|
	tables.invalid_lo
		.table_lookup(input.bitwise_and(U8x16.splat(0x0F)))
		.bitwise_and(tables.class_hi.table_lookup(input.shr_zf_wrap(4)))
		.eq_lanes(U8x16.splat(0))

## How many whole groups of 4 characters come before the first character
## outside the alphabet
valid_groups : U8x16, DecodeTables -> U64
valid_groups = |input, tables| valid_lanes(input, tables).to_bitmask().bitwise_not().count_trailing_zero_bits().to_u64() / 4

## Lookup tables for [decode16]. A byte with high nibble `h` and low
## nibble `l` is in the alphabet when `invalid_lo[l]` and `class_hi[h]`
## share no bits.
DecodeTables : { invalid_lo : U8x16, class_hi : U8x16, offsets : U8x16, c63 : U8 }

standard_tables : DecodeTables
standard_tables = tables_for(Standard)

url_safe_tables : DecodeTables
url_safe_tables = tables_for(UrlSafe)

## Each high nibble's bit: nibbles 0 and 1 (control characters, never
## valid) share bit 0, nibbles 2 to 7 get bits 1 to 6, and non-ASCII
## nibbles 8 to 15 share bit 7
nibble_class : U8 -> U8
nibble_class = |h|
	if h <= 1 {
		1
	} else if h <= 7 {
		(1.U8).shl_wrap(h - 1)
	} else {
		0x80
	}

tables_for : Base64.Alphabet -> DecodeTables
tables_for = |alphabet| {
	(_, c63) = special_chars(alphabet)
	nibbles = List.from_iter((0.U8).until(16))
	invalid_lo = nibbles.map(
		|l| nibbles.fold(
			0.U8,
			|bits, h|
				match sextet(h.shl_wrap(4).bitwise_or(l), alphabet) {
					Ok(_) => bits
					Err(NotInAlphabet) => bits.bitwise_or(nibble_class(h))
				},
		),
	)
	# For each slot, the offset of the alphabet characters there, or 0
	offset_for = |slot|
		List.from_iter((0.U32).until(256))
			.map(|n| n.to_u8_wrap())
			.keep_if(|c| if (c == c63) slot == c.shr_zf_wrap(4) + 8 else slot == c.shr_zf_wrap(4))
			.fold(
				0.U8,
				|offset, c|
					match sextet(c, alphabet) {
						Ok(v) => v.to_u8_wrap().minus_wrap(c)
						Err(NotInAlphabet) => offset
					},
			)
	{
		invalid_lo: vector(invalid_lo),
		class_hi: vector(nibbles.map(nibble_class)),
		offsets: vector(nibbles.map(offset_for)),
		c63,
	}
}

decode_pair_weights : I8x16
decode_pair_weights = vector([64, 1, 64, 1, 64, 1, 64, 1, 64, 1, 64, 1, 64, 1, 64, 1]).to_i8x16_bits()

## The 3 bytes of each group's 24 bits, most significant first; indices of
## 16 or more give 0
decode_shuffle : U8x16
decode_shuffle = vector([2, 1, 0, 6, 5, 4, 10, 9, 8, 14, 13, 12, 255, 255, 255, 255])

standard_offsets : U8x16
standard_offsets = encode_offsets(Standard)

url_safe_offsets : U8x16
url_safe_offsets = encode_offsets(UrlSafe)

## What to add to each range of values to reach its character; see [encode12]
encode_offsets : Base64.Alphabet -> U8x16
encode_offsets = |alphabet| {
	(c62, c63) = special_chars(alphabet)
	uppercase : U8
	uppercase = 'A'
	lowercase : U8
	lowercase = 'a'
	digits : U8
	digits = '0'
	vector(
		[lowercase - 26]
			.concat(List.repeat(digits.minus_wrap(52), 10))
			.concat([c62.minus_wrap(62), c63.minus_wrap(63), uppercase, 0, 0]),
	)
}

## A 32-bit constant in every lane, viewed as 16-bit lanes
splat32 : U32 -> U16x8
splat32 = |n| U32x4.splat(n).to_u8x16_bits().to_u16x8_bits()

## `chars` broken into lines of `width` characters, without a newline after
## the last line, copying a line at a time
wrap_lines : List(U8), U64, [Lf, CrLf] -> List(U8)
wrap_lines = |chars, width, newline|
	if width == 0 or chars.len() <= width {
		chars
	} else {
		separator = newline_bytes(newline)
		line_count = (chars.len() + width - 1) / width
		var $out = List.with_capacity(chars.len() + (line_count - 1) * separator.len())
		var $start = 0
		while $start < chars.len() {
			if $start > 0 {
				$out = $out.concat(separator)
			}
			$out = $out.concat(chars.sublist({ start: $start, len: width }))
			$start = $start + width
		}
		$out
	}

newline_bytes : [Lf, CrLf] -> List(U8)
newline_bytes = |newline|
	match newline {
		Lf => ['\n']
		CrLf => ['\r', '\n']
	}

newline_len : [Lf, CrLf] -> U64
newline_len = |newline| newline_bytes(newline).len()

standard_chars : List(U8)
standard_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".to_utf8()

url_safe_chars : List(U8)
url_safe_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".to_utf8()

## The character for the six bits of `n` starting at `shift`
char : U32, U8, Base64.Alphabet -> U8
char = |n, shift, alphabet| {
	index = n.shr_zf_wrap(shift).bitwise_and(63).to_u64()
	table = match alphabet {
		Standard => standard_chars
		UrlSafe => url_safe_chars
	}
	match table.get(index) {
		Ok(c) => c
		Err(OutOfBounds) => crash "a six-bit index is always within the 64 characters"
	}
}

## The eight bits of `n` starting at `shift`
byte_at : U32, U8 -> U8
byte_at = |n, shift| n.shr_zf_wrap(shift).to_u8_wrap()

## The six bits each byte stands for, indexed by byte, with 64 for bytes
## outside the alphabet
standard_values : List(U8)
standard_values = values_for(Standard)

url_safe_values : List(U8)
url_safe_values = values_for(UrlSafe)

values_for : Base64.Alphabet -> List(U8)
values_for = |alphabet|
	List.from_iter((0.U64).until(256)).map(
		|c| match sextet(c.to_u8_wrap(), alphabet) {
			Ok(v) => v.to_u8_wrap()
			Err(NotInAlphabet) => 64
		},
	)

## The six bits a character stands for
sextet : U8, Base64.Alphabet -> Try(U32, [NotInAlphabet])
sextet = |c, alphabet|
	if c >= 'A' and c <= 'Z' {
		Ok((c - 'A').to_u32())
	} else if c >= 'a' and c <= 'z' {
		Ok((c - 'a').to_u32() + 26)
	} else if c >= '0' and c <= '9' {
		Ok((c - '0').to_u32() + 52)
	} else {
		match (alphabet, c) {
			(Standard, '+') | (UrlSafe, '-') => Ok(62)
			(Standard, '/') | (UrlSafe, '_') => Ok(63)
			_ => Err(NotInAlphabet)
		}
	}

## Whether one more `=` is allowed after `leftover` data characters in the
## last group and `pads` padding characters so far
padding_fits : Base64.DecodePadding, U64, U64 -> Bool
padding_fits = |padding, leftover, pads|
	match padding {
		Forbidden => False
		Required | Optional => (leftover == 2 and pads < 2) or (leftover == 3 and pads < 1)
	}

is_whitespace : U8 -> Bool
is_whitespace = |c| c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0B or c == 0x0C

# RFC 4648 section 10 test vectors
expect Base64.encode("".to_utf8()) == ""
expect Base64.encode("f".to_utf8()) == "Zg=="
expect Base64.encode("fo".to_utf8()) == "Zm8="
expect Base64.encode("foo".to_utf8()) == "Zm9v"
expect Base64.encode("foob".to_utf8()) == "Zm9vYg=="
expect Base64.encode("fooba".to_utf8()) == "Zm9vYmE="
expect Base64.encode("foobar".to_utf8()) == "Zm9vYmFy"

expect Base64.decode("") == Ok("".to_utf8())
expect Base64.decode("Zg==") == Ok("f".to_utf8())
expect Base64.decode("Zm8=") == Ok("fo".to_utf8())
expect Base64.decode("Zm9v") == Ok("foo".to_utf8())
expect Base64.decode("Zm9vYg==") == Ok("foob".to_utf8())
expect Base64.decode("Zm9vYmE=") == Ok("fooba".to_utf8())
expect Base64.decode("Zm9vYmFy") == Ok("foobar".to_utf8())

# The last two characters differ between the alphabets
expect Base64.encode([251, 255, 254]) == "+//+"
expect Base64.encode_url([251, 255, 254]) == "-__-"
expect Base64.decode_url("-__-") == Ok([251, 255, 254])
expect Base64.encode_url_unpadded([251, 255]) == "-_8"
expect Base64.decode_url_unpadded("-_8") == Ok([251, 255])
expect Base64.decode("-__-") == Err(InvalidBase64({ index: 0, problem: InvalidByte('-') }))
expect Base64.decode_url("+//+") == Err(InvalidBase64({ index: 0, problem: InvalidByte('+') }))

# Random bytes, checked against Python's base64 module
expect Base64.encode([121]) == "eQ=="
expect Base64.encode_url([121]) == "eQ=="
expect Base64.encode_url_unpadded([121]) == "eQ"
expect Base64.encode([196, 18]) == "xBI="
expect Base64.encode_url([196, 18]) == "xBI="
expect Base64.encode_url_unpadded([196, 18]) == "xBI"
expect Base64.encode([31, 198, 8]) == "H8YI"
expect Base64.encode_url([31, 198, 8]) == "H8YI"
expect Base64.encode_url_unpadded([31, 198, 8]) == "H8YI"
expect Base64.encode([87, 223, 254, 252]) == "V9/+/A=="
expect Base64.encode_url([87, 223, 254, 252]) == "V9_-_A=="
expect Base64.encode_url_unpadded([87, 223, 254, 252]) == "V9_-_A"
expect Base64.encode([116, 185, 153, 204, 133]) == "dLmZzIU="
expect Base64.encode_url([116, 185, 153, 204, 133]) == "dLmZzIU="
expect Base64.encode_url_unpadded([116, 185, 153, 204, 133]) == "dLmZzIU"
expect Base64.encode([241, 144, 172, 70, 200, 188, 223]) == "8ZCsRsi83w=="
expect Base64.encode_url([241, 144, 172, 70, 200, 188, 223]) == "8ZCsRsi83w=="
expect Base64.encode_url_unpadded([241, 144, 172, 70, 200, 188, 223]) == "8ZCsRsi83w"
expect Base64.encode([114, 142, 112, 254, 108, 206, 134, 30, 51, 230]) == "co5w/mzOhh4z5g=="
expect Base64.encode_url([114, 142, 112, 254, 108, 206, 134, 30, 51, 230]) == "co5w_mzOhh4z5g=="
expect Base64.encode_url_unpadded([114, 142, 112, 254, 108, 206, 134, 30, 51, 230]) == "co5w_mzOhh4z5g"
expect Base64.encode([176, 234, 95, 93, 152, 201, 135, 94, 65, 217, 111, 230, 42, 173, 164, 208]) == "sOpfXZjJh15B2W/mKq2k0A=="
expect Base64.encode_url([176, 234, 95, 93, 152, 201, 135, 94, 65, 217, 111, 230, 42, 173, 164, 208]) == "sOpfXZjJh15B2W_mKq2k0A=="
expect Base64.encode_url_unpadded([176, 234, 95, 93, 152, 201, 135, 94, 65, 217, 111, 230, 42, 173, 164, 208]) == "sOpfXZjJh15B2W_mKq2k0A"
expect Base64.encode([68, 234, 185, 188, 212, 8, 204, 108, 222, 82, 71, 142, 215, 48, 144, 62, 194, 93, 250, 145, 107, 238, 121, 87, 206, 79, 93, 70, 245, 164, 40]) == "ROq5vNQIzGzeUkeO1zCQPsJd+pFr7nlXzk9dRvWkKA=="
expect Base64.encode_url([68, 234, 185, 188, 212, 8, 204, 108, 222, 82, 71, 142, 215, 48, 144, 62, 194, 93, 250, 145, 107, 238, 121, 87, 206, 79, 93, 70, 245, 164, 40]) == "ROq5vNQIzGzeUkeO1zCQPsJd-pFr7nlXzk9dRvWkKA=="
expect Base64.encode_url_unpadded([68, 234, 185, 188, 212, 8, 204, 108, 222, 82, 71, 142, 215, 48, 144, 62, 194, 93, 250, 145, 107, 238, 121, 87, 206, 79, 93, 70, 245, 164, 40]) == "ROq5vNQIzGzeUkeO1zCQPsJd-pFr7nlXzk9dRvWkKA"
expect Base64.encode([59, 219, 143, 39, 114, 147, 44, 60, 199, 124, 110, 236, 111, 178, 84, 208, 28, 117, 247, 160, 35, 217, 218, 141, 8, 240, 125, 168, 124, 232, 9, 106, 213, 121, 207, 19, 196, 71, 14, 13, 152, 26, 26, 212, 48, 30, 102, 151, 3, 165, 139, 241, 247, 107, 2, 99, 233]) == "O9uPJ3KTLDzHfG7sb7JU0Bx196Aj2dqNCPB9qHzoCWrVec8TxEcODZgaGtQwHmaXA6WL8fdrAmPp"
expect Base64.encode_url([59, 219, 143, 39, 114, 147, 44, 60, 199, 124, 110, 236, 111, 178, 84, 208, 28, 117, 247, 160, 35, 217, 218, 141, 8, 240, 125, 168, 124, 232, 9, 106, 213, 121, 207, 19, 196, 71, 14, 13, 152, 26, 26, 212, 48, 30, 102, 151, 3, 165, 139, 241, 247, 107, 2, 99, 233]) == "O9uPJ3KTLDzHfG7sb7JU0Bx196Aj2dqNCPB9qHzoCWrVec8TxEcODZgaGtQwHmaXA6WL8fdrAmPp"
expect Base64.encode_url_unpadded([59, 219, 143, 39, 114, 147, 44, 60, 199, 124, 110, 236, 111, 178, 84, 208, 28, 117, 247, 160, 35, 217, 218, 141, 8, 240, 125, 168, 124, 232, 9, 106, 213, 121, 207, 19, 196, 71, 14, 13, 152, 26, 26, 212, 48, 30, 102, 151, 3, 165, 139, 241, 247, 107, 2, 99, 233]) == "O9uPJ3KTLDzHfG7sb7JU0Bx196Aj2dqNCPB9qHzoCWrVec8TxEcODZgaGtQwHmaXA6WL8fdrAmPp"
expect Base64.encode([179, 2, 236, 197, 198, 29, 188, 235, 149, 245, 82, 23, 244, 116, 242, 118, 198, 1, 249, 173, 105, 55, 21, 108, 51, 144, 163, 162, 230, 146, 154, 161, 205, 164, 137, 248, 56, 191, 60, 5, 173, 218, 114, 119, 38, 47, 77, 215, 111, 115, 228, 131, 11, 59, 238, 21, 8, 58]) == "swLsxcYdvOuV9VIX9HTydsYB+a1pNxVsM5CjouaSmqHNpIn4OL88Ba3acncmL03Xb3Pkgws77hUIOg=="
expect Base64.encode_url([179, 2, 236, 197, 198, 29, 188, 235, 149, 245, 82, 23, 244, 116, 242, 118, 198, 1, 249, 173, 105, 55, 21, 108, 51, 144, 163, 162, 230, 146, 154, 161, 205, 164, 137, 248, 56, 191, 60, 5, 173, 218, 114, 119, 38, 47, 77, 215, 111, 115, 228, 131, 11, 59, 238, 21, 8, 58]) == "swLsxcYdvOuV9VIX9HTydsYB-a1pNxVsM5CjouaSmqHNpIn4OL88Ba3acncmL03Xb3Pkgws77hUIOg=="
expect Base64.encode_url_unpadded([179, 2, 236, 197, 198, 29, 188, 235, 149, 245, 82, 23, 244, 116, 242, 118, 198, 1, 249, 173, 105, 55, 21, 108, 51, 144, 163, 162, 230, 146, 154, 161, 205, 164, 137, 248, 56, 191, 60, 5, 173, 218, 114, 119, 38, 47, 77, 215, 111, 115, 228, 131, 11, 59, 238, 21, 8, 58]) == "swLsxcYdvOuV9VIX9HTydsYB-a1pNxVsM5CjouaSmqHNpIn4OL88Ba3acncmL03Xb3Pkgws77hUIOg"
expect Base64.encode([63, 56, 127, 179, 31, 98, 104, 163, 244, 134, 229, 72, 148, 90, 103, 10, 207, 39, 176, 233, 12, 118, 5, 215, 67, 68, 195, 155, 200, 140, 9, 255, 23, 90, 125, 63, 232, 225, 160, 141, 95, 107, 248, 235, 123, 27, 171, 1, 137, 178, 154, 147, 72, 85, 69, 109, 73, 119, 222]) == "Pzh/sx9iaKP0huVIlFpnCs8nsOkMdgXXQ0TDm8iMCf8XWn0/6OGgjV9r+Ot7G6sBibKak0hVRW1Jd94="
expect Base64.encode_url([63, 56, 127, 179, 31, 98, 104, 163, 244, 134, 229, 72, 148, 90, 103, 10, 207, 39, 176, 233, 12, 118, 5, 215, 67, 68, 195, 155, 200, 140, 9, 255, 23, 90, 125, 63, 232, 225, 160, 141, 95, 107, 248, 235, 123, 27, 171, 1, 137, 178, 154, 147, 72, 85, 69, 109, 73, 119, 222]) == "Pzh_sx9iaKP0huVIlFpnCs8nsOkMdgXXQ0TDm8iMCf8XWn0_6OGgjV9r-Ot7G6sBibKak0hVRW1Jd94="
expect Base64.encode_url_unpadded([63, 56, 127, 179, 31, 98, 104, 163, 244, 134, 229, 72, 148, 90, 103, 10, 207, 39, 176, 233, 12, 118, 5, 215, 67, 68, 195, 155, 200, 140, 9, 255, 23, 90, 125, 63, 232, 225, 160, 141, 95, 107, 248, 235, 123, 27, 171, 1, 137, 178, 154, 147, 72, 85, 69, 109, 73, 119, 222]) == "Pzh_sx9iaKP0huVIlFpnCs8nsOkMdgXXQ0TDm8iMCf8XWn0_6OGgjV9r-Ot7G6sBibKak0hVRW1Jd94"
expect Base64.encode([237, 131, 148, 225, 142, 1, 98, 181, 207, 89, 42, 142, 71, 36, 253, 151, 249, 219, 212, 116, 34, 43, 68, 226, 90, 239, 181, 218, 33, 83, 179, 102, 178, 82, 201, 244, 186, 32, 219, 157, 139, 112, 130, 118, 48, 6, 54, 237, 13, 5, 247, 52, 183, 47, 17, 239, 172, 78, 250, 250]) == "7YOU4Y4BYrXPWSqORyT9l/nb1HQiK0TiWu+12iFTs2ayUsn0uiDbnYtwgnYwBjbtDQX3NLcvEe+sTvr6"
expect Base64.encode_url([237, 131, 148, 225, 142, 1, 98, 181, 207, 89, 42, 142, 71, 36, 253, 151, 249, 219, 212, 116, 34, 43, 68, 226, 90, 239, 181, 218, 33, 83, 179, 102, 178, 82, 201, 244, 186, 32, 219, 157, 139, 112, 130, 118, 48, 6, 54, 237, 13, 5, 247, 52, 183, 47, 17, 239, 172, 78, 250, 250]) == "7YOU4Y4BYrXPWSqORyT9l_nb1HQiK0TiWu-12iFTs2ayUsn0uiDbnYtwgnYwBjbtDQX3NLcvEe-sTvr6"
expect Base64.encode_url_unpadded([237, 131, 148, 225, 142, 1, 98, 181, 207, 89, 42, 142, 71, 36, 253, 151, 249, 219, 212, 116, 34, 43, 68, 226, 90, 239, 181, 218, 33, 83, 179, 102, 178, 82, 201, 244, 186, 32, 219, 157, 139, 112, 130, 118, 48, 6, 54, 237, 13, 5, 247, 52, 183, 47, 17, 239, 172, 78, 250, 250]) == "7YOU4Y4BYrXPWSqORyT9l_nb1HQiK0TiWu-12iFTs2ayUsn0uiDbnYtwgnYwBjbtDQX3NLcvEe-sTvr6"
expect Base64.encode([14, 125, 243, 228, 19, 224, 57, 59, 240, 189, 203, 127, 45, 154, 23, 2, 146, 169, 100, 202, 184, 33, 78, 243, 62, 92, 4, 43, 11, 155, 228, 97, 19, 119, 75, 89, 67, 57, 34, 104, 85, 202, 92, 131, 140, 247, 111, 25, 35, 225, 97, 9, 161, 104, 90, 220, 73, 138, 238, 67, 34, 36, 150, 200, 151, 72, 129, 29, 41, 11, 21, 177, 189, 161, 55, 29, 252, 148, 130, 83, 225, 241, 67, 9, 45, 156, 93, 249, 168, 182, 151, 135, 246, 11, 210, 63, 64, 7, 184, 133]) == "Dn3z5BPgOTvwvct/LZoXApKpZMq4IU7zPlwEKwub5GETd0tZQzkiaFXKXIOM928ZI+FhCaFoWtxJiu5DIiSWyJdIgR0pCxWxvaE3HfyUglPh8UMJLZxd+ai2l4f2C9I/QAe4hQ=="
expect Base64.encode_url([14, 125, 243, 228, 19, 224, 57, 59, 240, 189, 203, 127, 45, 154, 23, 2, 146, 169, 100, 202, 184, 33, 78, 243, 62, 92, 4, 43, 11, 155, 228, 97, 19, 119, 75, 89, 67, 57, 34, 104, 85, 202, 92, 131, 140, 247, 111, 25, 35, 225, 97, 9, 161, 104, 90, 220, 73, 138, 238, 67, 34, 36, 150, 200, 151, 72, 129, 29, 41, 11, 21, 177, 189, 161, 55, 29, 252, 148, 130, 83, 225, 241, 67, 9, 45, 156, 93, 249, 168, 182, 151, 135, 246, 11, 210, 63, 64, 7, 184, 133]) == "Dn3z5BPgOTvwvct_LZoXApKpZMq4IU7zPlwEKwub5GETd0tZQzkiaFXKXIOM928ZI-FhCaFoWtxJiu5DIiSWyJdIgR0pCxWxvaE3HfyUglPh8UMJLZxd-ai2l4f2C9I_QAe4hQ=="
expect Base64.encode_url_unpadded([14, 125, 243, 228, 19, 224, 57, 59, 240, 189, 203, 127, 45, 154, 23, 2, 146, 169, 100, 202, 184, 33, 78, 243, 62, 92, 4, 43, 11, 155, 228, 97, 19, 119, 75, 89, 67, 57, 34, 104, 85, 202, 92, 131, 140, 247, 111, 25, 35, 225, 97, 9, 161, 104, 90, 220, 73, 138, 238, 67, 34, 36, 150, 200, 151, 72, 129, 29, 41, 11, 21, 177, 189, 161, 55, 29, 252, 148, 130, 83, 225, 241, 67, 9, 45, 156, 93, 249, 168, 182, 151, 135, 246, 11, 210, 63, 64, 7, 184, 133]) == "Dn3z5BPgOTvwvct_LZoXApKpZMq4IU7zPlwEKwub5GETd0tZQzkiaFXKXIOM928ZI-FhCaFoWtxJiu5DIiSWyJdIgR0pCxWxvaE3HfyUglPh8UMJLZxd-ai2l4f2C9I_QAe4hQ"

# MIME wrapping, checked against Python's base64.encodebytes
expect {
	mime_bytes = [80, 125, 145, 123, 47, 184, 234, 191, 120, 94, 225, 101, 139, 86, 235, 155, 67, 115, 192, 229, 170, 240, 188, 34, 14, 235, 226, 22, 56, 162, 237, 161, 87, 66, 184, 201, 158, 201, 69, 138, 113, 80, 83, 204, 124, 1, 172, 107, 14, 70, 52, 68, 78, 242, 40, 176, 34, 22, 36, 127, 159, 3, 44, 8, 172, 125, 73, 47, 22, 234, 162, 206, 59, 105, 248, 16, 165, 136, 101, 28, 76, 58, 159, 147, 241, 170, 8, 188, 242, 242, 93, 189, 102, 86, 149, 27, 40, 128, 58, 98, 235, 255, 148, 49, 155, 71, 111, 88, 81, 121, 72, 112, 222, 77, 42, 163, 111, 86, 80, 162]
	Base64.encode_mime(mime_bytes) == "UH2Rey+46r94XuFli1brm0NzwOWq8LwiDuviFjii7aFXQrjJnslFinFQU8x8AaxrDkY0RE7yKLAi\r\nFiR/nwMsCKx9SS8W6qLOO2n4EKWIZRxMOp+T8aoIvPLyXb1mVpUbKIA6Yuv/lDGbR29YUXlIcN5N\r\nKqNvVlCi"
}

# Every byte value, at every length of tail, survives a round trip with every
# combination of options
expect {
	all_bytes = List.from_iter((0.U32).until(256)).map(U32.to_u8_wrap)
	inputs = [all_bytes, all_bytes.drop_last(1), all_bytes.drop_last(2)]
	alphabets = [Standard, UrlSafe]
	paddings = [(Padded, Required), (Padded, Optional), (Unpadded, Forbidden), (Unpadded, Optional)]
	wraps = [(NoWrap, Reject), (Wrap({ width: 76, newline: CrLf }), Ignore), (Wrap({ width: 1, newline: Lf }), Ignore), (Wrap({ width: 0, newline: Lf }), Reject)]
	inputs.all(
		|bytes|
			alphabets.all(
				|alphabet|
					paddings.all(
						|(encode_padding, decode_padding)|
							wraps.all(
								|(wrap, whitespace)| {
									text = Base64.encode_with(bytes, { alphabet, padding: encode_padding, wrap })
									options = { alphabet, padding: decode_padding, whitespace, trailing_bits: Reject }
									Base64.decode_with(text, options) == Ok(bytes)
								},
							),
					),
			),
	)
}

# encoded_len matches the output for every length and option
expect {
	options = [
		Base64.default_encode,
		{ ..Base64.default_encode, padding: Unpadded },
		{ ..Base64.default_encode, wrap: Wrap({ width: 76, newline: CrLf }) },
		{ ..Base64.default_encode, padding: Unpadded, wrap: Wrap({ width: 5, newline: Lf }) },
		{ ..Base64.default_encode, wrap: Wrap({ width: 0, newline: CrLf }) },
	]
	List.from_iter((0.U64).until(200)).all(
		|n| {
			bytes = List.repeat(7, n)
			options.all(|o| Base64.encode_to_bytes_with(bytes, o).len() == Base64.encoded_len(n, o))
		},
	)
}

# Wrapping puts no newline before the first line or after the last
expect Base64.encode_with([], { ..Base64.default_encode, wrap: Wrap({ width: 4, newline: Lf }) }) == ""
expect Base64.encode_with("foo".to_utf8(), { ..Base64.default_encode, wrap: Wrap({ width: 4, newline: Lf }) }) == "Zm9v"
expect Base64.encode_with("foobar".to_utf8(), { ..Base64.default_encode, wrap: Wrap({ width: 4, newline: Lf }) }) == "Zm9v\nYmFy"
expect Base64.encode_with("foob".to_utf8(), { ..Base64.default_encode, wrap: Wrap({ width: 3, newline: CrLf }) }) == "Zm9\r\nvYg\r\n=="
expect Base64.decode_mime("Zm9v\r\nYmFy\r\n") == Ok("foobar".to_utf8())
expect Base64.decode_mime(" Zm 9v\tYg\n=\n= ") == Ok("foob".to_utf8())
expect Base64.decode("Zm9v\nYmFy") == Err(InvalidBase64({ index: 4, problem: InvalidByte('\n') }))

# Padding rules
expect Base64.decode("Zg") == Err(InvalidBase64({ index: 2, problem: MissingPadding }))
expect Base64.decode("Zg=") == Err(InvalidBase64({ index: 3, problem: MissingPadding }))
expect Base64.decode("Zm9") == Err(InvalidBase64({ index: 3, problem: MissingPadding }))
expect Base64.decode("Zm9v=") == Err(InvalidBase64({ index: 4, problem: UnexpectedPadding }))
expect Base64.decode("Zm8==") == Err(InvalidBase64({ index: 4, problem: UnexpectedPadding }))
expect Base64.decode("Zg===") == Err(InvalidBase64({ index: 4, problem: UnexpectedPadding }))
expect Base64.decode("====") == Err(InvalidBase64({ index: 0, problem: UnexpectedPadding }))
expect Base64.decode("Z===") == Err(InvalidBase64({ index: 1, problem: UnexpectedPadding }))
expect Base64.decode("=Zm9") == Err(InvalidBase64({ index: 0, problem: UnexpectedPadding }))
expect Base64.decode("Zg=a") == Err(InvalidBase64({ index: 3, problem: DataAfterPadding }))
expect Base64.decode("Zg==Zg==") == Err(InvalidBase64({ index: 4, problem: DataAfterPadding }))
expect Base64.decode_url_unpadded("Zg==") == Err(InvalidBase64({ index: 2, problem: UnexpectedPadding }))
expect Base64.decode_url_unpadded("Zg") == Ok("f".to_utf8())

optional : Base64.DecodeOptions
optional = { ..Base64.default_decode, padding: Optional }

expect Base64.decode_with("Zg", optional) == Ok("f".to_utf8())
expect Base64.decode_with("Zg==", optional) == Ok("f".to_utf8())
expect Base64.decode_with("Zg=", optional) == Err(InvalidBase64({ index: 3, problem: MissingPadding }))
expect Base64.decode_with("Zm8", optional) == Ok("fo".to_utf8())

# Lengths and characters outside the alphabet
expect Base64.decode("Z") == Err(InvalidBase64({ index: 1, problem: InvalidLength }))
expect Base64.decode("Zm9vY") == Err(InvalidBase64({ index: 5, problem: InvalidLength }))
expect Base64.decode("Zm9vY=") == Err(InvalidBase64({ index: 5, problem: UnexpectedPadding }))
expect Base64.decode("Zm9v!A==") == Err(InvalidBase64({ index: 4, problem: InvalidByte('!') }))
expect Base64.decode("Zm 9") == Err(InvalidBase64({ index: 2, problem: InvalidByte(' ') }))
expect Base64.decode("Zm9\u(e9)") == Err(InvalidBase64({ index: 3, problem: InvalidByte(0xC3) }))

# Non-canonical trailing bits are rejected unless allowed
expect Base64.decode("Zh==") == Err(InvalidBase64({ index: 1, problem: NonZeroTrailingBits }))
expect Base64.decode("Zm9=") == Err(InvalidBase64({ index: 2, problem: NonZeroTrailingBits }))
expect Base64.decode_with("Zh==", { ..Base64.default_decode, trailing_bits: Allow }) == Ok("f".to_utf8())
expect Base64.decode_with("Zm9=", { ..Base64.default_decode, trailing_bits: Allow }) == Ok("fo".to_utf8())

# The tests below guard the SIMD paths, which handle 12 input bytes (encoding)
# or 16 characters (decoding) at a time, by comparing them with a plain
# reference implementation at every length around those chunk sizes

## A byte-at-a-time encoder to compare against; `chars` is the alphabet
reference_encode : List(U8), Str -> List(U8)
reference_encode = |bytes, chars| {
	alphabet = chars.to_utf8()
	at = |n, shift|
		match alphabet.get(n.shr_zf_wrap(shift).bitwise_and(63).to_u64()) {
			Ok(c) => c
			Err(OutOfBounds) => crash "six bits always index the alphabet"
		}
	bytes.chunks_of(3).fold(
		[],
		|out, group|
			match group {
				[a, b, c] => {
					n = a.to_u32().shl_wrap(16).bitwise_or(b.to_u32().shl_wrap(8)).bitwise_or(c.to_u32())
					out.concat([at(n, 18), at(n, 12), at(n, 6), at(n, 0)])
				}
				[a, b] => {
					n = a.to_u32().shl_wrap(16).bitwise_or(b.to_u32().shl_wrap(8))
					out.concat([at(n, 18), at(n, 12), at(n, 6), '='])
				}
				[a] => {
					n = a.to_u32().shl_wrap(16)
					out.concat([at(n, 18), at(n, 12), '=', '='])
				}
				_ => out
			},
	)
}

## The error for an `=` at `position` in the middle of a long input: after 2 or
## 3 characters of a group it is padding, so the next character is the problem
padding_error : U64 -> Base64.DecodeErr
padding_error = |position|
	if position % 4 >= 2 {
		InvalidBase64({ index: position + 1, problem: DataAfterPadding })
	} else {
		InvalidBase64({ index: position, problem: UnexpectedPadding })
	}

## `list` with the item at `index` replaced
replace_at : List(U8), U64, U8 -> List(U8)
replace_at = |list, index, item| list.take_first(index).append(item).concat(list.drop_first(index + 1))

standard_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

url_safe_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

## `len` bytes that differ between positions and between calls with
## different `seed`s, covering every byte value
pattern : U64, U64 -> List(U8)
pattern = |len, seed| List.from_iter((0.U64).until(len)).map(|i| (i * 167 + seed * 31 + i / 7).to_u8_wrap())

lengths : List(U64)
lengths = List.from_iter((0.U64).until(100)).concat([127, 128, 129, 191, 192, 193, 255, 256, 257, 1000, 1023, 1024, 1025])

# Encoding matches the reference at every length, for both alphabets
expect lengths.all(
	|len|
		[0, 1, 2].all(
			|seed| {
				bytes = pattern(len, seed)
				Base64.encode_to_bytes_with(bytes, Base64.default_encode) == reference_encode(bytes, standard_alphabet)
					and Base64.encode_to_bytes_with(bytes, { ..Base64.default_encode, alphabet: UrlSafe }) == reference_encode(bytes, url_safe_alphabet)
			},
		),
)

# Decoding the reference output gives back the bytes at every length
expect lengths.all(
	|len|
		[0, 1, 2].all(
			|seed| {
				bytes = pattern(len, seed)
				Base64.decode_bytes_with(reference_encode(bytes, standard_alphabet), Base64.default_decode) == Ok(bytes)
					and Base64.decode_bytes_with(reference_encode(bytes, url_safe_alphabet), { ..Base64.default_decode, alphabet: UrlSafe }) == Ok(bytes)
			},
		),
)

# Every character of both alphabets decodes in every lane of a chunk
expect {
	text = standard_alphabet.to_utf8().concat(standard_alphabet.to_utf8().drop_first(3))
	Base64.decode_bytes_with(text.take_first(124), Base64.default_decode).map_ok(|bytes| reference_encode(bytes, standard_alphabet)) == Ok(text.take_first(124))
}
expect {
	text = url_safe_alphabet.to_utf8().concat(url_safe_alphabet.to_utf8().drop_first(3))
	options = { ..Base64.default_decode, alphabet: UrlSafe }
	Base64.decode_bytes_with(text.take_first(124), options).map_ok(|bytes| reference_encode(bytes, url_safe_alphabet)) == Ok(text.take_first(124))
}

# Any byte outside the alphabet, at any position of a long input, is reported
# where it is, by both alphabets
expect {
	valid = reference_encode(pattern(96, 5), standard_alphabet)
	List.from_iter((0.U64).until(valid.len())).all(
		|position|
			[0, '\n', ' ', '!', '-', '_', '.', '@', '[', '`', '{', 0x7F, 0x80, 0xFF].all(
				|bad| {
					text = replace_at(valid, position, bad)
					Base64.decode_bytes_with(text, Base64.default_decode) == Err(InvalidBase64({ index: position, problem: InvalidByte(bad) }))
				},
			),
	)
}
expect {
	valid = reference_encode(pattern(96, 6), url_safe_alphabet)
	options = { ..Base64.default_decode, alphabet: UrlSafe }
	List.from_iter((0.U64).until(valid.len())).all(
		|position|
			['+', '/', ' ', 0x80].all(
				|bad| Base64.decode_bytes_with(replace_at(valid, position, bad), options) == Err(InvalidBase64({ index: position, problem: InvalidByte(bad) })),
			)
				and (position + 1 == valid.len() or Base64.decode_bytes_with(replace_at(valid, position, '='), options) == Err(padding_error(position))),
	)
}

# Every byte value is classified correctly in every lane of a SIMD chunk, for
# both alphabets
classified_in_every_lane : Str, Base64.DecodeOptions -> Bool
classified_in_every_lane = |chars, options| {
	valid = reference_encode(pattern(48, 7), chars)
	List.from_iter((0.U64).until(256)).all(
		|n| {
			byte = n.to_u8_wrap()
			in_alphabet = chars.to_utf8().contains(byte)
			List.from_iter((16.U64).until(32)).all(
				|position| {
					result = Base64.decode_bytes_with(replace_at(valid, position, byte), options)
					if in_alphabet {
						result.is_ok()
					} else if byte == '=' {
						result == Err(padding_error(position))
					} else {
						result == Err(InvalidBase64({ index: position, problem: InvalidByte(byte) }))
					}
				},
			)
		},
	)
}

expect classified_in_every_lane(standard_alphabet, Base64.default_decode)
expect classified_in_every_lane(url_safe_alphabet, { ..Base64.default_decode, alphabet: UrlSafe })

# Whitespace and padding late in long inputs still decode
expect {
	bytes = pattern(200, 8)
	text = reference_encode(bytes, standard_alphabet)
	wrapped = text.take_first(100).append('\n').concat(text.drop_first(100))
	Base64.decode_bytes_with(wrapped, { ..Base64.default_decode, whitespace: Ignore }) == Ok(bytes)
}
expect {
	bytes = pattern(199, 9)
	Base64.decode_bytes_with(reference_encode(bytes, standard_alphabet), Base64.default_decode) == Ok(bytes)
}

# Wrapped input goes back to SIMD after each line break: every line width and
# both newlines decode, for both alphabets
expect {
	bytes = pattern(500, 10)
	widths = List.from_iter((1.U64).until(40)).concat([63, 64, 65, 76, 100])
	widths.all(
		|width|
			[Lf, CrLf].all(
				|newline|
					[Standard, UrlSafe].all(
						|alphabet| {
							text = Base64.encode_to_bytes_with(bytes, { alphabet, padding: Padded, wrap: Wrap({ width, newline }) })
							options = { ..Base64.default_decode, alphabet, whitespace: Ignore }
							Base64.decode_bytes_with(text, options) == Ok(bytes)
						},
					),
			),
	)
}

# Errors after a line break are still reported where they are
expect {
	text = Base64.encode_to_bytes_with(pattern(150, 11), { ..Base64.default_encode, wrap: Wrap({ width: 76, newline: CrLf }) })
	options = { ..Base64.default_decode, whitespace: Ignore }
	List.from_iter((0.U64).until(text.len())).all(
		|position| {
			original = match text.get(position) {
				Ok(c) => c
				Err(OutOfBounds) => crash "position is within the text"
			}
			result = Base64.decode_bytes_with(replace_at(text, position, '!'), options)
			# Replacing a line break with '!' is an error at the same place too
			original == '=' or result == Err(InvalidBase64({ index: position, problem: InvalidByte('!') }))
		},
	)
}

# Whitespace anywhere in a long input is skipped
expect {
	bytes = pattern(120, 12)
	text = reference_encode(bytes, standard_alphabet)
	options = { ..Base64.default_decode, whitespace: Ignore }
	List.from_iter((0.U64).until(text.len() + 1)).all(
		|position| {
			spaced = text.take_first(position).append(' ').concat(text.drop_first(position))
			Base64.decode_bytes_with(spaced, options) == Ok(bytes)
		},
	)
}

# Non-canonical trailing bits right after SIMD chunks
expect {
	text = reference_encode(pattern(49, 13), standard_alphabet)
	# 49 bytes end in "xx==" after 64 characters; set the unused bits
	last = match text.get(65) {
		Ok(c) => c
		Err(OutOfBounds) => crash "the text has 68 characters"
	}
	bumped = if (last == 'A') 'B' else if (last == 'Q') 'R' else if (last == 'g') 'h' else 'x'
	result = Base64.decode_bytes_with(replace_at(text, 65, bumped), Base64.default_decode)
	result == Err(InvalidBase64({ index: 65, problem: NonZeroTrailingBits }))
}
