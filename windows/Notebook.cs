using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace MeetinOS;

// Habillage avec la marque (brand/tokens.css) : crème, surface, encre, citron, titres serif.
// EB Garamond et Figtree ne sont pas embarquées : Georgia et Segoe UI sont les polices de repli du site.
internal sealed class Notebook : Form
{
    private static readonly Color Canvas = ColorTranslator.FromHtml("#FAF8F1");
    private static readonly Color Surface = ColorTranslator.FromHtml("#EDE9DA");
    private static readonly Color Line = ColorTranslator.FromHtml("#D9D3BF");
    private static readonly Color Ink = ColorTranslator.FromHtml("#14201C");
    private static readonly Color Muted = ColorTranslator.FromHtml("#5B665F");
    private static readonly Color Accent = ColorTranslator.FromHtml("#CFE86B");
    private static readonly Color Rec = ColorTranslator.FromHtml("#C8341C");
    private static readonly Font Serif = new("Georgia", 26);
    private static readonly Font SerifSmall = new("Georgia", 15);
    private static readonly Font Sans = new("Segoe UI", 10);
    private static readonly Font SansBold = new("Segoe UI Semibold", 10);

    private readonly Button record = ActionButton("Enregistrer", true);
    private readonly Button import = ActionButton("Importer un audio");
    private readonly Button folder = ActionButton("Voir les pistes");
    private readonly Button transcribe = ActionButton("Transcrire avec Gladia", true);
    private readonly Button copy = ActionButton("Copier la transcription");
    private readonly Button openAgent = ActionButton("Ouvrir l’espace agent", true);
    private readonly Button save = ActionButton("Enregistrer les réglages", true);
    private readonly TextBox notes = Editor("Notes de réunion");
    private readonly TextBox transcript = Editor("Transcription", true);
    private readonly TextBox key = Field("Clé API Gladia", true);
    private readonly TextBox site = Field("Adresse du site Meetin-OS");
    private readonly Label status = new() { Dock = DockStyle.Fill, AutoEllipsis = true, ForeColor = Muted, TextAlign = ContentAlignment.MiddleLeft, AccessibleName = "État du carnet" };
    private readonly ListBox meetings = new() { Dock = DockStyle.Fill, BorderStyle = BorderStyle.None, BackColor = Canvas, ForeColor = Ink, IntegralHeight = false, ItemHeight = 30, DrawMode = DrawMode.OwnerDrawFixed, AccessibleName = "Réunions enregistrées" };
    private readonly Panel pages = new() { Dock = DockStyle.Fill, BackColor = Canvas };
    private readonly Dictionary<string, Panel> pageByName = new();
    private readonly Dictionary<string, Button> navByName = new();
    private readonly GladiaClient gladia = new();
    private List<AudioTrack> tracks = new();
    private AudioCapture? capture;
    private CancellationTokenSource? transcriptionCancellation;
    private string? audioFolder;
    private string apiKey = Environment.GetEnvironmentVariable("GLADIA_API_KEY")?.Trim() ?? "";
    private Uri agentSite = SiteUri(Environment.GetEnvironmentVariable("MEETIN_WEB_URL")) ?? new Uri("http://localhost:3000");
    private bool busy;

    private static string RecordingsRoot => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Meetin-OS", "Recordings");

