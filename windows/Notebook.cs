using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;

namespace MeetinOS;

// Thème nuit de l’app Mac (mac/NightTheme.swift, web/theme-nuit.css) : fond encre, verre fumé, citron.
// EB Garamond (titres) et Figtree (interface) sont embarquées comme sur Mac (brand/fonts) ; Georgia et Segoe UI restent le repli.
internal static class Night
{
    public static readonly Color Canvas = ColorTranslator.FromHtml("#0F1613");
    public static readonly Color Veil = ColorTranslator.FromHtml("#0B100E");
    public static readonly Color Surface = ColorTranslator.FromHtml("#18211D");
    public static readonly Color Well = ColorTranslator.FromHtml("#131B17");
    public static readonly Color Ink = ColorTranslator.FromHtml("#F3F1E6");
    public static readonly Color Ink2 = ColorTranslator.FromHtml("#A3ADA5");
    public static readonly Color Line = ColorTranslator.FromHtml("#2B332E");
    public static readonly Color LineStrong = ColorTranslator.FromHtml("#4E5650");
    public static readonly Color Accent = ColorTranslator.FromHtml("#CFE86B");
    public static readonly Color AccentHover = ColorTranslator.FromHtml("#DDF083");
    public static readonly Color AccentTint = ColorTranslator.FromHtml("#2A3420");
    public static readonly Color OnAccent = ColorTranslator.FromHtml("#14201C");
    public static readonly Color Rec = ColorTranslator.FromHtml("#FF6A4D");
    public static readonly Color Warn = ColorTranslator.FromHtml("#F0B94F");
    public const int CardRadius = 14;
    public const int InputRadius = 10;

    public static Font Serif(float size) => BrandFonts.Create(BrandFonts.Serif, "Georgia", size * BrandFonts.SerifScale, FontStyle.Regular);
    public static Font Sans(float size, bool medium = false) => medium
        ? BrandFonts.Create(BrandFonts.SansMedium, "Segoe UI Semibold", size, FontStyle.Regular)
        : BrandFonts.Create(BrandFonts.Sans, "Segoe UI", size, FontStyle.Regular);
    public static Font Mono(float size) => new("Consolas", size, GraphicsUnit.Point);
    public static Font Icons(float size) => new("Segoe MDL2 Assets", size, GraphicsUnit.Point);

    public static GraphicsPath Rounded(Rectangle r, int radius)
    {
        var path = new GraphicsPath();
        var d = radius * 2;
        if (r.Width <= 0 || r.Height <= 0) { path.AddRectangle(new Rectangle(0, 0, 1, 1)); return path; }
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}

// Carte « verre fumé » : surface, bord fin, coins arrondis.
internal sealed class Glass : Panel
{
    public Glass()
    {
        BackColor = Night.Surface;
        DoubleBuffered = true;
        Padding = new Padding(20);
        Resize += (_, _) => UpdateRegion();
    }

    private void UpdateRegion()
    {
        var r = new Rectangle(0, 0, Width, Height);
        using var path = Night.Rounded(r, Night.CardRadius);
        Region = new Region(path);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var path = Night.Rounded(new Rectangle(0, 0, Width - 1, Height - 1), Night.CardRadius);
        using var pen = new Pen(Night.Line);
        e.Graphics.DrawPath(pen, path);
    }
}

internal enum CapsuleKind { Primary, Ghost, Record, Nav }

// Bouton capsule : citron plein, fantôme bordé, ou ligne de navigation.
internal sealed class Capsule : Button
{
    private bool hover;
    public CapsuleKind Kind { get; set; }
    public string Glyph { get; set; } = "";
    public bool Selected { get; set; }

    public Capsule(string text, CapsuleKind kind = CapsuleKind.Ghost, string glyph = "")
    {
        Text = text;
        Kind = kind;
        Glyph = glyph;
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.SupportsTransparentBackColor, true);
        FlatStyle = FlatStyle.Flat;
        FlatAppearance.BorderSize = 0;
        Cursor = Cursors.Hand;
        AutoSize = false;
        Font = Night.Sans(kind == CapsuleKind.Record ? 11.5f : 10f, kind == CapsuleKind.Record);
        Height = kind switch { CapsuleKind.Record => 48, CapsuleKind.Nav => 36, _ => 34 };
        Margin = kind == CapsuleKind.Nav ? new Padding(0, 0, 0, 4) : new Padding(0, 0, 10, 0);
        MouseEnter += (_, _) => { hover = true; Invalidate(); };
        MouseLeave += (_, _) => { hover = false; Invalidate(); };
        EnabledChanged += (_, _) => Invalidate();
        TextChanged += (_, _) => Fit();
        Fit();
    }

    private void Fit()
    {
        if (Kind == CapsuleKind.Nav) return;
        var text = TextRenderer.MeasureText(Text, Font).Width;
        var glyph = string.IsNullOrEmpty(Glyph) ? 0 : 24;
        Width = text + glyph + (Kind == CapsuleKind.Record ? 52 : 30);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(Parent?.BackColor ?? Night.Canvas);
        var r = new Rectangle(0, 0, Width - 1, Height - 1);
        var radius = Kind == CapsuleKind.Nav ? Night.InputRadius : Height / 2;
        using var path = Night.Rounded(r, radius);
        Color fore;
        switch (Kind)
        {
            case CapsuleKind.Primary:
            case CapsuleKind.Record:
                using (var b = new SolidBrush(hover && Enabled ? Night.AccentHover : Night.Accent)) g.FillPath(b, path);
                fore = Night.OnAccent;
                break;
            case CapsuleKind.Nav:
                if (Selected) using (var b = new SolidBrush(Night.AccentTint)) g.FillPath(b, path);
                else if (hover) using (var b = new SolidBrush(Night.Well)) g.FillPath(b, path);
                fore = Selected ? Night.Ink : Night.Ink2;
                break;
            default:
                if (hover && Enabled) using (var b = new SolidBrush(Night.Surface)) g.FillPath(b, path);
                using (var pen = new Pen(Night.LineStrong)) g.DrawPath(pen, path);
                fore = Night.Ink;
                break;
        }
        if (!Enabled) fore = Color.FromArgb(140, fore);

        var x = Kind == CapsuleKind.Nav ? 10 : (Kind == CapsuleKind.Record ? 24 : 15);
        if (Kind == CapsuleKind.Record)
        {
            using var white = new SolidBrush(Color.FromArgb(Enabled ? 255 : 140, Night.Ink));
            using var dot = new SolidBrush(Night.Accent);
            g.FillEllipse(white, x, Height / 2 - 7, 14, 14);
            g.FillEllipse(dot, x + 4.5f, Height / 2 - 2.5f, 5, 5);
            x += 24;
        }
        else if (!string.IsNullOrEmpty(Glyph))
        {
            using var icons = Night.Icons(10f);
            var glyphColor = Kind == CapsuleKind.Nav ? (Selected ? Night.Accent : Night.Ink2) : fore;
            TextRenderer.DrawText(g, Glyph, icons, new Rectangle(x, 0, 18, Height), glyphColor, TextFormatFlags.VerticalCenter | TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPadding);
            x += 26;
        }
        TextRenderer.DrawText(g, Text, Font, new Rectangle(x, 0, Width - x - 10, Height), fore, TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.NoPadding | TextFormatFlags.EndEllipsis);
    }
}

internal enum PillKind { Ok, Run, Wait, Rec }

internal sealed class Pill : Label
{
    public PillKind Kind { get; set; }

    public Pill(string text, PillKind kind)
    {
        Text = text;
        Kind = kind;
        Font = Night.Sans(8.5f, true);
        AutoSize = false;
        Height = 24;
        Width = TextRenderer.MeasureText(text, Font).Width + 26;
        Margin = new Padding(0);
        SetStyle(ControlStyles.SupportsTransparentBackColor, true);
        BackColor = Color.Transparent;
    }

    public void Set(string text, PillKind kind)
    {
        Kind = kind;
        Text = text;
        Width = TextRenderer.MeasureText(text, Font).Width + 26;
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        var (back, fore, dot) = Kind switch
        {
            PillKind.Ok => (Night.AccentTint, Night.Accent, Night.Accent),
            PillKind.Run => (Night.Well, Night.Ink, Night.Warn),
            PillKind.Rec => (Color.FromArgb(60, Night.Rec), Night.Rec, Night.Rec),
            _ => (Night.Well, Night.Ink2, Night.Ink2)
        };
        using var path = Night.Rounded(new Rectangle(0, 0, Width - 1, Height - 1), Height / 2);
        using (var b = new SolidBrush(back)) g.FillPath(b, path);
        using (var pen = new Pen(Night.Line)) g.DrawPath(pen, path);
        using (var d = new SolidBrush(dot)) g.FillEllipse(d, 9, Height / 2 - 3, 6, 6);
        TextRenderer.DrawText(g, Text, Font, new Rectangle(18, 0, Width - 18, Height), fore, TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.NoPadding);
    }
}

// Titre d’accueil : « Bonjour Prénom. Prêt pour la [prochaine réunion] ? », le citron surligne comme un coup de feutre.
internal sealed class Hero : Control
{
    private readonly string? firstName;

