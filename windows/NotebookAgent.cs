using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace MeetinOS;

// Direct Gladia, tâches proposées, espace Agent et Intégrations : le pendant Windows de MeetingFlow / AgentWorkspace / Integrations du Mac.
internal sealed partial class Notebook
{
    private readonly Panel proposalsHost = new() { Dock = DockStyle.Top, AutoSize = true, Margin = new Padding(0), Width = 700 };
    private readonly Label detectorError = new() { AutoSize = true, ForeColor = Night.Warn, Visible = false, MaximumSize = new Size(620, 0), Margin = new Padding(0, 0, 0, 10) };
    private readonly TextBox requestField = Field("Demande");
    private readonly TextBox excerptField = Editor("Extrait de réunion");
    private readonly TextBox answerField = Field("Votre précision");
    private readonly Label questionLabel = new() { AutoSize = true, Font = Night.Sans(10.5f, true), ForeColor = Night.Ink, MaximumSize = new Size(600, 0), Margin = new Padding(0, 10, 0, 6) };
    private readonly Label agentError = new() { AutoSize = true, ForeColor = Night.Warn, Visible = false, MaximumSize = new Size(600, 0), Margin = new Padding(0, 8, 0, 0) };
    private readonly Label agentHint = new() { AutoSize = true, ForeColor = Night.Ink2, MaximumSize = new Size(600, 0), Margin = new Padding(0, 0, 0, 12) };
    private readonly Capsule prepare = new("Préparer la tâche", CapsuleKind.Primary);
    private readonly Capsule addAnswer = new("Ajouter cette précision", CapsuleKind.Primary);
    private readonly Capsule insertTranscript = new("Insérer la transcription", CapsuleKind.Ghost);
    private readonly Capsule connectAgent = new("Connecter l’agent", CapsuleKind.Ghost);
    private readonly Panel reviewHost = new() { Dock = DockStyle.Top, AutoSize = true, Margin = new Padding(0, 12, 0, 0), Width = 620 };
    private readonly LinkLabel executionLink = new() { AutoSize = true, LinkColor = Night.Accent, ActiveLinkColor = Night.AccentHover, Visible = false, Margin = new Padding(0, 10, 0, 0) };
    private readonly FlowLayoutPanel questionBlock = new() { AutoSize = true, FlowDirection = FlowDirection.TopDown, WrapContents = false, Visible = false, Margin = new Padding(0) };
    private readonly TextBox serverField = Field("Adresse du site de l’équipe");
    private readonly TextBox codeField = Field("Code d’accès de l’équipe", true);
    private readonly Label integrationsIntro = new() { AutoSize = true, ForeColor = Night.Ink2, MaximumSize = new Size(600, 0), Margin = new Padding(0, 0, 0, 14) };
    private readonly Label integrationsIssue = new() { AutoSize = true, ForeColor = Night.Warn, Visible = false, MaximumSize = new Size(600, 0), Margin = new Padding(0, 8, 0, 0) };
    private readonly Pill gladiaPill = new("Facultatif", PillKind.Wait);
    private readonly Pill trelloPill = new("Non connecté", PillKind.Wait);
    private readonly Pill devinPill = new("Non connecté", PillKind.Wait);
    private readonly Capsule connect = new("Connecter", CapsuleKind.Primary);
    private readonly Capsule verifyAccess = new("Vérifier les accès", CapsuleKind.Primary) { Visible = false };
    private readonly Capsule disconnect = new("Déconnecter", CapsuleKind.Ghost) { Visible = false };
    private AgentPreparation? preparation;
    private List<AgentClarification> clarifications = new();
    private AgentExecution? execution;
    private bool agentBusy;
    private string? executionUrl;

    private AgentClient? Client => agentAccess != null && agentCode.Length > 0 && AgentClient.ServerUri(agentSite.AbsoluteUri) is { } server ? new AgentClient(server, agentCode) : null;

    // ---------- direct ----------

