using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace MeetinOS;

internal sealed class Notebook : Form
{
    private static readonly Color Canvas = ColorTranslator.FromHtml("#FAF8F1");
    private static readonly Color Ink = ColorTranslator.FromHtml("#14201C");
    private static readonly Color Accent = ColorTranslator.FromHtml("#CFE86B");
    private static readonly Color Rec = ColorTranslator.FromHtml("#C8341C");
    private readonly Button record = ActionButton("Enregistrer", true);
    private readonly Button import = ActionButton("Importer un audio");
    private readonly Button settings = ActionButton("Réglages");
    private readonly Button folder = ActionButton("Voir les pistes");
    private readonly Button transcribe = ActionButton("Transcrire avec Gladia", true);
    private readonly Button copy = ActionButton("Copier la transcription");
    private readonly TextBox notes = Editor("Notes de réunion");
    private readonly TextBox transcript = Editor("Transcription", true);
    private readonly Label status = new() { Dock = DockStyle.Fill, Height = 42, AutoEllipsis = true, AccessibleName = "État du carnet" };
    private readonly TabControl tabs = new() { Dock = DockStyle.Fill };
    private readonly TabPage transcriptionTab = new("Transcription");
    private readonly GladiaClient gladia = new();
    private List<AudioTrack> tracks = new();
    private AudioCapture? capture;
    private CancellationTokenSource? transcriptionCancellation;
    private string? audioFolder;
    private string apiKey = Environment.GetEnvironmentVariable("GLADIA_API_KEY")?.Trim() ?? "";
    private Uri agentSite = SiteUri(Environment.GetEnvironmentVariable("MEETIN_WEB_URL")) ?? new Uri("http://localhost:3000");
    private bool busy;

    public Notebook()
    {
        Text = "Meetin-OS";
        Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(720, 490);
        MinimumSize = new Size(640, 420);
        Font = new Font("Segoe UI", 10);
        BackColor = Canvas;
        ForeColor = Ink;
        AutoScaleMode = AutoScaleMode.Font;

        var content = NotebookLayout();
        var title = new Label { Text = "Carnet de réunion", Font = new Font("Georgia", 25), AutoSize = true };
        content.Controls.Add(title, 0, 0);
        content.Controls.Add(Row(record, import, settings), 0, 1);
        content.Controls.Add(tabs, 0, 2);
        content.Controls.Add(status, 0, 3);
        Controls.Add(content);

        var notesTab = new TabPage("Notes");
        notesTab.Controls.Add(notes);
        tabs.TabPages.Add(notesTab);
        var transcriptPanel = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 2, Padding = new Padding(8) };
        transcriptPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        transcriptPanel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        transcriptPanel.Controls.Add(Row(transcribe, folder), 0, 0);
        transcriptPanel.Controls.Add(transcript, 0, 1);
        transcriptionTab.Controls.Add(transcriptPanel);
        tabs.TabPages.Add(transcriptionTab);

