# Notchboard documentation site

The hosted documentation at [thepearl.github.io/notchboard](https://thepearl.github.io/notchboard/),
built with [Fumadocs](https://fumadocs.dev) on Next.js and deployed to GitHub Pages by
`.github/workflows/docs.yml` on every push to master that touches `website/`. This replaced the
GitBook space so the docs source lives in the repo and nothing else publishes it.

## Content

All pages are MDX under `content/docs/`, one folder per documentation space:

| Folder                    | Published at     | What is in it                                        |
| ------------------------- | ---------------- | ---------------------------------------------------- |
| `content/docs/documentation` | `/documentation` | The manual: getting started, concepts, guides, reference, maintainer docs |
| `content/docs/help-center`   | `/help-center`   | The FAQ                                              |
| `content/docs/integration`   | `/integration`   | The deeplink scheme, export file and room invite formats |
| `content/docs/changelog`     | `/changelog`     | Release notes                                        |

Each space folder's `meta.json` has `"root": true`, which is what renders the sidebar's space
switcher. Sidebar order and section headings live in the `meta.json` files, sidebar icons in each
page's `icon:` frontmatter (PascalCase [Lucide](https://lucide.dev) names).

## Working on it

```bash
npm install
npm run dev           # http://localhost:3000/notchboard (basePath applies in dev too)
npm run build         # static export to out/
npm run check-links   # verifies every internal href in out/ resolves; run after build
```

The site is a static export (`output: 'export'`) with `basePath: '/notchboard'`, because GitHub
Pages serves project sites under a path prefix. Search is Orama, pre-indexed at build time into
`out/api/search` and queried client-side, so it works with no server.
