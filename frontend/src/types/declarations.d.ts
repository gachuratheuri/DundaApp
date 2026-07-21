declare module 'base-64' {
  export function decode(input: string): string;
  export function encode(input: string): string;
}

declare module 'js-sha1' {
  interface Sha1 {
    (message: string | ArrayBuffer | Uint8Array | number[]): string;
    hex(message: string | ArrayBuffer | Uint8Array | number[]): string;
    array(message: string | ArrayBuffer | Uint8Array | number[]): number[];
    digest(message: string | ArrayBuffer | Uint8Array | number[]): number[];
    arrayBuffer(message: string | ArrayBuffer | Uint8Array | number[]): ArrayBuffer;
    hmac: {
      (key: string | ArrayBuffer | Uint8Array | number[], message: string | ArrayBuffer | Uint8Array | number[]): string;
      array(key: string | ArrayBuffer | Uint8Array | number[], message: string | ArrayBuffer | Uint8Array | number[]): number[];
    };
  }
  const sha1: Sha1;
  export default sha1;
}
