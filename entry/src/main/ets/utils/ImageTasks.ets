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
  return false
}
