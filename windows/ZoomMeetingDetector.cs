using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;

namespace MeetinOS;

// Même logique que ZoomMeetingDetector.swift : une réunion Zoom est visible quand une fenêtre
// du processus Zoom porte un titre de réunion. L’enregistrement reste manuel.
internal sealed class ZoomMeetingDetector
{
    private static readonly string[] MeetingTitles = { "zoom meeting", "réunion zoom", "zoom webinar", "webinaire zoom" };
    private int consecutiveAbsences;

    public bool InMeeting { get; private set; }

    // Retourne true une seule fois, au moment où la réunion apparaît.
    public bool Observe(IReadOnlyList<string>? titles)
    {
        if (titles == null) return false;
        var visible = titles.Any(t => MeetingTitles.Contains(t.Trim().ToLowerInvariant()));
        if (visible)
        {
            consecutiveAbsences = 0;
            if (InMeeting) return false;
            InMeeting = true;
            return true;
        }
        consecutiveAbsences = Math.Min(consecutiveAbsences + 1, 2);
        if (consecutiveAbsences == 2) InMeeting = false;
        return false;
    }

    public static List<string> WindowTitles()
    {
        var pids = new HashSet<int>();
        foreach (var process in Process.GetProcesses())
        {
            try { if (process.ProcessName.Equals("Zoom", StringComparison.OrdinalIgnoreCase)) pids.Add(process.Id); }
            catch { }
            finally { process.Dispose(); }
        }
        var titles = new List<string>();
        if (pids.Count == 0) return titles;
        EnumWindows((handle, _) =>
        {
            if (!IsWindowVisible(handle)) return true;
            GetWindowThreadProcessId(handle, out var pid);
            if (!pids.Contains((int)pid)) return true;
            var length = GetWindowTextLength(handle);
            if (length <= 0) return true;
            var buffer = new StringBuilder(length + 1);
            GetWindowText(handle, buffer, buffer.Capacity);
            titles.Add(buffer.ToString());
            return true;
        }, IntPtr.Zero);
        return titles;
    }

    private delegate bool EnumWindowsProc(IntPtr handle, IntPtr lparam);

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lparam);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr handle);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr handle, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextLength(IntPtr handle);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr handle, StringBuilder text, int max);
}