    public Notebook()
    {
        Text = "Meetin-OS";
        Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(960, 600);
        MinimumSize = new Size(800, 520);
        Font = Sans;
        BackColor = Canvas;
        ForeColor = Ink;
        AutoScaleMode = AutoScaleMode.Dpi;

        var shell = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 2 };
        shell.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 220));
        shell.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        shell.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        shell.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
        shell.Controls.Add(Sidebar(), 0, 0);
        shell.SetRowSpan(shell.GetControlFromPosition(0, 0), 2);
        shell.Controls.Add(pages, 1, 0);
        var statusBar = new Panel { Dock = DockStyle.Fill, Padding = new Padding(28, 0, 28, 0), BackColor = Canvas };
        statusBar.Controls.Add(status);
        shell.Controls.Add(statusBar, 1, 1);
        Controls.Add(shell);

        AddPage("Accueil", HomePage());
        AddPage("Réunions", MeetingsPage());
        AddPage("Agent", AgentPage());
        AddPage("Paramètres", SettingsPage());
        ShowPage("Accueil");

        record.Click += async (_, _) => await RecordAsync();
        import.Click += (_, _) => ImportAudio();
        transcribe.Click += async (_, _) => await TranscribeAsync();
        folder.Click += (_, _) => { if (audioFolder != null) Open(audioFolder); };
        copy.Click += (_, _) => { if (transcript.TextLength > 0) Clipboard.SetText(transcript.Text); };
        openAgent.Click += (_, _) => Open(new Uri(agentSite, "/agent").AbsoluteUri);
        save.Click += (_, _) => SaveSettings();
        meetings.DoubleClick += (_, _) => OpenSelectedMeeting();
        meetings.DrawItem += DrawMeeting;
        FormClosing += (_, args) =>
        {
            if (capture == null) { transcriptionCancellation?.Cancel(); return; }
            args.Cancel = true;
            capture.Stop();
            status.Text = "Finalisation de l’enregistrement…";
        };
        status.Text = "Prêt à enregistrer le micro et la sortie audio par défaut de Windows.";
        RefreshActions();
    }

    private Control Sidebar()
    {
        var side = new TableLayoutPanel { Dock = DockStyle.Fill, BackColor = Surface, ColumnCount = 1, RowCount = 3, Padding = new Padding(16, 22, 16, 18) };
        side.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        side.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        side.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        var brand = new Label { Text = "Meetin-OS", Font = SerifSmall, AutoSize = true, Margin = new Padding(10, 0, 0, 22) };
        side.Controls.Add(brand, 0, 0);
        var nav = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false };
        foreach (var name in new[] { "Accueil", "Réunions", "Agent", "Paramètres" })
        {
            var button = NavButton(name);
            button.Click += (_, _) => ShowPage(name);
            navByName[name] = button;
            nav.Controls.Add(button);
        }
        side.Controls.Add(nav, 0, 1);
        side.Controls.Add(new Label { Text = "Windows · " + Application.ProductVersion.Split('+')[0], ForeColor = Muted, AutoSize = true, Margin = new Padding(10, 0, 0, 0) }, 0, 2);
        return side;
    }

    private Panel HomePage()
    {
        var page = Page();
        var grid = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 3 };
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        grid.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        grid.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        grid.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        var heading = Heading("Carnet de réunion", "Enregistre le micro et l’audio de l’appel, puis transcris avec Gladia.");
        grid.Controls.Add(heading, 0, 0);
        grid.SetColumnSpan(heading, 2);
        var actions = Row(record, import);
        grid.Controls.Add(actions, 0, 1);
        grid.SetColumnSpan(actions, 2);
        grid.Controls.Add(Card("Notes", notes), 0, 2);
        grid.Controls.Add(Card("Transcription", transcript, Row(transcribe, folder, copy)), 1, 2);
        page.Controls.Add(grid);
        return page;
    }

    private Panel MeetingsPage()
    {
        var page = Page();
        var grid = Stack();
        grid.Controls.Add(Heading("Réunions", "Les enregistrements de ce PC. Double-clic pour ouvrir le dossier des pistes."), 0, 0);
        grid.Controls.Add(Card("Historique", meetings), 0, 1);
        page.Controls.Add(grid);
        return page;
    }

    private Panel AgentPage()
    {
        var page = Page();
        var grid = Stack();
        grid.Controls.Add(Heading("Agent", "Copie un extrait de la transcription et relis la tâche dans l’espace agent du site."), 0, 0);
        grid.Controls.Add(Row(copy, openAgent), 0, 1);
        page.Controls.Add(grid);
        return page;
    }

    private Panel SettingsPage()
    {
        var page = Page();
        var grid = Stack();
        grid.Controls.Add(Heading("Paramètres", "La clé Gladia reste en mémoire le temps de la session, jamais sur le disque."), 0, 0);
        var fields = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoSize = true };
        fields.Controls.Add(FieldLabel("Clé API Gladia"));
        fields.Controls.Add(key);
        fields.Controls.Add(FieldLabel("Adresse du site Meetin-OS"));
        fields.Controls.Add(site);
        fields.Controls.Add(save);
        grid.Controls.Add(fields, 0, 1);
        page.Controls.Add(grid);
        key.Text = apiKey;
        site.Text = agentSite.GetLeftPart(UriPartial.Authority);
        return page;
    }

    private void AddPage(string name, Panel page)
    {
        page.Visible = false;
        pageByName[name] = page;
        pages.Controls.Add(page);
    }

    private void ShowPage(string name)
    {
        foreach (var pair in pageByName) pair.Value.Visible = pair.Key == name;
        foreach (var pair in navByName)
        {
            pair.Value.BackColor = pair.Key == name ? Canvas : Surface;
            pair.Value.Font = pair.Key == name ? SansBold : Sans;
        }
        if (name == "Réunions") RefreshMeetings();
    }

    private void RefreshMeetings()
    {
        meetings.Items.Clear();
        if (!Directory.Exists(RecordingsRoot)) return;
        foreach (var dir in new DirectoryInfo(RecordingsRoot).GetDirectories().OrderByDescending(d => d.Name))
        {
            var files = dir.GetFiles("*.wav");
            if (files.Length == 0) continue;
            var when = dir.Name.Length >= 19 && DateTime.TryParseExact(dir.Name.Substring(0, 19), "yyyy-MM-dd_HH-mm-ss", null, System.Globalization.DateTimeStyles.None, out var date)
                ? date.ToString("dddd d MMMM yyyy · HH:mm") : dir.Name;
            meetings.Items.Add(new MeetingEntry(dir.FullName, when, files.Length == 2 ? "Micro + appel" : files[0].Name));
        }
    }

    private void OpenSelectedMeeting()
    {
        if (meetings.SelectedItem is MeetingEntry entry) Open(entry.Folder);
    }

    private void DrawMeeting(object? sender, DrawItemEventArgs e)
    {
        if (e.Index < 0 || meetings.Items[e.Index] is not MeetingEntry entry) return;
        var selected = (e.State & DrawItemState.Selected) != 0;
        using var back = new SolidBrush(selected ? Surface : Canvas);
        e.Graphics.FillRectangle(back, e.Bounds);
        TextRenderer.DrawText(e.Graphics, entry.Title, SansBold, new Point(e.Bounds.X + 8, e.Bounds.Y + 6), Ink);
        var width = TextRenderer.MeasureText(entry.Detail, Sans).Width;
        TextRenderer.DrawText(e.Graphics, entry.Detail, Sans, new Point(e.Bounds.Right - width - 8, e.Bounds.Y + 6), Muted);
    }

    private sealed class MeetingEntry
    {
        public MeetingEntry(string folder, string title, string detail) { Folder = folder; Title = title; Detail = detail; }
        public string Folder { get; }
        public string Title { get; }
        public string Detail { get; }
    }

    private async Task RecordAsync()
    {
        AudioCapture? recording = null;
        busy = true;
        RefreshActions();
        try
        {
            status.Text = "Ouverture du micro et de la sortie audio…";
            capture = recording = new AudioCapture();
            await recording.Started;
            transcript.Clear();
            notes.ReadOnly = true;
            status.Text = "Enregistrement en cours";
            using var meeting = new Form
            {
                Text = "Réunion en cours · Meetin-OS", Icon = Icon, ClientSize = new Size(680, 420),
                MinimumSize = new Size(560, 340), StartPosition = FormStartPosition.CenterParent,
                BackColor = Canvas, ForeColor = Ink, Font = Font, ShowInTaskbar = false
            };
            var meetingNotes = Editor("Notes pendant la réunion");
            meetingNotes.Text = notes.Text;
            var stop = ActionButton("Arrêter l’enregistrement", false, Rec, Color.White);
            var elapsed = Stopwatch.StartNew();
            var indicator = new Label { AutoSize = true, ForeColor = Rec, Font = SansBold, Text = "●  EN COURS", Margin = new Padding(0, 8, 18, 0) };
            using var timer = new System.Windows.Forms.Timer { Interval = 500 };
            timer.Tick += (_, _) => indicator.Text = $"●  EN COURS  {elapsed.Elapsed:hh\\:mm\\:ss}";
            stop.Click += (_, _) =>
            {
                stop.Enabled = false;
                timer.Stop();
                indicator.Text = "Finalisation…";
                recording.Stop();
            };
            meeting.FormClosing += (_, args) =>
            {
                if (capture != recording) return;
                args.Cancel = true;
                recording.Stop();
            };
            var panel = Stack();
            panel.Padding = new Padding(28);
            panel.Controls.Add(Heading("Réunion en cours", "Les deux pistes s’enregistrent. Prends tes notes ici."), 0, 0);
            panel.Controls.Add(Row(indicator, stop), 0, 1);
            panel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            panel.RowCount = 3;
            panel.Controls.Add(Card("Notes de réunion", meetingNotes), 0, 2);
            meeting.Controls.Add(panel);
            meeting.Show(this);
            timer.Start();

            var result = await recording.Finished;
            capture = null;
            notes.Text = meetingNotes.Text;
            meeting.Close();
            tracks = result.Tracks;
            audioFolder = tracks.Count > 0 ? recording.Folder : null;
            status.Text = tracks.Count == 2 ? "Deux pistes enregistrées." : "Pistes disponibles : " + tracks.Count + ".";
            if (result.Warnings.Count > 0) status.Text += " " + string.Join(" ", result.Warnings);
            ShowPage("Accueil");
            if (result.MicrophoneDenied) OfferMicrophoneSettings();
        }
        catch (Exception error) { status.Text = error.Message; }
        finally
        {
            recording?.Stop();
            capture = null;
            notes.ReadOnly = false;
            busy = false;
            RefreshActions();
        }
    }

    private void ImportAudio()
    {
        using var dialog = new OpenFileDialog { Title = "Importer un enregistrement", Filter = "Audio|*.wav;*.mp3;*.m4a;*.ogg;*.flac;*.webm" };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        tracks = new List<AudioTrack> { new(dialog.FileName) };
        audioFolder = Path.GetDirectoryName(dialog.FileName);
        transcript.Clear();
        status.Text = "Audio importé : " + Path.GetFileName(dialog.FileName);
        RefreshActions();
    }

    private async Task TranscribeAsync()
    {
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            status.Text = "Saisis ta clé Gladia dans Paramètres pour transcrire.";
            ShowPage("Paramètres");
            key.Focus();
            return;
        }

        using var cancellation = new CancellationTokenSource();
        transcriptionCancellation = cancellation;
        busy = true;
        RefreshActions();
        status.Text = "Envoi de l’audio à Gladia et attente de la transcription…";
        try
        {
            var text = await gladia.TranscribeAsync(tracks, apiKey, cancellation.Token);
            if (IsDisposed) return;
            transcript.Text = text;
            status.Text = "Transcription terminée.";
        }
        catch (OperationCanceledException)
        {
            if (!IsDisposed) status.Text = "Gladia n’a pas répondu dans le délai imparti. Tu peux réessayer.";
        }
        catch (Exception error) { if (!IsDisposed) status.Text = error.Message; }
        finally
        {
            transcriptionCancellation = null;
            busy = false;
            if (!IsDisposed) RefreshActions();
        }
    }

    private void SaveSettings()
    {
        var address = SiteUri(site.Text.Trim());
        if (address == null)
        {
            MessageBox.Show(this, "Indique une adresse HTTPS ou une adresse locale HTTP.", "Adresse invalide");
            return;
        }
        apiKey = key.Text.Trim();
        agentSite = address;
        status.Text = "Réglages enregistrés pour cette session.";
        ShowPage("Accueil");
    }

    private static Uri? SiteUri(string? address) => Uri.TryCreate(address, UriKind.Absolute, out var uri) &&
        string.IsNullOrEmpty(uri.UserInfo) && !string.IsNullOrEmpty(uri.Host) &&
        (uri.Scheme == Uri.UriSchemeHttps || (uri.Scheme == Uri.UriSchemeHttp && uri.IsLoopback)) ? uri : null;

    private void OfferMicrophoneSettings()
    {
        var answer = MessageBox.Show(this,
            "Windows bloque l’accès au micro pour les applications de bureau : micro.wav n’a pas été enregistré, seul appel.wav l’est.\n\n" +
            "Dans Paramètres > Confidentialité > Microphone, active « Autoriser l’accès au microphone sur cet appareil » et « Autoriser les applications de bureau à accéder à votre microphone », puis relance l’enregistrement.\n\n" +
            "Ouvrir ces paramètres maintenant ?",
            "Micro refusé par Windows", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
        if (answer == DialogResult.Yes) Open("ms-settings:privacy-microphone");
    }

    private void Open(string path)
    {
        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); }
        catch (Exception error) { status.Text = error.Message; }
    }

    private void RefreshActions()
    {
        record.Enabled = import.Enabled = save.Enabled = !busy;
        transcribe.Enabled = !busy && tracks.Count > 0;
        folder.Enabled = !busy && audioFolder != null;
        copy.Enabled = !busy && transcript.TextLength > 0;
    }

    private static Button ActionButton(string text, bool primary = false, Color? back = null, Color? fore = null)
    {
        var button = new Button
        {
            Text = text, AutoSize = true, MinimumSize = new Size(0, 38), Padding = new Padding(14, 0, 14, 0), Margin = new Padding(0, 0, 10, 10),
            FlatStyle = FlatStyle.Flat, BackColor = back ?? (primary ? Accent : Surface), ForeColor = fore ?? Ink, Cursor = Cursors.Hand, UseVisualStyleBackColor = false
        };
        button.FlatAppearance.BorderSize = 0;
        button.FlatAppearance.MouseOverBackColor = ControlPaint.Dark(button.BackColor, 0.05f);
        button.EnabledChanged += (_, _) => button.ForeColor = button.Enabled ? (fore ?? Ink) : Muted;
        return button;
    }

    private static Button NavButton(string text) => new()
    {
        Text = text, Width = 188, Height = 38, TextAlign = ContentAlignment.MiddleLeft, Padding = new Padding(8, 0, 0, 0), Margin = new Padding(0, 0, 0, 4),
        FlatStyle = FlatStyle.Flat, BackColor = Surface, ForeColor = Ink, Cursor = Cursors.Hand, UseVisualStyleBackColor = false, FlatAppearance = { BorderSize = 0 }
    };

    private static TextBox Editor(string label, bool readOnly = false) => new()
    {
        AccessibleName = label, Multiline = true, Dock = DockStyle.Fill, BorderStyle = BorderStyle.None,
        ScrollBars = ScrollBars.Vertical, ReadOnly = readOnly, BackColor = Color.White, ForeColor = Ink
    };

    private static TextBox Field(string label, bool secret = false) => new()
    {
        AccessibleName = label, UseSystemPasswordChar = secret, Width = 420, BackColor = Color.White, ForeColor = Ink, BorderStyle = BorderStyle.FixedSingle, Margin = new Padding(0, 0, 0, 16)
    };

    private static Label FieldLabel(string text) => new() { Text = text, AutoSize = true, Font = SansBold, Margin = new Padding(0, 0, 0, 6) };

    private static Panel Page() => new() { Dock = DockStyle.Fill, BackColor = Canvas, Padding = new Padding(32, 28, 32, 12) };

    private static TableLayoutPanel Stack()
    {
        var panel = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 2 };
        panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        panel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        return panel;
    }

    private static Control Heading(string title, string subtitle)
    {
        var block = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, Margin = new Padding(0, 0, 0, 14) };
        block.Controls.Add(new Label { Text = title, Font = Serif, AutoSize = true, Margin = new Padding(0) });
        block.Controls.Add(new Label { Text = subtitle, ForeColor = Muted, AutoSize = true, Margin = new Padding(2, 4, 0, 0) });
        return block;
    }

    private static Control Card(string title, Control body, Control? toolbar = null)
    {
        var card = new TableLayoutPanel { Dock = DockStyle.Fill, BackColor = Surface, ColumnCount = 1, RowCount = 3, Padding = new Padding(14), Margin = new Padding(0, 0, 12, 12) };
        card.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        card.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        card.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        card.Controls.Add(new Label { Text = title, Font = SansBold, AutoSize = true, Margin = new Padding(0, 0, 0, 8) }, 0, 0);
        if (toolbar != null) card.Controls.Add(toolbar, 0, 1);
        var frame = new Panel { Dock = DockStyle.Fill, BackColor = Color.White, Padding = new Padding(8) };
        frame.Controls.Add(body);
        card.Controls.Add(frame, 0, 2);
        return card;
    }

    private static FlowLayoutPanel Row(params Control[] controls)
    {
        var row = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, WrapContents = true, Margin = new Padding(0) };
        row.Controls.AddRange(controls);
        return row;
    }
}
