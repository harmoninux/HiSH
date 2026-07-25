export const actionMapStr: Map<number, string> = new Map([
  [MouseAction.Move, "move"],
  [MouseAction.Press, "press"],
  [MouseAction.Release, "release"],
  [MouseAction.Hover, "hover"]
])

export const buttonMapStr: Map<number, string> = new Map([
  [MouseButton.Left, "left"],
  [MouseButton.Right, "right"],
  [MouseButton.Middle, "middle"],
  [MouseButton.None, "move"]
])

export const button2rfb = new Map([
  [MouseButton.None, 0],
  [MouseButton.Left, 1],
  [MouseButton.Right, 4],
  [MouseButton.Middle, 2]
])

export const keyTypeMapStr: Map<number, string> = new Map([
  [KeyType.Down, "down"],
  [KeyType.Up, "up"]
])

export enum ScrollButtonMask {
  yBack = 1 << 3,
  yForward = 1 << 4,
  xBack = 1 << 5,
  xForward = 1 << 6
}
