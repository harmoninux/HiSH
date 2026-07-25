import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0000

async function deleteDirectoryRecursive(dirPath: string) {
  try {
    const dirEntries = await fs.listFile(dirPath, { recursion: false });
    for (const entry of dirEntries) {
      const fullPath = `${dirPath}/${entry}`;
      const stat = await fs.stat(fullPath);

      if (stat.isDirectory()) {
        await deleteDirectoryRecursive(fullPath);
      } else {
        await fs.unlink(fullPath);
      }
    }
    await fs.rmdir(dirPath);
  } catch (err) {
    hilog.error(DOMAIN, 'deleteDirectoryRecursive', '删除目录失败: %{public}s, 错误: %{public}s',
      dirPath, JSON.stringify(err));
  }
}

export default deleteDirectoryRecursive