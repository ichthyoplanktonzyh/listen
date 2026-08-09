//! Strict canonical JSON for Content Package v2 identity documents.
//!
//! The canonical profile is: UTF-8, recursively lexicographically sorted
//! object keys (byte order), compact separators, no BOM, no trailing
//! newline or other whitespace, and integer-only numbers. Identity
//! documents (release.json, delivery.json, and resource/rendition
//! descriptors) are parsed with `parse_canonical`, which rejects any
//! deviation from this profile. Payload blobs are *not* canonical JSON;
//! they are raw-byte hashed and may use resource-specific numeric types.

use serde_json::Value;
use thiserror::Error;

#[derive(Debug, Error, PartialEq, Eq)]
pub(crate) enum CanonicalError {
    #[error("non-canonical JSON at byte {0}: {1}")]
    NotCanonical(usize, &'static str),
    #[error("identity numbers must be integers: {0}")]
    NonIntegerNumber(String),
}

/// Parses `bytes` as canonical JSON, rejecting any deviation from the
/// canonical profile: whitespace, unsorted or duplicate object keys,
/// non-integer numbers, and invalid UTF-8.
pub(crate) fn parse_canonical(bytes: &[u8]) -> Result<Value, CanonicalError> {
    let mut parser = Parser { bytes, pos: 0 };
    let value = parser.parse_value()?;
    if parser.pos != bytes.len() {
        return Err(CanonicalError::NotCanonical(
            parser.pos,
            "trailing data after document",
        ));
    }
    Ok(value)
}

struct Parser<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> Parser<'a> {
    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.pos).copied()
    }

    fn next(&mut self) -> Result<u8, CanonicalError> {
        let byte = self
            .bytes
            .get(self.pos)
            .copied()
            .ok_or(CanonicalError::NotCanonical(
                self.pos,
                "unexpected end of input",
            ))?;
        self.pos += 1;
        Ok(byte)
    }

    fn parse_value(&mut self) -> Result<Value, CanonicalError> {
        match self.peek() {
            Some(b'{') => self.parse_object(),
            Some(b'[') => self.parse_array(),
            Some(b'"') => Ok(Value::String(self.parse_string()?)),
            Some(b't') => self.parse_literal("true", Value::Bool(true)),
            Some(b'f') => self.parse_literal("false", Value::Bool(false)),
            Some(b'n') => self.parse_literal("null", Value::Null),
            Some(b'-') | Some(b'0'..=b'9') => self.parse_number(),
            Some(byte) => Err(CanonicalError::NotCanonical(
                self.pos,
                match byte {
                    b' ' | b'\t' | b'\r' | b'\n' => "whitespace is not permitted",
                    _ => "unexpected character",
                },
            )),
            None => Err(CanonicalError::NotCanonical(
                self.pos,
                "unexpected end of input",
            )),
        }
    }

    fn parse_literal(&mut self, literal: &str, value: Value) -> Result<Value, CanonicalError> {
        for expected in literal.bytes() {
            if self.next()? != expected {
                return Err(CanonicalError::NotCanonical(
                    self.pos.saturating_sub(1),
                    "invalid literal",
                ));
            }
        }
        Ok(value)
    }

    fn parse_number(&mut self) -> Result<Value, CanonicalError> {
        let start = self.pos;
        if self.peek() == Some(b'-') {
            self.next()?;
        }
        match self.peek() {
            Some(b'0') => {
                self.next()?;
                if matches!(self.peek(), Some(b'0'..=b'9')) {
                    return Err(CanonicalError::NotCanonical(
                        self.pos,
                        "leading zeros are not permitted",
                    ));
                }
            }
            Some(b'1'..=b'9') => {
                while matches!(self.peek(), Some(b'0'..=b'9')) {
                    self.next()?;
                }
            }
            _ => return Err(CanonicalError::NotCanonical(self.pos, "invalid number")),
        }
        if matches!(self.peek(), Some(b'.' | b'e' | b'E')) {
            return Err(CanonicalError::NotCanonical(
                self.pos,
                "identity numbers must be integers",
            ));
        }
        let token = std::str::from_utf8(&self.bytes[start..self.pos])
            .map_err(|_| CanonicalError::NotCanonical(start, "invalid UTF-8 in number"))?;
        if token == "-0" {
            return Err(CanonicalError::NotCanonical(
                start,
                "negative zero is not permitted",
            ));
        }
        if let Ok(value) = token.parse::<i64>() {
            Ok(Value::Number(value.into()))
        } else if let Ok(value) = token.parse::<u64>() {
            Ok(Value::Number(value.into()))
        } else {
            Err(CanonicalError::NonIntegerNumber(token.to_owned()))
        }
    }

    fn parse_string(&mut self) -> Result<String, CanonicalError> {
        debug_assert_eq!(self.peek(), Some(b'"'));
        self.next()?;
        let mut output = Vec::new();
        loop {
            let byte = match self.peek() {
                Some(b'"') => {
                    self.next()?;
                    break;
                }
                Some(byte) => byte,
                None => {
                    return Err(CanonicalError::NotCanonical(
                        self.pos,
                        "unterminated string",
                    ));
                }
            };
            if byte == b'\\' {
                self.next()?;
                let escape = self.next()?;
                match escape {
                    b'"' => output.push(b'"'),
                    b'\\' => output.push(b'\\'),
                    b'/' => output.push(b'/'),
                    b'b' => output.push(0x08),
                    b'f' => output.push(0x0C),
                    b'n' => output.push(b'\n'),
                    b'r' => output.push(b'\r'),
                    b't' => output.push(b'\t'),
                    b'u' => {
                        let code = self.parse_hex_quad()?;
                        let scalar = decode_surrogate(code, self)?;
                        push_scalar(&mut output, scalar);
                    }
                    _ => {
                        return Err(CanonicalError::NotCanonical(
                            self.pos.saturating_sub(1),
                            "invalid escape",
                        ));
                    }
                }
            } else if byte < 0x20 {
                return Err(CanonicalError::NotCanonical(
                    self.pos,
                    "raw control character in string",
                ));
            } else {
                output.push(byte);
                self.pos += 1;
            }
        }
        String::from_utf8(output)
            .map_err(|_| CanonicalError::NotCanonical(self.pos, "invalid UTF-8 in string"))
    }

    fn parse_hex_quad(&mut self) -> Result<u32, CanonicalError> {
        let mut value = 0_u32;
        for _ in 0..4 {
            let byte = self.next()?;
            let digit = match byte {
                b'0'..=b'9' => (byte - b'0') as u32,
                b'a'..=b'f' => (byte - b'a' + 10) as u32,
                _ => {
                    return Err(CanonicalError::NotCanonical(
                        self.pos.saturating_sub(1),
                        "invalid hex digit in \\u escape",
                    ));
                }
            };
            value = value * 16 + digit;
        }
        Ok(value)
    }

    fn parse_object(&mut self) -> Result<Value, CanonicalError> {
        debug_assert_eq!(self.peek(), Some(b'{'));
        self.next()?;
        let mut map = serde_json::Map::new();
        if self.peek() == Some(b'}') {
            self.next()?;
            return Ok(Value::Object(map));
        }
        let mut previous_key: Option<Vec<u8>> = None;
        loop {
            if self.peek() != Some(b'"') {
                return Err(CanonicalError::NotCanonical(
                    self.pos,
                    "object keys must be strings",
                ));
            }
            let key = self.parse_string()?;
            let key_bytes = key.as_bytes();
            if let Some(previous) = &previous_key
                && key_bytes <= previous.as_slice()
            {
                return Err(CanonicalError::NotCanonical(
                    self.pos,
                    "object keys must be sorted and unique",
                ));
            }
            previous_key = Some(key_bytes.to_vec());
            if self.next()? != b':' {
                return Err(CanonicalError::NotCanonical(
                    self.pos.saturating_sub(1),
                    "expected ':' after object key",
                ));
            }
            let value = self.parse_value()?;
            map.insert(key, value);
            match self.next()? {
                b',' => continue,
                b'}' => return Ok(Value::Object(map)),
                _ => {
                    return Err(CanonicalError::NotCanonical(
                        self.pos.saturating_sub(1),
                        "expected ',' or '}' in object",
                    ));
                }
            }
        }
    }

    fn parse_array(&mut self) -> Result<Value, CanonicalError> {
        debug_assert_eq!(self.peek(), Some(b'['));
        self.next()?;
        let mut values = Vec::new();
        if self.peek() == Some(b']') {
            self.next()?;
            return Ok(Value::Array(values));
        }
        loop {
            values.push(self.parse_value()?);
            match self.next()? {
                b',' => continue,
                b']' => return Ok(Value::Array(values)),
                _ => {
                    return Err(CanonicalError::NotCanonical(
                        self.pos.saturating_sub(1),
                        "expected ',' or ']' in array",
                    ));
                }
            }
        }
    }
}

