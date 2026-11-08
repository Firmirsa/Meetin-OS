using System.Net;
using System.Text;
using System.Text.Json;
using MeetinOS;

var folder = Directory.CreateTempSubdirectory();
try
{
    var mic = Path.Combine(folder.FullName, "micro.wav");
    var call = Path.Combine(folder.FullName, "appel.wav");
    await File.WriteAllTextAsync(mic, "mic-fixture");
    await File.WriteAllTextAsync(call, "call-fixture");
    using var http = new HttpClient(new FakeGladia());
    var client = new GladiaClient(http);
    var me = Speaker.UserLabel;
    if (me.Length == 0) throw new Exception("Le nom affiché pour le micro ne doit pas être vide.");
    if (Speaker.Name("  Léa   Martin\n", "lea") != "Léa Martin") throw new Exception("Le nom complet doit être gardé, espaces nettoyés.");
    if (Speaker.Name(null, " lea ") != "lea") throw new Exception("Sans nom complet, le nom de session doit servir.");
    if (Speaker.Name("", " ") != "Vous") throw new Exception("Sans nom, le libellé doit être « Vous ».");
    var tracks = new[] { new AudioTrack(mic, me), new AudioTrack(call, "Audio de l’appel") };
    var transcript = await client.TranscribeAsync(tracks, "test-key", CancellationToken.None);
    var expected = string.Join(Environment.NewLine, "[00:01] Audio de l’appel · Voix distante", $"[00:01] {me} · Voix locale");
    if (transcript != expected) throw new Exception("La transcription des deux sources n’est pas dans l’ordre attendu.");

    try
    {
        await client.TranscribeAsync(tracks, "wrong-key", CancellationToken.None);
        throw new Exception("Une clé refusée doit produire une erreur.");
    }
    catch (InvalidOperationException error) when (error.Message.Contains("refusé la clé")) { }
    Console.WriteLine("Gladia simulé : téléversement des deux pistes, nom de l’utilisateur, résultat ordonné et rejet de clé vérifiés.");
}
finally { folder.Delete(recursive: true); }

sealed class FakeGladia : HttpMessageHandler
{
    private const string MicId = "45463597-20b7-4af7-b3b3-f5fb778203ab";
    private const string CallId = "52463597-20b7-4af7-b3b3-f5fb778203ab";

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
    {
        if (request.RequestUri?.Host != "api.gladia.io") throw new Exception("La clé a été envoyée hors de Gladia.");
        if (request.Headers.GetValues("x-gladia-key").Single() != "test-key") return new HttpResponseMessage(HttpStatusCode.Unauthorized);
        var path = request.RequestUri.AbsolutePath;
        if (request.Method == HttpMethod.Post && path == "/v2/upload")
        {
            var body = await request.Content!.ReadAsStringAsync(token);
            if (!body.Contains("name=audio") || !body.Contains("reunion.wav")) throw new Exception("Le formulaire audio est invalide.");
            var id = body.Contains("mic-fixture") ? MicId : body.Contains("call-fixture") ? CallId : throw new Exception("Piste inconnue.");
            return Json(HttpStatusCode.Created, new { audio_url = "https://files.gladia.io/" + id });
        }
        if (request.Method == HttpMethod.Post && path == "/v2/pre-recorded")
        {
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            var id = body.RootElement.GetProperty("audio_url").GetString()!.Split('/').Last();
            return Json(HttpStatusCode.Created, new { id, result_url = "https://invalid.example/" + id });
        }
        if (request.Method == HttpMethod.Get && path.StartsWith("/v2/pre-recorded/"))
        {
            var mic = path.EndsWith(MicId);
            var utterance = new { start = mic ? 1.8 : 1.2, text = mic ? "Voix locale" : "Voix distante", speaker = 0 };
            return Json(HttpStatusCode.OK, new { status = "done", result = new { transcription = new { utterances = new[] { utterance } } } });
        }
        throw new Exception("Requête Gladia inattendue.");
    }

    private static HttpResponseMessage Json(HttpStatusCode status, object body) => new(status)
    {
        Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json")
    };
}
