// m3launch — лаунчер Spotify для m3ify (в exe вшита M3-иконка).
// 1) если Spotify обновился (появился новый xpui.spa — обновление заодно заменяет Spotify.exe),
//    тихо переприменяет тему и иконку;
// 2) запускает Spotify с теми же аргументами и сразу выходит — в памяти не висит.
// Иконка окна и панели задач берётся из самого Spotify.exe (m3ify меняет в нём иконку),
// поэтому никаких своих AppUserModelID окну больше не ставим.
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;

static class M3Launch
{
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    struct PROPERTYKEY { public Guid fmtid; public uint pid; }

    [StructLayout(LayoutKind.Explicit, Size = 24)]
    struct PROPVARIANT { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr p; }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore
    {
        int GetCount(out uint c);
        int GetAt(uint i, out PROPERTYKEY k);
        int GetValue(ref PROPERTYKEY k, out PROPVARIANT v);
        int SetValue(ref PROPERTYKEY k, ref PROPVARIANT v);
        int Commit();
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHGetPropertyStoreFromParsingName(string path, IntPtr pbc, int flags, ref Guid riid, out IPropertyStore ps);

    // для установщика: m3launch.exe --clear-lnk-aumid <path.lnk> — убрать AppUserModelID,
    // оставшийся в ярлыке от прошлых версий m3ify
    static int ClearLinkAumid(string lnk)
    {
        var g = typeof(IPropertyStore).GUID;
        IPropertyStore ps;
        int hr = SHGetPropertyStoreFromParsingName(lnk, IntPtr.Zero, 2 /*GPS_READWRITE*/, ref g, out ps);
        if (hr != 0) return hr;
        var k = new PROPERTYKEY { fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };
        var v = new PROPVARIANT(); // VT_EMPTY
        ps.SetValue(ref k, ref v);
        return ps.Commit();
    }

    static string Quote(string a) { return a.Length > 0 && a.IndexOfAny(new[] { ' ', '"' }) < 0 ? a : "\"" + a.Replace("\"", "\\\"") + "\""; }

    [STAThread]
    static int Main(string[] args)
    {
        if (args.Length >= 2 && args[0] == "--clear-lnk-aumid") return ClearLinkAumid(args[1]);

        string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        string home = Path.GetDirectoryName(typeof(M3Launch).Assembly.Location);
        string spotifyDir = Path.Combine(appData, "Spotify");
        string spotify = Path.Combine(spotifyDir, "Spotify.exe");

        if (Process.GetProcessesByName("Spotify").Length == 0 && File.Exists(Path.Combine(spotifyDir, @"Apps\xpui.spa")))
        {
            // Spotify обновился — возвращаем тему и иконку перед запуском
            try
            {
                var psi = new ProcessStartInfo("powershell.exe",
                    "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " + Quote(Path.Combine(home, "m3ify.ps1")) + " apply -Quiet")
                { CreateNoWindow = true, UseShellExecute = false };
                using (var p = Process.Start(psi)) p.WaitForExit(120000);
            }
            catch { }
        }

        try
        {
            Process.Start(new ProcessStartInfo(spotify, string.Join(" ", args.Select(Quote)))
            { UseShellExecute = false, WorkingDirectory = spotifyDir });
        }
        catch { return 1; }
        return 0;
    }
}
