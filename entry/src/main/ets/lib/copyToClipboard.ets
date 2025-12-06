import { pasteboard } from "@kit.BasicServicesKit";
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0000

export default async function copyToClipboard(content: pasteboard.ValueType,
  uiContext?: UIContext) {
  try {
    const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, content)
    const systemPasteboard = pasteboard.getSystemPasteboard();
    await systemPasteboard.setData(pasteboardData);
    uiContext?.getPromptAction().showToast({
      message: '已复制到剪贴板',
      duration: 2000
    })
  } catch (e) {
    hilog.error(DOMAIN, 'copyToClipboard', '复制到剪贴板失败: %{public}s', JSON.stringify(e))
  }
}