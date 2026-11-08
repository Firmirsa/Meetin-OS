using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace MeetinOS;

// Mesure le volume des pistes (micro et son de l’appel) pour la barre d’enregistrement.
// Feed est appelé par les fils audio et ne fait qu’un calcul rapide ; Take est lu par l’interface.
internal sealed class AudioLevelMeter
{
    private readonly object gate = new();
    private float loudest;

    public void Feed(byte[] pcm16, int count)
    {
        var rms = Rms(pcm16, count);
        lock (gate) loudest = Math.Max(loudest, rms);
    }

    // Le son le plus fort reçu depuis la dernière lecture, entre 0 (silence) et 1 (voix forte).
    public double Take()
    {
        float value;
        lock (gate) { value = loudest; loudest = 0; }
        return Normalized(value);
    }

    // Puissance moyenne (RMS) d’un bloc PCM 16 bits, ramenée entre 0 et 1.
    public static float Rms(byte[] pcm16, int count)
    {
        var frames = count / 2;
        if (frames == 0) return 0;
        double sum = 0;
        for (var i = 0; i + 1 < count; i += 2)
        {
            var sample = BitConverter.ToInt16(pcm16, i) / 32768d;
            sum += sample * sample;
        }
        var rms = (float)Math.Sqrt(sum / frames);
        return float.IsNaN(rms) || float.IsInfinity(rms) ? 0 : rms;
    }

    // Convertit en décibels : -50 dB ou moins (silence, bruit de fond) donne 0, -10 dB donne 1.
    public static double Normalized(float rms)
    {
        if (rms <= 0) return 0;
        var decibels = 20 * Math.Log10(rms);
        return Math.Min(1, Math.Max(0, (decibels + 50) / 40));
    }
}

// Niveau lissé et chrono, mis à jour 25 fois par seconde pendant l’enregistrement.
internal sealed class RecordingLevel
{
    private readonly System.Windows.Forms.Timer loop = new() { Interval = 40 };
    private AudioLevelMeter? meter;
    private DateTime startedAt;

    public RecordingLevel() { loop.Tick += (_, _) => Update(); }

    public double Level { get; private set; }
    public TimeSpan Elapsed { get; private set; }
    public event Action? Changed;

    public void Start(AudioLevelMeter source, DateTime since)
    {
        Stop();
        meter = source;
        startedAt = since;
        Elapsed = TimeSpan.Zero;
        source.Take();
        loop.Start();
    }

    // Fige le chrono et remet les barres à plat.
    public void Stop()
    {
        loop.Stop();
        meter = null;
        Level = 0;
        Changed?.Invoke();
    }

    private void Update()
    {
        if (meter == null) return;
        var heard = meter.Take();
        // Monte vite quand quelqu’un parle, redescend en douceur au silence : les barres ne tremblent pas.
        var speed = heard > Level ? 0.55 : 0.18;
        var next = Level + (heard - Level) * speed;
        Level = next < 0.02 ? 0 : next;
        Elapsed = DateTime.Now - startedAt;
        Changed?.Invoke();
    }
}

// La barre d’enregistrement de la marque : point rouge, chrono, sept barres de niveau, Pause et Arrêter.
internal sealed class RecordingBar : Control
{
    private static readonly double[] Shape = { 0.45, 0.7, 1.0, 0.6, 0.9, 0.55, 0.35 };
    private static readonly Color Background = ColorTranslator.FromHtml("#14201C");
    private static readonly Color Foreground = ColorTranslator.FromHtml("#FAF8F1");
    private readonly RecordingLevel level;
    private Rectangle pauseRect, stopRect;
    private bool hoverStop, hoverPause;

    public RecordingBar(RecordingLevel level)
    {
        this.level = level;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
        Size = new Size(372, 52);
        Cursor = Cursors.Default;
        AccessibleName = "Enregistrement en cours";
        level.Changed += () => { if (IsHandleCreated && !IsDisposed) Invalidate(); };
    }