fn decode_surrogate(code: u32, parser: &mut Parser<'_>) -> Result<u32, CanonicalError> {
    if (0xD800..=0xDBFF).contains(&code) {
        // High surrogate: a low surrogate must follow.
        if parser.bytes.get(parser.pos) != Some(&b'\\')
            || parser.bytes.get(parser.pos + 1) != Some(&b'u')
        {
            return Err(CanonicalError::NotCanonical(
                parser.pos,
                "unpaired high surrogate",
            ));
        }
        parser.next()?;
        parser.next()?;
        let low = parser.parse_hex_quad()?;
        if !(0xDC00..=0xDFFF).contains(&low) {
            return Err(CanonicalError::NotCanonical(
                parser.pos,
                "unpaired high surrogate",
            ));
        }
        Ok(0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00))
    } else if (0xDC00..=0xDFFF).contains(&code) {
        Err(CanonicalError::NotCanonical(
            parser.pos,
            "unpaired low surrogate",
        ))
    } else {
        Ok(code)
    }
}

fn push_scalar(output: &mut Vec<u8>, scalar: u32) {
    match char::from_u32(scalar) {
        Some(character) => {
            let mut buffer = [0_u8; 4];
            output.extend_from_slice(character.encode_utf8(&mut buffer).as_bytes());
        }
        None => output.extend_from_slice("\u{FFFD}".as_bytes()),
    }
}

