// Builds the zip to upload to the Chrome Web Store: only the files the
// extension runs, nothing from tests or tooling.
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync } from "node:fs";

const root = new URL("..", import.meta.url).pathname;
const { version } = JSON.parse(readFileSync(`${root}/manifest.json`, "utf8"));
const out = `dist/shall-not-pass-${version}.zip`;

mkdirSync(`${root}/dist`, { recursive: true });
rmSync(`${root}/${out}`, { force: true });
execFileSync("zip", ["-qr", out, "manifest.json", "src", "icons", "-x", "*.DS_Store"], { cwd: root, stdio: "inherit" });
console.log(`Wrote extension/${out}`);
