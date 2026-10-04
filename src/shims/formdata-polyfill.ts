export const FormData = typeof window !== 'undefined'
  ? window.FormData
  : (typeof globalThis !== 'undefined' ? globalThis.FormData : class {});

export const File = typeof window !== 'undefined'
  ? window.File
  : (typeof globalThis !== 'undefined' ? globalThis.File : class {});

export function formDataToBlob(formData: any) {
  return formData;
}

export default FormData;
