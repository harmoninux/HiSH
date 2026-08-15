import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0000

/**
 * 根据文件扩展名推断 MIME 类型（用于 data URL）
 */
function mimeOf(path: string): string {
  const lower = path.toLowerCase()
  if (lower.endsWith('.ttf')) {
    return 'font/ttf'
  }
  if (lower.endsWith('.otf')) {
    return 'font/otf'
  }
  if (lower.endsWith('.woff2')) {
    return 'font/woff2'
  }
  if (lower.endsWith('.woff')) {
    return 'font/woff'
  }
  if (lower.endsWith('.png')) {
    return 'image/png'
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp'
  }
  if (lower.endsWith('.gif')) {
    return 'image/gif'
  }
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return 'image/jpeg'
  }
  return 'application/octet-stream'
}

/**
 * 读取文件内容并编码为 data URL 字符串。
 * 文件不存在或读取失败时返回空字符串。
 */
function fileToDataUrl(path: string): string {
  if (path.length === 0 || !fs.accessSync(path, fs.AccessModeType.EXIST)) {
    return ''
  }
  let file: fs.File | undefined = undefined
  try {
    const stat = fs.statSync(path)
    file = fs.openSync(path, fs.OpenMode.READ_ONLY)
    const buf = new ArrayBuffer(stat.size)
    let offset = 0
    while (offset < stat.size) {
      const readLen = fs.readSync(file.fd, buf, { offset: offset, length: stat.size - offset })
      if (readLen <= 0) {
        break
      }
      offset += readLen
    }
    const base64 = new util.Base64Helper().encodeToStringSync(new Uint8Array(buf, 0, offset))
    return `data:${mimeOf(path)};base64,${base64}`
  } catch (e) {
    hilog.error(DOMAIN, 'fileToDataUrl', 'read file failed: %{public}s, %{public}s', path, JSON.stringify(e))
    return ''
  } finally {
    if (file) {
      fs.closeSync(file)
    }
  }
}

export default fileToDataUrl
