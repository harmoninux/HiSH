import { fileIo as fs } from '@kit.CoreFileKit'

function readQcow2VirtualSize(filePath: string): number  {

  try {
    const f = fs.openSync(filePath, fs.OpenMode.READ_ONLY)

    const HEADER_SIZE = 32;
    const buffer = new ArrayBuffer(HEADER_SIZE);

    const bytesRead = fs.readSync(f.fd, buffer, { offset: 0, length: HEADER_SIZE })
    fs.close(f)

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

/**
 * 异步版本：读取 QCOW2 文件的虚拟大小
 * 不阻塞主线程，适用于 UI 组件的 aboutToAppear
 */
export async function readQcow2VirtualSizeAsync(filePath: string): Promise<number> {
  try {
    const f = await fs.open(filePath, fs.OpenMode.READ_ONLY)
    const HEADER_SIZE = 32
    const buffer = new ArrayBuffer(HEADER_SIZE)
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