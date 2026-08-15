import { uiMaterial } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0000

let cachedMaterial: uiMaterial.Material | undefined = undefined
let materialChecked = false

/**
 * 按钮用沉浸式系统材质（沉浸光感，API 26+）。
 * 超薄样式 + 按压弹性形变 + 流光反馈。
 * 低版本运行时返回 undefined，修饰器将跳过设置，保证兼容。
 */
function immersiveButtonMaterial(): uiMaterial.Material | undefined {
  if (materialChecked) {
    return cachedMaterial
  }
  materialChecked = true
  try {
    if (deviceInfo.sdkApiVersion >= 26) {
      const lightEffect: uiMaterial.LightEffectOptions = { color: undefined }
      cachedMaterial = new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        interactive: true,
        lightEffect: lightEffect
      })
    }
  } catch (e) {
    hilog.warn(DOMAIN, 'immersiveButton', 'immersive material unavailable: %{public}s', JSON.stringify(e))
    cachedMaterial = undefined
  }
  return cachedMaterial
}

/**
 * Button 沉浸光感修饰器：有材质则设置，无则不设（兼容 API < 26 运行时）。
 * 注意：材质层位于 backgroundColor 之下，被修饰组件不要设置不透明背景色。
 */
export class ImmersiveButtonModifier implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(instance: ButtonAttribute): void {
    const material = immersiveButtonMaterial()
    if (material !== undefined) {
      instance.systemMaterial(material)
    }
  }
}

/**
 * Toggle(Button 型) 沉浸光感修饰器，同上。
 */
export class ImmersiveToggleModifier implements AttributeModifier<ToggleAttribute> {
  applyNormalAttribute(instance: ToggleAttribute): void {
    const material = immersiveButtonMaterial()
    if (material !== undefined) {
      instance.systemMaterial(material)
    }
  }
}

let cachedPrimaryMaterial: uiMaterial.Material | undefined = undefined
let primaryChecked = false

/**
 * 主按钮用沉浸式系统材质：超薄材质 + 交互反馈，
 * 主按钮的视觉权重由调用方通过强调色文字体现。
 * 低版本运行时返回 undefined。
 */
function immersivePrimaryButtonMaterial(): uiMaterial.Material | undefined {
  if (primaryChecked) {
    return cachedPrimaryMaterial
  }
  primaryChecked = true
  try {
    if (deviceInfo.sdkApiVersion >= 26) {
      const lightEffect: uiMaterial.LightEffectOptions = { color: undefined }
      cachedPrimaryMaterial = new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        interactive: true,
        lightEffect: lightEffect
      })
    }
  } catch (e) {
    hilog.warn(DOMAIN, 'immersiveButton', 'primary material unavailable: %{public}s', JSON.stringify(e))
    cachedPrimaryMaterial = undefined
  }
  return cachedPrimaryMaterial
}

/**
 * 主按钮（强调色）沉浸光感修饰器。
 * 应用材质的同时把按钮自身背景设为透明（材质层位于 backgroundColor 之下），
 * 低版本运行时不做任何改动，保留默认强调色背景。
 */
export class ImmersivePrimaryButtonModifier implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(instance: ButtonAttribute): void {
    const material = immersivePrimaryButtonMaterial()
    if (material !== undefined) {
      instance.backgroundColor(Color.Transparent)
      instance.systemMaterial(material)
    }
  }
}
