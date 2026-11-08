import { PortMapping } from '../model/Emulator'

export interface PortMappingError {
  kind: 'incomplete' | 'range' | 'duplicate'
  index: number
}

function isTcpPort(port: number): boolean {
  return Number.isInteger(port) && port >= 1 && port <= 65535
}

/** Validate both ends before the mapping is saved and passed to QEMU. */
export function validatePortMappings(mappings: PortMapping[]): PortMappingError | undefined {
  const guestPorts = new Set<number>()
  const hostPorts = new Set<number>()
  for (let index = 0; index < mappings.length; index++) {
    const mapping = mappings[index]
    if (mapping.guest === undefined || mapping.host === undefined) {
      return { kind: 'incomplete', index }
    }
    if (!isTcpPort(mapping.guest) || !isTcpPort(mapping.host)) {
      return { kind: 'range', index }
    }
    if (guestPorts.has(mapping.guest) || hostPorts.has(mapping.host)) {
      return { kind: 'duplicate', index }
    }
    guestPorts.add(mapping.guest)
    hostPorts.add(mapping.host)
  }
  return undefined
}