    public Hero(string? firstName)
    {
        this.firstName = firstName;
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Height = 150;
        Margin = new Padding(0, 0, 0, 12);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.Clear(Parent?.BackColor ?? Night.Canvas);
        foreach (var size in new[] { 44f, 36f, 28f })
        {
            using var font = Night.Serif(size);
            var w1 = TextRenderer.MeasureText("Prêt pour la ", font).Width;
            var w2 = TextRenderer.MeasureText("prochaine réunion", font).Width;
            var w3 = TextRenderer.MeasureText(" ?", font).Width;
            if (w1 + w2 + w3 + 20 > Width && size > 28f) continue;
            var line = font.Height + 4;
            var y = 0;
            if (firstName != null)
            {
                TextRenderer.DrawText(g, "Bonjour " + firstName + ".", font, new Point(0, y), Night.Ink, TextFormatFlags.NoPadding);
                y += line;
            }
            TextRenderer.DrawText(g, "Prêt pour la ", font, new Point(0, y), Night.Ink, TextFormatFlags.NoPadding);
            var mark = new Rectangle(w1 - 4, y + (int)(font.Height * 0.16), w2 + 12, (int)(font.Height * 0.78));
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (var b = new SolidBrush(Night.Accent)) g.FillRectangle(b, mark);
            TextRenderer.DrawText(g, "prochaine réunion", font, new Point(w1 + 2, y), Night.OnAccent, TextFormatFlags.NoPadding);
            TextRenderer.DrawText(g, " ?", font, new Point(w1 + w2 + 8, y), Night.Ink, TextFormatFlags.NoPadding);
            var wanted = y + line + 6;
            if (Height != wanted) Height = wanted;
            break;
        }
    }
}

internal sealed class MeetingRecord
{
    public MeetingRecord(string folder, DateTime date, string title, List<AudioTrack> tracks, TimeSpan duration, bool transcribed, string source)
    {
        Folder = folder; Date = date; Title = title; Tracks = tracks; Duration = duration; Transcribed = transcribed; Source = source;
    }
    public string Folder { get; }
    public DateTime Date { get; }
    public string Title { get; }
    public List<AudioTrack> Tracks { get; }
    public TimeSpan Duration { get; }
    public bool Transcribed { get; set; }
    public string Source { get; }
    public string NotesPath => Path.Combine(Folder, "notes.txt");
    public string TranscriptPath => Path.Combine(Folder, "transcription.txt");
}

internal static class MeetingStore
{
    private static readonly CultureInfo French = CultureInfo.GetCultureInfo("fr-FR");
    public static string AppData => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Meetin-OS");
    public static string Recordings => Path.Combine(AppData, "Recordings");

    public static List<MeetingRecord> Load()
    {
        var list = new List<MeetingRecord>();
        if (!Directory.Exists(Recordings)) return list;
        foreach (var dir in new DirectoryInfo(Recordings).GetDirectories().OrderByDescending(d => d.Name))
        {
            var record = FromFolder(dir.FullName);
            if (record != null) list.Add(record);
        }
        return list;
    }

    public static MeetingRecord? FromFolder(string folder)
    {
        var dir = new DirectoryInfo(folder);
        var wavs = dir.GetFiles("*.wav").Where(f => f.Length > 44).OrderBy(f => f.Name == "micro.wav" ? 0 : 1).ToList();
        var importedPath = Path.Combine(folder, "audio.txt");
        var imported = wavs.Count == 0 && File.Exists(importedPath) ? File.ReadAllText(importedPath).Trim() : null;
        if (wavs.Count == 0 && (imported == null || !File.Exists(imported))) return null;
        var name = dir.Name;
        var date = name.Length >= 19 && DateTime.TryParseExact(name.Substring(0, 19), "yyyy-MM-dd_HH-mm-ss", CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsed) ? parsed : dir.CreationTime;
        var tracks = imported != null
            ? new List<AudioTrack> { new(imported) }
            : wavs.Select(f => new AudioTrack(f.FullName, f.Name == "micro.wav" ? Speaker.UserLabel : "Audio de l’appel")).ToList();
        var titlePath = Path.Combine(folder, "titre.txt");
        var title = File.Exists(titlePath) ? File.ReadAllText(titlePath).Trim() : DefaultTitle(date, false);
        var sourcePath = Path.Combine(folder, "source.txt");
        var source = File.Exists(sourcePath) && File.ReadAllText(sourcePath).Trim() is { Length: > 0 } s ? s : "Windows";
        return new MeetingRecord(folder, date, title, tracks, SafeDuration(tracks[0].Path), File.Exists(Path.Combine(folder, "transcription.txt")), source);
    }

    public static string DefaultTitle(DateTime date, bool zoom) =>
        (zoom ? "Réunion Zoom du " : "Réunion du ") + date.ToString("d MMMM 'à' HH:mm", French);

    private static TimeSpan SafeDuration(string path)
    {
        try { return path.EndsWith(".wav", StringComparison.OrdinalIgnoreCase) ? Duration(path) : TimeSpan.Zero; }
        catch { return TimeSpan.Zero; }
    }

    // Un enregistrement ouvert depuis un fichier rejoint l’historique ; le fichier reste à sa place et n’est jamais supprimé avec la réunion.
    public static MeetingRecord? AddImported(string file)
    {
        var folder = Path.Combine(Recordings, DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss") + "_import");
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "audio.txt"), file);
        File.WriteAllText(Path.Combine(folder, "titre.txt"), Path.GetFileNameWithoutExtension(file));
        File.WriteAllText(Path.Combine(folder, "source.txt"), "Import");
        return FromFolder(folder);
    }

    private static TimeSpan Duration(string wav)
    {
        try
        {
            using var stream = File.OpenRead(wav);
            var header = new byte[44];
            if (stream.Read(header, 0, 44) < 44) return TimeSpan.Zero;
            var byteRate = BitConverter.ToInt32(header, 28);
            return byteRate > 0 ? TimeSpan.FromSeconds((stream.Length - 44) / (double)byteRate) : TimeSpan.Zero;
        }
        catch { return TimeSpan.Zero; }
    }

    public static string Day(DateTime date)
    {
        if (date.Date == DateTime.Today) return "Aujourd’hui";
        if (date.Date == DateTime.Today.AddDays(-1)) return "Hier";
        var text = date.ToString(date.Year == DateTime.Today.Year ? "ddd d MMM" : "d MMM yyyy", French);
        return char.ToUpper(text[0], French) + text.Substring(1);
    }

    public static string Time(DateTime date) => date.ToString("HH:mm", French);

    public static string DurationText(TimeSpan d) => d.TotalSeconds < 60 ? Math.Max((int)Math.Round(d.TotalSeconds), 0) + " s" : (int)Math.Round(d.TotalMinutes) + " min";

    public static string DateLine() => DateTime.Now.ToString("dddd d MMMM", French).ToUpper(French);

    private static string KeyFile => Path.Combine(AppData, "gladia.key");

    // La clé reste sur ce PC, chiffrée pour ta session Windows (DPAPI), l’équivalent du trousseau du Mac.
    public static string LoadKey()
    {
        try
        {
            if (!File.Exists(KeyFile)) return "";
            return Encoding.UTF8.GetString(ProtectedData.Unprotect(File.ReadAllBytes(KeyFile), null, DataProtectionScope.CurrentUser)).Trim();
        }
        catch { return ""; }
    }

    public static void SaveKey(string key)
    {
        Directory.CreateDirectory(AppData);
        if (string.IsNullOrWhiteSpace(key)) { if (File.Exists(KeyFile)) File.Delete(KeyFile); return; }
        File.WriteAllBytes(KeyFile, ProtectedData.Protect(Encoding.UTF8.GetBytes(key.Trim()), null, DataProtectionScope.CurrentUser));
    }

    private static string CodeFile => Path.Combine(AppData, "agent.key");
    public static string LoadAgentCode()
    {
        try { return File.Exists(CodeFile) ? Encoding.UTF8.GetString(ProtectedData.Unprotect(File.ReadAllBytes(CodeFile), null, DataProtectionScope.CurrentUser)).Trim() : ""; }
        catch { return ""; }
    }
    public static void SaveAgentCode(string code)
    {
        Directory.CreateDirectory(AppData);
        if (string.IsNullOrWhiteSpace(code)) { if (File.Exists(CodeFile)) File.Delete(CodeFile); return; }
        File.WriteAllBytes(CodeFile, ProtectedData.Protect(Encoding.UTF8.GetBytes(code.Trim()), null, DataProtectionScope.CurrentUser));
    }

    private static string LiveFile => Path.Combine(AppData, "live.txt");
    public static bool LoadLiveEnabled() => !File.Exists(LiveFile) || File.ReadAllText(LiveFile).Trim() != "off";
    public static void SaveLiveEnabled(bool enabled) { Directory.CreateDirectory(AppData); File.WriteAllText(LiveFile, enabled ? "on" : "off"); }
    private static string ZoomFile => Path.Combine(AppData, "zoom.flag");
    public static bool LoadZoomEnabled() => File.Exists(ZoomFile) && File.ReadAllText(ZoomFile).Trim() == "on";
    public static void SaveZoomEnabled(bool enabled) { Directory.CreateDirectory(AppData); File.WriteAllText(ZoomFile, enabled ? "on" : "off"); }

    public static List<TaskProposal> LoadProposals(string folder)
    {
        try
        {
            var path = Path.Combine(folder, "proposals.json");
            if (!File.Exists(path)) return new List<TaskProposal>();
            using var stream = File.OpenRead(path);
            return new System.Runtime.Serialization.Json.DataContractJsonSerializer(typeof(List<TaskProposal>)).ReadObject(stream) as List<TaskProposal> ?? new List<TaskProposal>();
        }
        catch { return new List<TaskProposal>(); }
    }

    public static void SaveProposals(string folder, List<TaskProposal> proposals)
    {
        try
        {
            var path = Path.Combine(folder, "proposals.json");
            if (proposals.Count == 0) { if (File.Exists(path)) File.Delete(path); return; }
            using var stream = File.Create(path);
            new System.Runtime.Serialization.Json.DataContractJsonSerializer(typeof(List<TaskProposal>)).WriteObject(stream, proposals);
        }
        catch { }
    }

    // Un titre vide est refusé : l’ancien titre reste.
    public static bool Rename(MeetingRecord record, string title)
    {
        var trimmed = (title ?? "").Trim();
        if (trimmed.Length == 0) return false;
        File.WriteAllText(Path.Combine(record.Folder, "titre.txt"), trimmed);
        return true;
    }

    // Le dossier de la réunion (audio, notes, transcription) part dans la Corbeille de Windows, d’où il se récupère.
    public static void Delete(MeetingRecord record) =>
        Microsoft.VisualBasic.FileIO.FileSystem.DeleteDirectory(
            record.Folder,
            Microsoft.VisualBasic.FileIO.UIOption.OnlyErrorDialogs,
            Microsoft.VisualBasic.FileIO.RecycleOption.SendToRecycleBin);

    private static string SiteFile => Path.Combine(AppData, "site.txt");
    public static string? LoadSite() => File.Exists(SiteFile) ? File.ReadAllText(SiteFile).Trim() : null;
    public static void SaveSite(string site) { Directory.CreateDirectory(AppData); File.WriteAllText(SiteFile, site); }
}