        var agentTab = new TabPage("Agent");
        var openAgent = ActionButton("Ouvrir l’espace agent", true);
        var agentActions = new FlowLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(14), FlowDirection = FlowDirection.TopDown };
        agentActions.Controls.Add(new Label { AutoSize = true, Text = "Copie un extrait de la transcription et relis la tâche dans l’espace agent." });
        agentActions.Controls.Add(Row(copy, openAgent));
        agentTab.Controls.Add(agentActions);
        tabs.TabPages.Add(agentTab);

        record.Click += async (_, _) => await RecordAsync();
        import.Click += (_, _) => ImportAudio();
        settings.Click += (_, _) => ShowSettings();
        transcribe.Click += async (_, _) => await TranscribeAsync();
        folder.Click += (_, _) => { if (audioFolder != null) Open(audioFolder); };
        copy.Click += (_, _) => { if (transcript.TextLength > 0) Clipboard.SetText(transcript.Text); };
        openAgent.Click += (_, _) => Open(new Uri(agentSite, "/agent").AbsoluteUri);
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
                Text = "Réunion en cours · Meetin-OS", Icon = Icon, ClientSize = new Size(630, 390),
                MinimumSize = new Size(520, 320), StartPosition = FormStartPosition.CenterParent,
                BackColor = Canvas, ForeColor = Ink, Font = Font, ShowInTaskbar = false
            };
            var meetingNotes = Editor("Notes pendant la réunion");
            meetingNotes.Text = notes.Text;
            var stop = ActionButton("Arrêter l’enregistrement");
            var elapsed = Stopwatch.StartNew();
            var indicator = new Label { AutoSize = true, ForeColor = Rec, Text = "●  EN COURS" };
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
            var panel = NotebookLayout();
            panel.Controls.Add(Row(indicator, stop), 0, 0);
            panel.Controls.Add(new Label { Text = "Notes de réunion", AutoSize = true }, 0, 1);
            panel.Controls.Add(meetingNotes, 0, 2);
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
            tabs.SelectedTab = transcriptionTab;
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
        tabs.SelectedTab = transcriptionTab;
        RefreshActions();
    }

    private async Task TranscribeAsync()
    {
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            status.Text = "Saisis ta clé Gladia dans les réglages pour transcrire.";
            ShowSettings();
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

    private void ShowSettings()
    {
        using var dialog = new Form
        {
            Text = "Réglages · Meetin-OS", ClientSize = new Size(455, 222), StartPosition = FormStartPosition.CenterParent,
            FormBorderStyle = FormBorderStyle.FixedDialog, MinimizeBox = false, MaximizeBox = false, ShowInTaskbar = false,
            Font = Font, BackColor = Canvas, ForeColor = Ink
        };
        var key = new TextBox { UseSystemPasswordChar = true, Text = apiKey, Width = 400, AccessibleName = "Clé API Gladia" };
        var site = new TextBox { Text = agentSite.GetLeftPart(UriPartial.Authority), Width = 400, AccessibleName = "Adresse du site Meetin-OS" };
        var save = ActionButton("Enregistrer", true);
        var fields = new FlowLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(14), FlowDirection = FlowDirection.TopDown, WrapContents = false };
        fields.Controls.Add(new Label { AutoSize = true, Text = "Clé API Gladia · session en cours" });
        fields.Controls.Add(key);
        fields.Controls.Add(new Label { AutoSize = true, Text = "Adresse du site Meetin-OS" });
        fields.Controls.Add(site);
        fields.Controls.Add(save);
        dialog.Controls.Add(fields);
        dialog.AcceptButton = save;
        save.Click += (_, _) =>
        {
            var address = SiteUri(site.Text.Trim());
            if (address == null)
            {
                MessageBox.Show(dialog, "Indique une adresse HTTPS ou une adresse locale HTTP.", "Adresse invalide");
                return;
            }
            apiKey = key.Text.Trim();
            agentSite = address;
            dialog.Close();
        };
        dialog.ShowDialog(this);
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
        record.Enabled = import.Enabled = settings.Enabled = !busy;
        transcribe.Enabled = !busy && tracks.Count > 0;
        folder.Enabled = !busy && audioFolder != null;
        copy.Enabled = !busy && transcript.TextLength > 0;
    }

    private static Button ActionButton(string text, bool primary = false)
    {
        var button = new Button { Text = text, AutoSize = true, MinimumSize = new Size(0, 34), Padding = new Padding(8, 0, 8, 0) };
        if (primary) { button.BackColor = Accent; button.ForeColor = Ink; button.FlatStyle = FlatStyle.Flat; }
        return button;
    }

    private static TextBox Editor(string label, bool readOnly = false) => new()
    {
        AccessibleName = label, Multiline = true, Dock = DockStyle.Fill,
        ScrollBars = ScrollBars.Vertical, ReadOnly = readOnly, BackColor = Color.White
    };

    private static TableLayoutPanel NotebookLayout()
    {
        var panel = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 4, Padding = new Padding(18) };
        panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        panel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        return panel;
    }

    private static FlowLayoutPanel Row(params Control[] controls)
    {
        var row = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, WrapContents = true };
        row.Controls.AddRange(controls);
        return row;
    }
}
