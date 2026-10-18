# 生成 overlay/win32/code.ico（XII 品牌图标，不依赖 .NET）
# 用法：
#   node .\scripts\make-icon.js            # 生成默认 XII 图标
#   node .\scripts\make-icon.js <src.png>  # 从自定义 PNG（≥256px 方形）生成
# 原理：纯 JS 解析 PNG（含 zlib inflate）→ 采样 → 手工拼 ico 容器（BMP32 全尺寸）

'use strict';

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

function parsePng(buf) {
  const sig = [137, 80, 78, 71, 13, 10, 26, 10];
  for (let i = 0; i < 8; i++) if (buf[i] !== sig[i]) throw new Error('not a PNG');
  let off = 8;
  let w = 0, h = 0, bitDepth = 0, colorType = 0;
  const idat = [];
  while (off + 8 <= buf.length) {
    const len = buf.readUInt32BE(off); off += 4;
    const type = buf.toString('ascii', off, off + 4); off += 4;
    const data = buf.subarray(off, off + len); off += len;
    off += 4; // CRC
    if (type === 'IHDR') {
      w = data.readUInt32BE(0);
      h = data.readUInt32BE(4);
      bitDepth = data.readUInt8(8);
      colorType = data.readUInt8(9);
    } else if (type === 'IDAT') {
      idat.push(Buffer.from(data));
    } else if (type === 'IEND') {
      break;
    }
  }
  if (colorType !== 6 || bitDepth !== 8) {
    throw new Error(`unsupported PNG (colorType=${colorType}, bitDepth=${bitDepth}); needs RGBA8 (e.g. re-encode with any tool)`);
  }
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = w * 4;
  const px = Buffer.alloc(w * h * 4);
  for (let y = 0; y < h; y++) {
    const filter = raw[y * (stride + 1)];
    const rowStart = y * (stride + 1) + 1;
    for (let x = 0; x < w; x++) {
      const i = rowStart + x * 4;
      const a = raw[i + 3];
      const r = a === 0 ? 0 : raw[i];
      const g = a === 0 ? 0 : raw[i + 1];
      const b = a === 0 ? 0 : raw[i + 2];
      // un-premultiply with nearest-neighbour-friendly approximation
      const o = (y * w + x) * 4;
      px[o] = r; px[o + 1] = g; px[o + 2] = b; px[o + 3] = a;
      void filter;
    }
  }
  return { w, h, px };
}

function sampleNearest(src, dstW, dstH) {
  const out = Buffer.alloc(dstW * dstH * 4);
  const sx = src.w / dstW, sy = src.h / dstH;
  for (let y = 0; y < dstH; y++) {
    const syi = Math.min(src.h - 1, Math.floor((y + 0.5) * sy));
    for (let x = 0; x < dstW; x++) {
      const sxi = Math.min(src.w - 1, Math.floor((x + 0.5) * sx));
      const s = (syi * src.w + sxi) * 4;
      const d = (y * dstW + x) * 4;
      out[d] = src.px[s]; out[d + 1] = src.px[s + 1]; out[d + 2] = src.px[s + 2]; out[d + 3] = src.px[s + 3];
    }
  }
  return out;
}

function bmp32(px) {
  // BGRA, bottom-up, 32bpp BITMAPINFOHEADER (30 bytes, biCompression=0)
  const w = px.length / 4;
  const h = px.length / (w * 4);
  const stride = Math.ceil(w * 4 / 4) * 4;
  const bmp = Buffer.alloc(40 + stride * h);
  bmp.writeUInt32LE(40, 0);
  bmp.writeInt32LE(w, 4);
  bmp.writeInt32LE(h, 8); // positive h = bottom-up
  bmp.writeUInt16LE(1, 12);
  bmp.writeUInt16LE(32, 14);
  bmp.writeUInt32LE(0, 16);
  const imgSize = stride * h;
  bmp.writeUInt32LE(imgSize, 20);
  for (let y = 0; y < h; y++) {
    const srcRow = px.subarray((h - 1 - y) * w * 4, h * w * 4 - y * w * 4); // top-to-bottom -> bottom-up
    for (let x = 0; x < w; x++) {
      const o = 40 + y * stride + x * 4;
      const s = srcRow.subarray(x * 4, x * 4 + 4);
      // BGRA
      bmp[o] = s[2]; bmp[o + 1] = s[1]; bmp[o + 2] = s[0]; bmp[o + 3] = s[3];
    }
  }
  return bmp;
}

function buildIco(sizes) {
  const images = sizes.map(s => bmp32(sampleNearest(global.__src, s, s)));
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0); header.writeUInt16LE(1, 2); header.writeUInt16LE(sizes.length, 4);
  let offset = 14 + images.length * 16;
  const entries = [];
  images.forEach((img, i) => {
    const e = Buffer.alloc(16);
    const dim = sizes[i] >= 256 ? 0 : sizes[i];
    e[0] = dim; e[1] = 0; e[2] = 0; e[3] = 1;
    e.writeUInt16LE(32, 4);
    e.writeUInt32LE(img.length, 8);
    e.writeUInt32LE(offset, 12);
    offset += img.length;
    entries.push(e);
  });
  return Buffer.concat([header, ...entries, ...images]);
}

const outPath = path.resolve(__dirname, '..', 'overlay', 'win32', 'code.ico');
const srcPng = process.argv[2];

if (srcPng) {
  global.__src = parsePng(fs.readFileSync(srcPng));
} else {
  // 程序化生成 XII 占位图标：深底圆角 + 米色 "XII"
  const N = 256;
  const px = Buffer.alloc(N * N * 4);
  for (let y = 0; y < N; y++) {
    for (let x = 0; x < N; x++) {
      const o = (y * N + x) * 4;
      // rounded rect background (corner radius 48)
      const r = 48;
      const cx = x < r ? r : (x > N - r ? N - r : x);
      const cy = y < r ? r : (y > N - r ? N - r : y);
      const dx = x - cx, dy = y - cy;
      const inside = dx * dx + dy * dy <= r * r;
      px[o + 3] = inside ? 255 : 0;
      px[o] = 25; px[o + 1] = 30; px[o + 2] = 42; // 深灰蓝底
      // 简易 "XII" 字形：三根竖条 + 左竖斜交叉
      const T0 = 70, T1 = 186;
      const inX = (v) => v >= T0 && v <= T1;
      const bars =
        (inX(x) && inX(y) && (x >= 60 && x <= 78 || x >= 130 && x <= 148)) ||      // I I
        (inX(x) && inX(y) && x >= 196 && x <= 214) ||                                // I
        (inX(x) && inX(y) && (Math.abs((x - 60) * 1.0 - (y - T0)) < 10 || Math.abs((x - 60) * -1.0 - (y - T0)) < 10)); // X 交叉
      if (inside && bars) { px[o] = 214; px[o + 1] = 198; px[o + 2] = 158; } // 米金色
    }
  }
  global.__src = { w: N, h: N, px };
}

const ico = buildIco([16, 24, 32, 48, 64, 128, 256]);
fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, ico);
console.log(`icon written: ${outPath} (${ico.length} bytes)`);
