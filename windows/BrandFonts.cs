using System;
using System.Drawing;
using System.Drawing.Text;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;

namespace MeetinOS;

// Charge EB Garamond et Figtree depuis le dossier Fonts de l’app, pour GDI+ (Font) et GDI (TextRenderer).
internal static class BrandFonts
{
    private static readonly PrivateFontCollection Collection = new();
    public static readonly FontFamily? Serif;
    public static readonly FontFamily? Sans;
    public static readonly FontFamily? SansMedium;

    // EB Garamond paraît plus petite que Georgia à taille égale : on la grossit légèrement, comme le rendu Mac.
    public static float SerifScale => Serif == null ? 1f : 1.12f;

    static BrandFonts()
    {
        try
        {
            var folder = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Fonts");
            foreach (var file in new[] { "EBGaramond.ttf", "Figtree.ttf" })
            {
                var path = Path.Combine(folder, file);
                if (!File.Exists(path)) continue;
                AddFontResourceEx(path, FrPrivate, IntPtr.Zero);
                Collection.AddFontFile(path);
            }
            Serif = Find("EB Garamond");
            Sans = Find("Figtree");
            SansMedium = Find("Figtree Medium") ?? Find("Figtree SemiBold") ?? Sans;
        }
        catch { Serif = Sans = SansMedium = null; }
    }

    public static string[] Families => Collection.Families.Select(f => f.Name).ToArray();

    public static Font Create(FontFamily? family, string fallback, float size, FontStyle style)
    {
        if (family != null && family.IsStyleAvailable(style))
        {
            try { return new Font(family, size, style, GraphicsUnit.Point); } catch { }
        }
        return new Font(fallback, size, style, GraphicsUnit.Point);
    }

    private static FontFamily? Find(string name) =>
        Collection.Families.FirstOrDefault(f => string.Equals(f.Name, name, StringComparison.OrdinalIgnoreCase));

    private const uint FrPrivate = 0x10;

    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    private static extern int AddFontResourceEx(string name, uint flags, IntPtr reserved);
}
