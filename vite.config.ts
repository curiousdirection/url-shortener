import { execFileSync } from "node:child_process";
import { defineConfig } from "vite";

// Outside a git checkout there is none.
function release(): string {
  try {
    return execFileSync("infra/scripts/app-version.sh", { encoding: "utf8" }).trim();
  } catch {
    return "dev";
  }
}

export default defineConfig({
  root: "web",
  build: { outDir: "../build/web", emptyOutDir: true, assetsDir: "assets" },
  plugins: [{ name: "release-meta", transformIndexHtml: (html) => html.replace("%RELEASE%", release()) }],
});