    private LiveTranscription? StartLive(AudioCapture recording)
    {
        if (!liveEnabled || string.IsNullOrWhiteSpace(apiKey)) return null;
        var session = new LiveTranscription(apiKey);
        session.Problem += message => BeginInvoke(new Action(() => SetStatus(message)));
        recording.LiveTap = session.Feed;
        transcriptIncomplete = false;
        return session;
    }

    private string LiveLabel() => live == null
        ? (liveEnabled && string.IsNullOrWhiteSpace(apiKey) ? "Direct : clé Gladia manquante" : "Direct désactivé")
        : live.State switch
        {
            LiveState.Live => "Direct Gladia",
            LiveState.Reconnecting => "Direct : reconnexion…",
            LiveState.Unauthorized => "Direct : clé refusée",
            LiveState.Ended => "Direct arrêté",
            LiveState.Failed => "Direct indisponible",
            _ => "Direct : connexion…"
        };

    private PillKind LivePillKind() => live == null ? PillKind.Wait : live.State switch
    {
        LiveState.Live => PillKind.Ok,
        LiveState.Reconnecting => PillKind.Run,
        LiveState.Unauthorized or LiveState.Failed or LiveState.Ended => PillKind.Rec,
        _ => PillKind.Wait
    };

    private string LiveWaitingMessage() => liveEnabled && string.IsNullOrWhiteSpace(apiKey)
        ? "Ajoute une clé Gladia dans Paramètres pour le direct. L’enregistrement continue."
        : "La transcription sera disponible après l’arrêt de l’enregistrement et l’envoi à Gladia.";

    // Le texte du direct devient la transcription de la réunion ; le dernier passage de détection lit le texte complet.
    private async Task<string?> FinishLiveAsync()
    {
        string? text = null;
        if (live != null)
        {
            SetStatus("Finalisation de la transcription…");
            await live.FinishAsync();
            text = live.Transcript.FinalText;
            transcriptIncomplete = live.IsIncomplete;
            if (text.Length == 0) text = null;
        }
        if (detector != null)
        {
            var finishing = detector;
            await finishing.FinishAsync();
            if (detector == finishing) detector = null;
        }
        live = null;
        return text;
    }

    private TaskDetector? StartDetection()
    {
        if (live == null || agentAccess?.Planning != true || Client is not { } client || SynchronizationContext.Current is not { } ui) return null;
        var transcript = live.Transcript;
        var created = new TaskDetector(() => transcript.ConfirmedText, client.DetectAsync, ui);
        created.NewProposal += proposal =>
        {
            proposals.Add(proposal);
            SetStatus("Tâche proposée : " + proposal.Review.Title);
            if (pageByName["Agent"].Visible) RefreshAgentPage();
        };
        created.UpdatedProposal += _ => { if (pageByName["Agent"].Visible) RefreshAgentPage(); };
        created.Changed += () => { detectorError.Text = created.LastError == null ? "" : "Détection interrompue : " + created.LastError; detectorError.Visible = created.LastError != null; };
        created.Start();
        return created;
    }

    // ---------- page Agent ----------

