export interface VirtualKeyMetrics {
  margin: number
  padding: number
  height: number
  width: number
  fontSize: number
  radius: number
}

export function getVirtualKeyMetrics(deviceType: string): VirtualKeyMetrics {
  const isPhone = deviceType === 'phone'
  return {
    margin: isPhone ? 1 : 2,
    padding: isPhone ? 2 : 4,
    height: 28,
    width: isPhone ? 48 : 60,
    fontSize: isPhone ? 11 : 14,
    radius: 5
  }
}

export interface FunctionKeySequencesMap {
  F1: string
  F2: string
  F3: string
  F4: string
  F5: string
  F6: string
  F7: string
  F8: string
  F9: string
  F10: string
  F11: string
  F12: string
}

export const FunctionKeyOrder: string[] = ['F1', 'F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8', 'F9', 'F10', 'F11', 'F12']

export const FunctionKeySequences: FunctionKeySequencesMap = {
  F1: '\x1bOP',
  F2: '\x1bOQ',
  F3: '\x1bOR',
  F4: '\x1bOS',
  F5: '\x1b[15~',
  F6: '\x1b[17~',
  F7: '\x1b[18~',
  F8: '\x1b[19~',
  F9: '\x1b[20~',
  F10: '\x1b[21~',
  F11: '\x1b[23~',
  F12: '\x1b[24~'
}

export interface NormalKeySequencesMap {
  ESC: string
  TAB: string
  PGUP: string
  HOME: string
  UP: string
  UP_APP: string
  END: string
  PGDN: string
  LEFT: string
  LEFT_APP: string
  DOWN: string
  DOWN_APP: string
  RIGHT: string
  RIGHT_APP: string
}

export const NormalKeySequences: NormalKeySequencesMap = {
  ESC: '\x1b',
  TAB: '\t',
  PGUP: '\x1b[5~',
  HOME: '\x1b[H',
  UP: '\x1b[A',
  UP_APP: '\x1bOA',
  END: '\x1b[F',
  PGDN: '\x1b[6~',
  LEFT: '\x1b[D',
  LEFT_APP: '\x1bOD',
  DOWN: '\x1b[B',
  DOWN_APP: '\x1bOB',
  RIGHT: '\x1b[C',
  RIGHT_APP: '\x1bOC'
}

export interface InputModifierResult {
  data: string
  shouldResetCtrl: boolean
  ctrlConverted: boolean
  shiftConverted: boolean
}

export function applyVirtualKeyModifiers(data: string, ctrlPressed: boolean, shiftPressed: boolean): InputModifierResult {
  let output = data
  let ctrlConverted = false
  let shiftConverted = false
  let shouldResetCtrl = false

  if (ctrlPressed && output.length === 1) {
    const char = output.charAt(0)
    if (char >= 'a' && char <= 'z') {
      output = String.fromCharCode(char.charCodeAt(0) - 'a'.charCodeAt(0) + 1)
      ctrlConverted = true
    }
    shouldResetCtrl = true
  }

  if (shiftPressed && output.length === 1) {
    const char = output.charAt(0)
    if (char >= 'a' && char <= 'z') {
      output = char.toUpperCase()
      shiftConverted = true
    }
  }

  return {
    data: output,
    shouldResetCtrl: shouldResetCtrl,
    ctrlConverted: ctrlConverted,
    shiftConverted: shiftConverted
  }
}
