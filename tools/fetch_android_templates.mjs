// Fetches ONLY the Android export templates out of Godot's 1.1 GB template
// archive, using HTTP range requests + the zip central directory.
//
//   node tools/fetch_android_templates.mjs "C:\Users\you\AppData\Roaming\Godot\export_templates\4.7.1.stable"
//
// Outputs android_debug.apk and android_release.apk, which is all a prebuilt
// (non-gradle) Android export needs.

import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const ARCHIVE = 'https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_export_templates.tpz';
const outDir = process.argv[2];

if (!outDir) {
	console.error('usage: node fetch_android_templates.mjs <output-directory>');
	process.exit(1);
}
fs.mkdirSync(outDir, { recursive: true });

const head = await fetch(ARCHIVE, { method: 'HEAD', redirect: 'follow' });
if (!head.ok) throw new Error(`HEAD failed: ${head.status}`);
const finalUrl = head.url;
const size = Number(head.headers.get('content-length'));
console.log(`archive: ${(size / 1048576).toFixed(1)} MB`);

async function getRange(start, end) {
	const res = await fetch(finalUrl, { headers: { Range: `bytes=${start}-${end}` } });
	if (res.status !== 206 && res.status !== 200) throw new Error(`range failed: ${res.status}`);
	return Buffer.from(await res.arrayBuffer());
}

// Find the end-of-central-directory record at the tail of the archive.
const tailLen = Math.min(size, 200000);
const tail = await getRange(size - tailLen, size - 1);
let eocd = -1;
for (let i = tail.length - 22; i >= 0; i -= 1) {
	if (tail.readUInt32LE(i) === 0x06054b50) {
		eocd = i;
		break;
	}
}
if (eocd < 0) throw new Error('could not find zip end-of-central-directory');
const cdSize = tail.readUInt32LE(eocd + 12);
const cdOffset = tail.readUInt32LE(eocd + 16);

const cd = await getRange(cdOffset, cdOffset + cdSize - 1);
const entries = [];
let p = 0;
while (p + 46 <= cd.length && cd.readUInt32LE(p) === 0x02014b50) {
	const method = cd.readUInt16LE(p + 10);
	const compSize = cd.readUInt32LE(p + 20);
	const nameLen = cd.readUInt16LE(p + 28);
	const extraLen = cd.readUInt16LE(p + 30);
	const commentLen = cd.readUInt16LE(p + 32);
	const localOffset = cd.readUInt32LE(p + 42);
	const name = cd.toString('utf8', p + 46, p + 46 + nameLen);
	entries.push({ name, method, compSize, localOffset });
	p += 46 + nameLen + extraLen + commentLen;
}

const wanted = entries.filter((e) => e.name === 'templates/android_debug.apk' || e.name === 'templates/android_release.apk');
if (wanted.length === 0) throw new Error('android templates not found in archive');

for (const entry of wanted) {
	console.log(`fetching ${entry.name} (${(entry.compSize / 1048576).toFixed(1)} MB compressed)...`);
	const lh = await getRange(entry.localOffset, entry.localOffset + 29);
	if (lh.readUInt32LE(0) !== 0x04034b50) throw new Error(`bad local header for ${entry.name}`);
	const nameLen = lh.readUInt16LE(26);
	const extraLen = lh.readUInt16LE(28);
	const dataStart = entry.localOffset + 30 + nameLen + extraLen;
	const raw = await getRange(dataStart, dataStart + entry.compSize - 1);
	let out;
	if (entry.method === 0) out = raw;
	else if (entry.method === 8) out = zlib.inflateRawSync(raw);
	else throw new Error(`unsupported zip compression ${entry.method}`);
	const target = path.join(outDir, path.basename(entry.name));
	fs.writeFileSync(target, out);
	console.log(`wrote ${target} (${(out.length / 1048576).toFixed(1)} MB)`);
}
console.log('done');
