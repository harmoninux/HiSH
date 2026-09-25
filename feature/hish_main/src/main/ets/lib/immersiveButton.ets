// 注意：原有的沉浸光感（uiMaterial.ImmersiveMaterial / systemMaterial / ULTRA_THIN）
// 属于 API 26+ 才能编译的 ArkUI API，而本项目声明的工具链与 SDK 为 HarmonyOS 6.1.1 / API 24，
// 直接 import 与调用会编译失败（api 版本不匹配）。
// 因此这里将材质逻辑改为空实现（无操作），保留导出的修饰器类名，
// 使所有调用点（EmulatorItem / SettingsContent / WebTerminal / Index 等的 .attributeModifier(...)）仍能正常编译。
// 视觉效果回退为系统默认按钮样式，不影响终端背景/字体等核心功能。

/**
 * Button 沉浸光感修饰器（API24 工具链下空实现，不做任何改动）。
 */
export class ImmersiveButtonModifier implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(instance: ButtonAttribute): void {
    // 空实现：API24 SDK 无 uiMaterial/systemMaterial
  }
}

/**
 * Toggle(Button 型) 沉浸光感修饰器，同上。
 */
export class ImmersiveToggleModifier implements AttributeModifier<ToggleAttribute> {
  applyNormalAttribute(instance: ToggleAttribute): void {
    // 空实现：API24 SDK 无 uiMaterial/systemMaterial
  }
}

/**
 * 主按钮（强调色）沉浸光感修饰器，同上。
 */
export class ImmersivePrimaryButtonModifier implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(instance: ButtonAttribute): void {
    // 空实现：API24 SDK 无 uiMaterial/systemMaterial
  }
}
