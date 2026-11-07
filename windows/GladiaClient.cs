using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Threading;
using System.Threading.Tasks;

namespace MeetinOS;

internal sealed class AudioTrack
{
    public AudioTrack(string path, string? label = null) { Path = path; Label = label; }
    public string Path { get; }
    public string? Label { get; }
}

internal sealed class GladiaClient
{
    private const string Api = "https://api.gladia.io/v2/";
    private static readonly HttpClient SharedClient = new(new HttpClientHandler { AllowAutoRedirect = false })
    {
        Timeout = TimeSpan.FromMinutes(4)
    };
    private readonly HttpClient http;

    public GladiaClient(HttpClient? http = null) => this.http = http ?? SharedClient;

    public async Task<string> TranscribeAsync(IEnumerable<AudioTrack> tracks, string key, CancellationToken token)
    {
        var jobs = tracks.Select(async track => (Track: track, Segments: await FetchAsync(track, key, token).ConfigureAwait(false)));
        var completed = await Task.WhenAll(jobs).ConfigureAwait(false);
        var lines = completed.SelectMany(job => job.Segments.Select(segment => new
        {
            Time = double.IsNaN(segment.Start) || double.IsInfinity(segment.Start) ? 0 : Math.Min(86400, Math.Max(0, segment.Start)),
            Label = job.Track.Label ?? (segment.Speaker is int speaker ? $"Voix {speaker + 1}" : "Voix"),
            Text = segment.Text
        })).OrderBy(line => line.Time).Select(line => $"[{Clock((int)line.Time)}] {line.Label} · {line.Text}");
        var missing = completed.Where(job => job.Segments.Length == 0)
            .Select(job => job.Track.Label == null ? "Aucune parole reconnue." : $"{job.Track.Label} · aucune parole reconnue.");
        return string.Join(Environment.NewLine, lines.Concat(missing));
    }

    private static string Clock(int seconds) => seconds >= 3600
        ? $"{seconds / 3600:00}:{seconds / 60 % 60:00}:{seconds % 60:00}"
        : $"{seconds / 60:00}:{seconds % 60:00}";

    private async Task<Segment[]> FetchAsync(AudioTrack track, string key, CancellationToken token)
    {
        Upload uploaded;
        using (var file = File.OpenRead(track.Path))
        using (var form = new MultipartFormDataContent())
        {
            var audio = new StreamContent(file);
            audio.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
            form.Add(audio, "audio", "reunion" + Path.GetExtension(track.Path));
            uploaded = await RequestAsync<Upload>("upload", "envoi de l’audio", key, token, form).ConfigureAwait(false);
        }
        if (string.IsNullOrWhiteSpace(uploaded.AudioUrl)) throw new InvalidDataException("Gladia n’a pas renvoyé de lien audio.");

        var json = new MemoryStream();
        new DataContractJsonSerializer(typeof(TranscriptionRequest)).WriteObject(json, new TranscriptionRequest { AudioUrl = uploaded.AudioUrl });
        json.Position = 0;
        using var payload = new StreamContent(json);
        payload.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        var job = await RequestAsync<Job>("pre-recorded", "lancement de la transcription", key, token, payload).ConfigureAwait(false);
        if (!Guid.TryParse(job.Id, out var id)) throw new InvalidDataException("Gladia n’a pas renvoyé d’identifiant de transcription valide.");

        // Reconstruit le lien sur le domaine Gladia plutôt que de transmettre la clé à une URL de réponse.
        using var poll = CancellationTokenSource.CreateLinkedTokenSource(token);
        poll.CancelAfter(TimeSpan.FromMinutes(4));
        while (true)
        {
            var response = await RequestAsync<Job>("pre-recorded/" + id.ToString("D"), "lecture du résultat", key, poll.Token).ConfigureAwait(false);
            if (response.Status == "done")
            {
                var transcription = response.Result?.Transcription
                    ?? throw new InvalidDataException("Gladia a terminé sans renvoyer de transcription.");
                var segments = (transcription.Utterances ?? Array.Empty<Segment>()).Where(segment => !string.IsNullOrWhiteSpace(segment.Text)).ToArray();
                if (segments.Length > 0 || string.IsNullOrWhiteSpace(transcription.Text)) return segments;
                return new[] { new Segment { Text = transcription.Text } };
            }
            if (response.Status == "error" || response.Status == "failed") throw new InvalidOperationException("La transcription a échoué chez Gladia.");
            await Task.Delay(TimeSpan.FromSeconds(2), poll.Token).ConfigureAwait(false);
        }
    }

    private async Task<T> RequestAsync<T>(string path, string stage, string key, CancellationToken token, HttpContent? body = null)
    {
        using var request = new HttpRequestMessage(body == null ? HttpMethod.Get : HttpMethod.Post, Api + path) { Content = body };
        request.Headers.Add("x-gladia-key", key);
        using var response = await http.SendAsync(request, token).ConfigureAwait(false);
        if (response.StatusCode == HttpStatusCode.Unauthorized || response.StatusCode == HttpStatusCode.Forbidden)
            throw new InvalidOperationException("Gladia a refusé la clé. Vérifie-la dans Réglages, puis réessaie.");
        if (!response.IsSuccessStatusCode) throw new InvalidOperationException($"Gladia · {stage} impossible (HTTP {(int)response.StatusCode}).");

        using var stream = await response.Content.ReadAsStreamAsync().ConfigureAwait(false);
        return (T)(new DataContractJsonSerializer(typeof(T)).ReadObject(stream)
            ?? throw new InvalidDataException($"Gladia · réponse vide pendant {stage}."));
    }

    [DataContract]
    private sealed class Upload { [DataMember(Name = "audio_url")] public string? AudioUrl { get; set; } }

    [DataContract]
    private sealed class TranscriptionRequest
    {
        [DataMember(Name = "audio_url")] public string? AudioUrl { get; set; }
        [DataMember(Name = "diarization")] public bool Diarization { get; set; } = true;
    }

    [DataContract]
    private sealed class Job
    {
        [DataMember(Name = "id")] public string? Id { get; set; }
        [DataMember(Name = "status")] public string? Status { get; set; }
        [DataMember(Name = "result")] public Details? Result { get; set; }
    }

    [DataContract]
    private sealed class Details { [DataMember(Name = "transcription")] public Transcript? Transcription { get; set; } }

    [DataContract]
    private sealed class Transcript
    {
        [DataMember(Name = "utterances")] public Segment[]? Utterances { get; set; }
        [DataMember(Name = "full_transcript")] public string? Text { get; set; }
    }

    [DataContract]
    private sealed class Segment
    {
        [DataMember(Name = "start")] public double Start { get; set; }
        [DataMember(Name = "speaker")] public int? Speaker { get; set; }
        [DataMember(Name = "text")] public string? Text { get; set; }
    }
}
