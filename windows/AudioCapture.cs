using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace MeetinOS;

internal sealed class CaptureResult
{
    public List<AudioTrack> Tracks { get; } = new();
    public List<string> Warnings { get; } = new();
}

internal sealed class AudioCapture
{
    private static readonly WaveFormat Format = new(16000, 16, 1);
    private const int MaxFrames = 2 * 60 * 60 * 16000;
    private readonly TaskCompletionSource<bool> started = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly TaskCompletionSource<CaptureResult> finished = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private volatile bool stopRequested;

    public AudioCapture()
    {
        var date = DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss");
        var name = date + "_" + Guid.NewGuid().ToString("N").Substring(0, 8);
        Folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Meetin-OS", "Recordings", name);
        var thread = new Thread(Record) { IsBackground = true, Name = "Meetin-OS audio" };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
    }

    public string Folder { get; }
    public Task Started => started.Task;
    public Task<CaptureResult> Finished => finished.Task;
    public void Stop() => stopRequested = true;

    private static double Clock100ns() => Stopwatch.GetTimestamp() * (10_000_000d / Stopwatch.Frequency);

    private void Record()
    {
        var result = new CaptureResult();
        TrackWriter? mic = null;
        TrackWriter? call = null;
        try
        {
            using var devices = new MMDeviceEnumerator();
            using var input = devices.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Multimedia);
            using var output = devices.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
            Directory.CreateDirectory(Folder);
            mic = new TrackWriter(input, new AudioTrack(Path.Combine(Folder, "micro.wav"), Speaker.UserLabel), "Micro", false);
            call = new TrackWriter(output, new AudioTrack(Path.Combine(Folder, "appel.wav"), "Audio de l’appel"), "Audio de l’appel", true);
            var origin = Clock100ns();
            mic.Start();
            call.Start();
            started.SetResult(true);

            while (!stopRequested)
            {
                mic.ReadPackets(origin);
                call.ReadPackets(origin);
                if (Clock100ns() - origin >= 2 * TimeSpan.TicksPerHour)
                {
                    result.Warnings.Add("Enregistrement arrêté après deux heures.");
                    break;
                }
                Thread.Sleep(10);
            }
        }
        catch (Exception error)
        {
            var message = $"Capture audio interrompue ({error.Message}). Vérifie le micro et la sortie audio dans les réglages Windows.";
            if (!started.TrySetException(new InvalidOperationException(message, error))) result.Warnings.Add(message);
        }
        finally
        {
            CompleteTrack(mic, result);
            CompleteTrack(call, result);
            finished.SetResult(result);
        }
    }

    private static void CompleteTrack(TrackWriter? writer, CaptureResult result)
    {
        if (writer == null) return;
        try
        {
            writer.Dispose();
            if (writer.HasAudio) result.Tracks.Add(writer.Track);
            else
            {
                File.Delete(writer.Track.Path);
                result.Warnings.Add($"{writer.Source} : aucun signal détecté.");
            }
        }
        catch (Exception error)
        {
            result.Warnings.Add($"{writer.Source} : fichier audio incomplet ({error.Message}).");
        }
    }

    private sealed class TrackWriter : IDisposable
    {
        private readonly AudioClient client;
        private readonly AudioCaptureClient capture;
        private readonly WaveFileWriter writer;
        private readonly byte[] silence = new byte[32768];
        private byte[] samples = new byte[4096];
        private int framesWritten;
        private bool running;

        // source nomme l'appareil dans les avertissements ; le libellé de la piste sert à la transcription.
        public TrackWriter(MMDevice device, AudioTrack track, string source, bool loopback)
        {
            Track = track;
            Source = source;
            client = device.AudioClient;
            try
            {
                var flags = AudioClientStreamFlags.AutoConvertPcm | AudioClientStreamFlags.SrcDefaultQuality;
                if (loopback) flags |= AudioClientStreamFlags.Loopback;
                client.Initialize(AudioClientShareMode.Shared, flags, 1_000_000, 0, Format, Guid.Empty);
                capture = client.AudioCaptureClient;
                writer = new WaveFileWriter(track.Path, Format);
            }
            catch
            {
                client.Dispose();
                throw;
            }
        }

        public AudioTrack Track { get; }
        public string Source { get; }
        public bool HasAudio { get; private set; }

        public void Start()
        {
            client.Start();
            running = true;
        }

        public void ReadPackets(double origin)
        {
            while (framesWritten < MaxFrames && capture.GetNextPacketSize() > 0)
            {
                var buffer = capture.GetBuffer(out var frames, out var flags, out _, out var timestamp);
                if (frames == 0) return;
                var silent = (flags & AudioClientBufferFlags.Silent) != 0;
                var bytes = frames * Format.BlockAlign;
                try
                {
                    if (!silent)
                    {
                        if (samples.Length < bytes) Array.Resize(ref samples, bytes);
                        Marshal.Copy(buffer, samples, 0, bytes);
                    }
                }
                finally { capture.ReleaseBuffer(frames); }

                // WASAPI peut ne rien livrer pendant un silence. Les deux pistes gardent la même horloge.
                if ((flags & AudioClientBufferFlags.TimestampError) == 0 && timestamp >= origin && timestamp <= Clock100ns())
                {
                    var position = (int)((timestamp - origin) * Format.SampleRate / TimeSpan.TicksPerSecond);
                    var gap = position - framesWritten;
                    if (gap > Format.SampleRate / 50) WriteSilence(Math.Min(gap, MaxFrames - framesWritten));
                }

                frames = Math.Min(frames, MaxFrames - framesWritten);
                if (silent) WriteSilence(frames);
                else if (frames > 0)
                {
                    writer.Write(samples, 0, frames * Format.BlockAlign);
                    framesWritten += frames;
                    HasAudio = true;
                }
            }
        }

        private void WriteSilence(int frames)
        {
            var bytes = frames * Format.BlockAlign;
            while (bytes > 0)
            {
                var count = Math.Min(bytes, silence.Length);
                writer.Write(silence, 0, count);
                bytes -= count;
            }
            framesWritten += frames;
        }

        public void Dispose()
        {
            try
            {
                if (running) client.Stop();
            }
            finally
            {
                try { writer.Dispose(); }
                finally { client.Dispose(); }
            }
        }
    }
}
