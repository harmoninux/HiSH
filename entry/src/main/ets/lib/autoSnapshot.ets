import { hilog } from '@kit.PerformanceAnalysisKit'
import napi from 'libentry.so'
import appOption from '../model/appOption'
import { Emulator } from '../model/Emulator'

const DOMAIN = 0x0000

/**
 * 创建自动快照（退出 VM 时调用）
 * 从 AppStorage 读取当前运行的 emulator，生成 auto-<timestamp> 快照
 */
export async function createAutoSnapshot(): Promise<void> {
  const autoSnapshot = AppStorage.get<boolean>(appOption.autoSnapshotOnExit)
  if (!autoSnapshot) return

  const emulatorId = AppStorage.get<string>(appOption.currentRunningEmulator)
  if (!emulatorId) return

  try {
    const emulatorsJson = AppStorage.get<string>(appOption.emulators)
    const emulators = JSON.parse(emulatorsJson ?? '[]') as Emulator[]
    const currentEmulator = emulators.find((e: Emulator) => e.id === emulatorId)
    if (currentEmulator?.rootFilesystem) {
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)
      const snapshotName = `auto-${timestamp}`
      hilog.info(DOMAIN, 'autoSnapshot', 'Creating %{public}s on %{public}s',
        snapshotName, currentEmulator.rootFilesystem)
      napi.createSnapshot(currentEmulator.rootFilesystem, snapshotName)
      hilog.info(DOMAIN, 'autoSnapshot', 'Created: %{public}s', snapshotName)
    }
  } catch (e) {
    hilog.error(DOMAIN, 'autoSnapshot', 'Failed: %{public}s', JSON.stringify(e))
  }
}
