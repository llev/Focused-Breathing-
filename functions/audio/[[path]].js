// Answers range requests for the Classical mix on Cloudflare Pages.
//
// Pages serves static files whole, but Safari on iPhone, iPad and Mac only plays audio from a server that can send
// part of a file. This passes each piece through and, when a part is asked for, streams just that part.
// It streams rather than reading the whole file, so it stays fast and light even for the longest pieces.
export async function onRequestGet({ request, env }) {
  let res = await env.ASSETS.fetch(request);
  const range = /^bytes=(\d*)-(\d*)$/.exec(request.headers.get('range') || '');
  const headers = new Headers(res.headers);
  headers.set('accept-ranges', 'bytes');
  if (res.status !== 200 || !range || !res.body) return new Response(res.body, { status: res.status, headers });
  let size = Number(res.headers.get('content-length'));
  if (!size) {
    // The size isn't always given, so read the piece to find it. The part sent back is a view of it, not a copy.
    const whole = new Uint8Array(await res.arrayBuffer());
    size = whole.byteLength;
    res = new Response(whole);
  }

  let start, end;
  if (range[1] === '') {
    // "bytes=-500" means the last 500 bytes.
    start = Math.max(0, size - Number(range[2]));
    end = size - 1;
  } else {
    start = Number(range[1]);
    end = range[2] === '' ? size - 1 : Math.min(Number(range[2]), size - 1);
  }
  if (start >= size || start > end) {
    res.body.cancel();
    return new Response(null, { status: 416, headers: { 'content-range': `bytes */${size}`, 'accept-ranges': 'bytes' } });
  }

  let pos = 0;
  const part = res.body.pipeThrough(new TransformStream({
    transform(chunk, out) {
      const from = Math.max(0, start - pos), to = Math.min(chunk.byteLength, end + 1 - pos);
      if (to > from) out.enqueue(chunk.subarray(from, to));
      pos += chunk.byteLength;
    }
  }));
  headers.set('content-range', `bytes ${start}-${end}/${size}`);
  headers.set('content-length', String(end - start + 1));
  return new Response(part, { status: 206, headers });
}

export async function onRequestHead(context) {
  const res = await onRequestGet(context);
  return new Response(null, { status: res.status, headers: res.headers });
}
