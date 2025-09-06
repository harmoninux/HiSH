export const startVM: (width: number, height: number, dataCb: (ArrayBuffer) => void, exitCb: () => void) => void;
export const send: (content: ArrayBuffer) => void;
export const add: (a: number, b: number) => number;