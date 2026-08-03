using System.IO;
using System.IO.Pipes;
using System.Text;

namespace Photokompressor.Core;

/// <summary>
/// Explorer's classic context-menu verbs launch one process per selected file.
/// The first process to grab the mutex becomes primary and runs a named-pipe
/// server; every later process hands its path over the pipe and exits.
/// </summary>
public sealed class SingleInstance : IDisposable
{
    private const string MutexName = @"Local\Photokompressor.Singleton";
    private const string PipeName = "Photokompressor.Pipe";

    private Mutex? _mutex;

    public bool TryBecomePrimary()
    {
        try
        {
            _mutex = new Mutex(initiallyOwned: true, MutexName, out var createdNew);
            if (createdNew)
                return true;
            try
            {
                if (_mutex.WaitOne(0))
                    return true; // previous primary exited between our ctor and here
            }
            catch (AbandonedMutexException)
            {
                return true; // previous primary crashed; we own the mutex now
            }
            return false;
        }
        catch
        {
            return true; // mutex machinery failing should never block the app
        }
    }

    /// <summary>Primary side: accepts path messages until cancelled.</summary>
    public async Task RunServerAsync(Action<string> onPathReceived, CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            NamedPipeServerStream? server = null;
            try
            {
                server = new NamedPipeServerStream(PipeName, PipeDirection.In,
                    NamedPipeServerStream.MaxAllowedServerInstances,
                    PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
                await server.WaitForConnectionAsync(ct);
                using var reader = new StreamReader(server, Encoding.UTF8);
                var payload = await reader.ReadToEndAsync(ct);
                foreach (var line in payload.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                    onPathReceived(line);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch
            {
                // A single broken client connection shouldn't kill the accept loop.
            }
            finally
            {
                server?.Dispose();
            }
        }
    }

    /// <summary>Secondary side: sends paths to the primary. Retries while the primary's pipe comes up.</summary>
    public static bool TrySendToPrimary(IEnumerable<string> paths, int timeoutMs = 3000)
    {
        var payload = Encoding.UTF8.GetBytes(string.Join('\n', paths));
        var deadline = Environment.TickCount64 + timeoutMs;
        while (Environment.TickCount64 < deadline)
        {
            try
            {
                using var client = new NamedPipeClientStream(".", PipeName, PipeDirection.Out);
                client.Connect(200);
                client.Write(payload);
                client.Flush();
                return true;
            }
            catch (TimeoutException)
            {
                Thread.Sleep(50);
            }
            catch (IOException)
            {
                Thread.Sleep(50);
            }
        }
        return false;
    }

    public void Dispose()
    {
        try
        {
            _mutex?.ReleaseMutex();
        }
        catch { /* not owned */ }
        _mutex?.Dispose();
    }
}
