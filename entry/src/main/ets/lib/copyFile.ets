import { fileIo as fs } from '@kit.CoreFileKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0000

async function copyFile(srcPathOrUri: string, destPathOrUri: string) {
  let srcFile: fs.File | null = null
  let destFile: fs.File | null = null
  
  try {
    srcFile = await fs.open(srcPathOrUri, fs.OpenMode.READ_ONLY)
    destFile = await fs.open(destPathOrUri, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE)
    await fs.copyFile(srcFile.fd, destFile.fd)
  } catch (e) {
    hilog.error(DOMAIN, 'copyFile', '复制文件失败: %{public}s -> %{public}s, 错误: %{public}s', 
      srcPathOrUri, destPathOrUri, JSON.stringify(e))
    throw new Error(`复制文件失败: ${srcPathOrUri} -> ${destPathOrUri}`)
  } finally {
    if (srcFile) {
      try { await fs.close(srcFile.fd) } catch (closeErr) { /* 忽略关闭错误 */ }
    }
    if (destFile) {
      try { await fs.close(destFile.fd) } catch (closeErr) { /* 忽略关闭错误 */ }
    }
  }
}

export default copyFile