    private Control AgentPage()
    {
        var scroll = ScrollPane();
        var content = Column(48, 40, 48, 40);
        content.Controls.Add(new Label { Text = "Agent", Font = Night.Serif(30f), ForeColor = Night.Ink, AutoSize = true, Margin = new Padding(0, 0, 0, 18) });
        content.Controls.Add(detectorError);
        content.Controls.Add(proposalsHost);
        content.Controls.Add(new Label { Text = "Tâche à exécuter", Font = Night.Serif(22f), ForeColor = Night.Ink, AutoSize = true, Margin = new Padding(0, 10, 0, 10) });
        content.Controls.Add(agentHint);
        content.Controls.Add(FieldLabel("Demande"));
        requestField.Width = 600;
        requestField.Margin = new Padding(0, 0, 0, 12);
        requestField.TextChanged += (_, _) => InvalidateReview();
        content.Controls.Add(requestField);
        content.Controls.Add(FieldLabel("Extrait de réunion"));
        excerptField.Dock = DockStyle.None;
        excerptField.Size = new Size(600, 110);
        excerptField.BackColor = Night.Well;
        excerptField.BorderStyle = BorderStyle.FixedSingle;
        excerptField.Margin = new Padding(0, 0, 0, 8);
        excerptField.TextChanged += (_, _) => InvalidateReview();
        content.Controls.Add(excerptField);
        var tools = new FlowLayoutPanel { AutoSize = true, WrapContents = true, Margin = new Padding(0, 0, 0, 8) };
        insertTranscript.Click += (_, _) => { var text = transcript.Text; excerptField.Text = text.Length > TaskDetector.MaxTranscript ? text.Substring(0, TaskDetector.MaxTranscript) : text; };
        tools.Controls.Add(insertTranscript);
        content.Controls.Add(tools);
        content.Controls.Add(Muted("Préparer envoie la demande et l’extrait sélectionné à Holo (H Company). Rien n’est lancé sans ta confirmation."));
        var actions = new FlowLayoutPanel { AutoSize = true, WrapContents = true, Margin = new Padding(0, 12, 0, 0) };
        prepare.Click += async (_, _) => await PrepareAsync(null);
        connectAgent.Click += (_, _) => ShowPage("Intégrations");
        actions.Controls.Add(prepare);
        actions.Controls.Add(connectAgent);
        content.Controls.Add(actions);
        questionBlock.Controls.Add(questionLabel);
        answerField.Width = 600;
        answerField.Margin = new Padding(0, 0, 0, 10);
        questionBlock.Controls.Add(answerField);
        addAnswer.Click += async (_, _) => await PrepareAsync(questionLabel.Text);
        questionBlock.Controls.Add(addAnswer);
        content.Controls.Add(questionBlock);
        content.Controls.Add(reviewHost);
        content.Controls.Add(agentError);
        executionLink.LinkClicked += (_, _) => { if (executionUrl != null) Open(executionUrl); };
        content.Controls.Add(executionLink);
        scroll.Controls.Add(content);
        content.Resize += (_, _) => { var w = Math.Max(300, Math.Min(760, content.ClientSize.Width - content.Padding.Horizontal)); proposalsHost.Width = w; reviewHost.Width = Math.Min(w, 620); };
        return scroll;
    }

    private void RefreshAgentPage()
    {
        var client = Client;
        agentHint.Text = client == null
            ? "Tu peux préparer ta demande ici. L’accès de l’équipe sera demandé au moment d’utiliser l’agent."
            : "Le code de l’équipe est validé pour cette session.";
        connectAgent.Visible = client == null;
        prepare.Visible = preparation == null || preparation.Ready;
        prepare.Enabled = !agentBusy && (requestField.Text.Trim().Length > 0 || excerptField.Text.Trim().Length > 0);
        prepare.Text = agentBusy ? "L’agent traite la demande…" : "Préparer la tâche";
        insertTranscript.Enabled = !agentBusy && transcript.TextLength > 0;
        insertTranscript.Text = transcript.TextLength > TaskDetector.MaxTranscript ? "Insérer le début de la transcription" : "Insérer la transcription";
        questionBlock.Visible = preparation?.NeedsClarification == true;
        addAnswer.Enabled = !agentBusy && answerField.Text.Trim().Length > 0;
        RenderReview();
        RenderProposals();
    }

    private void InvalidateReview()
    {
        preparation = null;
        clarifications = new List<AgentClarification>();
        answerField.Text = "";
        agentError.Visible = false;
        if (pageByName.TryGetValue("Agent", out var page) && page.Visible) RefreshAgentPage();
    }