/// Serializes `value` back into canonical JSON bytes (sorted keys, compact
/// separators, no BOM or trailing whitespace). The input must already be a
/// canonical parse result; numbers are emitted as stored.
pub(crate) fn serialize_canonical(value: &Value) -> Result<Vec<u8>, CanonicalError> {
    let mut output = Vec::new();
    write_value(value, &mut output)?;
    Ok(output)
}

fn write_value(value: &Value, output: &mut Vec<u8>) -> Result<(), CanonicalError> {
    match value {
        Value::Null => output.extend_from_slice(b"null"),
        Value::Bool(true) => output.extend_from_slice(b"true"),
        Value::Bool(false) => output.extend_from_slice(b"false"),
        Value::Number(number) => write_number(number, output)?,
        Value::String(string) => write_string(string, output),
        Value::Array(values) => {
            output.push(b'[');
            for (index, value) in values.iter().enumerate() {
                if index > 0 {
                    output.push(b',');
                }
                write_value(value, output)?;
            }
            output.push(b']');
        }
        Value::Object(map) => {
            output.push(b'{');
            for (index, (key, value)) in map.iter().enumerate() {
                if index > 0 {
                    output.push(b',');
                }
                write_string(key, output);
                output.push(b':');
                write_value(value, output)?;
            }
            output.push(b'}');
        }
    }
    Ok(())
}

