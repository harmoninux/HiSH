function toHex(value: number) {
  let hex = value.toString(16);
  if ((hex.length % 2) > 0) {
    hex = "0" + hex;
  }
  return hex;
}

function charCodeEscape(v: number) {
  if (v >= 127 || v < 32) {
    return '\\x' + toHex(v)
  } else {
    const c = String.fromCharCode(v)
    if (c === '\'' || c === '\"' || c === '\\') {
      return '\\' + c;
    } else {
      return c
    }
  }
}

function codeEscape(ab: ArrayBuffer) {
  const ua: Uint8Array = new Uint8Array(ab);
  const ha: string[] = [];
  ua.forEach(v => {
    const c = charCodeEscape(v);
    ha.push(c);
  });
  const hex = ha.join('');
  return hex;
}

export default codeEscape