import fs from '@ohos.file.fs';

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
    console.error(`failed to remove directory: ${JSON.stringify(err)}`);
  }
}

export default deleteDirectoryRecursive