// Ligne de la liste des réunions : titre, méta, pastille d’état, durée.
internal sealed class MeetingRow : Control
{
    private readonly MeetingRecord record;
    private readonly bool divider;
    private bool hover;
    private const int MenuZone = 40;

    public event Action? Open;
    public ContextMenuStrip? Actions { get; set; }

    public MeetingRow(MeetingRecord record, bool divider)
    {
        this.record = record;
        this.divider = divider;
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Height = 58;
        Dock = DockStyle.Top;
        Cursor = Cursors.Hand;
        MouseEnter += (_, _) => { hover = true; Invalidate(); };
        MouseLeave += (_, _) => { hover = false; Invalidate(); };
        AccessibleName = record.Title;
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        if (e.Button == MouseButtons.Right || (e.Button == MouseButtons.Left && e.X >= Width - MenuZone))
            Actions?.Show(this, e.Location);
        else if (e.Button == MouseButtons.Left)
            Open?.Invoke();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.Clear(hover ? Night.Well : Night.Surface);
        if (divider) using (var pen = new Pen(Night.Line)) g.DrawLine(pen, 0, 0, Width, 0);
        using var title = Night.Sans(10.5f, true);
        using var meta = Night.Sans(9f);
        using var mono = Night.Mono(9f);
        using var pillFont = Night.Sans(8.5f, true);
        var status = record.Transcribed ? "Transcrite" : "À transcrire";
        var pillWidth = TextRenderer.MeasureText(status, pillFont).Width + 26;
        var durationText = MeetingStore.DurationText(record.Duration);
        var durationWidth = Math.Max(TextRenderer.MeasureText(durationText, mono).Width, 52);
        TextRenderer.DrawText(g, "⋯", title, new Rectangle(Width - MenuZone, 0, MenuZone - 8, Height), Night.Ink2, TextFormatFlags.VerticalCenter | TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPadding);
        var right = Width - MenuZone - 4;
        TextRenderer.DrawText(g, durationText, mono, new Rectangle(right - durationWidth, 0, durationWidth, Height), Night.Ink2, TextFormatFlags.VerticalCenter | TextFormatFlags.Right | TextFormatFlags.NoPadding);
        right -= durationWidth + 16;
        var pill = new Rectangle(right - pillWidth, Height / 2 - 12, pillWidth, 24);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        using (var path = Night.Rounded(pill, 12))
        {
            using var b = new SolidBrush(record.Transcribed ? Night.AccentTint : Night.Well);
            g.FillPath(b, path);
            using var pen = new Pen(Night.Line);
            g.DrawPath(pen, path);
        }
        using (var d = new SolidBrush(record.Transcribed ? Night.Accent : Night.Warn)) g.FillEllipse(d, pill.X + 9, pill.Y + 9, 6, 6);
        TextRenderer.DrawText(g, status, pillFont, new Rectangle(pill.X + 18, pill.Y, pill.Width - 18, pill.Height), record.Transcribed ? Night.Accent : Night.Ink, TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.NoPadding);
        right -= pillWidth + 16;
        var textWidth = right - 18;
        TextRenderer.DrawText(g, record.Title, title, new Rectangle(18, 11, textWidth, 20), Night.Ink, TextFormatFlags.Left | TextFormatFlags.NoPadding | TextFormatFlags.EndEllipsis);
        var metaText = MeetingStore.Day(record.Date) + " · " + MeetingStore.Time(record.Date) + " · " + record.Source;
        TextRenderer.DrawText(g, metaText, meta, new Rectangle(18, 32, textWidth, 18), Night.Ink2, TextFormatFlags.Left | TextFormatFlags.NoPadding | TextFormatFlags.EndEllipsis);
    }
}

internal sealed partial class Notebook : Form
{
    private readonly Capsule record = new("Commencer à enregistrer", CapsuleKind.Record);
    private readonly Capsule import = new("Ouvrir un enregistrement", CapsuleKind.Ghost, "\uE8B7");
    private readonly Capsule transcribe = new("Transcrire avec Gladia", CapsuleKind.Primary);
    private readonly Capsule folder = new("Voir les pistes", CapsuleKind.Ghost, "\uE8B7");
    private readonly Capsule copy = new("Copier la transcription", CapsuleKind.Ghost, "\uE8C8");
    private readonly Capsule saveKey = new("Enregistrer la clé", CapsuleKind.Primary);
    private readonly Capsule removeKey = new("Retirer", CapsuleKind.Ghost);
    private readonly Capsule saveSite = new("Enregistrer l’adresse", CapsuleKind.Ghost);
    private readonly Capsule agentButton = new("Agent", CapsuleKind.Ghost, "\uE99A");
    private readonly Capsule newRecording = new("Nouvel enregistrement", CapsuleKind.Ghost, "\uE710");
    private readonly Capsule showMeeting = new("Afficher la réunion", CapsuleKind.Ghost, "\uE7C4") { Visible = false };
    private readonly Capsule renameMeeting = new("Renommer", CapsuleKind.Ghost, "\uE70F");
    private readonly Capsule deleteMeeting = new("Supprimer", CapsuleKind.Ghost, "\uE74D");
    private readonly Pill incompletePill = new("Incomplète", PillKind.Run) { Visible = false, Margin = new Padding(0, 5, 0, 0) };
    private readonly TextBox notes = Editor("Notes de réunion");
    private readonly TextBox transcript = Editor("Transcription", true);
    private readonly TextBox keyField = Field("Clé API Gladia", true);
    private readonly TextBox siteField = Field("Adresse du site Meetin-OS");
    private readonly Pill keyPill = new("Aucune clé", PillKind.Wait);
    private readonly Label status = new() { AutoSize = true, ForeColor = Night.Ink2, Margin = new Padding(0, 0, 0, 8), MaximumSize = new Size(900, 0) };
    private readonly Label keyMessage = new() { AutoSize = true, ForeColor = Night.Ink2, Font = Night.Sans(9.5f), Margin = new Padding(0, 6, 0, 0) };
    private readonly Label detailTitle = new() { AutoSize = true, Font = Night.Serif(30), ForeColor = Night.Ink, Margin = new Padding(0, 0, 0, 4) };
    private readonly Label detailMeta = new() { AutoSize = true, ForeColor = Night.Ink2, Margin = new Padding(0, 0, 0, 18) };
    private readonly Label micDot = Dot();
    private readonly Label audioDot = Dot();
    private readonly LinkLabel keyDot = new() { AutoSize = true, Font = Night.Sans(9.5f), LinkColor = Night.Ink, ActiveLinkColor = Night.Accent, LinkBehavior = LinkBehavior.AlwaysUnderline, Text = "●  Ajouter la clé Gladia", Margin = new Padding(0, 0, 18, 0) };
    private readonly Panel pages = new() { Dock = DockStyle.Fill, BackColor = Night.Canvas };
    private readonly Dictionary<string, Control> pageByName = new();
    private readonly Dictionary<string, Capsule> navByName = new();
    private readonly Panel recentHost = new() { Dock = DockStyle.Top, AutoSize = true, Margin = new Padding(0) };
    private readonly Panel allHost = new() { Dock = DockStyle.Top, AutoSize = true, Margin = new Padding(0) };
    private readonly Glass notesCard;
    private readonly Glass transcriptCard;
    private readonly GladiaClient gladia = new();
    private List<MeetingRecord> meetings = new();
    private MeetingRecord? current;
    private List<AudioTrack> tracks = new();
    private AudioCapture? capture;
    private CancellationTokenSource? transcriptionCancellation;
    private string? audioFolder;
    private string apiKey;
    private Uri agentSite;
    private bool busy;
    private bool? systemAudioOk;
    private bool suppressNotesSave;
    private LiveTranscription? live;
    private TaskDetector? detector;
    private AgentAccess? agentAccess;
    private string agentCode;
    private bool liveEnabled;
    private bool zoomEnabled;
    private bool startedInZoom;
    private ZoomMeetingDetector zoomDetector = new();
    private readonly System.Windows.Forms.Timer zoomTimer = new() { Interval = 2000 };
    private readonly RecordingLevel recordingLevel = new();
    private readonly RecordingBar homeBar;
    private readonly NotifyIcon tray = new() { Text = "Meetin-OS" };
    private Form? meetingWindow;
    private string? notificationTarget;
    private bool transcriptIncomplete;
    private List<TaskProposal> proposals = new();

