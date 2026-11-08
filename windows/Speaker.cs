using System;
using System.Runtime.InteropServices;
using System.Text;

namespace MeetinOS;

// Nom affiché devant les phrases de la piste micro. La piste elle-même reste « micro.wav ».
internal static class Speaker
{
    private static readonly Lazy<string> User = new(() => Name(DisplayName(), Environment.UserName));

    public static string UserLabel => User.Value;

    // Nom complet du compte Windows, sinon le nom de session, sinon « Vous ».
    public static string Name(string? fullName, string? accountName)
    {
        foreach (var candidate in new[] { fullName, accountName })
        {
            var name = string.Join(" ", (candidate ?? "").Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
            if (name.Length > 0) return name;
        }
        return "Vous";
    }

    private static string? DisplayName()
    {
        try
        {
            uint size = 256;
            var buffer = new StringBuilder((int)size);
            return GetUserNameEx(NameDisplay, buffer, ref size) ? buffer.ToString() : null;
        }
        catch (Exception error) when (error is DllNotFoundException || error is EntryPointNotFoundException)
        {
            return null;
        }
    }

    private const int NameDisplay = 3;

    [DllImport("secur32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool GetUserNameEx(int nameFormat, StringBuilder buffer, ref uint size);
}
