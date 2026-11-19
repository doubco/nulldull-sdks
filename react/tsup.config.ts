import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["src/index.ts"],
  format: ["esm", "cjs"],
  dts: true,
  sourcemap: true,
  clean: true,
  target: "es2020",
  platform: "neutral",
  external: ["react", "@nulldull/sdk"],
  // Hooks need a client boundary in React Server Components frameworks (Next.js App Router).
  banner: { js: '"use client";' },
});
