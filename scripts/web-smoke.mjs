// Checks the web build (target/web, from build-web.sh) in headless Chrome:
// loads it, which opens the welcome file (a first visit), goes to the
// listing (`-`), makes a file there (`ohello.txt`, Esc, Space Space to
// apply, `y` to confirm), undoes that (`u`, `y`), which trashes it, then
// deletes the welcome file (`dd`, applied) and undoes that, which brings
// it back from the trash. Then empties the trash (`:emptytrash`, `y`),
// drops a file on the page (imported into the open dir), pastes what the
// browser's clipboard has (`"+p`, applied), and opens a second tab, which
// says Koil is open in the first, until its Use Koil Here moves it there,
// with the files. It fails if a file isn't where that leaves it on Koil's
// disk, if a tab doesn't say what it should, or if Koil stopped (a panic
// or a crash aborts it, see docs/platform.md, Web).
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
const devtools = path => `http://127.0.0.1:${port}/json/${path}`;
const problems = [];
const sockets = [];

// A tab, by its DevTools socket: what's sent to it, and keys typed in it.
async function connect(webSocketUrl, name) {
  const socket = new WebSocket(webSocketUrl);
  sockets.push(socket);
  await new Promise(done => socket.addEventListener("open", done));
  let id = 0;
  const pending = new Map();
  socket.addEventListener("message", event => {
    const message = JSON.parse(event.data);
    if (pending.has(message.id)) {
      pending.get(message.id)(message.result);
      pending.delete(message.id);
    } else if (message.method === "Runtime.consoleAPICalled") {
      const text = message.params.args.map(arg => arg.value ?? arg.description).join(" ");
      if (/abort|panic|RuntimeError|unreachable/i.test(text)) problems.push(`${name}: ${text}`);
      if (process.env.VERBOSE) console.log(`${name} console: ${text}`);
    } else if (message.method === "Runtime.exceptionThrown") {
      const details = message.params.exceptionDetails;
      problems.push(`${name}: ${details.exception?.description ?? details.text}`);
    }
  });
  const tab = {};
  tab.send = (method, params = {}) => new Promise(done => {
    pending.set(++id, done);
    socket.send(JSON.stringify({ id, method, params }));
  });
  tab.evaluate = async expression =>
    (await tab.send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true }))
      ?.result?.value;
  tab.shot = async shotName => {
    if (!shots) return;
    const { data } = await tab.send("Page.captureScreenshot", { format: "png" });
    writeFileSync(join(shots, `${shotName}.png`), Buffer.from(data, "base64"));
  };
  const codes = { Escape: 27, Enter: 13 };
  tab.key = async keyName => {
    const special = keyName in codes;
    const text = special ? (keyName === "Enter" ? "\r" : undefined) : keyName;
    const event = { key: keyName, code: special ? keyName : undefined,
      windowsVirtualKeyCode: special ? codes[keyName] : keyName.toUpperCase().charCodeAt(0) };
    await tab.send("Input.dispatchKeyEvent", { type: text ? "keyDown" : "rawKeyDown", text, ...event });
    await tab.send("Input.dispatchKeyEvent", { type: "keyUp", ...event });
    await sleep(30);
  };
  tab.type = async text => { for (const c of text) await tab.key(c); };
  tab.exists = path => tab.evaluate(`window.koil?.FS?.analyzePath("/home/web_user/${path}").exists`);
  tab.status = () => tab.evaluate(
    "document.getElementById('status').hidden ? '' : document.getElementById('message').textContent");
  // The page hides its status once Koil is loaded; then QML takes a moment.
  // Not once Koil stopped (the console said so meanwhile).
  tab.loaded = async () => {
    const before = problems.length;
    for (let i = 0; i < 600 && problems.length === before; i++) {
      await sleep(100);
      if (await tab.evaluate("document.getElementById('status')?.hidden === true")) {
        await sleep(1500);
        return;
      }
    }
    throw new Error(`${name}: Koil didn't load`);
  };
  await tab.send("Runtime.enable");
  await tab.send("Page.enable");
  if (dark) {
    await tab.send("Emulation.setEmulatedMedia",
      { features: [{ name: "prefers-color-scheme", value: "dark" }] });
  }
  return tab;
}

// Applies the listing's changes: Space Space, then y to the question.
async function apply(tab, shotName) {
  await tab.type("  ");
  await sleep(800);
  await tab.shot(`${shotName}-asked`);
  await tab.type("y");
  await sleep(800);
}

// With nothing for vim to undo, `u` asks to undo the last apply.
async function undoApply(tab) {
  await tab.type("u");
  await sleep(800);
  await tab.type("y");
  await sleep(800);
}

