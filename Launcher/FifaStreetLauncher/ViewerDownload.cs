using System.Diagnostics;
using System.IO.Compression;
using System.Security.Cryptography;
using ReStreet.Ui;

namespace FifaStreetLauncher;

// Wine/Proton only: if Viewer\ReStreetViewer.exe is not next to the launcher, download ReStreet-Viewer.zip once from the
// fixed "viewer" release of the repository (built by .github/workflows/publish-viewer.yml), check its SHA-256 and unpack it.
// The viewer never changes between launcher versions, so one release serves every launcher version.
// A small progress window shows the download. RESTREET_NO_VIEWER_DOWNLOAD=1 turns all of this off.
// Any failure only means the browser fallback is used, as before.
public partial class LauncherForm
{
    private const string ViewerZipUrl = "https://github.com/samuelit0davila/fifa-street-pc-port/releases/download/viewer/ReStreet-Viewer.zip";
    private const string ViewerShaUrl = ViewerZipUrl + ".sha256";

    // While true the classic window stays hidden (RevealWindow checks it), so only the progress window is on screen.
    private bool viewerDownloading;

    private async Task EnsureViewerAsync()
    {
        if (Environment.GetEnvironmentVariable("RESTREET_NO_VIEWER_DOWNLOAD") == "1") return;
        string root = AppContext.BaseDirectory;
        string viewer = Path.Combine(root, "Viewer");
        if (File.Exists(Path.Combine(viewer, "ReStreetViewer.exe"))) return;
        string temp = Path.Combine(root, "Viewer.download");
        ViewerProgressForm? progress = null;
        viewerDownloading = true;
        try
        {
            BrowserLog("Viewer missing; downloading " + ViewerZipUrl);
            using var http = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
            http.DefaultRequestHeaders.UserAgent.ParseAdd("ReStreetLauncher/" + LauncherVersion);
            string expected = (await http.GetStringAsync(ViewerShaUrl)).Trim().Split(' ', '\t')[0].ToLowerInvariant();
            if (Directory.Exists(temp)) Directory.Delete(temp, true);
            Directory.CreateDirectory(temp);
            progress = new ViewerProgressForm(Icon);
            progress.Show();
            progress.Set("Downloading the ReStreet window (first launch only)", "Connecting...", 0);
            string zip = Path.Combine(temp, "ReStreet-Viewer.zip");
            using (var response = await http.GetAsync(ViewerZipUrl, HttpCompletionOption.ResponseHeadersRead))
            {
                response.EnsureSuccessStatusCode();
                long? total = response.Content.Headers.ContentLength;
                await using var input = await response.Content.ReadAsStreamAsync();
                await using var output = File.Create(zip);
                var buffer = new byte[81920];
                long done = 0;
                var lastPaint = DateTime.UtcNow;
                int n;
                while ((n = await input.ReadAsync(buffer)) > 0)
                {
                    await output.WriteAsync(buffer.AsMemory(0, n));
                    done += n;
                    if (DateTime.UtcNow - lastPaint > TimeSpan.FromMilliseconds(100))
                    {
                        lastPaint = DateTime.UtcNow;
                        string detail = total is > 0
                            ? $"{done / 1048576.0:0.0} / {total.Value / 1048576.0:0.0} MB  ({100.0 * done / total.Value:0}%)"
                            : $"{done / 1048576.0:0.0} MB";
                        progress.Set("Downloading the ReStreet window (first launch only)", detail, total is > 0 ? (double)done / total.Value : -1);
                    }
                }
            }
            progress.Set("Checking the download", "", -1);
            string actual;
            await using (var check = File.OpenRead(zip))
                actual = Convert.ToHexString(await SHA256.HashDataAsync(check)).ToLowerInvariant();
            if (actual != expected) { BrowserLog("Viewer download rejected: SHA-256 mismatch."); return; }
            progress.Set("Unpacking", "This takes a few seconds", -1);
            string extracted = Path.Combine(temp, "extracted");
            await Task.Run(() => ZipFile.ExtractToDirectory(zip, extracted));
            // The zip holds a top-level "Viewer" folder (build-viewer.ps1 includes the base directory); accept a flat zip too.
            string unpacked = File.Exists(Path.Combine(extracted, "Viewer", "ReStreetViewer.exe")) ? Path.Combine(extracted, "Viewer") : extracted;
            if (!File.Exists(Path.Combine(unpacked, "ReStreetViewer.exe"))) { BrowserLog("Viewer download rejected: no ReStreetViewer.exe inside."); return; }
            if (Directory.Exists(viewer)) Directory.Delete(viewer, true);
            Directory.Move(unpacked, viewer);
            BrowserLog("Viewer installed at " + viewer);
        }
        catch (Exception ex) when (ex is HttpRequestException or IOException or InvalidDataException or UnauthorizedAccessException or TaskCanceledException)
        {
            BrowserLog("Viewer download failed: " + ex.Message);
        }
        finally
        {
            viewerDownloading = false;
            progress?.Close();
            progress?.Dispose();
            try { if (Directory.Exists(temp)) Directory.Delete(temp, true); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { Debug.WriteLine(ex.Message); }
        }
    }

    // A small window in the launcher's colours: title, one line of status, a bar and the size done.
    private sealed class ViewerProgressForm : Form
    {
        private double fraction = -1;  // below 0: the bar just moves (size unknown, or a step with no percentage)
        private string status = "";
        private string detail = "";
        private int tick;
        private readonly System.Windows.Forms.Timer anim = new() { Interval = 40 };

        public ViewerProgressForm(Icon? icon)
        {
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(460, 120);
            BackColor = StreetTheme.Asphalt;
            ShowInTaskbar = true;
            TopMost = true;
            Text = "ReStreet";
            if (icon != null) Icon = icon;
            DoubleBuffered = true;
            anim.Tick += (_, _) => { tick++; if (fraction < 0) Invalidate(); };
            anim.Start();
        }

        public void Set(string newStatus, string newDetail, double newFraction)
        {
            status = newStatus;
            detail = newDetail;
            fraction = newFraction;
            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            using (var border = new Pen(StreetTheme.Yellow, 2)) g.DrawRectangle(border, 1, 1, Width - 3, Height - 3);
            using var title = StreetTheme.Condensed(16, FontStyle.Bold);
            using var body = StreetTheme.Body(10);
            using var small = StreetTheme.Body(9);
            TextRenderer.DrawText(g, "RESTREET", title, new Point(22, 14), StreetTheme.Yellow);
            TextRenderer.DrawText(g, status, body, new Point(22, 46), StreetTheme.Ink);
            var bar = new Rectangle(22, 78, Width - 44, 10);
            using (var back = new SolidBrush(StreetTheme.PanelFlat)) g.FillRectangle(back, bar);
            using (var fill = new SolidBrush(StreetTheme.Yellow))
            {
                if (fraction >= 0)
                    g.FillRectangle(fill, bar.X, bar.Y, (int)(bar.Width * Math.Min(1.0, fraction)), bar.Height);
                else
                {
                    int seg = 110;
                    int x = (tick * 7) % (bar.Width + seg) - seg;
                    int left = Math.Max(0, x), right = Math.Min(bar.Width, x + seg);
                    if (right > left) g.FillRectangle(fill, bar.X + left, bar.Y, right - left, bar.Height);
                }
            }
            TextRenderer.DrawText(g, detail, small, new Point(22, 94), StreetTheme.Muted);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) anim.Dispose();
            base.Dispose(disposing);
        }
    }
}
