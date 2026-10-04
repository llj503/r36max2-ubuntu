// fb2png - turn a raw /dev/fb0 dump into a PNG using only Node built-ins.
// usage: node fb2png.js in.raw out.png W H BPP LINE_LENGTH [R_SHIFT G_SHIFT]
const fs = require('fs');
const zlib = require('zlib');

const [, , inPath, outPath, wS, hS, bppS, llS, rShift, gShift] = process.argv;
if (!inPath || !outPath || !wS || !hS) {
  console.error('usage: node fb2png.js in.raw out.png W H BPP LINE_LENGTH [R_SHIFT G_SHIFT]');
  process.exit(2);
}
const W = +wS, H = +hS, BPP = +(bppS || 32);
const bytes = BPP / 8;
const LL = +(llS || W * bytes);
const rOff = rShift !== undefined ? +rShift : (BPP === 16 ? 11 : 16);
const gOff = gShift !== undefined ? +gShift : (BPP === 16 ? 5 : 8);
const bOff = 0;

const raw = fs.readFileSync(inPath);
const rgb = Buffer.alloc(W * H * 3);
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    const o = y * LL + x * bytes;
    if (o + bytes > raw.length) break;
    let px;
    if (bytes === 4) px = raw.readUInt32LE(o);
    else if (bytes === 2) px = raw.readUInt16LE(o);
    else px = raw[o];
    let r = (px >> rOff) & 0xff, g = (px >> gOff) & 0xff, b = (px >> bOff) & 0xff;
    if (BPP === 16) {   // 5/6/5 -> 8 bit
      r = (r << 3) | (r >> 2); g = (g << 2) | (g >> 4); b = (b << 3) | (b >> 2);
    }
    const t = (y * W + x) * 3;
    rgb[t] = r; rgb[t + 1] = g; rgb[t + 2] = b;
  }
}

const TBL = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c; }
  return t;
})();
function crc32(buf) {
  let c = ~0;
  for (let i = 0; i < buf.length; i++) c = TBL[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (~c >>> 0);
}
function chunk(tag, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(tag, 'ascii'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}

const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4);
ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;

const stride = W * 3;
const rows = Buffer.alloc((stride + 1) * H);
for (let y = 0; y < H; y++) {
  rows[y * (stride + 1)] = 0;                                  // filter: none
  rgb.copy(rows, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
}

const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0d]),
  chunk('IHDR', ihdr),
  chunk('IDAT', zlib.deflateSync(rows, { level: 6 })),
  chunk('IEND', Buffer.alloc(0)),
]);
fs.writeFileSync(outPath, png);
console.log(`fb ${W}x${H} bpp=${BPP} line_length=${LL} r<<${rOff} g<<${gOff} -> ${outPath} (${png.length} bytes)`);
