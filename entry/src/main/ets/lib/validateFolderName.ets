export interface ValidateOptions {
  /**
   * Maximum length for a single path component.
   * Common filesystem limit is 255 (ext4, many others).
   */
  maxLength?: number;
}

export interface ValidationResult {
  valid: boolean;
  reason?: string | null;
}

/**
 * Validate a single POSIX folder name (path component).
 *
 * @param name - candidate folder name
 * @param opts - optional settings (maxLength)
 * @returns ValidationResult - { valid: boolean, reason?: string }
 */
export function validateFolderName(name: string): boolean {

  const maxLength = 255

  if (typeof name !== "string") {
    return false
  }

  if (name.length === 0) {
    return false
  }

  if (name === "." || name === "..") {
    return false
  }

  if (name.length > maxLength) {
    return false
  }

  if (name.includes("\0")) {
    return false
  }

  if (name.includes("/")) {
    return false
  }

  return true
}

export default validateFolderName;