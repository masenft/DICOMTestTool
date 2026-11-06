namespace DicomTestTool.Services;

/// <summary>Only one instance may run (two Storage SCPs would compete for the port). A second start brings the first window to the front.</summary>
internal static class SingleInstance
{
    private const string MutexName = @"Local\DICOMTestTool.SingleInstance";
    private const string EventName = @"Local\DICOMTestTool.Show";
    private static Mutex? _mutex;
    private static EventWaitHandle? _event;

    public static bool TryAcquire()
    {
        if (!OperatingSystem.IsWindows()) return true;
        _mutex = new Mutex(true, MutexName, out var created);
        if (!created) return false;
        _event = new EventWaitHandle(false, EventResetMode.AutoReset, EventName);
        return true;
    }

    public static void SignalFirstInstance()
    {
        if (!OperatingSystem.IsWindows()) return;
        try { using var e = EventWaitHandle.OpenExisting(EventName); e.Set(); } catch { }
    }

    /// <summary>Calls <paramref name="onShow"/> (on a background thread) whenever another instance was started.</summary>
    public static void ListenForShowRequests(Action onShow)
    {
        if (_event == null) return;
        var t = new Thread(() =>
        {
            while (true)
            {
                _event.WaitOne();
                onShow();
            }
        }) { IsBackground = true, Name = "SingleInstance" };
        t.Start();
    }
}
