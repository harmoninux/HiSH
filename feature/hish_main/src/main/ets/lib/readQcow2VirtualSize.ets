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

export default readQcow2VirtualSize