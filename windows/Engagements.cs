using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace MeetinOS;

// Onglet « Engagements » : même design et même logique que la page Réunion du site
// (web/app/reunions/[id]) et que l'écran après-réunion du Mac (mac/Review.swift).
// Contrat front ↔ agent : docs/contrat-front-agent.md. L'agent est simulé : pour brancher la vraie
// route, remplace FixtureAgent.SubmitAsync par un appel HTTP.

internal static class Brand
{
    public static readonly Color Canvas = ColorTranslator.FromHtml("#FAF8F1");
    public static readonly Color Surface = ColorTranslator.FromHtml("#EDE9DA");
    public static readonly Color Ink = ColorTranslator.FromHtml("#14201C");
    public static readonly Color Ink2 = ColorTranslator.FromHtml("#5E675F");
    public static readonly Color Accent = ColorTranslator.FromHtml("#CFE86B");
    public static readonly Color AccentTint = ColorTranslator.FromHtml("#EEF3C7");
    public static readonly Color AccentText = ColorTranslator.FromHtml("#5C6B0F");
    public static readonly Color Rec = ColorTranslator.FromHtml("#C8341C");
    public static readonly Color RecTint = ColorTranslator.FromHtml("#FBEAE6");
    public static readonly Color Warn = ColorTranslator.FromHtml("#8A5A0B");
    public static readonly Color WarnTint = ColorTranslator.FromHtml("#F6E7C8");
}

// ---------- Contrat ----------

internal sealed class Proposal
{
    public Proposal(string id, string title, string? assignee, string? dueDate, string excerpt, int startMs, int endMs)
    {
        Id = id; Title = title; Assignee = assignee; DueDate = dueDate; Excerpt = excerpt; StartMs = startMs; EndMs = endMs;
    }
    public string Id { get; }
    public string Title { get; }
    public string? Assignee { get; }
    public string? DueDate { get; }
    public string Excerpt { get; }
    public int StartMs { get; }
    public int EndMs { get; }
}

internal sealed class Validation
{
    public Validation(string validationId, string proposalId, string title, string assignee, string? dueDate)
    {
        ValidationId = validationId; ProposalId = proposalId; Title = title; Assignee = assignee; DueDate = dueDate;
    }
    public string ValidationId { get; }
    public string ProposalId { get; }
    public string Title { get; }
    public string Assignee { get; }
    public string? DueDate { get; }
    public bool SameContent(string title, string assignee, string? dueDate) =>
        Title == title && Assignee == assignee && DueDate == dueDate;
}

internal enum ExecutionStatus { Pending, Verified, NeedsClarification, Failed }

internal sealed class Execution
{
    public Execution(ExecutionStatus status, string validationId, string? taskUrl = null, string? message = null, Validation? observed = null)
    {
        Status = status; ValidationId = validationId; TaskUrl = taskUrl; Message = message; Observed = observed;
    }
    public ExecutionStatus Status { get; }
    public string ValidationId { get; }
    public string? TaskUrl { get; }
    public string? Message { get; }
    public Validation? Observed { get; }
}

internal enum Scenario { Verified, Ambigu, Failed }

// ---------- Données de démo (copie de web/lib/reunions-demo.json, réunion « Point de lancement ») ----------

internal static class ReviewDemo
{
    public const string FixtureProposalId = "proposal-demo-001";
    public const string TaskUrl = "https://example.com/tasks/demo-42";
    public const string Clarification = "Deux fiches correspondent à « Relire le guide de lancement ». Précisez le projet.";
    public const string Failure = "La fiche n’a pas pu être relue après la mise à jour.";

    public static readonly Proposal[] Proposals =
    {
        new("proposal-demo-001", "Relire le guide de lancement", "Karim", "2026-11-10",
            "Léa devait relire le guide. Finalement, Karim s’en charge mardi.", 18000, 24000),
        new("proposal-demo-002", "Envoyer le devis à Atlas", "Léa", "2026-11-12",
            "Je m’en occupe, j’envoie le devis à Atlas jeudi.", 763000, 768000),
        new("proposal-demo-003", "Préparer la démo pour le jury", null, null,
            "Il faudrait que quelqu’un prépare la démo pour le jury, on verra qui.", 1534000, 1540000),
    };

    public static string Label(Scenario scenario) => scenario switch
    {
        Scenario.Ambigu => "Fiche ambiguë",
        Scenario.Failed => "Échec puis relance",
        _ => "Fiche mise à jour",
    };
}

