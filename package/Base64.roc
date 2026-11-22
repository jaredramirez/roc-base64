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

	## A decoding failure. `index` counts bytes from the start of the input;
	## problems found at the end of the input report its length.
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
		var $out = List.with_capacity(encoded_len(bytes.len(), options))
		var $acc = 0.U32
		var $count = 0.U8
		for byte in bytes {
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
		var $out = List.with_capacity(chars.len() / 4 * 3 + 2)
		var $acc = 0.U32
		var $data = 0.U64
		var $pads = 0.U64
		var $last_data = 0.U64
		var $index = 0.U64
		table = match options.alphabet {
			Standard => standard_values
			UrlSafe => url_safe_values
		}
		ignore_whitespace = match options.whitespace {
			Ignore => True
			Reject => False
		}
		var $failure = None
		for c in chars {
			value = match table.get(c.to_u64()) {
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
	## and newlines.
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

	## `chars` broken into lines of `width` characters, without a newline after
	## the last line
	wrap_lines : List(U8), U64, [Lf, CrLf] -> List(U8)
	wrap_lines = |chars, width, newline| {
		line_count = (chars.len() + width - 1) / width
		var $out = List.with_capacity(chars.len() + (line_count - 1) * newline_len(newline))
		var $column = 0.U64
		for c in chars {
			if $column == width {
				$out = $out.concat(newline_bytes(newline))
				$column = 0
			}
			$out = $out.append(c)
			$column = $column + 1
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
	char : U32, U8, Alphabet -> U8
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

	values_for : Alphabet -> List(U8)
	values_for = |alphabet|
		List.from_iter((0.U64).until(256)).map(
			|c| match sextet(c.to_u8_wrap(), alphabet) {
				Ok(v) => v.to_u8_wrap()
				Err(NotInAlphabet) => 64
			},
		)

	## The six bits a character stands for
	sextet : U8, Alphabet -> Try(U32, [NotInAlphabet])
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
	padding_fits : DecodePadding, U64, U64 -> Bool
	padding_fits = |padding, leftover, pads|
		match padding {
			Forbidden => False
			Required | Optional => (leftover == 2 and pads < 2) or (leftover == 3 and pads < 1)
		}

	is_whitespace : U8 -> Bool
	is_whitespace = |c| c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0B or c == 0x0C
}

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
