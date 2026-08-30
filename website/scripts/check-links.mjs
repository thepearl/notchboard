// Post-build link check: walks every HTML file in out/ and verifies that each
// internal href/src resolves to a file in the export. Run after `npm run build`.
import { readdirSync, readFileSync, existsSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const OUT = new URL('../out', import.meta.url).pathname;
const BASE_PATH = '/notchboard';

function* htmlFiles(dir) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) yield* htmlFiles(full);
    else if (entry.endsWith('.html')) yield full;
  }
}

function targetExists(pathname) {
  const rel = pathname.replace(/\/+$/, '');
  if (rel === '') return existsSync(join(OUT, 'index.html'));
  return (
    existsSync(join(OUT, rel)) ||
    existsSync(join(OUT, rel, 'index.html')) ||
    existsSync(join(OUT, `${rel}.html`)) ||
    // Next emits route-handler outputs as extensionless files ("api/search").
    existsSync(join(OUT, `${rel}.txt`))
  );
}

if (!existsSync(OUT)) {
  console.error('out/ not found - run `npm run build` first.');
  process.exit(1);
}

let checked = 0;
const broken = [];
for (const file of htmlFiles(OUT)) {
  const html = readFileSync(file, 'utf8');
  // \s guard keeps data-href= and friends out of the match.
  for (const match of html.matchAll(/\s(?:href|src)="([^"#?]+)[^"]*"/g)) {
    const url = match[1];
    if (/^[a-z][a-z+.-]*:/i.test(url)) continue; // external scheme (https, mailto, ...)
    if (!url.startsWith('/')) {
      // A relative href in the export is a content link that escaped resolution.
      broken.push(`${relative(OUT, file)}: ${url} (unresolved relative link)`);
      continue;
    }
    if (!url.startsWith(`${BASE_PATH}/`) && url !== BASE_PATH) {
      broken.push(`${relative(OUT, file)}: ${url} (missing basePath)`);
      continue;
    }
    checked++;
    const pathname = url === BASE_PATH ? '' : decodeURI(url.slice(BASE_PATH.length + 1));
    if (!targetExists(pathname)) broken.push(`${relative(OUT, file)}: ${url}`);
  }
}

if (broken.length > 0) {
  console.error(`${broken.length} broken internal link(s):`);
  for (const line of [...new Set(broken)]) console.error(`  ${line}`);
  process.exit(1);
}
console.log(`ok - ${checked} internal references checked across the export.`);