internal static class ReviewFormat
{
    private static readonly CultureInfo French = CultureInfo.GetCultureInfo("fr-FR");

    /// <summary>Millisecondes depuis le début de l'audio → « mm:ss ».</summary>
    public static string Time(int ms)
    {
        var total = Math.Max(0, ms / 1000);
        return $"{total / 60:00}:{total % 60:00}";
    }

    public static DateTime? Parse(string? civil) =>
        DateTime.TryParseExact(civil, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var date) ? date : null;

    public static string? Civil(DateTime? date) => date?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    public static string Due(string? civil) => Parse(civil)?.ToString("dddd d MMMM yyyy", French) ?? "Aucune";

    public static string DueShort(string? civil) => Parse(civil)?.ToString("ddd d MMM", French) ?? "Sans échéance";

    /// <summary>Sépare la dernière phrase de l'extrait pour la passer au surligneur.</summary>
    public static (string Before, string Highlight) SplitExcerpt(string text)
    {
        var cut = new[] { ". ", "! ", "? ", "… " }
            .Select(separator => text.LastIndexOf(separator, StringComparison.Ordinal))
            .Where(index => index >= 0)
            .Select(index => index + 2)
            .DefaultIfEmpty(-1)
            .Max();
        return cut < 0 ? ("", text) : (text.Substring(0, cut).TrimEnd(), text.Substring(cut));
    }
}

/// <summary>Agent simulé, idempotent : une validation déjà vérifiée renvoie la même fiche.</summary>
internal sealed class FixtureAgent
{
    private readonly Scenario scenario;
    private readonly Dictionary<string, Execution> results = new();
    private string? firstId;
    private int attempts;

    public FixtureAgent(Scenario scenario) => this.scenario = scenario;

    public async Task<(Execution Result, bool Replayed)> SubmitAsync(Validation validation)
    {
        await Task.Delay(1700);
        var id = validation.ValidationId;
        if (results.TryGetValue(id, out var known) && known.Status == ExecutionStatus.Verified) return (known, true);
        attempts += 1;
        firstId ??= id;
        var isFixture = validation.ProposalId == ReviewDemo.FixtureProposalId;
        Execution result;
        if (scenario == Scenario.Ambigu && id == firstId)
        {
            var message = isFixture ? ReviewDemo.Clarification : $"Deux fiches correspondent à « {validation.Title} ». Précisez le projet.";
            result = new Execution(ExecutionStatus.NeedsClarification, id, message: message);
        }
        else if (scenario == Scenario.Failed && attempts == 1)
        {
            result = new Execution(ExecutionStatus.Failed, id, message: ReviewDemo.Failure);
        }
        else
        {
            var url = isFixture ? ReviewDemo.TaskUrl : $"https://example.com/tasks/{validation.ProposalId}";
            result = new Execution(ExecutionStatus.Verified, id, taskUrl: url, observed: validation);
        }
        results[id] = result;
        return (result, false);
    }
}

// ---------- Panneau des engagements ----------

