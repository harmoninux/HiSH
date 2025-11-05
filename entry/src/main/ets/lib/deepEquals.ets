type ValueType = number | string | boolean | Array<number> | Array<string> | Array<boolean> | Uint8Array | object
  | bigint;

function deepEquals(obj1: ValueType, obj2: ValueType): boolean {
  if (obj1 === obj2) {
    return true;
  }

  if (Array.isArray(obj1) && Array.isArray(obj2)) {
    if (obj1.length !== obj2.length) {
      return false;
    }
    for (let i = 0; i < obj1.length; i++) {
      if (!deepEquals(obj1[i], obj2[i])) {
        return false;
      }
    }
    return true;
  }

  if (typeof obj1 === 'object' && typeof obj2 === 'object') {
    const keys1 = Object.keys(obj1);
    const keys2 = Object.keys(obj2);
    if (keys1.length !== keys2.length) {
      return false;
    }
    for (const key of keys1) {
      if (!keys2.includes(key)) {
        return false;
      }
      if (!deepEquals(obj1[key], obj2[key])) {
        return false;
      }
    }
    return true;
  }

  return false;
}

export default deepEquals