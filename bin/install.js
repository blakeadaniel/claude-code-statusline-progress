#!/usr/bin/env node

import fs from "fs";
import path from "path";
import os from "os";
import readline from "readline";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SCRIPT_SRC = path.resolve(__dirname, "../statusline-command.sh");
const CLAUDE_DIR = path.join(os.homedir(), ".claude");
const SCRIPT_DEST = path.join(CLAUDE_DIR, "statusline-command.sh");
const SETTINGS_PATH = path.join(CLAUDE_DIR, "settings.json");

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const ask = (q) => new Promise((res) => rl.question(q, res));

function pct(raw, def) {
  const n = parseFloat(raw);
  if (raw.trim() === "") return def;
  if (isNaN(n) || n < 0 || n > 100) throw new Error(`"${raw}" is not a valid percentage`);
  return n;
}

function patch(src, name, value) {
  const frac = (value / 100).toFixed(2);
  return src.replace(
    new RegExp(`(^${name}\\s*=\\s*)[\\d.]+`, "m"),
    `$1${frac}`
  );
}

async function promptThresholds() {
  console.log("\nSet color thresholds (press Enter to accept the default):\n");

  const sections = [
    {
      label: "Session context window",
      warnKey: "CONTEXT_WARN",   warnDef: 20,
      dangerKey: "CONTEXT_DANGER", dangerDef: 50,
    },
    {
      label: "5-hour usage allowance",
      warnKey: "USAGE_5H_WARN",   warnDef: 50,
      dangerKey: "USAGE_5H_DANGER", dangerDef: 90,
    },
    {
      label: "7-day usage allowance",
      warnKey: "USAGE_7D_WARN",   warnDef: 50,
      dangerKey: "USAGE_7D_DANGER", dangerDef: 90,
    },
  ];

  const values = {};

  for (const { label, warnKey, warnDef, dangerKey, dangerDef } of sections) {
    console.log(`${label}:`);
    let warnVal, dangerVal;

    while (true) {
      try {
        const raw = await ask(`  Warning at  [${warnDef}%]: `);
        warnVal = pct(raw, warnDef);
        break;
      } catch (e) {
        console.error(`  ${e.message} — enter a number between 0 and 100`);
      }
    }

    while (true) {
      try {
        const raw = await ask(`  Danger at   [${dangerDef}%]: `);
        dangerVal = pct(raw, dangerDef);
        if (dangerVal <= warnVal) {
          console.error(`  Danger must be greater than warning (${warnVal}%)`);
          continue;
        }
        break;
      } catch (e) {
        console.error(`  ${e.message} — enter a number between 0 and 100`);
      }
    }

    console.log();
    values[warnKey] = warnVal;
    values[dangerKey] = dangerVal;
  }

  return values;
}

function installScript(thresholds) {
  let src = fs.readFileSync(SCRIPT_SRC, "utf8");
  for (const [name, value] of Object.entries(thresholds)) {
    src = patch(src, name, value);
  }
  fs.mkdirSync(CLAUDE_DIR, { recursive: true });
  fs.writeFileSync(SCRIPT_DEST, src, { mode: 0o755 });
  console.log(`✓ Installed script → ${SCRIPT_DEST}`);
}

function patchSettings() {
  let settings = {};
  if (fs.existsSync(SETTINGS_PATH)) {
    try {
      settings = JSON.parse(fs.readFileSync(SETTINGS_PATH, "utf8"));
    } catch {
      console.error(`✗ Could not parse ${SETTINGS_PATH} — fix it manually and re-run.`);
      process.exit(1);
    }
  }
  settings.statusLine = { type: "command", command: `bash ${SCRIPT_DEST}` };
  fs.writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2) + "\n");
  console.log(`✓ Updated settings  → ${SETTINGS_PATH}`);
}

console.log("Claude Code Statusline Installer");
console.log("================================");

const thresholds = await promptThresholds();
rl.close();

console.log("Installing...");
installScript(thresholds);
patchSettings();
console.log("\nDone! Restart Claude Code to see your statusline.");