/// <summary>L'accordéon : une seule carte ouverte à la fois, avec le seul bouton citron « Valider ».</summary>
internal sealed class EngagementsPanel : UserControl
{
    private readonly FlowLayoutPanel list = new()
    {
        Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true,
        Padding = new Padding(0, 4, 0, 12), BackColor = Brand.Canvas
    };
    private readonly Label count = new() { AutoSize = true, Padding = new Padding(8, 3, 8, 3), Margin = new Padding(12, 10, 0, 0) };
    private readonly ComboBox demo = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 170, AccessibleName = "Scénario de démo" };
    private readonly List<EngagementCard> cards = new();
    private string? openId;

    public event Action? ShowTranscriptRequested;
    internal FixtureAgent Agent { get; private set; } = new(Scenario.Verified);

    public EngagementsPanel()
    {
        Dock = DockStyle.Fill;
        BackColor = Brand.Canvas;
        ForeColor = Brand.Ink;

        var title = new Label { Text = "Engagements", AutoSize = true, Font = new Font("Georgia", 18), AccessibleRole = AccessibleRole.StaticText };
        var demoLabel = new Label { Text = "Données de démo", AutoSize = true, ForeColor = Brand.Ink2, Margin = new Padding(24, 12, 6, 0) };
        foreach (Scenario scenario in Enum.GetValues(typeof(Scenario))) demo.Items.Add(ReviewDemo.Label(scenario));
        demo.SelectedIndex = 0;
        demo.SelectedIndexChanged += (_, _) => Build((Scenario)demo.SelectedIndex);

        var header = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true, WrapContents = true, Padding = new Padding(0, 0, 0, 6) };
        header.Controls.AddRange(new Control[] { title, count, demoLabel, demo });
        Controls.Add(list);
        Controls.Add(header);
        list.Resize += (_, _) => FitCards();
        Build(Scenario.Verified);
    }

    private void Build(Scenario scenario)
    {
        Agent = new FixtureAgent(scenario);
        list.SuspendLayout();
        foreach (var card in cards) card.Dispose();
        cards.Clear();
        list.Controls.Clear();
        foreach (var proposal in ReviewDemo.Proposals)
        {
            var card = new EngagementCard(proposal, this);
            cards.Add(card);
            list.Controls.Add(card);
        }
        openId = cards.FirstOrDefault()?.Id;
        foreach (var card in cards) card.SetOpen(card.Id == openId);
        FitCards();
        list.ResumeLayout();
        Changed();
    }

    private void FitCards()
    {
        var width = Math.Max(300, list.ClientSize.Width - SystemInformation.VerticalScrollBarWidth - 8);
        foreach (var card in cards) card.SetWidth(width);
    }

    internal bool IsSendingAny => cards.Any(card => card.IsSending);

    internal void Toggle(EngagementCard card)
    {
        openId = openId == card.Id ? null : card.Id;
        foreach (var other in cards) other.SetOpen(other.Id == openId);
        if (openId != null) list.ScrollControlIntoView(card);
    }

    internal void Changed()
    {
        var todo = cards.Count(card => card.IsTodo);
        count.Text = todo > 0 ? $"{todo} à valider" : "Tout est traité";
        count.BackColor = Brand.AccentTint;
        count.ForeColor = Brand.AccentText;
        demo.Enabled = !IsSendingAny;
    }

    /// <summary>Laisse voir la fiche vérifiée, puis ouvre l'engagement suivant à valider.</summary>
    internal void Verified(EngagementCard card)
    {
        Changed();
        // Minuteur WinForms : il se déclenche toujours sur le fil de l'interface.
        var delay = new Timer { Interval = 1500 };
        delay.Tick += (_, _) =>
        {
            delay.Stop();
            delay.Dispose();
            if (IsDisposed || card.IsDisposed || openId != card.Id) return;
            var next = cards.FirstOrDefault(other => other.IsTodo && !other.IsSending);
            if (next != null) Toggle(next);
        };
        delay.Start();
    }

    internal void ShowTranscript() => ShowTranscriptRequested?.Invoke();
}

internal enum ReviewState { Proposed, Validated, Ignored }

/// <summary>Une carte : repliée, l'essentiel ; ouverte, les champs, l'extrait et le suivi de l'agent.</summary>
internal sealed class EngagementCard : Panel
{
    private const int StepCount = 5;
    private readonly Proposal proposal;
    private readonly EngagementsPanel owner;
    private readonly Timer stepTimer = new() { Interval = 280 };
    private readonly List<Label> stepLabels = new();
    private string title;
    private string assignee;
    private DateTime? due;
    private ReviewState state = ReviewState.Proposed;
    private bool open;
    private bool editingTitle;
    private Validation? validation;
    private Execution? execution;
    private bool replayed;
    private int runningStep;
    private string? notice;
    private Button? toggle;
    private Label? summary;
    private Label? pill;
    private Button? validate;
    private TableLayoutPanel? stack;
    private int innerWidth = 440;

    public EngagementCard(Proposal proposal, EngagementsPanel owner)
    {
        this.proposal = proposal;
        this.owner = owner;
        title = proposal.Title;
        assignee = proposal.Assignee ?? "";
        due = ReviewFormat.Parse(proposal.DueDate);
        BackColor = Brand.Surface;
        ForeColor = Brand.Ink;
        Padding = new Padding(16, 12, 16, 14);
        Margin = new Padding(0, 0, 0, 10);
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        stepTimer.Tick += (_, _) => { runningStep = Math.Min(runningStep + 1, StepCount - 1); UpdateSteps(); };
        Render();
    }

