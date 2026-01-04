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
    throw new Error(`Copy file failed: ${srcPathOrUri} -> ${destPathOrUri}`)
  } finally {
    if (srcFile) {
      try { await fs.close(srcFile.fd) } catch (closeErr) { /* 忽略关闭错误 */ }
    }
    if (destFile) {
      try { await fs.close(destFile.fd) } catch (closeErr) { /* 忽略关闭错误 */ }
    }
  }
}

/**
 * 带进度回调的文件复制
 * @param srcPath 源文件路径
 * @param destPath 目标文件路径
 * @param onProgress 进度回调 (0-100)
 * @param chunkSize 分块大小，默认 4MB
 */
export async function copyFileWithProgress(
  srcPath: string, 
  destPath: string, 
  onProgress?: (progress: number) => void,
  chunkSize: number = 4 * 1024 * 1024
): Promise<void> {
  let srcFile: fs.File | null = null
  let destFile: fs.File | null = null
  
  try {
    srcFile = await fs.open(srcPath, fs.OpenMode.READ_ONLY)
    destFile = await fs.open(destPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE)
    
    // 获取源文件大小
    const srcStat = await fs.stat(srcPath)
    const totalSize = srcStat.size
    let copiedSize = 0
    
    const buffer = new ArrayBuffer(chunkSize)
    
    while (copiedSize < totalSize) {
      // fs.read 会自动从文件当前位置读取，无需指定 offset
      const readSize = await fs.read(srcFile.fd, buffer)
      if (readSize <= 0) break
      
      // 写入目标文件 - fs.write 同样从当前位置写入
      const writeBuffer = readSize < chunkSize ? buffer.slice(0, readSize) : buffer
      await fs.write(destFile.fd, writeBuffer)
      
      copiedSize += readSize
      
      // 回调进度
      if (onProgress) {
        const progress = Math.min(100, Math.round((copiedSize / totalSize) * 100))
        onProgress(progress)
      }
    }
    
    if (onProgress) {
      onProgress(100)
    }
  } catch (e) {
    hilog.error(DOMAIN, 'copyFileWithProgress', '复制文件失败: %{public}s -> %{public}s, 错误: %{public}s', 
      srcPath, destPath, JSON.stringify(e))
    throw new Error(`Copy file failed: ${srcPath} -> ${destPath}`)
  } finally {
    if (srcFile) {
      try { await fs.close(srcFile.fd) } catch (closeErr) { /* 忽略 */ }
    }
    if (destFile) {
      try { await fs.close(destFile.fd) } catch (closeErr) { /* 忽略 */ }
    }
  }
}

export default copyFile