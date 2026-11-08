using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Runtime.Serialization;
using System.Threading;
using System.Threading.Tasks;

namespace MeetinOS;

internal enum ProposalState { Pending, Launched, Ignored }

// Tâche proposée pendant la réunion. Rien ne part sans un clic : la carte attend une validation.
[DataContract]
internal sealed class TaskProposal
{
    [DataMember(Name = "id", Order = 0)] public string Id { get; set; } = "";
    [DataMember(Name = "state", Order = 1)] public string StateRaw { get; set; } = "pending";
    [DataMember(Name = "sessionUrl", Order = 2)] public string? SessionUrl { get; set; }
    [DataMember(Name = "review", Order = 3)] public AgentReview Review { get; set; } = new();
    public string? Issue { get; set; }
    public bool Launching { get; set; }

    public ProposalState State
    {
        get => StateRaw == "launched" ? ProposalState.Launched : StateRaw == "ignored" ? ProposalState.Ignored : ProposalState.Pending;
        set => StateRaw = value == ProposalState.Launched ? "launched" : value == ProposalState.Ignored ? "ignored" : "pending";
    }
}

// Cherche des tâches dans le texte définitif du direct, toutes les 15 s, seulement si le texte a changé.
internal sealed class TaskDetector
{
    public const int MaxTranscript = 5000;
    private const int MaxKnown = 10;
    private const int MaxKnownTask = 400;
    private readonly Func<string> text;
    private readonly Func<string, List<KnownTask>, Task<List<DetectedTask>>> detect;
    private readonly SynchronizationContext ui;
    private readonly TimeSpan interval;
    private CancellationTokenSource? loop;
    private string lastSent = "";
    private volatile bool running;

    public TaskDetector(Func<string> text, Func<string, List<KnownTask>, Task<List<DetectedTask>>> detect, SynchronizationContext ui, TimeSpan? interval = null)
    {
        this.text = text;
        this.detect = detect;
        this.ui = ui;
        this.interval = interval ?? TimeSpan.FromSeconds(15);
    }

    public List<TaskProposal> Proposals { get; } = new();
    public bool IsStopped { get; private set; }
    public string? LastError { get; private set; }
    public event Action<TaskProposal>? NewProposal;
    public event Action<TaskProposal>? UpdatedProposal;
    public event Action? Changed;

    public void Start()
    {
        if (loop != null) return;
        var cancel = loop = new CancellationTokenSource();
        Task.Run(async () =>
        {
            while (!cancel.IsCancellationRequested)
            {
                try { await Task.Delay(interval, cancel.Token).ConfigureAwait(false); } catch { return; }
                if (cancel.IsCancellationRequested || IsStopped) return;
                await TickAsync().ConfigureAwait(false);
            }
        });
    }

    public void Stop()
    {
        loop?.Cancel();
        loop = null;
    }

    // Dernier passage à l’arrêt, sur le texte complet : attend l’appel en cours, sans bloquer plus de 40 s.
    public async Task FinishAsync()
    {
        Stop();
        var deadline = DateTime.UtcNow.AddSeconds(40);
        while (running && DateTime.UtcNow < deadline) await Task.Delay(200).ConfigureAwait(false);
        await TickAsync().ConfigureAwait(false);
    }

    public async Task TickAsync()
    {
        if (running || IsStopped) return;
        var current = text();
        if (string.IsNullOrEmpty(current) || current == lastSent) return;
        running = true;
        try
        {
            var found = await detect(Window(current), Known()).ConfigureAwait(false);
            lastSent = current;
            LastError = null;
            ui.Post(_ => Apply(found), null);
        }
        catch (AgentFailure failure) when (failure.Status == 401 || failure.Status == 503)
        {
            LastError = failure.Message;
            IsStopped = true;
            ui.Post(_ => Changed?.Invoke(), null);
        }
        catch (Exception error)
        {
            LastError = error.Message;
            ui.Post(_ => Changed?.Invoke(), null);
        }
        finally { running = false; }
    }

    private List<KnownTask> Known()
    {
        List<TaskProposal> snapshot;
        lock (Proposals) snapshot = Proposals.Skip(Math.Max(0, Proposals.Count - MaxKnown)).ToList();
        return snapshot.Select(p => new KnownTask
        {
            Ref = p.Id, Title = p.Review.Title, Task = p.Review.Task.Length > MaxKnownTask ? p.Review.Task.Substring(0, MaxKnownTask) : p.Review.Task
        }).ToList();
    }

    private void Apply(List<DetectedTask> found)
    {
        foreach (var task in found)
        {
            TaskProposal? existing;
            lock (Proposals) existing = Proposals.FirstOrDefault(p => p.Id == task.Replaces || SameTitle(p.Review.Title, task.Title));
            if (existing != null)
            {
                if (existing.State != ProposalState.Pending) continue;
                existing.Review = task;
                existing.Issue = null;
                UpdatedProposal?.Invoke(existing);
            }
            else
            {
                var proposal = new TaskProposal { Id = task.Id, Review = task };
                lock (Proposals) Proposals.Add(proposal);
                NewProposal?.Invoke(proposal);
            }
        }
        Changed?.Invoke();
    }

    private static bool SameTitle(string first, string second) =>
        string.Compare(first, second, CultureInfo.InvariantCulture, CompareOptions.IgnoreCase | CompareOptions.IgnoreNonSpace) == 0;

    // Les dernières lignes entières qui tiennent dans la limite du serveur : les citations restent exactes.
    public static string Window(string text)
    {
        if (text.Length <= MaxTranscript) return text;
        var kept = new List<string>();
        var size = 0;
        foreach (var line in text.Split('\n').Reverse())
        {
            var cost = line.Length + 1;
            if (size + cost > MaxTranscript) break;
            kept.Add(line);
            size += cost;
        }
        if (kept.Count == 0) return text.Substring(text.Length - MaxTranscript);
        kept.Reverse();
        return string.Join("\n", kept);
    }
}
