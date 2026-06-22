import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0000

async function deleteDirectoryRecursive(dirPath: string): Promise<void> {
  const failedItems: string[] = []

  const dirEntries = await fs.listFile(dirPath, { recursion: false });
  for (const entry of dirEntries) {
    const fullPath = `${dirPath}/${entry}`;
    try {
      const stat = await fs.stat(fullPath);

      if (stat.isDirectory()) {
        await deleteDirectoryRecursive(fullPath);
      } else {
        await fs.unlink(fullPath);
      }
    } catch (e) {
      // 记录失败项但不中断循环，确保尽可能多地删除文件
      hilog.error(DOMAIN, 'deleteDirectoryRecursive', '删除子项失败: %{public}s, 错误: %{public}s',
        fullPath, JSON.stringify(e));
      failedItems.push(fullPath)
    }
  }

  if (failedItems.length > 0) {
    // 有子项删除失败时，rmdir 大概率也会失败（目录非空），但仍尝试清理
    hilog.warn(DOMAIN, 'deleteDirectoryRecursive', '部分删除失败 (%{public}d 项): %{public}s',
      failedItems.length, dirPath)
  }

  try {
    await fs.rmdir(dirPath);
  } catch (e) {
    // 如果目录非空（有删除失败的子项残留），向调用方抛出明确错误
    hilog.error(DOMAIN, 'deleteDirectoryRecursive', '删除目录失败: %{public}s, 错误: %{public}s',
      dirPath, JSON.stringify(e));
    throw new Error(`Failed to delete directory: ${failedItems.length} items could not be removed`)
  }
}

export default deleteDirectoryRecursive