    public Notebook()
    {
        apiKey = Environment.GetEnvironmentVariable("GLADIA_API_KEY")?.Trim() is { Length: > 0 } env ? env : MeetingStore.LoadKey();
        agentSite = SiteUri(Environment.GetEnvironmentVariable("MEETIN_WEB_URL")) ?? SiteUri(MeetingStore.LoadSite()) ?? new Uri("http://localhost:3000");
        agentCode = MeetingStore.LoadAgentCode();
        liveEnabled = MeetingStore.LoadLiveEnabled();
        zoomEnabled = MeetingStore.LoadZoomEnabled();
        zoomTimer.Tick += (_, _) => PollZoom();
        zoomTimer.Enabled = zoomEnabled;

        Text = "Meetin-OS";
        Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        tray.Icon = Icon;
        tray.Visible = true;
        tray.BalloonTipClicked += (_, _) => OpenFromNotification();
        tray.Click += (_, _) => OpenFromNotification();
        homeBar = new RecordingBar(recordingLevel) { Visible = false };
        homeBar.StopRequested += () => capture?.Stop();
        KeyPreview = true;
        StartPosition = FormStartPosition.CenterScreen;
        var work = Screen.PrimaryScreen.WorkingArea;
        ClientSize = new Size(Math.Max(940, (int)(work.Width * 0.8)), Math.Max(620, (int)(work.Height * 0.8)));
        MinimumSize = new Size(940, 620);
        Font = Night.Sans(10f);
        BackColor = Night.Canvas;
        ForeColor = Night.Ink;
        AutoScaleMode = AutoScaleMode.Dpi;
        DoubleBuffered = true;

        notesCard = Card("Notes", notes);
        transcriptCard = Card("Transcription", transcript);

        var shell = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 1, BackColor = Night.Canvas };
        shell.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 250));
        shell.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        shell.Controls.Add(Sidebar(), 0, 0);
        shell.Controls.Add(pages, 1, 0);
        Controls.Add(shell);

        AddPage("Accueil", HomePage());
        AddPage("Réunions", MeetingsPage());
        AddPage("Détail", DetailPage());
        AddPage("Agent", AgentPage());
        AddPage("Intégrations", IntegrationsPage());
        AddPage("Paramètres", SettingsPage());
        AddPage("Compte", AccountPage());
        if (agentCode.Length > 0) _ = RefreshAccessAsync(false);
        meetings = MeetingStore.Load();
        systemAudioOk = meetings.Any(m => m.Tracks.Any(t => t.Path.EndsWith("appel.wav", StringComparison.OrdinalIgnoreCase))) ? true : null;
        ShowPage("Accueil");

        record.Click += async (_, _) => await RecordAsync();
        import.Click += (_, _) => ImportAudio();
        transcribe.Click += async (_, _) => await TranscribeAsync();
        folder.Click += (_, _) => { if (audioFolder != null) Open(audioFolder); };
        copy.Click += (_, _) => { if (transcript.TextLength > 0) Clipboard.SetText(transcript.Text); };
        saveKey.Click += (_, _) => SaveKey();
        removeKey.Click += (_, _) => { keyField.Text = ""; SaveKey(); };
        saveSite.Click += (_, _) => SaveSite();
        agentButton.Click += (_, _) => ShowPage("Agent");
        newRecording.Click += async (_, _) => { if (CanSwitchMeeting) await RecordAsync(); };
        showMeeting.Click += (_, _) => { if (meetingWindow is { IsDisposed: false } window) { window.Show(); window.Activate(); } };
        renameMeeting.Click += (_, _) => { if (current != null) RenameMeeting(current); };
        deleteMeeting.Click += (_, _) => { if (current != null) DeleteMeeting(current); };
        keyDot.LinkClicked += (_, _) => { ShowPage("Paramètres"); keyField.Focus(); };
        notes.TextChanged += (_, _) => SaveNotes();
        FormClosing += (_, args) =>
        {
            if (capture == null) { transcriptionCancellation?.Cancel(); return; }
            args.Cancel = true;
            capture.Stop();
            status.Text = "Finalisation de l’enregistrement…";
        };
        SetStatus("Prêt à enregistrer");
        RefreshActions();
        RefreshReadiness();
    }

    // ---------- barre latérale ----------

    private Control Sidebar()
    {
        var side = new TableLayoutPanel { Dock = DockStyle.Fill, BackColor = Night.Veil, ColumnCount = 1, RowCount = 5, Padding = new Padding(12, 18, 12, 16) };
        side.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        side.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        side.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        side.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        side.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        var brand = new FlowLayoutPanel { AutoSize = true, Margin = new Padding(10, 0, 0, 20), WrapContents = false };
        var logo = new PictureBox { Size = new Size(28, 28), SizeMode = PictureBoxSizeMode.Zoom, Margin = new Padding(0, 2, 10, 0), Image = Icon.ToBitmap() };
        brand.Controls.Add(logo);
        brand.Controls.Add(new Label { Text = "Meetin-OS", Font = Night.Serif(16.5f), ForeColor = Night.Ink, AutoSize = true, Margin = new Padding(0) });
        side.Controls.Add(brand, 0, 0);

        var top = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top, FlowDirection = FlowDirection.TopDown, WrapContents = false, Margin = new Padding(0) };
        top.Controls.Add(Nav("Accueil", "\uE80F"));
        top.Controls.Add(Nav("Réunions", "\uE7C3"));
        top.Controls.Add(Nav("Agent", "\uE99A"));
        side.Controls.Add(top, 0, 1);

        var section = new Label { Text = "COMPTE", Font = Night.Sans(8f, true), ForeColor = Night.Ink2, AutoSize = true, Margin = new Padding(10, 0, 0, 6) };
        side.Controls.Add(section, 0, 3);
        var bottom = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top, FlowDirection = FlowDirection.TopDown, WrapContents = false, Margin = new Padding(0) };
        bottom.Controls.Add(Nav("Intégrations", "\uE71B"));
        bottom.Controls.Add(Nav("Paramètres", "\uE713"));
        bottom.Controls.Add(Nav("Compte", "\uE77B"));
        var billing = new Capsule("Facturation et abonnement", CapsuleKind.Nav, "\uE8C7") { Width = 226 };
        billing.Click += (_, _) => Open(new Uri(agentSite, "/abonnement").AbsoluteUri);
        bottom.Controls.Add(billing);
        side.Controls.Add(bottom, 0, 4);
        return side;
    }

    private Capsule Nav(string name, string glyph)
    {
        var button = new Capsule(name, CapsuleKind.Nav, glyph) { Width = 226 };
        button.Click += (_, _) => ShowPage(name);
        navByName[name] = button;
        return button;
    }

    // ---------- pages ----------

    private Control HomePage()
    {
        var page = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 3, BackColor = Night.Canvas };
        page.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 1));
        page.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        var scroll = ScrollPane();
        var content = Column(48, 32, 48, 20);
        content.Controls.Add(new Label { Text = MeetingStore.DateLine(), Font = Night.Sans(8.5f, true), ForeColor = Night.Accent, AutoSize = true, Margin = new Padding(0, 0, 0, 16) });
        var hero = new Hero(FirstName()) { Width = 700 };
        content.Controls.Add(hero);
        void FitHome() { var w = PageWidth(scroll, content); hero.Width = w; }
        scroll.Resize += (_, _) => FitHome();
        scroll.VisibleChanged += (_, _) => FitHome();
        content.Controls.Add(new Label
        {
            Text = "Lance l’enregistrement quand l’appel commence. Meetin-OS garde tes notes et la transcription, et t’aide à préparer les tâches à valider.",
            Font = Night.Sans(11f), ForeColor = Night.Ink2, AutoSize = true, MaximumSize = new Size(560, 0), Margin = new Padding(0, 0, 0, 20)
        });
        var readiness = new FlowLayoutPanel { AutoSize = true, WrapContents = true, Margin = new Padding(0, 0, 0, 34) };
        readiness.Controls.Add(micDot);
        readiness.Controls.Add(audioDot);
        readiness.Controls.Add(keyDot);
        content.Controls.Add(readiness);
        var recentHeader = new TableLayoutPanel { AutoSize = true, ColumnCount = 2, Margin = new Padding(0, 0, 0, 14), Width = 700 };
        recentHeader.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        recentHeader.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        recentHeader.Controls.Add(new Label { Text = "Réunions récentes", Font = Night.Serif(18f), ForeColor = Night.Ink, AutoSize = true, Margin = new Padding(0, 4, 0, 0) }, 0, 0);
        var seeAll = new Capsule("Voir tout  →", CapsuleKind.Ghost) { Height = 30, Margin = new Padding(0) };
        seeAll.Click += (_, _) => ShowPage("Réunions");
        recentHeader.Controls.Add(seeAll, 1, 0);
        content.Controls.Add(recentHeader);
        recentHost.Width = 700;
        content.Controls.Add(recentHost);
        void FitRecent() { var w = PageWidth(scroll, content); hero.Width = w; recentHeader.MinimumSize = new Size(w, 0); recentHost.Width = w; }
        scroll.Resize += (_, _) => FitRecent();
        scroll.VisibleChanged += (_, _) => FitRecent();
        scroll.Controls.Add(content);
        page.Controls.Add(scroll, 0, 0);
        page.Controls.Add(new Panel { Dock = DockStyle.Fill, BackColor = Night.Line, Margin = new Padding(0) }, 0, 1);

        var bar = new Panel { Dock = DockStyle.Fill, AutoSize = true, Padding = new Padding(24, 14, 24, 18), BackColor = Night.Canvas, MinimumSize = new Size(0, 96) };
        bar.Controls.Add(status);
        bar.Controls.Add(record);
        bar.Controls.Add(homeBar);
        void Center()
        {
            status.Location = new Point((bar.ClientSize.Width - status.Width) / 2, 12);
            var top = status.Visible ? status.Bottom + 8 : 24;
            record.Location = new Point((bar.ClientSize.Width - record.Width) / 2, top);
            homeBar.Location = new Point((bar.ClientSize.Width - homeBar.Width) / 2, top);
            bar.Height = Math.Max(record.Bottom, homeBar.Bottom) + 18;
        }
        homeBar.SizeChanged += (_, _) => Center();
        bar.Resize += (_, _) => Center();
        status.SizeChanged += (_, _) => Center();
        status.VisibleChanged += (_, _) => Center();
        record.SizeChanged += (_, _) => Center();
        page.Controls.Add(bar, 0, 2);
        return page;
    }

    private Control MeetingsPage()
    {
        var scroll = ScrollPane();
        var content = Column(48, 40, 48, 40);
        var header = new TableLayoutPanel { AutoSize = true, ColumnCount = 2, Margin = new Padding(0, 0, 0, 20), Width = 700 };
        header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        header.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        header.Controls.Add(new Label { Text = "Réunions", Font = Night.Serif(30f), ForeColor = Night.Ink, AutoSize = true, Margin = new Padding(0) }, 0, 0);
        import.Margin = new Padding(0, 10, 0, 0);
        header.Controls.Add(import, 1, 0);
        content.Controls.Add(header);
        allHost.Width = 700;
        content.Controls.Add(allHost);
        // L’en-tête est AutoSize : seule MinimumSize l’élargit, et la liste (Dock) suit le plus large élément de la colonne.
        void FitList() { var w = PageWidth(scroll, content); header.MinimumSize = new Size(w, 0); allHost.Width = w; }
        scroll.Resize += (_, _) => FitList();
        scroll.VisibleChanged += (_, _) => FitList();
        scroll.Controls.Add(content);
        return scroll;
    }

    private Control DetailPage()
    {
        var page = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 3, BackColor = Night.Canvas, Padding = new Padding(48, 32, 48, 24) };
        page.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        page.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        page.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        var back = new LinkLabel { Text = "‹  Réunions", AutoSize = true, LinkColor = Night.Ink2, ActiveLinkColor = Night.Accent, LinkBehavior = LinkBehavior.HoverUnderline, Margin = new Padding(0, 0, 0, 10) };
        back.LinkClicked += (_, _) => ShowPage("Réunions");
        var head = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top, FlowDirection = FlowDirection.TopDown, WrapContents = false, Margin = new Padding(0) };
        head.Controls.Add(back);
        head.Controls.Add(detailTitle);
        head.Controls.Add(detailMeta);
        page.Controls.Add(head, 0, 0);
        page.SetColumnSpan(head, 2);
        var actions = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top, WrapContents = true, Margin = new Padding(0, 0, 0, 18) };
        actions.Controls.Add(transcribe);
        actions.Controls.Add(folder);
        actions.Controls.Add(copy);
        actions.Controls.Add(agentButton);
        actions.Controls.Add(showMeeting);
        actions.Controls.Add(newRecording);
        actions.Controls.Add(renameMeeting);
        actions.Controls.Add(deleteMeeting);
        actions.Controls.Add(incompletePill);
        page.Controls.Add(actions, 0, 1);
        page.SetColumnSpan(actions, 2);
        notesCard.Margin = new Padding(0, 0, 10, 0);
        transcriptCard.Margin = new Padding(10, 0, 0, 0);
        page.Controls.Add(notesCard, 0, 2);
        page.Controls.Add(transcriptCard, 1, 2);
        return page;
    }

    private Control SettingsPage()
    {
        var scroll = ScrollPane();
        var content = Column(48, 40, 48, 40);
        content.Controls.Add(new Label { Text = "Paramètres", Font = Night.Serif(30f), ForeColor = Night.Ink, AutoSize = true, Margin = new Padding(0, 0, 0, 18) });

        var transcription = Section("Transcription", out var transcriptionStack);
        var keyHeader = new TableLayoutPanel { AutoSize = true, ColumnCount = 2, Margin = new Padding(0, 0, 0, 10), Width = 560 };
        keyHeader.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        keyHeader.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        keyHeader.Controls.Add(new Label { Text = "Clé API Gladia", Font = Night.Sans(10.5f, true), ForeColor = Night.Ink, AutoSize = true, Margin = new Padding(0, 3, 0, 0) }, 0, 0);
        keyHeader.Controls.Add(keyPill, 1, 0);
        transcriptionStack.Controls.Add(keyHeader);
        transcriptionStack.Controls.Add(Muted("Meetin-OS utilise Gladia pour transcrire l’audio. La clé est gardée sur ce PC, chiffrée pour ta session Windows."));
        keyField.Width = 560;
        keyField.Margin = new Padding(0, 10, 0, 12);
        transcriptionStack.Controls.Add(keyField);
        var keyActions = new FlowLayoutPanel { AutoSize = true, WrapContents = true, Margin = new Padding(0) };
        keyActions.Controls.Add(saveKey);
        keyActions.Controls.Add(removeKey);
        var getKey = new LinkLabel { Text = "Obtenir une clé", AutoSize = true, LinkColor = Night.Ink, ActiveLinkColor = Night.Accent, Font = Night.Sans(9.5f), Margin = new Padding(4, 8, 0, 0) };
        getKey.LinkClicked += (_, _) => Open("https://app.gladia.io/apikeys");
        keyActions.Controls.Add(getKey);
        transcriptionStack.Controls.Add(keyActions);
        transcriptionStack.Controls.Add(keyMessage);
        var liveToggle = new CheckBox { Text = "Transcription en direct pendant l’enregistrement", Checked = liveEnabled, AutoSize = true, ForeColor = Night.Ink, Margin = new Padding(0, 14, 0, 4) };
        liveToggle.CheckedChanged += (_, _) => { liveEnabled = liveToggle.Checked; MeetingStore.SaveLiveEnabled(liveEnabled); };
        transcriptionStack.Controls.Add(liveToggle);
        transcriptionStack.Controls.Add(Muted("L’audio est envoyé en continu à Gladia pendant l’enregistrement. Si l’agent est connecté, le texte part aussi chez Holo (H Company) toutes les 15 s pour proposer des tâches. Rien n’est lancé sans ta validation."));
        content.Controls.Add(transcription);

        var zoom = Section("Détection Zoom", out var zoomStack);
        var zoomToggle = new CheckBox { Text = "Me prévenir quand je rejoins une réunion Zoom", Checked = zoomEnabled, AutoSize = true, ForeColor = Night.Ink, Margin = new Padding(0, 4, 0, 4) };
        zoomToggle.CheckedChanged += (_, _) => { zoomEnabled = zoomToggle.Checked; MeetingStore.SaveZoomEnabled(zoomEnabled); zoomDetector = new ZoomMeetingDetector(); zoomTimer.Enabled = zoomEnabled; };
        zoomStack.Controls.Add(zoomToggle);
        zoomStack.Controls.Add(Muted("Meetin-OS surveille les fenêtres de Zoom toutes les 2 s et propose de lancer l’enregistrement. L’enregistrement se lance manuellement."));
        content.Controls.Add(zoom);

        var audio = Section("Autorisations audio", out var audioStack);
        audioStack.Controls.Add(Muted("Windows ne demande rien au premier enregistrement : si le micro est refusé dans Confidentialité, seul l’audio de l’appel est gardé."));
        var audioActions = new FlowLayoutPanel { AutoSize = true, WrapContents = true, Margin = new Padding(0, 12, 0, 0) };
        var mic = new Capsule("Microphone", CapsuleKind.Ghost);
        mic.Click += (_, _) => Open("ms-settings:privacy-microphone");
        var sound = new Capsule("Audio du système", CapsuleKind.Ghost);
        sound.Click += (_, _) => Open("ms-settings:sound");
        audioActions.Controls.Add(mic);
        audioActions.Controls.Add(sound);
        audioStack.Controls.Add(audioActions);
        content.Controls.Add(audio);

        var site = Section("Espace web", out var siteStack);
        siteStack.Controls.Add(Muted("Adresse du site Meetin-OS utilisée pour l’agent, les intégrations et l’abonnement."));
        siteField.Width = 560;
        siteField.Margin = new Padding(0, 10, 0, 12);
        siteStack.Controls.Add(siteField);
        siteStack.Controls.Add(saveSite);
        content.Controls.Add(site);

        keyField.Text = apiKey;
        siteField.Text = agentSite.GetLeftPart(UriPartial.Authority);
        RefreshKeyPill();
        scroll.Controls.Add(content);
        return scroll;
    }

    private Control AccountPage()
    {
        var scroll = ScrollPane();
        var content = Column(48, 40, 48, 40);
        content.Controls.Add(new Label { Text = "Compte", Font = Night.Serif(30f), ForeColor = Night.Ink, AutoSize = true, Margin = new Padding(0, 0, 0, 18) });
        var section = Section(Environment.UserName, out var stack);
        stack.Controls.Add(Muted("Le compte, l’abonnement et l’agent se gèrent dans l’espace web Meetin-OS. Cette version Windows enregistre et transcrit en local."));
        var actions = new FlowLayoutPanel { AutoSize = true, WrapContents = true, Margin = new Padding(0, 12, 0, 0) };
        var open = new Capsule("Ouvrir l’espace agent", CapsuleKind.Primary);
        open.Click += (_, _) => Open(new Uri(agentSite, "/agent").AbsoluteUri);
        var account = new Capsule("Mon compte", CapsuleKind.Ghost);
        account.Click += (_, _) => Open(new Uri(agentSite, "/compte").AbsoluteUri);
        actions.Controls.Add(open);
        actions.Controls.Add(account);
        stack.Controls.Add(actions);
        content.Controls.Add(section);
        content.Controls.Add(new Label { Text = "Meetin-OS pour Windows · " + Application.ProductVersion.Split('+')[0], ForeColor = Night.Ink2, AutoSize = true, Margin = new Padding(0, 18, 0, 0) });
        scroll.Controls.Add(content);
        return scroll;
    }

    private void AddPage(string name, Control page)
    {
        page.Visible = false;
        page.Dock = DockStyle.Fill;
        pageByName[name] = page;
        pages.Controls.Add(page);
    }

    private void ShowPage(string name)
    {
        if (name == "Accueil" || name == "Réunions") RefreshMeetings();
        if (name == "Agent") RefreshAgentPage();
        if (name == "Intégrations") RefreshIntegrationsPage();
        foreach (var pair in pageByName) pair.Value.Visible = pair.Key == name;
        foreach (var pair in navByName)
        {
            pair.Value.Selected = pair.Key == name || (name == "Détail" && pair.Key == "Réunions");
            pair.Value.Invalidate();
        }
    }

    // ---------- réunions ----------

    private void RefreshMeetings()
    {
        meetings = MeetingStore.Load();
        Fill(recentHost, meetings.Take(5).ToList(), "Aucune réunion pour l’instant. Ton premier enregistrement apparaîtra ici.");
        Fill(allHost, meetings, "Aucune réunion enregistrée sur ce PC.");
        RefreshReadiness();
    }

    private void Fill(Panel host, List<MeetingRecord> records, string empty)
    {
        host.SuspendLayout();
        foreach (var c in host.Controls.Cast<Control>().ToList()) c.Dispose();
        host.Controls.Clear();
        var glass = new Glass { Dock = DockStyle.Top, AutoSize = true, Padding = new Padding(0) };
        if (records.Count == 0)
        {
            glass.Padding = new Padding(18);
            glass.Controls.Add(new Label { Text = empty, ForeColor = Night.Ink2, AutoSize = true, Dock = DockStyle.Top, Font = Night.Sans(10f) });
        }
        else
        {
            for (var i = records.Count - 1; i >= 0; i--)
            {
                var item = records[i];
                var row = new MeetingRow(item, i > 0) { Actions = MeetingMenu(item) };
                row.Open += () => OpenMeeting(item);
                glass.Controls.Add(row);
            }
        }
        host.Controls.Add(glass);
        host.ResumeLayout();
    }

    // afterRecording : la réunion qui vient d’être enregistrée s’ouvre même si le carnet est encore occupé à la finaliser.
    private void OpenMeeting(MeetingRecord item, bool afterRecording = false)
    {
        if (!afterRecording && !CanSwitchMeeting) { SetStatus(capture != null ? "Enregistrement en cours. Arrête-le pour rouvrir une réunion." : "Attends la fin de l’opération en cours pour changer de réunion."); return; }
        current = item;
        tracks = item.Tracks;
        audioFolder = item.Folder;
        suppressNotesSave = true;
        notes.Text = File.Exists(item.NotesPath) ? File.ReadAllText(item.NotesPath) : "";
        suppressNotesSave = false;
        transcript.Text = File.Exists(item.TranscriptPath) ? File.ReadAllText(item.TranscriptPath) : "";
        proposals = MeetingStore.LoadProposals(item.Folder);
        transcriptIncomplete = File.Exists(Path.Combine(item.Folder, "incomplete.txt"));
        incompletePill.Visible = transcriptIncomplete;
        detailTitle.Text = item.Title;
        detailMeta.Text = MeetingStore.Day(item.Date) + " · " + MeetingStore.Time(item.Date) + " · " + MeetingStore.DurationText(item.Duration) + " · " + item.Tracks.Count + (item.Tracks.Count > 1 ? " pistes" : " piste");
        ShowPage("Détail");
        RefreshActions();
    }

    private bool CanSwitchMeeting => !busy && capture == null && !agentBusy;
    private bool CanDeleteMeetings => CanSwitchMeeting;

    private ContextMenuStrip MeetingMenu(MeetingRecord item)
    {
        var menu = new ContextMenuStrip { ShowImageMargin = false };
        menu.Items.Add("Renommer…", null, (_, _) => RenameMeeting(item));
        var delete = menu.Items.Add("Supprimer…", null, (_, _) => DeleteMeeting(item));
        menu.Opening += (_, _) => delete.Enabled = CanDeleteMeetings;
        return menu;
    }

    private void RenameMeeting(MeetingRecord item)
    {
        var title = Prompt("Renommer la réunion", "Le nouveau titre est enregistré sur ce PC.", item.Title);
        if (title == null) return;
        try
        {
            if (!MeetingStore.Rename(item, title)) return;
        }
        catch (Exception ex) { SetStatus("Titre non enregistré : " + ex.Message); return; }
        if (current != null && current.Folder == item.Folder)
        {
            current = MeetingStore.FromFolder(item.Folder) ?? current;
            detailTitle.Text = current.Title;
        }
        RefreshMeetings();
    }

    private void DeleteMeeting(MeetingRecord item)
    {
        if (!CanDeleteMeetings)
        {
            SetStatus("Attends la fin de l’enregistrement ou de la transcription pour supprimer.");
            return;
        }
        var answer = MessageBox.Show(this,
            "« " + item.Title + " » : l’audio, les notes et la transcription seront effacés. Le dossier part dans la Corbeille de Windows, d’où tu peux encore le récupérer.",
            "Supprimer cette réunion ?", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
        if (answer != DialogResult.OK) return;
        try { MeetingStore.Delete(item); }
        catch (Exception ex) { SetStatus("Réunion non supprimée : le dossier n’a pas pu aller à la Corbeille (" + ex.Message + ")."); return; }
        var wasOpen = current != null && current.Folder == item.Folder;
        if (wasOpen)
        {
            current = null;
            tracks = new List<AudioTrack>();
            audioFolder = null;
            suppressNotesSave = true;
            notes.Text = "";
            suppressNotesSave = false;
            transcript.Text = "";
            proposals = new List<TaskProposal>();
            transcriptIncomplete = false;
            incompletePill.Visible = false;
            SetStatus("Prêt à enregistrer");
        }
        RefreshMeetings();
        if (wasOpen) ShowPage("Réunions");
        RefreshActions();
    }

    private string? Prompt(string title, string message, string value)
    {
        using var form = new Form
        {
            Text = title, Icon = Icon, FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, MinimizeBox = false,
            StartPosition = FormStartPosition.CenterParent, BackColor = Night.Surface, ForeColor = Night.Ink, AutoScaleMode = AutoScaleMode.Dpi,
            ClientSize = new Size(440, 170), Font = Night.Sans(10f), ShowInTaskbar = false
        };
        var label = new Label { Text = message, AutoSize = false, Bounds = new Rectangle(20, 18, 400, 22), ForeColor = Night.Ink2 };
        var field = new TextBox { Text = value, Bounds = new Rectangle(20, 50, 400, 28), BackColor = Night.Well, ForeColor = Night.Ink, BorderStyle = BorderStyle.FixedSingle };
        var ok = new Capsule("Renommer", CapsuleKind.Primary) { DialogResult = DialogResult.OK, Location = new Point(20, 104) };
        var cancel = new Capsule("Annuler", CapsuleKind.Ghost) { DialogResult = DialogResult.Cancel, Location = new Point(150, 104) };
        field.TextChanged += (_, _) => ok.Enabled = field.Text.Trim().Length > 0;
        form.Controls.AddRange(new Control[] { label, field, ok, cancel });
        form.AcceptButton = ok;
        form.CancelButton = cancel;
        field.SelectAll();
        return form.ShowDialog(this) == DialogResult.OK ? field.Text.Trim() : null;
    }

    private void SaveNotes()
    {
        if (suppressNotesSave || current == null) return;
        try { File.WriteAllText(current.NotesPath, notes.Text); } catch { }
    }

    // ---------- enregistrement ----------

    private void PollZoom()
    {
        if (!zoomEnabled) return;
        List<string> titles;
        try { titles = ZoomMeetingDetector.WindowTitles(); } catch { return; }
        if (!zoomDetector.Observe(titles) || busy || capture != null) return;
        if (Form.ActiveForm == null) Notify("Tu es en appel Zoom", "Lancer l’enregistrement dans Meetin-OS ?", "Accueil");
        if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
        Activate();
        ShowPage("Accueil");
        SetStatus("Réunion Zoom détectée.");
        var answer = MessageBox.Show(this, "Une réunion Zoom vient de commencer. Lancer l’enregistrement ?", "Meetin-OS", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
        if (answer == DialogResult.Yes && !busy && capture == null) _ = RecordAsync();
    }

    private async Task RecordAsync()
    {
        AudioCapture? recording = null;
        busy = true;
        RefreshActions();
        try
        {
            SetStatus("Ouverture du micro et de la sortie audio…");
            capture = recording = new AudioCapture();
            startedInZoom = zoomDetector.InMeeting;
            live = StartLive(recording);
            var meter = new AudioLevelMeter();
            var liveTap = recording.LiveTap;
            recording.LiveTap = (track, bytes, count, time) => { meter.Feed(bytes, count); liveTap?.Invoke(track, bytes, count, time); };
            await recording.Started;
            recordingLevel.Start(meter, DateTime.Now);
            record.Visible = false;
            homeBar.Visible = true;
            SetStatus("Enregistrement en cours");
            proposals = new List<TaskProposal>();
            detector = StartDetection();
            using var meeting = new Form
            {
                Text = "Réunion en cours · Meetin-OS", Icon = Icon, ClientSize = new Size(720, 460),
                MinimumSize = new Size(560, 360), StartPosition = FormStartPosition.CenterParent,
                BackColor = Night.Canvas, ForeColor = Night.Ink, Font = Font, ShowInTaskbar = false
            };
            var meetingNotes = Editor("Notes pendant la réunion");
            meetingNotes.Text = notes.Text;
            var stop = new RecordingBar(recordingLevel) { Margin = new Padding(0, 0, 14, 0) };
            var indicator = new Pill("Finalisation…", PillKind.Wait) { Margin = new Padding(0, 14, 14, 0), Visible = false };
            void StopRecording()
            {
                stop.Enabled = false;
                indicator.Visible = true;
                recording.Stop();
            }
            stop.StopRequested += StopRecording;
            homeBar.StopRequested += StopRecording;
            meetingWindow = meeting;
            meeting.FormClosing += (_, args) =>
            {
                if (capture != recording) return;
                args.Cancel = true;
                recording.Stop();
            };
            var panel = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 3, Padding = new Padding(32, 28, 32, 24), BackColor = Night.Canvas };
            panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
            panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
            panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            panel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            var heading = new Label { Text = "Réunion en cours", Font = Night.Serif(26f), ForeColor = Night.Ink, AutoSize = true, Margin = new Padding(0, 0, 0, 14) };
            panel.Controls.Add(heading, 0, 0);
            panel.SetColumnSpan(heading, 2);
            var row = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top, WrapContents = false, Margin = new Padding(0, 0, 0, 18) };
            row.Controls.Add(indicator);
            row.Controls.Add(stop);
            var livePill = new Pill(LiveLabel(), LivePillKind()) { Margin = new Padding(0, 14, 0, 0) };
            row.Controls.Add(livePill);
            var taskPill = new Pill("0 tâche proposée", PillKind.Wait) { Margin = new Padding(10, 14, 0, 0), Visible = false };
            row.Controls.Add(taskPill);
            panel.Controls.Add(row, 0, 1);
            panel.SetColumnSpan(row, 2);
            var notesCardLive = Card("Notes de réunion", meetingNotes);
            notesCardLive.Margin = new Padding(0, 0, 10, 0);
            panel.Controls.Add(notesCardLive, 0, 2);
            var liveText = Editor("Transcription en direct", true);
            liveText.Text = live == null ? LiveWaitingMessage() : "En attente du premier passage…";
            var liveCard = Card("Transcription en direct", liveText);
            liveCard.Margin = new Padding(10, 0, 0, 0);
            panel.Controls.Add(liveCard, 1, 2);
            meeting.Controls.Add(panel);
            meeting.Show(this);
            using var liveTimer = new System.Windows.Forms.Timer { Interval = 700 };
            liveTimer.Tick += (_, _) =>
            {
                livePill.Set(LiveLabel(), LivePillKind());
                if (live != null)
                {
                    var text = live.Transcript.FinalText;
                    if (text.Length > 0 && text != liveText.Text) { liveText.Text = text; liveText.SelectionStart = liveText.TextLength; liveText.ScrollToCaret(); }
                }
                var count = proposals.Count(p => p.State == ProposalState.Pending);
                taskPill.Visible = count > 0;
                if (count > 0) taskPill.Set(count + (count > 1 ? " tâches proposées" : " tâche proposée"), PillKind.Run);
            };
            liveTimer.Start();

            var result = await recording.Finished;
            capture = null;
            homeBar.StopRequested -= StopRecording;
            recordingLevel.Stop();
            meetingWindow = null;
            meeting.Close();
            var liveResult = await FinishLiveAsync();
            if (result.Tracks.Count > 0)
            {
                Directory.CreateDirectory(recording.Folder);
                File.WriteAllText(Path.Combine(recording.Folder, "notes.txt"), meetingNotes.Text);
                if (startedInZoom)
                {
                    File.WriteAllText(Path.Combine(recording.Folder, "source.txt"), "Zoom");
                    File.WriteAllText(Path.Combine(recording.Folder, "titre.txt"), MeetingStore.DefaultTitle(DateTime.Now, true));
                }
                if (liveResult != null)
                {
                    File.WriteAllText(Path.Combine(recording.Folder, "transcription.txt"), liveResult);
                    if (transcriptIncomplete) File.WriteAllText(Path.Combine(recording.Folder, "incomplete.txt"), "Le direct a pu manquer une partie de l’appel.");
                }
                MeetingStore.SaveProposals(recording.Folder, proposals);
                systemAudioOk = result.Tracks.Any(t => t.Path.EndsWith("appel.wav", StringComparison.OrdinalIgnoreCase)) ? true : systemAudioOk;
                var saved = MeetingStore.FromFolder(recording.Folder);
                SetStatus(result.Tracks.Count == 2 ? "Deux pistes enregistrées." : "Pistes disponibles : " + result.Tracks.Count + ".", result.Warnings);
                if (saved != null) OpenMeeting(saved, afterRecording: true);
            }
            else SetStatus("Aucune piste enregistrée.", result.Warnings);
            RefreshReadiness(result.MicrophoneDenied);
            if (result.MicrophoneDenied) OfferMicrophoneSettings();
        }
        catch (Exception error) { SetStatus(error.Message); }
        finally
        {
            recording?.Stop();
            capture = null;
            recordingLevel.Stop();
            meetingWindow = null;
            homeBar.Visible = false;
            record.Visible = true;
            busy = false;
            RefreshActions();
        }
    }

    // Ctrl+R démarre ou arrête l’enregistrement, comme ⌘R sur Mac.
    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        if (keyData == (Keys.Control | Keys.R))
        {
            if (capture != null) capture.Stop();
            else if (record.Enabled && !busy) _ = RecordAsync();
            return true;
        }
        return base.ProcessCmdKey(ref msg, keyData);
    }

    // Notifications Windows : une tâche à valider, le direct interrompu ou une réunion Zoom détectée. Le clic ouvre la page visée.
    private void Notify(string title, string message, string page, ToolTipIcon icon = ToolTipIcon.None)
    {
        notificationTarget = page;
        try { tray.ShowBalloonTip(8000, title, message, icon); } catch { }
    }

    private void OpenFromNotification()
    {
        if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
        Activate();
        if (notificationTarget is { } page) { notificationTarget = null; ShowPage(page); }
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        tray.Visible = false;
        tray.Dispose();
        base.OnFormClosed(e);
    }

    private void ImportAudio()
    {
        if (!CanSwitchMeeting) return;
        using var dialog = new OpenFileDialog { Title = "Ouvrir un enregistrement", Filter = "Audio|*.wav;*.mp3;*.m4a;*.ogg;*.flac;*.webm" };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        MeetingRecord? record;
        try { record = MeetingStore.AddImported(dialog.FileName); }
        catch (Exception error) { SetStatus("Fichier non ajouté : " + error.Message); return; }
        if (record == null) { SetStatus("Fichier audio introuvable : " + dialog.FileName); return; }
        RefreshMeetings();
        OpenMeeting(record);
        SetStatus("Fichier audio prêt : " + Path.GetFileName(dialog.FileName));
    }

    private async Task TranscribeAsync()
    {
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            SetStatus("Ajoute ta clé Gladia dans Paramètres pour transcrire.");
            ShowPage("Paramètres");
            keyField.Focus();
            return;
        }

        using var cancellation = new CancellationTokenSource();
        transcriptionCancellation = cancellation;
        busy = true;
        RefreshActions();
        SetStatus("Envoi de l’audio à Gladia et attente de la transcription…");
        transcript.Text = "Transcription en cours…";
        try
        {
            var text = await gladia.TranscribeAsync(tracks, apiKey, cancellation.Token);
            if (IsDisposed) return;
            transcript.Text = text;
            if (current != null)
            {
                File.WriteAllText(current.TranscriptPath, text);
                current.Transcribed = true;
                var flag = Path.Combine(current.Folder, "incomplete.txt");
                if (File.Exists(flag)) File.Delete(flag);
                transcriptIncomplete = false;
                incompletePill.Visible = false;
            }
            SetStatus("Transcription terminée.");
        }
        catch (OperationCanceledException)
        {
            if (!IsDisposed) { transcript.Text = ""; SetStatus("Gladia n’a pas répondu dans le délai imparti. Tu peux réessayer."); }
        }
        catch (Exception error) { if (!IsDisposed) { transcript.Text = ""; SetStatus(error.Message); } }
        finally
        {
            transcriptionCancellation = null;
            busy = false;
            if (!IsDisposed) RefreshActions();
        }
    }

    // ---------- réglages ----------

    private void SaveKey()
    {
        apiKey = keyField.Text.Trim();
        try
        {
            MeetingStore.SaveKey(apiKey);
            keyMessage.Text = apiKey.Length > 0 ? "Clé enregistrée sur ce PC." : "Clé retirée.";
        }
        catch (Exception error) { keyMessage.Text = error.Message; }
        RefreshKeyPill();
        RefreshReadiness();
        RefreshActions();
    }

    private void SaveSite()
    {
        var address = SiteUri(siteField.Text.Trim());
        if (address == null)
        {
            MessageBox.Show(this, "Indique une adresse HTTPS ou une adresse locale HTTP.", "Adresse invalide");
            return;
        }
        agentSite = address;
        try { MeetingStore.SaveSite(address.GetLeftPart(UriPartial.Authority)); } catch { }
        SetStatus("Adresse du site enregistrée.");
    }

    private void RefreshKeyPill()
    {
        keyPill.Set(string.IsNullOrWhiteSpace(apiKey) ? "Aucune clé" : "Clé enregistrée", string.IsNullOrWhiteSpace(apiKey) ? PillKind.Wait : PillKind.Ok);
        removeKey.Visible = !string.IsNullOrWhiteSpace(apiKey);
    }

    private void RefreshReadiness(bool? microphoneDenied = null)
    {
        var allowed = microphoneDenied.HasValue ? !microphoneDenied.Value : MicrophoneAllowed();
        micDot.Text = allowed ? "●  Micro autorisé" : "●  Micro refusé";
        micDot.ForeColor = allowed ? Night.Accent : Night.Rec;
        audioDot.Text = systemAudioOk == true ? "●  Audio système autorisé" : "●  Audio système non vérifié";
        audioDot.ForeColor = systemAudioOk == true ? Night.Accent : Night.Warn;
        var hasKey = !string.IsNullOrWhiteSpace(apiKey);
        keyDot.Text = hasKey ? "●  Clé Gladia enregistrée" : "●  Ajouter la clé Gladia";
        keyDot.LinkColor = hasKey ? Night.Accent : Night.Ink;
        keyDot.LinkBehavior = hasKey ? LinkBehavior.NeverUnderline : LinkBehavior.AlwaysUnderline;
    }

    private static bool MicrophoneAllowed()
    {
        try
        {
            const string path = @"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone";
            using var user = Registry.CurrentUser.OpenSubKey(path);
            using var machine = Registry.LocalMachine.OpenSubKey(path);
            using var desktop = Registry.CurrentUser.OpenSubKey(path + @"\NonPackaged");
            return (user?.GetValue("Value") as string ?? "Allow") == "Allow"
                && (machine?.GetValue("Value") as string ?? "Allow") == "Allow"
                && (desktop?.GetValue("Value") as string ?? "Allow") == "Allow";
        }
        catch { return true; }
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
        catch (Exception error) { SetStatus(error.Message); }
    }

    private void SetStatus(string text, List<string>? warnings = null)
    {
        status.Text = warnings is { Count: > 0 } ? text + " " + string.Join(" ", warnings) : text;
        status.Visible = status.Text != "Prêt à enregistrer";
    }

    private void RefreshActions()
    {
        record.Enabled = import.Enabled = !busy;
        record.Text = busy && capture != null ? "Enregistrement en cours…" : "Commencer à enregistrer";
        transcribe.Enabled = !busy && tracks.Count > 0;
        folder.Enabled = !busy && audioFolder != null;
        copy.Enabled = !busy && transcript.TextLength > 0 && transcript.Text != "Transcription en cours…";
        saveKey.Enabled = !busy;
        newRecording.Enabled = CanSwitchMeeting;
        showMeeting.Visible = capture != null && meetingWindow is { IsDisposed: false };
        renameMeeting.Enabled = current != null;
        deleteMeeting.Enabled = current != null && CanDeleteMeetings;
    }

    private static string? FirstName()
    {
        var name = Environment.UserName;
        if (string.IsNullOrWhiteSpace(name)) return null;
        var first = name.Split(' ', '.', '_', '-')[0];
        return first.Length == 0 ? null : char.ToUpper(first[0]) + first.Substring(1);
    }

    // ---------- fabrique de contrôles ----------

    private static Panel ScrollPane() => new() { Dock = DockStyle.Fill, AutoScroll = true, BackColor = Night.Canvas };

    // Comme sur Mac (maxWidth 800, marges 48, centré) : colonne de 800 pt au plus, centrée dans la page.
    private static int PageWidth(Panel scroll, FlowLayoutPanel content)
    {
        var scale = scroll.DeviceDpi / 96f;
        var available = scroll.ClientSize.Width - SystemInformation.VerticalScrollBarWidth;
        var column = (int)Math.Min(800 * scale, Math.Max(300, available - 96 * scale));
        var side = Math.Max((int)(48 * scale), (available - column) / 2);
        if (content.Padding.Left != side || content.Padding.Right != side)
            content.Padding = new Padding(side, content.Padding.Top, side, content.Padding.Bottom);
        return column;
    }

    private static FlowLayoutPanel Column(int left, int top, int right, int bottom) => new()
    {
        Dock = DockStyle.Top, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink,
        FlowDirection = FlowDirection.TopDown, WrapContents = false, Padding = new Padding(left, top, right, bottom), BackColor = Night.Canvas
    };

    private static Glass Section(string title, out FlowLayoutPanel stack)
    {
        var glass = new Glass { AutoSize = true, Padding = new Padding(20), Margin = new Padding(0, 0, 0, 18), MinimumSize = new Size(620, 0) };
        stack = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true, FlowDirection = FlowDirection.TopDown, WrapContents = false, Margin = new Padding(0), BackColor = Night.Surface };
        stack.Controls.Add(new Label { Text = title, Font = Night.Serif(16.5f), ForeColor = Night.Ink, AutoSize = true, Margin = new Padding(0, 0, 0, 12) });
        glass.Controls.Add(stack);
        return glass;
    }

    private static Label FieldLabel(string text) => new() { Text = text, AutoSize = true, Font = Night.Sans(10f, true), ForeColor = Night.Ink, Margin = new Padding(0, 0, 0, 6) };

    private static Label Muted(string text) => new() { Text = text, ForeColor = Night.Ink2, AutoSize = true, MaximumSize = new Size(560, 0), Font = Night.Sans(10f), Margin = new Padding(0) };

    private static Label Dot() => new() { AutoSize = true, Font = Night.Sans(9.5f), ForeColor = Night.Ink2, Margin = new Padding(0, 0, 18, 0) };

    private static Glass Card(string title, Control body)
    {
        var card = new Glass { Dock = DockStyle.Fill, Padding = new Padding(16) };
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 2, BackColor = Night.Surface };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.Controls.Add(new Label { Text = title, Font = Night.Sans(10.5f, true), ForeColor = Night.Ink, AutoSize = true, Margin = new Padding(0, 0, 0, 10) }, 0, 0);
        layout.Controls.Add(body, 0, 1);
        card.Controls.Add(layout);
        return card;
    }

    private static TextBox Editor(string label, bool readOnly = false) => new()
    {
        AccessibleName = label, Multiline = true, Dock = DockStyle.Fill, BorderStyle = BorderStyle.None,
        ScrollBars = ScrollBars.Vertical, ReadOnly = readOnly, BackColor = Night.Surface, ForeColor = Night.Ink, Font = Night.Sans(10.5f)
    };

    private static TextBox Field(string label, bool secret = false) => new()
    {
        AccessibleName = label, UseSystemPasswordChar = secret, BackColor = Night.Well, ForeColor = Night.Ink, BorderStyle = BorderStyle.FixedSingle, Font = Night.Sans(10.5f)
    };
}
