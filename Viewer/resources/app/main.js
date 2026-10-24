// ReStreet viewer: opens the launcher page, and only that page, in a window of its own.
// The launcher starts it as:  ReStreetViewer.exe --no-sandbox --restreet-url=<url> --restreet-size=<w>,<h>
const { app, BrowserWindow } = require('electron');
const net = require('net');

const arg = (name) => {
  const hit = process.argv.find((a) => a.startsWith(name + '='));
  return hit ? hit.slice(name.length + 1) : '';
};

// Only the launcher's own page is accepted: loopback, a random 32-character secret path, launcher.html.
const url = arg('--restreet-url');
const valid = /^http:\/\/127\.0\.0\.1:\d+\/[0-9a-f]{32}\/launcher\.html$/.test(url);
if (!valid) app.exit(1);

// Wine and Proton: the GPU process is the usual thing that fails, and a launcher page does not need it.
// RESTREET_VIEWER_GPU=1 turns hardware acceleration back on.
if (process.env.RESTREET_VIEWER_GPU !== '1') app.disableHardwareAcceleration();
app.commandLine.appendSwitch('no-sandbox');

const [w, h] = (arg('--restreet-size').split(',').map(Number).filter((n) => n > 0));
const origin = valid ? new URL(url).origin : '';

app.whenReady().then(() => {
  if (!valid) return;
  const win = new BrowserWindow({
    width: Math.max(w || 1250, 900),
    height: Math.max(h || 720, 560),
    minWidth: 900,
    minHeight: 560,
    title: 'Launcher - ReStreet',
    backgroundColor: '#0b0c12',
    autoHideMenuBar: true,
    show: false,
    // A normal frame: the page's own drag and minimize buttons are not used when it runs in a browser window.
    webPreferences: { contextIsolation: true, nodeIntegration: false },
  });
  win.removeMenu();
  win.on('page-title-updated', (e) => e.preventDefault());
  win.once('ready-to-show', () => win.show());

  // The page never leaves the launcher: no pop-ups, no navigation elsewhere.
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.webContents.on('will-navigate', (e, target) => { if (!target.startsWith(origin + '/')) e.preventDefault(); });

  // The launcher's server may need a moment: try again a few times before giving up.
  let tries = 0;
  win.webContents.on('did-fail-load', (_e, _code, _desc, _u, isMainFrame) => {
    if (isMainFrame && tries++ < 5) setTimeout(() => win.loadURL(url), 1000);
  });
  win.loadURL(url);
});

// If the launcher goes away (it was closed for an update, or it crashed), close this window too instead of leaving a
// dead page on screen. A plain TCP connect to the launcher's port every few seconds; three misses in a row quit.
function watchLauncher() {
  const port = Number(new URL(url).port);
  let misses = 0;
  setInterval(() => {
    const socket = net.connect({ host: '127.0.0.1', port, timeout: 4000 });
    let done = false;
    const finish = (ok) => {
      if (done) return;
      done = true;
      socket.destroy();
      misses = ok ? 0 : misses + 1;
      if (misses >= 3) app.quit();
    };
    socket.once('connect', () => finish(true));
    socket.once('error', () => finish(false));
    socket.once('timeout', () => finish(false));
  }, 5000);
}
if (valid) app.whenReady().then(() => setTimeout(watchLauncher, 15000));

app.on('window-all-closed', () => app.quit());