    private async Task PrepareAsync(string? question)
    {
        var client = Client;
        if (client == null) { ShowPage("Intégrations"); return; }
        if (agentAccess?.Planning == false) { ShowPage("Intégrations"); integrationsIssue.Text = "Ton équipe doit activer l’agent sur son serveur. Tu peux continuer à utiliser le carnet."; integrationsIssue.Visible = true; return; }
        var task = requestField.Text.Trim();
        var excerpt = excerptField.Text.Trim();
        if (agentBusy || (task.Length == 0 && excerpt.Length == 0)) return;
        var turns = new List<AgentClarification>(clarifications);
        if (question != null) turns.Add(new AgentClarification { Question = question, Answer = answerField.Text.Trim() });
        agentBusy = true;
        agentError.Visible = false;
        RefreshAgentPage();
        try
        {
            preparation = await client.PrepareAsync(task, excerpt, turns);
            clarifications = turns;
            answerField.Text = "";
            execution = null;
            executionLink.Visible = false;
            if (preparation.NeedsClarification) questionLabel.Text = preparation.Question ?? "";
        }
        catch (Exception error)
        {
            agentError.Text = error.Message + ((error as AgentFailure)?.Status == 401 ? " Modifie l’accès de l’équipe dans Intégrations." : "");
            agentError.Visible = true;
            if ((error as AgentFailure)?.Status == 401) agentAccess = null;
        }
        finally
        {
            agentBusy = false;
            RefreshAgentPage();
        }
    }

    private void RenderReview()
    {
        foreach (var c in reviewHost.Controls.Cast<Control>().ToList()) c.Dispose();
        reviewHost.Controls.Clear();
        if (preparation is not { Ready: true } review) { reviewHost.Visible = false; return; }
        reviewHost.Visible = true;
        var card = ReviewCard("À confirmer", review, null);
        reviewHost.Controls.Add(card);
    }

