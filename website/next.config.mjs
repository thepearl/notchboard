import { createMDX } from 'fumadocs-mdx/next';

const withMDX = createMDX();

// Served from https://thepearl.github.io/notchboard/ (GitHub Pages project site).
const basePath = '/notchboard';

/** @type {import('next').NextConfig} */
const config = {
  output: 'export',
  basePath,
  // next/image and static imports get the prefix on their own, but a plain src pointing into
  // public/ (the promo <video>) does not, so pages read it from here.
  env: { NEXT_PUBLIC_BASE_PATH: basePath },
  trailingSlash: true,
  // Static export cannot run the image optimizer; remarkImage renders via next/image.
  images: { unoptimized: true },
  reactStrictMode: true,
};

export default withMDX(config);
