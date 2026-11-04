export const DEFAULT_PAGE_SIZE = 20;
export const MAX_PAGE_SIZE = 100;
export const MAX_PAGE = 1500;

// Validates and parses the HTTP `Range` header (RFC 9110, section 14) for a resource of known size.
//
// Usage:  const range = parseByteRangeHeader(req.headers.range, fileSizeInBytes);
//
// What each result means for the response:
//  full                    -> no usable Range header: send the whole file with `200 OK`
//  partial                 -> send bytes [startByteInclusive, endByteInclusive] with `206 Partial Content`
//  malformed               -> the header is syntactically invalid: answer `400 Bad Request`
//                              (the RFC also allows ignoring it and answering 200 instead)
//  unsatisfiable           -> the range lies outside the file: answer `416 Range Not Satisfiable`
//                              and set the header  Content-Range: bytes */<fileSizeInBytes>
//   start_bytes_mandatory  -> if file size is not provided and last N bytes are requested
export type ByteRangeParseResult =
    | { kind: 'full' }
    | { kind: 'partial'; startByteInclusive: number; endByteInclusive: number }
    | { kind: 'malformed' }
    | { kind: 'unsatisfiable' }
    | { kind: 'start_bytes_mandatory' };

// "bytes=<first>-<last>", "bytes=<first>-" or "bytes=-<suffixLength>". The unit is case-insensitive.
const SINGLE_BYTE_RANGE_PATTERN = /^bytes=(\d*)-(\d*)$/i;

/** Digits that don't fit a safe integer are clamped, so they still compare correctly against the file size. */
function parseDigitsClampedToSafeInteger(digits: string): number {
    const parsedNumber = Number(digits);
    return Number.isSafeInteger(parsedNumber) ? parsedNumber : Number.MAX_SAFE_INTEGER;
}

export function parseByteRangeHeader(rangeHeader: string | undefined, fileSizeInBytes?: number): ByteRangeParseResult {
    if (rangeHeader === undefined) return { kind: 'full' };

    const trimmedHeader = rangeHeader.trim();

    // A range unit we don't understand must be ignored (RFC 9110).
    if (!/^bytes\s*=/i.test(trimmedHeader)) return { kind: 'full' };

    // Several ranges ("bytes=0-10,20-30") are ignored too: browsers' audio/video players send a single range,
    // and ignoring the rest avoids having to build multipart responses (or being hit with overlapping-range abuse).
    if (trimmedHeader.includes(',')) return { kind: 'full' };

    const match = SINGLE_BYTE_RANGE_PATTERN.exec(trimmedHeader);
    if (match === null) return { kind: 'malformed' };

    const [, firstByteDigits, lastByteDigits] = match;
    const hasFirstByte = firstByteDigits !== '';
    const hasLastByte = lastByteDigits !== '';

    // "bytes=-" has neither a start nor a suffix length.
    if (!hasFirstByte && !hasLastByte) return { kind: 'malformed' };

    // Suffix range, "bytes=-500": the LAST 500 bytes of the file.
    if (!hasFirstByte) {
        if (fileSizeInBytes === undefined) return { kind: 'start_bytes_mandatory' }

        const suffixLengthInBytes = parseDigitsClampedToSafeInteger(lastByteDigits);
        if (suffixLengthInBytes === 0 || fileSizeInBytes === 0) return { kind: 'unsatisfiable' };

        return {
            kind: 'partial',
            startByteInclusive: Math.max(0, fileSizeInBytes - suffixLengthInBytes),
            endByteInclusive: fileSizeInBytes - 1,
        };
    }

    const startByteInclusive = parseDigitsClampedToSafeInteger(firstByteDigits);
    const requestedEndByteInclusive = hasLastByte ? parseDigitsClampedToSafeInteger(lastByteDigits) : Number.MAX_SAFE_INTEGER;

    // An end before the start is invalid syntax, whatever the file size is.
    if (hasLastByte && requestedEndByteInclusive < startByteInclusive) return { kind: 'malformed' };

    // Starting at or after the end of the file (this also covers an empty file).
    if (fileSizeInBytes !== undefined && startByteInclusive >= fileSizeInBytes) return { kind: 'unsatisfiable' };

    return {
        kind: 'partial',
        startByteInclusive,
        // "bytes=0-" means "to the end", and an end past the end of the file is clamped to it.
        endByteInclusive: fileSizeInBytes !== undefined ? Math.min(requestedEndByteInclusive, fileSizeInBytes - 1) : requestedEndByteInclusive,
    };
}