fn write_number(number: &serde_json::Number, output: &mut Vec<u8>) -> Result<(), CanonicalError> {
    if number.is_f64() {
        return Err(CanonicalError::NonIntegerNumber(number.to_string()));
    }
    output.extend_from_slice(number.to_string().as_bytes());
    Ok(())
}

fn write_string(string: &str, output: &mut Vec<u8>) {
    output.push(b'"');
    for character in string.chars() {
        match character {
            '"' => output.extend_from_slice(b"\\\""),
            '\\' => output.extend_from_slice(b"\\\\"),
            '\u{08}' => output.extend_from_slice(b"\\b"),
            '\u{0C}' => output.extend_from_slice(b"\\f"),
            '\n' => output.extend_from_slice(b"\\n"),
            '\r' => output.extend_from_slice(b"\\r"),
            '\t' => output.extend_from_slice(b"\\t"),
            character if (character as u32) < 0x20 => {
                output.extend_from_slice(format!("\\u{:04x}", character as u32).as_bytes());
            }
            character => {
                let mut buffer = [0_u8; 4];
                output.extend_from_slice(character.encode_utf8(&mut buffer).as_bytes());
            }
        }
    }
    output.push(b'"');
}

/// Parses `bytes` and verifies the canonical serialization round-trips
/// byte-for-byte. This rejects non-minimal escapes, non-canonical numbers,
/// and any other deviation from the canonical profile.
pub(crate) fn parse_canonical_verified(bytes: &[u8]) -> Result<Value, CanonicalError> {
    let value = parse_canonical(bytes)?;
    let canonical = serialize_canonical(&value)?;
    if canonical != bytes {
        return Err(CanonicalError::NotCanonical(
            0,
            "document does not round-trip to canonical JSON",
        ));
    }
    Ok(value)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_canonical_documents() {
        for bytes in [
            b"{}".as_slice(),
            b"{\"a\":1,\"b\":[true,null,\"x\\u0000\"]}",
            b"{\"a\":-2,\"b\":18446744073709551615}",
            b"[]",
            b"\"plain\"",
        ] {
            assert!(parse_canonical_verified(bytes).is_ok(), "{bytes:?}");
        }
    }

    #[test]
    fn rejects_whitespace_and_bom() {
        for bytes in [
            b" { }".as_slice(),
            b"{\"a\": 1}",
            b"{\"a\":1}\n",
            b"\xEF\xBB\xBF{}",
            b"{\"a\":1} ",
        ] {
            assert!(
                parse_canonical_verified(bytes).is_err(),
                "should reject {bytes:?}"
            );
        }
    }

    #[test]
    fn rejects_unsorted_or_duplicate_keys() {
        assert!(parse_canonical_verified(b"{\"b\":1,\"a\":2}").is_err());
        assert!(parse_canonical_verified(b"{\"a\":1,\"a\":2}").is_err());
        assert!(parse_canonical_verified(b"{\"a\":1,\"ab\":2,\"b\":3}").is_ok());
    }

    #[test]
    fn rejects_non_integer_numbers() {
        for bytes in [
            b"{\"a\":1.5}".as_slice(),
            b"{\"a\":1e3}",
            b"{\"a\":1E3}",
            b"{\"a\":01}",
            b"{\"a\":-0}",
        ] {
            assert!(
                parse_canonical_verified(bytes).is_err(),
                "should reject {bytes:?}"
            );
        }
    }

    #[test]
    fn rejects_non_minimal_escapes() {
        assert!(parse_canonical_verified(b"{\"a\":\"\\u0061\"}").is_err());
        assert!(parse_canonical_verified(b"{\"a\":\"a\"}").is_ok());
    }

    #[test]
    fn canonical_serialization_sorts_keys() {
        let value: serde_json::Value = serde_json::from_str(r#"{"b":1,"a":2}"#).unwrap();
        assert_eq!(serialize_canonical(&value).unwrap(), b"{\"a\":2,\"b\":1}");
    }
}
