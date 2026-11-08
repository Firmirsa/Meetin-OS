using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.WebSockets;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace MeetinOS;

// Transcription en direct Gladia, flux parallèle à l’enregistrement (même logique que mac/LiveTranscription.swift).
// Une panne ici ne touche jamais les fichiers audio : « Transcrire avec Gladia » reste disponible après l’arrêt.
internal sealed class LiveUtterance
{
    public LiveUtterance(string id, string text, double start, bool isFinal) { Id = id; Text = text; Start = start; IsFinal = isFinal; }
    public string Id { get; }
    public string Text { get; }
    public double Start { get; }
    public bool IsFinal { get; }
}

internal sealed class LiveLine
{
    public LiveLine(string id, double time, string track, string text, bool isFinal) { Id = id; Time = time; Track = track; Text = text; IsFinal = isFinal; }
    public string Id { get; }
    public double Time { get; }
    public string Track { get; }
    public string Text { get; }
    public bool IsFinal { get; }
    public string Formatted => LiveTranscript.Line(Time, Track, Text);
}

internal sealed class LiveTranscript
{
    private readonly object gate = new();
    private readonly Dictionary<string, LiveUtterance> utterances = new();
    private readonly Dictionary<string, double> firstAudio = new();

    public static string Line(double start, string label, string text)
    {
        var seconds = (int)(double.IsNaN(start) || double.IsInfinity(start) ? 0 : Math.Min(Math.Max(0, start), 86400));
        return $"[{seconds / 60:00}:{seconds % 60:00}] {label} · {text}";
    }

    public void NoteFirstAudio(string track, double seconds)
    {
        lock (gate) { if (!firstAudio.ContainsKey(track)) firstAudio[track] = seconds; }
    }

    public void Apply(LiveUtterance utterance, string track)
    {
        lock (gate)
        {
            var key = track + "\n" + utterance.Id;
            if (string.IsNullOrWhiteSpace(utterance.Text)) utterances.Remove(key);
            else utterances[key] = utterance;
        }
    }

    public List<LiveLine> Lines
    {
        get
        {
            lock (gate)
            {
                var origin = firstAudio.Count == 0 ? 0 : firstAudio.Values.Min();
                var all = utterances.Select(pair =>
                {
                    var track = pair.Key.Substring(0, pair.Key.IndexOf('\n'));
                    var offset = firstAudio.TryGetValue(track, out var first) ? first - origin : 0;
                    return new LiveLine(track + "-" + pair.Value.Id, pair.Value.Start + offset, track, pair.Value.Text, pair.Value.IsFinal);
                }).OrderBy(line => line.Time).ThenBy(line => line.Id, StringComparer.Ordinal).ToList();
                var call = all.Where(line => line.Track != "Micro").ToList();
                return all.Where(line => !IsEcho(line, call)).ToList();
            }
        }
    }

    // Sans casque, le micro capte les haut-parleurs : la piste de l’appel, plus nette, garde la phrase.
    private static bool IsEcho(LiveLine line, List<LiveLine> call)
    {
        if (line.Track != "Micro") return false;
        var words = Words(line.Text);
        if (words.Count < 3) return false;
        var heard = new HashSet<string>(call.Where(c => Math.Abs(c.Time - line.Time) <= 10).SelectMany(c => Words(c.Text)));
        if (heard.Count == 0) return false;
        return words.Count(heard.Contains) / (double)words.Count >= 0.7;
    }

    private static List<string> Words(string text)
    {
        var folded = text.Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder();
        foreach (var c in folded) if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) builder.Append(char.ToLowerInvariant(c));
        return builder.ToString().Split(new[] { ' ', '\n', '\t', ',', '.', ';', ':', '!', '?', '’', '\'', '"', '(', ')', '-' }, StringSplitOptions.RemoveEmptyEntries).ToList();
    }

    public string ConfirmedText => string.Join("\n", Lines.Where(l => l.IsFinal).Select(l => l.Formatted));
    public string FinalText => string.Join("\n", Lines.Select(l => l.Formatted));
}

internal enum LiveState { Connecting, Live, Reconnecting, Unauthorized, Ended, Failed }

