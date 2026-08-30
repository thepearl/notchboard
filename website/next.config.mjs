import { createMDX } from 'fumadocs-mdx/next';

const withMDX = createMDX();

/** @type {import('next').NextConfig} */
const config = {
  output: 'export',
  // Served from https://thepearl.github.io/notchboard/ (GitHub Pages project site).
  basePath: '/notchboard',
  trailingSlash: true,
  // Static export cannot run the image optimizer; remarkImage renders via next/image.
  images: { unoptimized: true },
  reactStrictMode: true,
};

export default withMDX(config);
