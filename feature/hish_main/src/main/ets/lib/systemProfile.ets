import { fileIo as fs } from '@kit.CoreFileKit'
import { ListFileOptions } from '@kit.CoreFileKit';

const cpuOptions: number[] = [1, 2, 4, 6, 8, 10, 16, 24, 32]
const memOptions: number[] = [512, 1024, 2 * 1024, 4 * 1024, 6 * 1024, 8 * 1024, 12 * 1024, 16 * 1024]

function getCpuCount(): number {
  try {
    let filesDir = "/sys/devices/system/cpu";
    let listFileOption: ListFileOptions = {
      recursion: false,
      listNum: 0,
      filter: {}
    };
    if (listFileOption.filter != undefined) {
      listFileOption.filter.displayName = ['cpu*'];
    }

    let files = fs.listFileSync(filesDir, listFileOption);
    let count = 0;
    for (let i = 0; i < files.length; i++) {
      if (files[i].toString().length > 3 && !isNaN(parseInt(files[i].toString()[3]))) {
        count++;
      }
    }
    return count
  } catch (e) {
    return 4
  }
}

function getMemSize(): number {

  try {
    const info = fs.readLinesSync('/proc/meminfo')
    let item = info.next()
    do {
      if (item.value.indexOf('MemTotal') >= 0) {
        //  parse mem
        const line = item.value.trim().toUpperCase()
        const match = line.match(/MEMTOTAL.*?(\d+)/i)
        if (match) {
          return Math.max(parseInt(match[1]) / 1024, 4 * 1024)
        }
        break
      }
      item = info.next();
    } while (!item.done);
    return 8 * 1024
  } catch (e) {
    return 8 * 1024
  }
}

export {getCpuCount, getMemSize, cpuOptions, memOptions}