    public string Id => proposal.Id;
    public bool IsSending => execution?.Status == ExecutionStatus.Pending;
    public bool IsTodo => state != ReviewState.Ignored && execution?.Status != ExecutionStatus.Verified;
    private string? DueValue => ReviewFormat.Civil(due);
    private bool CanValidate => title.Trim().Length > 0 && assignee.Trim().Length > 0 && !IsSending;

    public void SetOpen(bool value)
    {
        if (open == value && Controls.Count > 0) return;
        open = value;
        Render();
    }

    /// <summary>Largeur imposée par la liste : la carte ne grandit qu'en hauteur (pas de cycle de taille automatique).</summary>
    public void SetWidth(int width)
    {
        if (MinimumSize.Width == width) return;
        MinimumSize = new Size(width, 0);
        MaximumSize = new Size(width, 0);
        innerWidth = width - Padding.Horizontal;
        Render();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) stepTimer.Dispose();
        base.Dispose(disposing);
    }

    // ---------- Rendu ----------

    private void Render()
    {
        SuspendLayout();
        foreach (Control control in Controls) control.Dispose();
        Controls.Clear();
        stepLabels.Clear();
        stack = new TableLayoutPanel
        {
            ColumnCount = 1, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, BackColor = Brand.Surface,
            Location = new Point(Padding.Left, Padding.Top), Margin = Padding.Empty,
            MinimumSize = new Size(innerWidth, 0), MaximumSize = new Size(innerWidth, 0)
        };
        stack.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        stack.Controls.Add(Header());
        if (open) foreach (var control in Body()) stack.Controls.Add(control);
        Controls.Add(stack);
        ResumeLayout();
        UpdateHeader();
    }

    private Control Header()
    {
        toggle = new Button
        {
            FlatStyle = FlatStyle.Flat, TextAlign = ContentAlignment.MiddleLeft, AutoSize = true, Cursor = Cursors.Hand,
            Font = new Font("Georgia", 13), BackColor = Brand.Surface, ForeColor = Brand.Ink, Padding = Padding.Empty, Margin = Padding.Empty
        };
        toggle.FlatAppearance.BorderSize = 0;
        toggle.FlatAppearance.MouseOverBackColor = Brand.Surface;
        toggle.FlatAppearance.MouseDownBackColor = Brand.Surface;
        toggle.Click += (_, _) => owner.Toggle(this);
        summary = new Label { AutoSize = true, ForeColor = Brand.Ink2, Margin = new Padding(3, 0, 0, 0) };
        summary.Click += (_, _) => owner.Toggle(this);
        pill = new Label { AutoSize = true, Padding = new Padding(8, 3, 8, 3), Anchor = AnchorStyles.Right };

        var header = new TableLayoutPanel { ColumnCount = 2, RowCount = 2, Dock = DockStyle.Fill, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink };
        header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        header.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        header.Controls.Add(toggle, 0, 0);
        header.Controls.Add(summary, 0, 1);
        header.Controls.Add(pill, 1, 0);
        header.SetRowSpan(pill, 2);
        return header;
    }

    private void UpdateHeader()
    {
        if (toggle == null || summary == null || pill == null) return;
        toggle.Text = (title.Trim().Length > 0 ? title.Trim() : "Sans titre") + (open ? "  ▴" : "  ▾");
        toggle.AccessibleName = $"{title}, {(open ? "replier" : "ouvrir")} l’engagement";
        summary.Text = $"{(assignee.Trim().Length > 0 ? assignee.Trim() : "Responsable à préciser")} · {ReviewFormat.DueShort(DueValue)}";
        var (text, back, fore) = PillStyle();
        pill.Text = text;
        pill.BackColor = back;
        pill.ForeColor = fore;
        if (validate != null) validate.Enabled = CanValidate;
    }

    private (string, Color, Color) PillStyle()
    {
        if (state == ReviewState.Ignored) return ("Ignoré", Brand.Canvas, Brand.Ink2);
        return execution?.Status switch
        {
            ExecutionStatus.Pending => ("En cours", Brand.AccentTint, Brand.AccentText),
            ExecutionStatus.Verified => ("Fiche à jour", Brand.AccentTint, Brand.AccentText),
            ExecutionStatus.NeedsClarification => ("Précision requise", Brand.RecTint, Brand.Rec),
            ExecutionStatus.Failed => ("Échec", Brand.RecTint, Brand.Rec),
            _ => ("À valider", Brand.Canvas, Brand.Ink2),
        };
    }

    private IEnumerable<Control> Body()
    {
        var locked = state != ReviewState.Proposed || IsSending;
        validate = null;

        if (editingTitle)
        {
            var titleBox = new TextBox { Text = title, Width = 360, Font = new Font("Georgia", 12), AccessibleName = "Titre de l’engagement" };
            titleBox.TextChanged += (_, _) => { title = titleBox.Text; UpdateHeader(); };
            yield return Field("Titre", titleBox);
        }

        var assigneeBox = new TextBox { Text = assignee, Width = 170, Enabled = !locked, AccessibleName = "Responsable" };
        assigneeBox.TextChanged += (_, _) => { assignee = assigneeBox.Text; UpdateHeader(); };
        var dueBox = new DateTimePicker
        {
            Format = DateTimePickerFormat.Custom, CustomFormat = "dd/MM/yyyy", Width = 150, ShowCheckBox = true,
            Checked = due != null, Value = due ?? DateTime.Today, Enabled = !locked, AccessibleName = "Échéance (case décochée : aucune)"
        };
        dueBox.ValueChanged += (_, _) => { due = dueBox.Checked ? dueBox.Value.Date : null; UpdateHeader(); };
        var fields = Row(Field("Responsable", assigneeBox), Field("Échéance", dueBox));
        fields.Margin = new Padding(0, 10, 0, 0);
        yield return fields;

        if (assignee.Trim().Length == 0 && state == ReviewState.Proposed)
            yield return Note("Personne n’a été désigné. Renseigne le responsable pour pouvoir valider.", Brand.Surface, Brand.Ink2);
        if (notice != null) yield return Note(notice, Brand.WarnTint, Brand.Warn);

        yield return Excerpt();

        if (state == ReviewState.Proposed)
        {
            validate = ActionButton("Valider", primary: true);
            validate.Enabled = CanValidate;
            validate.Click += async (_, _) => await ValidateAsync();
            var edit = ActionButton(editingTitle ? "Terminer" : "Corriger le titre");
            edit.Click += (_, _) => { editingTitle = !editingTitle; Render(); };
            var ignore = ActionButton("Ignorer");
            ignore.FlatAppearance.BorderSize = 0;
            ignore.ForeColor = Brand.Ink2;
            ignore.Click += (_, _) => { state = ReviewState.Ignored; editingTitle = false; owner.Changed(); Render(); };
            yield return Row(validate, edit, ignore);
        }
        else if (state == ReviewState.Ignored)
        {
            var resume = ActionButton("Reprendre");
            resume.Click += (_, _) => { state = ReviewState.Proposed; owner.Changed(); Render(); };
            yield return Row(new Label { Text = "Ignoré. Rien n’est envoyé à l’agent.", AutoSize = true, ForeColor = Brand.Ink2, Margin = new Padding(0, 9, 8, 0) }, resume);
        }
        else
        {
            yield return new Label { Text = "Validé et envoyé à l’agent.", AutoSize = true, ForeColor = Brand.Ink2, Margin = new Padding(0, 8, 0, 0) };
        }

        if (execution != null && validation != null) yield return AgentSection(validation, execution);
    }

    private Control Excerpt()
    {
        var (before, highlight) = ReviewFormat.SplitExcerpt(proposal.Excerpt);
        var quote = new FlowLayoutPanel { AutoSize = true, WrapContents = true, BackColor = Brand.Canvas, Padding = new Padding(10, 8, 10, 8), MaximumSize = new Size(innerWidth, 0) };
        if (before.Length > 0) quote.Controls.Add(new Label { Text = "« " + before, AutoSize = true, MaximumSize = new Size(Math.Max(240, innerWidth - 24), 0), Margin = new Padding(0, 0, 4, 2) });
        quote.Controls.Add(new Label
        {
            Text = (before.Length > 0 ? "" : "« ") + highlight + " »", AutoSize = true, BackColor = Brand.Accent, ForeColor = Brand.Ink,
            MaximumSize = new Size(Math.Max(240, innerWidth - 24), 0), Padding = new Padding(3, 1, 3, 1), Margin = new Padding(0, 0, 0, 2)
        });
        var time = new LinkLabel
        {
            Text = $"{ReviewFormat.Time(proposal.StartMs)} · Voir dans la transcription", AutoSize = true,
            LinkColor = Brand.AccentText, ActiveLinkColor = Brand.Ink, Margin = new Padding(0, 4, 0, 0)
        };
        time.LinkClicked += (_, _) => owner.ShowTranscript();
        quote.SetFlowBreak(quote.Controls[quote.Controls.Count - 1], true);
        quote.Controls.Add(time);
        quote.Margin = new Padding(0, 10, 0, 6);
        return quote;
    }

    private Control AgentSection(Validation current, Execution result)
    {
        var panel = new TableLayoutPanel { ColumnCount = 1, AutoSize = true, BackColor = Brand.Canvas, Padding = new Padding(12, 10, 12, 10), Margin = new Padding(0, 10, 0, 0), Dock = DockStyle.Fill };
        var (pillText, pillBack, pillFore) = result.Status switch
        {
            ExecutionStatus.Pending => ("En cours", Brand.AccentTint, Brand.AccentText),
            ExecutionStatus.Verified => ("Terminé", Brand.AccentTint, Brand.AccentText),
            ExecutionStatus.NeedsClarification => ("Précision requise", Brand.RecTint, Brand.Rec),
            _ => ("Échec", Brand.RecTint, Brand.Rec),
        };
        panel.Controls.Add(Row(
            new Label { Text = "L’agent", AutoSize = true, Font = new Font("Georgia", 13) },
            new Label { Text = pillText, AutoSize = true, BackColor = pillBack, ForeColor = pillFore, Padding = new Padding(8, 3, 8, 3), Margin = new Padding(10, 3, 0, 0) }));

        var steps = new[]
        {
            $"Retrouve la fiche « {current.Title} »",
            "Ouvre la fiche",
            $"Passe le responsable à {current.Assignee}",
            current.DueDate != null ? $"Fixe l’échéance au {ReviewFormat.Due(current.DueDate)}" : "Laisse l’échéance vide",
            "Relit la fiche pour vérifier",
        };
        foreach (var step in steps)
        {
            var label = new Label { Text = step, AutoSize = true, Tag = step, Margin = new Padding(0, 4, 0, 0) };
            stepLabels.Add(label);
            panel.Controls.Add(label);
        }
        UpdateSteps();

        if (result.Status == ExecutionStatus.Failed)
        {
            var retry = ActionButton("Relancer");
            retry.Click += async (_, _) => await SendAsync(current, replay: false);
            panel.Controls.Add(Row(new Label { Text = result.Message, AutoSize = true, ForeColor = Brand.Rec, Margin = new Padding(0, 9, 8, 0) }, retry));
        }
        if (result.Status == ExecutionStatus.NeedsClarification)
            panel.Controls.Add(new Label { Text = result.Message, AutoSize = true, ForeColor = Brand.Warn, MaximumSize = new Size(Math.Max(240, innerWidth - 24), 0), Margin = new Padding(0, 8, 0, 0) });
        if (result.Status == ExecutionStatus.Verified && result.Observed is { } observed)
        {
            panel.Controls.Add(new Label { Text = "Valeurs relues sur la fiche", AutoSize = true, ForeColor = Brand.Ink2, Margin = new Padding(0, 10, 0, 2) });
            panel.Controls.Add(new Label
            {
                AutoSize = true,
                Text = $"Titre : {observed.Title}\nResponsable : {observed.Assignee}\nÉchéance : {ReviewFormat.Due(observed.DueDate)}",
                BackColor = Brand.Surface, Padding = new Padding(8, 6, 8, 6)
            });
            if (replayed)
                panel.Controls.Add(new Label { Text = "Fiche déjà à jour : aucune nouvelle fiche créée.", AutoSize = true, ForeColor = Brand.AccentText, Margin = new Padding(0, 6, 0, 0) });
            var openRecord = new LinkLabel { Text = "Ouvrir la fiche", AutoSize = true, LinkColor = Brand.AccentText, Margin = new Padding(0, 8, 12, 0) };
            openRecord.LinkClicked += (_, _) => OpenRecord(result.TaskUrl);
            var replay = ActionButton("Rejouer la validation");
            replay.Click += async (_, _) => await SendAsync(current, replay: true);
            panel.Controls.Add(Row(openRecord, replay));
        }
        return panel;
    }

    private void UpdateSteps()
    {
        for (var index = 0; index < stepLabels.Count; index++)
        {
            var (symbol, color) = StepStatus(index);
            stepLabels[index].Text = $"{symbol}  {stepLabels[index].Tag}";
            stepLabels[index].ForeColor = color;
        }
    }

    private (string, Color) StepStatus(int index) => execution?.Status switch
    {
        ExecutionStatus.Pending => index < runningStep ? ("✓", Brand.Ink) : index == runningStep ? ("●", Brand.Ink) : ("○", Brand.Ink2),
        ExecutionStatus.Verified => ("✓", Brand.Ink),
        ExecutionStatus.NeedsClarification => index == 0 ? ("✕", Brand.Rec) : ("○", Brand.Ink2),
        ExecutionStatus.Failed => index < StepCount - 1 ? ("✓", Brand.Ink) : ("✕", Brand.Rec),
        _ => ("○", Brand.Ink2),
    };

    // ---------- Actions ----------

    private async Task ValidateAsync()
    {
        if (!CanValidate) return;
        var cleanTitle = title.Trim();
        var cleanAssignee = assignee.Trim();
        var dueValue = DueValue;
        // Même contenu que la dernière validation → même identifiant. Contenu modifié → nouvel identifiant.
        var id = validation != null && validation.SameContent(cleanTitle, cleanAssignee, dueValue)
            ? validation.ValidationId
            : Guid.NewGuid().ToString();
        state = ReviewState.Validated;
        editingTitle = false;
        notice = null;
        await SendAsync(new Validation(id, proposal.Id, cleanTitle, cleanAssignee, dueValue), replay: false);
    }

    private async Task SendAsync(Validation next, bool replay)
    {
        if (IsSending) return;
        validation = next;
        replayed = false;
        runningStep = 0;
        execution = new Execution(ExecutionStatus.Pending, next.ValidationId);
        owner.Changed();
        Render();
        stepTimer.Start();
        var (result, wasReplay) = await owner.Agent.SubmitAsync(next);
        if (IsDisposed) return;
        if (InvokeRequired) BeginInvoke(new Action(() => Apply(result, wasReplay, replay)));
        else Apply(result, wasReplay, replay);
    }

    /// <summary>Applique la réponse de l'agent, sur le fil de l'interface.</summary>
    private void Apply(Execution result, bool wasReplay, bool replay)
    {
        if (IsDisposed) return;
        stepTimer.Stop();
        execution = result;
        replayed = replay && wasReplay;
        if (result.Status == ExecutionStatus.NeedsClarification)
        {
            // Cible ambiguë : la carte redevient modifiable pour que l'utilisateur précise.
            state = ReviewState.Proposed;
            notice = result.Message + " Corrige le titre pour désigner la bonne fiche, puis valide à nouveau.";
        }
        Render();
        if (result.Status == ExecutionStatus.Verified && !replay) owner.Verified(this);
        else owner.Changed();
    }

    private void OpenRecord(string? url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp)) return;
        try { Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true }); }
        catch (Exception error) { notice = error.Message; Render(); }
    }

    // ---------- Petits blocs ----------

    private static Button ActionButton(string text, bool primary = false)
    {
        var button = new Button
        {
            Text = text, AutoSize = true, MinimumSize = new Size(0, 32), Padding = new Padding(8, 0, 8, 0),
            FlatStyle = FlatStyle.Flat, BackColor = primary ? Brand.Accent : Brand.Surface, ForeColor = Brand.Ink, Margin = new Padding(0, 4, 8, 0)
        };
        button.FlatAppearance.BorderColor = primary ? Brand.Accent : Brand.Ink2;
        return button;
    }

    private static Control Field(string label, Control input)
    {
        var field = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, WrapContents = false, Margin = new Padding(0, 0, 12, 0) };
        field.Controls.Add(new Label { Text = label, AutoSize = true, ForeColor = Brand.Ink2 });
        field.Controls.Add(input);
        return field;
    }

    private Control Note(string text, Color back, Color fore) => new Label
    {
        Text = text, AutoSize = true, BackColor = back, ForeColor = fore, Padding = new Padding(8, 5, 8, 5),
        MaximumSize = new Size(innerWidth, 0), Margin = new Padding(0, 8, 0, 0)
    };

    private static FlowLayoutPanel Row(params Control[] controls)
    {
        var row = new FlowLayoutPanel { AutoSize = true, WrapContents = true, Margin = new Padding(0, 6, 0, 0) };
        row.Controls.AddRange(controls);
        return row;
    }
}