internal sealed class LiveTranscription
{
    private const int ChunkBytes = 3200;
    private const int MaxChunks = 600;
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };
    private readonly string key;
    private readonly Dictionary<string, TrackSession> sessions = new();
    private readonly Dictionary<string, LiveState> trackStates = new();
    private readonly object gate = new();
    private bool finishing;
    private bool alerted;
    private DateTime? reconnectingSince;

    public LiveTranscription(string key)
    {
        this.key = key;
        ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
    }

    public LiveTranscript Transcript { get; } = new();
    public LiveState State { get; private set; } = LiveState.Connecting;
    public string? Failure { get; private set; }
    public bool IsIncomplete { get; private set; }
    public bool LostAudio { get; private set; }
    public event Action? Changed;
    public event Action<string>? Problem;

    // Appelé depuis le fil audio : copie les octets et rend la main tout de suite.
    public void Feed(string track, byte[] data, int count, double seconds)
    {
        TrackSession? session;
        lock (gate)
        {
            if (!sessions.TryGetValue(track, out session))
            {
                session = new TrackSession(this, track);
                sessions[track] = session;
                var started = session;
                Task.Run(() => started.RunAsync());
            }
        }
        Transcript.NoteFirstAudio(track, seconds);
        session.Feed(data, count);
    }

    public async Task FinishAsync()
    {
        finishing = true;
        List<TrackSession> all;
        lock (gate) all = sessions.Values.ToList();
        foreach (var session in all) session.Complete();
        var deadline = DateTime.UtcNow.AddSeconds(8);
        while (all.Any(s => !s.Finished) && DateTime.UtcNow < deadline) await Task.Delay(100).ConfigureAwait(false);
        if (all.Any(s => !s.Finished)) IsIncomplete = true;
        foreach (var session in all) session.Abort();
    }

    private void Update(string track, LiveState state, string? failure = null)
    {
        lock (gate)
        {
            trackStates[track] = state;
            var states = trackStates.Values.ToList();
            if (failure != null) Failure = failure;
            if (states.Contains(LiveState.Unauthorized)) State = LiveState.Unauthorized;
            else if (states.Contains(LiveState.Reconnecting)) State = LiveState.Reconnecting;
            else if (states.Contains(LiveState.Live)) State = LiveState.Live;
            else if (states.Contains(LiveState.Ended)) State = LiveState.Ended;
            else if (states.Contains(LiveState.Failed)) State = LiveState.Failed;
            if (!finishing)
            {
                if (states.Contains(LiveState.Unauthorized)) { IsIncomplete = true; Alert("Gladia a refusé la clé. L’enregistrement continue."); }
                else if (states.Contains(LiveState.Failed)) { IsIncomplete = true; Alert("Le direct n’a pas pu démarrer. L’enregistrement continue."); }
                else if (states.Contains(LiveState.Ended)) { IsIncomplete = true; Alert("Le direct s’est arrêté. L’enregistrement continue."); }
                else if (states.Contains(LiveState.Reconnecting))
                {
                    reconnectingSince ??= DateTime.UtcNow;
                    if ((DateTime.UtcNow - reconnectingSince.Value).TotalSeconds >= 30) { IsIncomplete = true; Alert("Le direct est coupé depuis 30 s. L’enregistrement continue."); }
                }
                else { reconnectingSince = null; alerted = false; }
            }
        }
        Changed?.Invoke();
    }

    private void Alert(string message)
    {
        if (alerted) return;
        alerted = true;
        Problem?.Invoke(message);
    }

    private void Dropped()
    {
        LostAudio = true;
        IsIncomplete = true;
    }

    private async Task<Uri> CreateSessionAsync()
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.gladia.io/v2/live");
        request.Headers.Add("x-gladia-key", key);
        request.Content = new StringContent(
            "{\"encoding\":\"wav/pcm\",\"sample_rate\":16000,\"bit_depth\":16,\"channels\":1," +
            "\"language_config\":{\"languages\":[\"fr\",\"en\"],\"code_switching\":true},\"messages_config\":{\"receive_partial_transcripts\":true}}",
            Encoding.UTF8, "application/json");
        using var response = await Http.SendAsync(request).ConfigureAwait(false);
        if (response.StatusCode == HttpStatusCode.Unauthorized || response.StatusCode == HttpStatusCode.Forbidden) throw new UnauthorizedAccessException("Gladia a refusé la clé.");
        if (!response.IsSuccessStatusCode) throw new InvalidOperationException($"Gladia · ouverture du direct impossible (HTTP {(int)response.StatusCode}).");
        using var stream = await response.Content.ReadAsStreamAsync().ConfigureAwait(false);
        var created = new DataContractJsonSerializer(typeof(Created)).ReadObject(stream) as Created;
        if (created?.Url == null || !Uri.TryCreate(created.Url, UriKind.Absolute, out var url) || url.Scheme != "wss" || url.Host != "api.gladia.io")
            throw new InvalidOperationException("Gladia · réponse illisible pendant l’ouverture du direct.");
        return url;
    }

    private static LiveUtterance? Parse(string text)
    {
        try
        {
            using var stream = new MemoryStream(Encoding.UTF8.GetBytes(text));
            if (new DataContractJsonSerializer(typeof(Message)).ReadObject(stream) is not Message message || message.Type != "transcript") return null;
            var data = message.Data;
            if (data?.Id == null || data.Utterance == null) return null;
            return new LiveUtterance(data.Id, data.Utterance.Text ?? "", data.Utterance.Start, data.IsFinal);
        }
        catch { return null; }
    }

    [DataContract] private sealed class Created { [DataMember(Name = "url")] public string? Url { get; set; } }

    [DataContract]
    private sealed class Message
    {
        [DataMember(Name = "type")] public string? Type { get; set; }
        [DataMember(Name = "data")] public Details? Data { get; set; }
    }

    [DataContract]
    private sealed class Details
    {
        [DataMember(Name = "id")] public string? Id { get; set; }
        [DataMember(Name = "is_final")] public bool IsFinal { get; set; }
        [DataMember(Name = "utterance")] public Utterance? Utterance { get; set; }
    }

    [DataContract]
    private sealed class Utterance
    {
        [DataMember(Name = "text")] public string? Text { get; set; }
        [DataMember(Name = "start")] public double Start { get; set; }
    }

    // Une session Gladia par piste : une piste en panne n’arrête pas l’autre.
    private sealed class TrackSession
    {
        private readonly LiveTranscription owner;
        private readonly string track;
        private readonly BlockingCollection<byte[]> queue = new(new ConcurrentQueue<byte[]>(), MaxChunks);
        private readonly MemoryStream pending = new();
        private readonly CancellationTokenSource aborted = new();
        private volatile bool serverClosed;

        public TrackSession(LiveTranscription owner, string track) { this.owner = owner; this.track = track; }
        public bool Finished { get; private set; }

        public void Feed(byte[] data, int count)
        {
            if (queue.IsAddingCompleted) return;
            pending.Write(data, 0, count);
            if (pending.Length < ChunkBytes) return;
            Enqueue(pending.ToArray());
            pending.SetLength(0);
        }

        private void Enqueue(byte[] chunk)
        {
            if (queue.TryAdd(chunk)) return;
            // Au-delà de 60 s de coupure, le plus ancien est abandonné.
            queue.TryTake(out _);
            owner.Dropped();
            queue.TryAdd(chunk);
        }

        public void Complete()
        {
            if (queue.IsAddingCompleted) return;
            if (pending.Length > 0) { Enqueue(pending.ToArray()); pending.SetLength(0); }
            queue.CompleteAdding();
        }

        public void Abort() => aborted.Cancel();

        public async Task RunAsync()
        {
            try { await StreamAsync().ConfigureAwait(false); }
            finally { Finished = true; }
        }

        private async Task StreamAsync()
        {
            Uri url;
            try { url = await owner.CreateSessionAsync().ConfigureAwait(false); }
            catch (UnauthorizedAccessException) { owner.Update(track, LiveState.Unauthorized); return; }
            catch (Exception error) { owner.Update(track, LiveState.Failed, error.Message); return; }

            byte[]? unsent = null;
            var delay = 1.0;
            while (!aborted.IsCancellationRequested)
            {
                using var socket = new ClientWebSocket();
                serverClosed = false;
                Task? receiver = null;
                try
                {
                    await socket.ConnectAsync(url, aborted.Token).ConfigureAwait(false);
                    receiver = ReceiveAllAsync(socket);
                    var announced = false;
                    if (unsent != null)
                    {
                        await socket.SendAsync(new ArraySegment<byte>(unsent), WebSocketMessageType.Binary, true, aborted.Token).ConfigureAwait(false);
                        unsent = null;
                        announced = true;
                        owner.Update(track, LiveState.Live);
                    }
                    while (true)
                    {
                        byte[] chunk;
                        try { chunk = queue.Take(aborted.Token); }
                        catch (InvalidOperationException) { break; }
                        unsent = chunk;
                        await socket.SendAsync(new ArraySegment<byte>(chunk), WebSocketMessageType.Binary, true, aborted.Token).ConfigureAwait(false);
                        unsent = null;
                        delay = 1.0;
                        if (!announced) { announced = true; owner.Update(track, LiveState.Live); }
                    }
                    var stop = Encoding.UTF8.GetBytes("{\"type\":\"stop_recording\"}");
                    await socket.SendAsync(new ArraySegment<byte>(stop), WebSocketMessageType.Text, true, aborted.Token).ConfigureAwait(false);
                    await receiver.ConfigureAwait(false);
                    return;
                }
                catch (OperationCanceledException) { return; }
                catch (Exception)
                {
                    if (receiver != null) { try { await receiver.ConfigureAwait(false); } catch { } }
                    if (aborted.IsCancellationRequested) return;
                    if (serverClosed) { owner.Update(track, LiveState.Ended); return; }
                    owner.Update(track, LiveState.Reconnecting);
                    try { await Task.Delay(TimeSpan.FromSeconds(delay), aborted.Token).ConfigureAwait(false); } catch { return; }
                    delay = Math.Min(delay * 2, 15);
                }
            }
        }

        private async Task ReceiveAllAsync(ClientWebSocket socket)
        {
            var buffer = new byte[16384];
            var text = new MemoryStream();
            while (true)
            {
                WebSocketReceiveResult result;
                try { result = await socket.ReceiveAsync(new ArraySegment<byte>(buffer), aborted.Token).ConfigureAwait(false); }
                catch (WebSocketException) when (socket.CloseStatus == WebSocketCloseStatus.NormalClosure) { serverClosed = true; return; }
                if (result.MessageType == WebSocketMessageType.Close) { serverClosed = true; return; }
                text.Write(buffer, 0, result.Count);
                if (!result.EndOfMessage) continue;
                var message = Encoding.UTF8.GetString(text.ToArray());
                text.SetLength(0);
                var utterance = Parse(message);
                if (utterance == null) continue;
                owner.Transcript.Apply(utterance, track);
                owner.Changed?.Invoke();
            }
        }
    }
}
