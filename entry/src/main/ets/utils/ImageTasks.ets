import { taskpool } from '@kit.ArkTS';
import napi from 'libentry.so';

@Concurrent
export async function getSnapshotsTask(path: string): Promise<string> {
  return napi.getSnapshots(path);
}

@Concurrent
export async function createSnapshotTask(path: string, name: string): Promise<string> {
  return napi.createSnapshot(path, name);
}

@Concurrent
export async function applySnapshotTask(path: string, name: string): Promise<string> {
  return napi.applySnapshot(path, name);
}

@Concurrent
export async function deleteSnapshotTask(path: string, name: string): Promise<string> {
  return napi.deleteSnapshot(path, name);
}

@Concurrent
export async function optimizeImageTask(path: string, tempPath: string, mode: 'sparse' | 'prealloc' | 'cleanup' | 'optimize'): Promise<string> {
  return napi.optimizeImage(path, tempPath, mode);
}

@Concurrent
export async function getImageInfoTask(path: string): Promise<string> {
  return napi.getImageInfo(path);
}

@Concurrent
export async function needRestartTask(): Promise<boolean> {
  return napi.needRestart();
}

// ================== 数据盘管理功能 ==================

/**
 * 执行 qemu-img 命令（用于创建数据盘等操作）
 * @param args 命令参数数组（不包含 "qemu-img" 本身）
 * @returns JSON 格式的结果 {success: true} 或 {error: string}
 */
@Concurrent
export async function executeQemuImgTask(args: string[]): Promise<string> {
  return napi.executeQemuImg(args);
}
