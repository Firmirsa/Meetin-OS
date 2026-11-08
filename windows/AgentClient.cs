using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;
using System.Threading.Tasks;

namespace MeetinOS;

// Client de l’API agent du site (web/lib/agent.mjs), même contrat que mac/AgentClient.swift.
internal enum AgentExecutor { Devin, ComputerUse }

internal static class AgentExecutors
{
    public static AgentExecutor Parse(string? raw) => raw == "computer_use" ? AgentExecutor.ComputerUse : AgentExecutor.Devin;
    public static string Name(this AgentExecutor executor) => executor == AgentExecutor.Devin ? "Devin" : "H Computer Use";
    public static string SessionHost(this AgentExecutor executor) => executor == AgentExecutor.Devin ? "app.devin.ai" : "platform.hcompany.ai";
}

[DataContract]
internal sealed class AgentClarification
{
    [DataMember(Name = "question", Order = 0)] public string Question { get; set; } = "";
    [DataMember(Name = "answer", Order = 1)] public string Answer { get; set; } = "";
}

[DataContract]
[KnownType(typeof(AgentPreparation))]
[KnownType(typeof(DetectedTask))]
internal class AgentReview
{
    [DataMember(Name = "executor", Order = 0)] public string? ExecutorRaw { get; set; }
    [DataMember(Name = "destination", Order = 1)] public string Destination { get; set; } = "";
    [DataMember(Name = "title", Order = 2)] public string Title { get; set; } = "";
    [DataMember(Name = "task", Order = 3)] public string Task { get; set; } = "";
    [DataMember(Name = "quote", Order = 4)] public string Quote { get; set; } = "";
    [DataMember(Name = "clarifications", Order = 5)] public List<AgentClarification>? Clarifications { get; set; }
    [DataMember(Name = "approval", Order = 6)] public string Approval { get; set; } = "";

    public AgentExecutor Executor => AgentExecutors.Parse(ExecutorRaw);
    public List<AgentClarification> Turns => Clarifications ?? new List<AgentClarification>();
    public bool UsesTrello => Executor == AgentExecutor.ComputerUse && Uri.TryCreate(Destination, UriKind.Absolute, out var uri)
        && (uri.Host == "trello.com" || uri.Host == "www.trello.com");
}

[DataContract]
internal sealed class AgentPreparation : AgentReview
{
    [DataMember(Name = "status")] public string? Status { get; set; }
    [DataMember(Name = "question")] public string? Question { get; set; }
    public bool NeedsClarification => Status == "needs_clarification";
    public bool Ready => Status == "ready";
}

[DataContract]
internal sealed class DetectedTask : AgentReview
{
    [DataMember(Name = "id")] public string Id { get; set; } = "";
    [DataMember(Name = "replaces")] public string? Replaces { get; set; }
}

[DataContract]
internal sealed class KnownTask
{
    [DataMember(Name = "ref", Order = 0)] public string Ref { get; set; } = "";
    [DataMember(Name = "title", Order = 1)] public string Title { get; set; } = "";
    [DataMember(Name = "task", Order = 2)] public string Task { get; set; } = "";
}

[DataContract]
internal sealed class AgentExecution
{
    [DataMember(Name = "executor")] public string? ExecutorRaw { get; set; }
    [DataMember(Name = "url")] public string? Url { get; set; }
    public AgentExecutor Executor => AgentExecutors.Parse(ExecutorRaw);
}

[DataContract]
internal sealed class AgentAccess
{
    [DataMember(Name = "planning")] public bool Planning { get; set; }
    [DataMember(Name = "trello")] public bool Trello { get; set; }
    [DataMember(Name = "devin")] public bool Devin { get; set; }
}

internal sealed class AgentFailure : Exception
{
    public AgentFailure(string message, int? status = null, string? code = null) : base(message) { Status = status; Code = code; }
    public int? Status { get; }
    public string? Code { get; }
}

internal sealed class AgentClient
{
    private static readonly HttpClient Shared = new(new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(35) };
    private readonly HttpClient http;

    public AgentClient(Uri baseUri, string accessCode, HttpClient? http = null)
    {
        BaseUri = baseUri;
        AccessCode = accessCode;
        this.http = http ?? Shared;
    }

    public Uri BaseUri { get; }
    public string AccessCode { get; }

