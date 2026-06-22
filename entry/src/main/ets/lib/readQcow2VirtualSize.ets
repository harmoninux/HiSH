import { fileIo as fs } from '@kit.CoreFileKit'

async function readQcow2VirtualSize(filePath: string): Promise<number> {
  try {
    const f = await fs.open(filePath, fs.OpenMode.READ_ONLY)

    const HEADER_SIZE = 32;
    const buffer = new ArrayBuffer(HEADER_SIZE);

    const bytesRead = await fs.read(f.fd, buffer, { offset: 0, length: HEADER_SIZE })
    await fs.close(f)

    if (bytesRead < HEADER_SIZE) {
      return 0
    }

    const dataView = new DataView(buffer)
    const size = dataView.getBigInt64(24, false)
    return Number(size)
  } catch (e) {
    return 0
  }
}

export default readQcow2VirtualSize