/** Web preview accepts HTTP(S) only, without exposing a native JS bridge. */
export function normalizeWebPreviewUrl(input: string): string | undefined {
  const value = input.trim()
  if (!value || /[\s\\\u0000-\u001f]/.test(value)) {
    return undefined
  }
  let address = value
  if (!/^https?:\/\//i.test(address)) {
    // A host:port is not a URL scheme. Reject file:, javascript:, etc.
    if (/^[a-z][a-z0-9+.-]*:/i.test(address) && !/^[^/:]+:\d+(?:[/?#]|$)/.test(address)) {
      return undefined
    }
    address = 'http://' + address
  }
  const match = /^(https?):\/\/([^/?#]+)(.*)$/i.exec(address)
  if (!match || match[2].includes('@')) {
    return undefined
  }
  const authority = match[2]
  const host = /^(\[[0-9a-f:]+\]|[a-z0-9.-]+)(?::([0-9]+))?$/i.exec(authority)
  if (!host) {
    return undefined
  }
  if (host[2] !== undefined) {
    const port = Number(host[2])
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      return undefined
    }
  }
  return match[1].toLowerCase() + '://' + authority + match[3]
}