    public event Action? StopRequested;
    public event Action? PauseRequested;

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var stop = stopRect.Contains(e.Location);
        var pause = pauseRect.Contains(e.Location);
        if (stop != hoverStop || pause != hoverPause) { hoverStop = stop; hoverPause = pause; Cursor = stop || pause ? Cursors.Hand : Cursors.Default; Invalidate(); }
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        base.OnMouseLeave(e);
        hoverStop = hoverPause = false;
        Invalidate();
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        if (e.Button != MouseButtons.Left || !Enabled) return;
        if (stopRect.Contains(e.Location)) StopRequested?.Invoke();
        else if (pauseRect.Contains(e.Location)) PauseRequested?.Invoke();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        using (var back = new SolidBrush(Parent?.BackColor ?? Night.Canvas)) g.FillRectangle(back, ClientRectangle);
        var bounds = new Rectangle(0, 0, Width - 1, Height - 1);
        using (var path = Rounded(bounds, Height / 2))
        {
            using var fill = new SolidBrush(Background);
            using var edge = new Pen(Color.FromArgb(36, Foreground));
            g.FillPath(fill, path);
            g.DrawPath(edge, path);
        }
        var x = 14;
        var middle = Height / 2;
        using (var red = new SolidBrush(Night.Rec)) g.FillEllipse(red, x, middle - 5, 10, 10);
        x += 22;
        var seconds = (int)level.Elapsed.TotalSeconds;
        var time = $"{seconds / 3600:00}:{seconds % 3600 / 60:00}:{seconds % 60:00}";
        using var mono = Night.Mono(10.5f);
        var timeSize = TextRenderer.MeasureText(g, time, mono, Size.Empty, TextFormatFlags.NoPadding);
        TextRenderer.DrawText(g, time, mono, new Point(x, middle - timeSize.Height / 2), Foreground, TextFormatFlags.NoPadding);
        x += timeSize.Width + 12;
        using (var bar = new SolidBrush(Color.FromArgb(204, Foreground)))
        {
            foreach (var shape in Shape)
            {
                var h = (int)Math.Max(4, 24 * level.Level * shape);
                var rect = new Rectangle(x, middle - h / 2, 3, h);
                using var capsule = Rounded(rect, 1);
                g.FillPath(bar, capsule);
                x += 6;
            }
        }
        x += 12;
        using var font = Night.Sans(10f, true);
        var pauseText = "Pause";
        var pauseSize = TextRenderer.MeasureText(g, pauseText, font, Size.Empty, TextFormatFlags.NoPadding);
        pauseRect = new Rectangle(x, middle - 18, pauseSize.Width + 32, 36);
        using (var ghost = Rounded(pauseRect, 18))
        using (var edge = new Pen(Color.FromArgb(hoverPause ? 140 : 82, Foreground)))
            g.DrawPath(edge, ghost);
        TextRenderer.DrawText(g, pauseText, font, pauseRect, Foreground, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        x = pauseRect.Right + 8;
        var stopText = "Arrêter";
        var stopSize = TextRenderer.MeasureText(g, stopText, font, Size.Empty, TextFormatFlags.NoPadding);
        stopRect = new Rectangle(x, middle - 18, stopSize.Width + 32, 36);
        using (var solid = Rounded(stopRect, 18))
        using (var fill = new SolidBrush(Enabled ? (hoverStop ? Color.White : Foreground) : Color.FromArgb(120, Foreground)))
            g.FillPath(fill, solid);
        TextRenderer.DrawText(g, stopText, font, stopRect, Background, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        var wanted = stopRect.Right + 8;
        if (wanted != Width) Width = wanted;
    }

    private static GraphicsPath Rounded(Rectangle r, int radius)
    {
        var d = Math.Max(1, radius * 2);
        var path = new GraphicsPath();
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}
