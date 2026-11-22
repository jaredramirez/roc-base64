app [target] {
	base64: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.7.0/HBigHQhVZWEF2EkLxpYK35u8P6UNsAmPYxpNFTxXK1Br.tar.zst",
}

import fuzz.Fuzz
import base64.Base64

## Raw fuzz input; `choice` picks the options, so any value is meaningful
Input : { data : List(U8), choice : U8 }

## Encoding and decoding options picked by `choice`, with matching settings
options_for : U8 -> (Base64.EncodeOptions, Base64.DecodeOptions)
options_for = |choice| {
	alphabet = if (choice.bitwise_and(1) == 0) Standard else UrlSafe
	(encode_padding, decode_padding) = match choice.shr_zf_wrap(1) % 4 {
		0 => (Padded, Required)
		1 => (Padded, Optional)
		2 => (Unpadded, Forbidden)
		_ => (Unpadded, Optional)
	}
	width = choice.shr_zf_wrap(3).to_u64()
	(wrap, whitespace) = if (width == 0) (NoWrap, Reject) else (Wrap({ width, newline: if (width % 2 == 0) Lf else CrLf }), Ignore)
	(
		{ alphabet, padding: encode_padding, wrap },
		{ alphabet, padding: decode_padding, whitespace, trailing_bits: Reject },
	)
}

## Encoding round trips and has the predicted length, strict decoding of
## arbitrary bytes either fails or accepts only the canonical encoding, and
## decoding arbitrary bytes with any options reports errors where they are
test! : Input => Fuzz.Outcome
test! = |{ data, choice }| {
	(encode_options, decode_options) = options_for(choice)
	encoded = Base64.encode_to_bytes_with(data, encode_options)
	if encoded.len() != Base64.encoded_len(data.len(), encode_options) {
		crash "encoded_len was wrong"
	}
	if Base64.decode_bytes_with(encoded, decode_options) != Ok(data) {
		crash "round trip failed"
	}

	strict = { ..decode_options, padding: Required, whitespace: Reject }
	canonical = { ..encode_options, padding: Padded, wrap: NoWrap }
	match Base64.decode_bytes_with(data, strict) {
		Ok(decoded) if Base64.encode_to_bytes_with(decoded, canonical) == data => {}
		Ok(_) => crash "strict decoding accepted a non-canonical encoding"
		Err(InvalidBase64({ index, problem: _ })) if index <= data.len() => {}
		Err(_) => crash "error index past the end of the input"
	}

	# Any options, on arbitrary bytes: errors point at the offending byte, and
	# whatever decodes re-encodes to something strict decoding accepts
	lenient = {
		alphabet: decode_options.alphabet,
		padding: if (choice.bitwise_and(0x40) == 0) Optional else decode_options.padding,
		whitespace: if (choice.bitwise_and(0x80) == 0) Ignore else Reject,
		trailing_bits: if (choice.bitwise_and(0x20) == 0) Allow else Reject,
	}
	match Base64.decode_bytes_with(data, lenient) {
		Ok(decoded) => {
			again = Base64.encode_to_bytes_with(decoded, canonical)
			if Base64.decode_bytes_with(again, strict) != Ok(decoded) {
				crash "a lenient decode did not survive a canonical round trip"
			}
		}
		Err(InvalidBase64({ index, problem: InvalidByte(byte) })) if data.get(index) == Ok(byte) => {}
		Err(InvalidBase64({ problem: InvalidByte(_), .. })) => crash "InvalidByte points at the wrong byte"
		Err(InvalidBase64({ index, problem: _ })) if index <= data.len() => {}
		Err(_) => crash "error index past the end of the input"
	}
	Fuzz.keep
}

target = Fuzz.target_with!({
	examples: [
		Fuzz.example({ name: "empty", revision: "1", make: || { data: [], choice: 0 } }),
		Fuzz.example({ name: "rfc", revision: "1", make: || { data: "Zm9vYg==".to_utf8(), choice: 0 } }),
		Fuzz.example({ name: "wrapped-url", revision: "1", make: || { data: [251, 255, 254, 0, 1], choice: 0x2B } }),
	],
	name: "base64",
	generator: Fuzz.map2(Fuzz.bytes, Fuzz.u8, |data, choice| { data, choice }),
	test!,
	show: |input| Str.inspect(input),
})
