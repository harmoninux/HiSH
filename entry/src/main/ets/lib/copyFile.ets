import { fileIo as fs } from '@kit.CoreFileKit'

async function copyFile(srcPathOrUri: string, destPathOrUri: string) {

  const srcFile = await fs.open(srcPathOrUri, fs.OpenMode.READ_ONLY);
  const destFile = await fs.open(destPathOrUri, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);

  await fs.copyFile(srcFile.fd, destFile.fd)

  await fs.close(srcFile.fd);
  await fs.close(destFile.fd);
}

export default copyFile