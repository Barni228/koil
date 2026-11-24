// Checks the web build (target/web, from build-web.sh) in headless Chrome:
// loads it, which opens the welcome file (a first visit), goes to the
// listing (`-`), makes a file there (`ohello.txt`, Esc, Space Space to
// apply, `y` to confirm), and fails if either file isn't on Koil's disk,
// or if Koil stopped (a panic or a crash aborts it, see docs/platform.md,
// Web).
//
//   node scripts/web-smoke.mjs [--shots <dir>] [--dark]
//
// --shots saves screenshots there as it goes; --dark has the browser ask
// for dark mode. CHROME names the browser, if it isn't found.
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";

const args = process.argv.slice(2);
const option = name => args.includes(name) ? args[args.indexOf(name) + 1] : undefined;
const shots = option("--shots");
const dark = args.includes("--dark");
const site = join(dirname(fileURLToPath(import.meta.url)), "..", "target", "web");
const sleep = ms => new Promise(done => setTimeout(done, ms));

function fail(why) {
  console.error(`web-smoke: ${why}`);
  process.exitCode = 1;
}

// The site, served as Pages does, from a port of its own.
const types = { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm",
  ".png": "image/png" };
const server = createServer((request, response) => {
  const path = join(site, new URL(request.url, "http://x").pathname.replace(/\/$/, "/index.html"));
  if (!path.startsWith(site) || !existsSync(path)) {
    response.writeHead(404).end();
    return;
  }
  response.writeHead(200, { "Content-Type": types[extname(path)] ?? "application/octet-stream" });
  response.end(readFileSync(path));
});
await new Promise(done => server.listen(0, "127.0.0.1", done));
const url = `http://127.0.0.1:${server.address().port}/`;

const chromes = [process.env.CHROME, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser"];
const chromePath = chromes.find(path => path && existsSync(path));
if (!chromePath) {
  fail("no Chrome found: set CHROME");
  process.exit();
}
const profile = mkdtempSync(join(tmpdir(), "koil-smoke-"));
// CI's Linux has no sandbox for it.
const chrome = spawn(chromePath, ["--headless=new", `--user-data-dir=${profile}`,
  "--no-first-run", "--no-default-browser-check", "--enable-unsafe-swiftshader",
  "--use-angle=swiftshader", "--window-size=1100,700", "--remote-debugging-port=0",
  ...(process.env.CI ? ["--no-sandbox"] : []), "about:blank"], { stdio: "ignore" });

// Chrome writes the port it took to the profile.
let port;
for (let i = 0; i < 100 && !port; i++) {
  await sleep(100);
  const file = join(profile, "DevToolsActivePort");
  if (existsSync(file)) port = readFileSync(file, "utf8").split("\n")[0];
}
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const socket = new WebSocket(targets.find(target => target.type === "page").webSocketDebuggerUrl);
await new Promise(done => socket.addEventListener("open", done));

let id = 0;
const pending = new Map();
const problems = [];
socket.addEventListener("message", event => {
  const message = JSON.parse(event.data);
  if (pending.has(message.id)) {
    pending.get(message.id)(message.result);
    pending.delete(message.id);
  } else if (message.method === "Runtime.consoleAPICalled") {
    const text = message.params.args.map(arg => arg.value ?? arg.description).join(" ");
    if (/abort|panic|RuntimeError|unreachable/i.test(text)) problems.push(text);
    if (process.env.VERBOSE) console.log(`console: ${text}`);
  } else if (message.method === "Runtime.exceptionThrown") {
    const details = message.params.exceptionDetails;
    problems.push(details.exception?.description ?? details.text);
  }
});
const send = (method, params = {}) => new Promise(done => {
  pending.set(++id, done);
  socket.send(JSON.stringify({ id, method, params }));
});
const evaluate = async expression =>
  (await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true }))
    ?.result?.value;
const shot = async name => {
  if (!shots) return;
  const { data } = await send("Page.captureScreenshot", { format: "png" });
  writeFileSync(join(shots, `${name}.png`), Buffer.from(data, "base64"));
};
const codes = { Escape: 27, Enter: 13 };
async function key(name) {
  const special = name in codes;
  const text = special ? (name === "Enter" ? "\r" : undefined) : name;
  const event = { key: name, code: special ? name : undefined,
    windowsVirtualKeyCode: special ? codes[name] : name.toUpperCase().charCodeAt(0) };
  await send("Input.dispatchKeyEvent", { type: text ? "keyDown" : "rawKeyDown", text, ...event });
  await send("Input.dispatchKeyEvent", { type: "keyUp", ...event });
  await sleep(30);
}
const type = async text => { for (const c of text) await key(c); };

try {
  await send("Runtime.enable");
  await send("Page.enable");
  if (dark) {
    await send("Emulation.setEmulatedMedia",
      { features: [{ name: "prefers-color-scheme", value: "dark" }] });
  }
  await send("Page.navigate", { url });
  // The page hides its status once Koil is loaded; then QML takes a moment.
  let loaded = false;
  for (let i = 0; i < 600 && !loaded && !problems.length; i++) {
    await sleep(100);
    loaded = await evaluate("document.getElementById('status')?.hidden === true");
  }
  if (!loaded) throw new Error("Koil didn't load");
  await sleep(1500);
  await shot("loaded");

  const exists = path => evaluate(`window.koil?.FS?.analyzePath("/home/web_user/${path}").exists`);
  if (await exists("welcome.txt") !== true) problems.push("welcome.txt wasn't made");

  await send("Input.dispatchMouseEvent", { type: "mousePressed", x: 400, y: 120, button: "left", clickCount: 1 });
  await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: 400, y: 120, button: "left", clickCount: 1 });
  await sleep(300);
  await type("-");
  await sleep(500);
  await type("ohello.txt");
  await key("Escape");
  await type("  ");
  await sleep(800);
  await shot("asked");
  await type("y");
  await sleep(800);
  await shot("applied");

  if (await exists("hello.txt") !== true) problems.push("hello.txt wasn't made");
} catch (error) {
  problems.push(String(error));
}

socket.close();
chrome.kill();
server.close();
await sleep(200);
rmSync(profile, { recursive: true, force: true });
for (const problem of problems) fail(problem);
if (!problems.length) console.log("web-smoke: ok");
process.exit();