    // https partout, http seulement en local, sans chemin ni identifiants.
    public static Uri? ServerUri(string? address)
    {
        if (!Uri.TryCreate(address?.Trim(), UriKind.Absolute, out var uri) || string.IsNullOrEmpty(uri.Host)) return null;
        if (!string.IsNullOrEmpty(uri.UserInfo) || !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment)) return null;
        if (uri.AbsolutePath != "/" && uri.AbsolutePath.Length > 0) return null;
        if (uri.Scheme == Uri.UriSchemeHttps) return uri;
        return uri.Scheme == Uri.UriSchemeHttp && (uri.Host == "localhost" || uri.Host == "127.0.0.1") ? uri : null;
    }

    public Task<AgentAccess> AccessAsync() => PostAsync<AgentAccess>("agent-access", new Empty());

    public Task<AgentPreparation> PrepareAsync(string task, string transcript, List<AgentClarification> clarifications) =>
        PostAsync<AgentPreparation>("agent-prepare", new PrepareRequest { Task = task, Transcript = transcript, Clarifications = clarifications });

    public async Task<List<DetectedTask>> DetectAsync(string transcript, List<KnownTask> known)
    {
        var response = await PostAsync<DetectResponse>("agent-detect", new DetectRequest { Transcript = transcript, Known = known }).ConfigureAwait(false);
        return response.Tasks ?? new List<DetectedTask>();
    }

    public async Task<AgentExecution> LaunchAsync(AgentReview review)
    {
        var result = await PostAsync<AgentExecution>("agent-execute", new ConfirmRequest { Approval = review.Approval }).ConfigureAwait(false);
        if (result.Executor != review.Executor || !Uri.TryCreate(result.Url, UriKind.Absolute, out var url) || url.Scheme != Uri.UriSchemeHttps
            || url.Host != result.Executor.SessionHost() || !string.IsNullOrEmpty(url.UserInfo) || (url.Port != 443 && url.Port != -1))
            throw new AgentFailure("Le service n’a pas renvoyé de lien de session valide.");
        return result;
    }

    private async Task<T> PostAsync<T>(string operation, object body) where T : class
    {
        var json = new MemoryStream();
        new DataContractJsonSerializer(body.GetType()).WriteObject(json, body);
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(BaseUri, "/api/" + operation));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", AccessCode);
        request.Content = new ByteArrayContent(json.ToArray());
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        HttpResponseMessage response;
        try { response = await http.SendAsync(request).ConfigureAwait(false); }
        catch (TaskCanceledException) { throw new AgentFailure("L’agent n’a pas répondu dans le délai imparti."); }
        catch (HttpRequestException error) { throw new AgentFailure("Agent injoignable : " + (error.InnerException?.Message ?? error.Message)); }
        using (response)
        {
            var bytes = await response.Content.ReadAsByteArrayAsync().ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                var problem = TryRead<ErrorResponse>(bytes);
                throw new AgentFailure(problem?.Error ?? $"L’agent n’a pas confirmé la requête (HTTP {(int)response.StatusCode}).", (int)response.StatusCode, problem?.Code);
            }
            return TryRead<T>(bytes) ?? throw new AgentFailure("Réponse de l’agent illisible.");
        }
    }

    private static T? TryRead<T>(byte[] bytes) where T : class
    {
        try
        {
            using var stream = new MemoryStream(bytes);
            return new DataContractJsonSerializer(typeof(T)).ReadObject(stream) as T;
        }
        catch { return null; }
    }

    [DataContract] private sealed class Empty { }

    [DataContract]
    private sealed class PrepareRequest
    {
        [DataMember(Name = "task", Order = 0)] public string Task { get; set; } = "";
        [DataMember(Name = "transcript", Order = 1)] public string Transcript { get; set; } = "";
        [DataMember(Name = "clarifications", Order = 2)] public List<AgentClarification> Clarifications { get; set; } = new();
    }

    [DataContract]
    private sealed class DetectRequest
    {
        [DataMember(Name = "transcript", Order = 0)] public string Transcript { get; set; } = "";
        [DataMember(Name = "known", Order = 1)] public List<KnownTask> Known { get; set; } = new();
    }

    [DataContract]
    private sealed class DetectResponse { [DataMember(Name = "tasks")] public List<DetectedTask>? Tasks { get; set; } }

    [DataContract]
    private sealed class ConfirmRequest
    {
        [DataMember(Name = "approval", Order = 0)] public string Approval { get; set; } = "";
        [DataMember(Name = "confirmed", Order = 1)] public bool Confirmed { get; set; } = true;
    }

    [DataContract]
    private sealed class ErrorResponse
    {
        [DataMember(Name = "error")] public string? Error { get; set; }
        [DataMember(Name = "code")] public string? Code { get; set; }
    }
}