    private Glass ReviewCard(string heading, AgentReview review, TaskProposal? proposal)
    {
        var glass = new Glass { Dock = DockStyle.Top, AutoSize = true, Padding = new Padding(16), Margin = new Padding(0, 0, 0, 12) };
        var stack = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true, FlowDirection = FlowDirection.TopDown, WrapContents = false, Margin = new Padding(0), BackColor = Night.Surface };
        var head = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0, 0, 0, 6) };
        head.Controls.Add(new Label { Text = proposal == null ? heading : review.Title, Font = Night.Sans(11.5f, true), ForeColor = Night.Ink, AutoSize = true, MaximumSize = new Size(440, 0), Margin = new Padding(0, 2, 12, 0) });
        if (proposal != null) head.Controls.Add(new Pill(proposal.State == ProposalState.Launched ? "Lancée" : "À valider", proposal.State == ProposalState.Launched ? PillKind.Ok : PillKind.Run));
        stack.Controls.Add(head);
        if (proposal == null) stack.Controls.Add(new Label { Text = review.Title, Font = Night.Sans(11f, true), ForeColor = Night.Ink, AutoSize = true, MaximumSize = new Size(560, 0), Margin = new Padding(0, 0, 0, 6) });
        stack.Controls.Add(new Label { Text = review.Task, ForeColor = Night.Ink, AutoSize = true, MaximumSize = new Size(560, 0), Margin = new Padding(0, 0, 0, 6) });
        stack.Controls.Add(new Label { Text = review.Executor.Name() + " · " + review.Destination, ForeColor = Night.Ink2, AutoSize = true, MaximumSize = new Size(560, 0), Margin = new Padding(0, 0, 0, 6) });
        if (review.Quote.Length > 0) stack.Controls.Add(new Label { Text = "« " + review.Quote + " »", ForeColor = Night.Ink2, Font = Night.Sans(9.5f), AutoSize = true, MaximumSize = new Size(560, 0), Margin = new Padding(0, 0, 0, 6) });
        foreach (var turn in review.Turns) stack.Controls.Add(new Label { Text = turn.Question + " " + turn.Answer, ForeColor = Night.Ink2, Font = Night.Sans(9.5f), AutoSize = true, MaximumSize = new Size(560, 0) });
        if (proposal?.Issue != null) stack.Controls.Add(new Label { Text = proposal.Issue, ForeColor = Night.Warn, Font = Night.Sans(9.5f), AutoSize = true, MaximumSize = new Size(560, 0), Margin = new Padding(0, 4, 0, 4) });
        var actions = new FlowLayoutPanel { AutoSize = true, WrapContents = true, Margin = new Padding(0, 8, 0, 0) };
        if (proposal?.State == ProposalState.Launched)
        {
            var link = new LinkLabel { Text = "Suivre dans " + review.Executor.Name(), AutoSize = true, LinkColor = Night.Accent, ActiveLinkColor = Night.AccentHover };
            link.LinkClicked += (_, _) => { if (proposal.SessionUrl != null) Open(proposal.SessionUrl); };
            actions.Controls.Add(link);
        }
        else if (review.UsesTrello && agentAccess?.Trello == false)
        {
            stack.Controls.Add(Muted("Ton équipe doit relier Trello. La proposition reste disponible ici."));
            var see = new Capsule("Voir l’accès Trello", CapsuleKind.Primary);
            see.Click += (_, _) => ShowPage("Intégrations");
            actions.Controls.Add(see);
        }
        else if (review.Executor == AgentExecutor.Devin && agentAccess?.Devin == false)
        {
            stack.Controls.Add(Muted("Ton équipe doit activer Devin avant de lancer cette tâche."));
            var see = new Capsule("Voir l’accès Devin", CapsuleKind.Primary);
            see.Click += (_, _) => ShowPage("Intégrations");
            actions.Controls.Add(see);
        }
        else
        {
            var launch = new Capsule(proposal != null && proposal.Launching ? "Lancement en cours…" : "Confirmer et lancer", proposal == null ? CapsuleKind.Primary : CapsuleKind.Ghost) { Enabled = !agentBusy && Client != null && !(proposal?.Launching ?? false) };
            if (Client == null) { launch.Text = "Connecter l’agent"; launch.Enabled = true; launch.Click += (_, _) => ShowPage("Intégrations"); }
            else launch.Click += async (_, _) => { if (proposal == null) await LaunchReviewAsync(review); else await LaunchProposalAsync(proposal); };
            actions.Controls.Add(launch);
            if (proposal != null)
            {
                var edit = new Capsule("Modifier", CapsuleKind.Ghost) { Enabled = !agentBusy && !proposal.Launching };
                edit.Click += (_, _) => EditProposal(proposal);
                var ignore = new Capsule("Ignorer", CapsuleKind.Ghost) { Enabled = !proposal.Launching };
                ignore.Click += (_, _) => { proposal.State = ProposalState.Ignored; PersistProposals(); RefreshAgentPage(); };
                actions.Controls.Add(edit);
                actions.Controls.Add(ignore);
            }
        }
        stack.Controls.Add(actions);
        glass.Controls.Add(stack);
        return glass;
    }

    private void RenderProposals()
    {
        foreach (var c in proposalsHost.Controls.Cast<Control>().ToList()) c.Dispose();
        proposalsHost.Controls.Clear();
        var visible = proposals.Where(p => p.State != ProposalState.Ignored).ToList();
        if (visible.Count == 0) { proposalsHost.Visible = false; return; }
        proposalsHost.Visible = true;
        for (var i = visible.Count - 1; i >= 0; i--) proposalsHost.Controls.Add(ReviewCard("", visible[i].Review, visible[i]));
        proposalsHost.Controls.Add(new Label { Text = "Tâches proposées", Font = Night.Serif(22f), ForeColor = Night.Ink, AutoSize = true, Dock = DockStyle.Top, Margin = new Padding(0, 0, 0, 12), Padding = new Padding(0, 0, 0, 12) });
    }

    private void EditProposal(TaskProposal proposal)
    {
        if (agentBusy) return;
        InvalidateReview();
        requestField.Text = proposal.Review.Task;
        excerptField.Text = proposal.Review.Quote;
        execution = null;
        executionLink.Visible = false;
        proposal.State = ProposalState.Ignored;
        PersistProposals();
        RefreshAgentPage();
    }

    private async Task LaunchReviewAsync(AgentReview review)
    {
        var client = Client;
        if (client == null || agentBusy) return;
        agentBusy = true;
        agentError.Visible = false;
        RefreshAgentPage();
        try
        {
            execution = await client.LaunchAsync(review);
            executionUrl = execution.Url;
            executionLink.Text = "Suivre dans " + execution.Executor.Name();
            executionLink.Visible = true;
            preparation = null;
            SetStatus("Tâche lancée : " + review.Title + " · " + execution.Executor.Name());
        }
        catch (Exception error)
        {
            var failure = error as AgentFailure;
            if (failure?.Status == 401) agentAccess = null;
            if (failure?.Status != 401 && failure?.Code != "trello_setup") preparation = null;
            agentError.Text = error.Message;
            agentError.Visible = true;
        }
        finally
        {
            agentBusy = false;
            RefreshAgentPage();
        }
    }

    // Seul un clic lance une tâche détectée.
    private async Task LaunchProposalAsync(TaskProposal proposal)
    {
        var client = Client;
        if (client == null || proposal.Launching || proposal.State != ProposalState.Pending) return;
        proposal.Launching = true;
        proposal.Issue = null;
        RefreshAgentPage();
        try
        {
            var result = await client.LaunchAsync(proposal.Review);
            proposal.State = ProposalState.Launched;
            proposal.SessionUrl = result.Url;
            SetStatus("Tâche lancée : " + proposal.Review.Title + " · " + result.Executor.Name());
        }
        catch (Exception error) { proposal.Issue = error.Message; }
        finally
        {
            proposal.Launching = false;
            PersistProposals();
            RefreshAgentPage();
        }
    }

    private void PersistProposals()
    {
        if (current != null) MeetingStore.SaveProposals(current.Folder, proposals);
    }

    // ---------- page Intégrations ----------

    private Control IntegrationsPage()
    {
        var scroll = ScrollPane();
        var content = Column(48, 40, 48, 40);
        content.Controls.Add(new Label { Text = "Intégrations", Font = Night.Serif(30f), ForeColor = Night.Ink, AutoSize = true, Margin = new Padding(0, 0, 0, 14) });
        content.Controls.Add(integrationsIntro);
        var tools = Section("Outils", out var toolsStack);
        toolsStack.Controls.Add(ToolRow("Gladia", "Transcrire un enregistrement", gladiaPill, "Configurer", () => ShowPage("Paramètres")));
        toolsStack.Controls.Add(ToolRow("Trello", "Créer une fiche après ta confirmation", trelloPill, null, null));
        toolsStack.Controls.Add(ToolRow("Google Calendar", "Retrouver les réunions prévues", new Pill("À venir", PillKind.Wait), null, null));
        toolsStack.Controls.Add(ToolRow("Devin", "Confier une tâche de code", devinPill, null, null));
        content.Controls.Add(tools);
        var agent = Section("Connecter l’agent", out var agentStack);
        agentStack.Controls.Add(Muted("Utilise le code fourni par ton équipe. Il donne accès aux outils qu’elle a configurés."));
        agentStack.Controls.Add(FieldLabel("Adresse du site de l’équipe"));
        serverField.Width = 560;
        serverField.Margin = new Padding(0, 0, 0, 12);
        agentStack.Controls.Add(serverField);
        agentStack.Controls.Add(FieldLabel("Code d’accès de l’équipe"));
        codeField.Width = 560;
        codeField.Margin = new Padding(0, 0, 0, 12);
        agentStack.Controls.Add(codeField);
        var actions = new FlowLayoutPanel { AutoSize = true, WrapContents = true, Margin = new Padding(0) };
        connect.Click += async (_, _) => await ConnectAgentAsync();
        verifyAccess.Click += async (_, _) => await RefreshAccessAsync(true);
        disconnect.Click += (_, _) => { agentCode = ""; agentAccess = null; MeetingStore.SaveAgentCode(""); codeField.Text = ""; RefreshIntegrationsPage(); };
        actions.Controls.Add(connect);
        actions.Controls.Add(verifyAccess);
        actions.Controls.Add(disconnect);
        agentStack.Controls.Add(actions);
        agentStack.Controls.Add(integrationsIssue);
        content.Controls.Add(agent);
        scroll.Controls.Add(content);
        return scroll;
    }

    private Control ToolRow(string name, string purpose, Pill status, string? action, Action? onAction)
    {
        var row = new TableLayoutPanel { AutoSize = true, ColumnCount = 3, Width = 560, Margin = new Padding(0, 0, 0, 10) };
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        var text = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.TopDown, WrapContents = false, Margin = new Padding(0) };
        text.Controls.Add(new Label { Text = name, Font = Night.Sans(10.5f, true), ForeColor = Night.Ink, AutoSize = true, Margin = new Padding(0) });
        text.Controls.Add(new Label { Text = purpose, ForeColor = Night.Ink2, Font = Night.Sans(9.5f), AutoSize = true, Margin = new Padding(0) });
        row.Controls.Add(text, 0, 0);
        status.Margin = new Padding(8, 6, 8, 0);
        row.Controls.Add(status, 1, 0);
        if (action != null)
        {
            var button = new Capsule(action, CapsuleKind.Ghost) { Height = 30, Margin = new Padding(0) };
            button.Click += (_, _) => onAction?.Invoke();
            row.Controls.Add(button, 2, 0);
        }
        return row;
    }

    private void RefreshIntegrationsPage()
    {
        integrationsIntro.Text = agentAccess == null
            ? "Le carnet et l’enregistrement sont disponibles sans compte. Connecte l’agent quand tu en as besoin."
            : agentAccess.Planning ? "Le code de l’équipe est validé pour cette session." : "Ton équipe doit activer l’agent sur son serveur. Tu peux continuer à utiliser le carnet.";
        gladiaPill.Set(string.IsNullOrWhiteSpace(apiKey) ? "Facultatif" : "Clé renseignée", string.IsNullOrWhiteSpace(apiKey) ? PillKind.Wait : PillKind.Ok);
        trelloPill.Set(agentAccess == null ? "Non connecté" : agentAccess.Trello ? "Prêt" : "À relier par l’équipe", agentAccess?.Trello == true ? PillKind.Ok : PillKind.Wait);
        devinPill.Set(agentAccess == null ? "Non connecté" : agentAccess.Devin ? "Prêt" : "À activer par l’équipe", agentAccess?.Devin == true ? PillKind.Ok : PillKind.Wait);
        if (serverField.Text.Length == 0) serverField.Text = agentSite.GetLeftPart(UriPartial.Authority);
        connect.Visible = agentAccess == null;
        verifyAccess.Visible = disconnect.Visible = agentAccess != null;
    }

    private async Task ConnectAgentAsync()
    {
        var server = AgentClient.ServerUri(serverField.Text);
        var code = codeField.Text.Trim();
        if (server == null) { integrationsIssue.Text = "Indique une adresse HTTPS (ou http://localhost en local)."; integrationsIssue.Visible = true; return; }
        if (code.Length == 0) { integrationsIssue.Text = "Saisis le code d’accès de l’équipe."; integrationsIssue.Visible = true; return; }
        agentSite = server;
        try { MeetingStore.SaveSite(server.GetLeftPart(UriPartial.Authority)); } catch { }
        siteField.Text = server.GetLeftPart(UriPartial.Authority);
        agentCode = code;
        await RefreshAccessAsync(true);
        if (agentAccess != null) { MeetingStore.SaveAgentCode(code); SetStatus("Agent connecté."); }
    }

    private async Task RefreshAccessAsync(bool report)
    {
        if (AgentClient.ServerUri(agentSite.AbsoluteUri) is not { } server || agentCode.Length == 0) return;
        connect.Enabled = verifyAccess.Enabled = false;
        integrationsIssue.Visible = false;
        try
        {
            agentAccess = await new AgentClient(server, agentCode).AccessAsync();
        }
        catch (Exception error)
        {
            agentAccess = null;
            if ((error as AgentFailure)?.Status == 401) { agentCode = ""; MeetingStore.SaveAgentCode(""); }
            if (report) { integrationsIssue.Text = (error as AgentFailure)?.Status == 401 ? "Code refusé par le serveur de l’équipe." : error.Message; integrationsIssue.Visible = true; }
        }
        finally
        {
            connect.Enabled = verifyAccess.Enabled = true;
            if (!IsDisposed) { RefreshIntegrationsPage(); if (pageByName.TryGetValue("Agent", out var page) && page.Visible) RefreshAgentPage(); }
        }
    }
}