try {
  const pages = await (await fetch(devtools("list"))).json();
  const tab = await connect(pages.find(page => page.type === "page").webSocketDebuggerUrl, "first tab");
  await tab.send("Page.navigate", { url });
  await tab.loaded();
  await tab.shot("loaded");
  if (await tab.exists("welcome.txt") !== true) problems.push("welcome.txt wasn't made");

  await tab.send("Input.dispatchMouseEvent", { type: "mousePressed", x: 400, y: 120, button: "left", clickCount: 1 });
  await tab.send("Input.dispatchMouseEvent", { type: "mouseReleased", x: 400, y: 120, button: "left", clickCount: 1 });
  await sleep(300);
  await tab.type("-");
  await sleep(500);
  await tab.type("ohello.txt");
  await tab.key("Escape");
  await apply(tab, "create");
  if (await tab.exists("hello.txt") !== true) problems.push("hello.txt wasn't made");

  // Undoing the create trashes it, in the trash koil-core keeps on the web.
  const trashed = name => tab.exists(`.local/share/Trash/files/${name}`);
  await undoApply(tab);
  await tab.shot("undone");
  if (await tab.exists("hello.txt") !== false) problems.push("undoing hello.txt's create left it");
  if (await trashed("hello.txt") !== true) problems.push("hello.txt isn't in the trash");

  await tab.type("dd");
  await apply(tab, "delete");
  if (await tab.exists("welcome.txt") !== false) problems.push("welcome.txt wasn't deleted");
  if (await trashed("welcome.txt") !== true) problems.push("welcome.txt isn't in the trash");
  await undoApply(tab);
  await tab.shot("restored");
  if (await tab.exists("welcome.txt") !== true) problems.push("welcome.txt didn't come back");

  await tab.type(":emptytrash");
  await tab.key("Enter");
  await sleep(800);
  await tab.shot("empty-trash-asked");
  await tab.type("y");
  await sleep(800);
  if (await tab.exists(".local/share/Trash") !== false) problems.push("the trash wasn't emptied");

  // A file dropped on the page comes into the open dir.
  const dropped = join(profile, "dropped.txt");
  writeFileSync(dropped, "dropped\n");
  const data = { items: [], files: [dropped], dragOperationsMask: 1 };
  for (const type of ["dragEnter", "dragOver", "drop"]) {
    await tab.send("Input.dispatchDragEvent", { type, x: 500, y: 300, data });
    await sleep(300);
  }
  await sleep(1000);
  await tab.shot("dropped");
  if (await tab.exists("dropped.txt") !== true) problems.push("the dropped file wasn't imported");
  // Which opened it: back to the listing.
  await tab.type("-");
  await sleep(500);

  // "+p asks the browser for its clipboard.
  await tab.send("Browser.grantPermissions", { origin: url.replace(/\/$/, ""),
    permissions: ["clipboardReadWrite", "clipboardSanitizedWrite"] });
  await tab.send("Emulation.setFocusEmulationEnabled", { enabled: true });
  // A line, which goes under the cursor's.
  await tab.evaluate("navigator.clipboard.writeText('pasted.txt\\n')");
  await tab.type('G"+p');
  await sleep(800);
  await tab.shot("pasted");
  await apply(tab, "paste");
  if (await tab.exists("pasted.txt") !== true) problems.push("\"+p didn't paste the browser's clipboard");

  // A second tab: Koil is open in the first, until Use Koil Here.
  const second = await connect((await (await fetch(devtools(`new?${url}`), { method: "PUT" })).json())
    .webSocketDebuggerUrl, "second tab");
  await sleep(3000);
  await second.shot("second-tab");
  if (await second.status() !== "Koil is open in another tab.")
    problems.push(`the second tab says “${await second.status()}”`);
  if (await second.evaluate("window.koil === undefined") !== true)
    problems.push("Koil started in the second tab too");
  await second.evaluate("document.getElementById('use-here').click()");
  await second.loaded();
  await second.shot("second-tab-took");
  if (await tab.status() !== "Koil is open in another tab now.")
    problems.push(`the first tab says “${await tab.status()}”`);
  for (const name of ["welcome.txt", "dropped.txt", "pasted.txt"]) {
    if (await second.exists(name) !== true) problems.push(`the second tab hasn't ${name}`);
  }
} catch (error) {
  problems.push(String(error));
}

for (const socket of sockets) socket.close();
chrome.kill();
server.close();
await sleep(200);
rmSync(profile, { recursive: true, force: true });
for (const problem of problems) fail(problem);
if (!problems.length) console.log("web-smoke: ok");
process.exit();
