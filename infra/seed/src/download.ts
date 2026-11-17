import type { Download } from "./seed.ts";

export const fetchDownload: Download = async (url) => {
  const response = await fetch(url);
  const body = new Uint8Array(await response.arrayBuffer());
  return { status: response.status, body };
};
