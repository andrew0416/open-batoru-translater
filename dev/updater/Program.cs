using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

var app = new UpdaterApp(AppContext.BaseDirectory);
return await app.RunAsync();

internal sealed class UpdaterApp
{
    private readonly string _baseDirectory;
    private readonly string _logPath;

    public UpdaterApp(string baseDirectory)
    {
        _baseDirectory = baseDirectory;
        _logPath = Path.Combine(_baseDirectory, "translate-updater.log");
    }

    public async Task<int> RunAsync()
    {
        try
        {
            DeleteIfExists(_logPath);

            var configPath = Path.Combine(_baseDirectory, "translate-source.json");
            var config = await ReadJsonFileAsync<UpdaterConfig>(configPath) ?? new UpdaterConfig();
            if (!config.Enabled)
            {
                Log("updater is disabled");
                return 0;
            }

            if (!string.Equals(config.Mode, "manifest", StringComparison.OrdinalIgnoreCase))
            {
                Log($"only manifest mode is supported; current mode={config.Mode}");
                return 0;
            }

            if (string.IsNullOrWhiteSpace(config.ManifestUrl))
            {
                Log("manifestUrl is empty; skipping update");
                return 0;
            }

            var databasePath = ResolveGamePath(config.DatabasePath);
            var statePath = databasePath + ".update.json";
            var state = await ReadJsonFileAsync<UpdateState>(statePath);

            Log($"manifest: {config.ManifestUrl}");
            Log($"database: {databasePath}");

            var manifest = await DownloadJsonAsync<TranslateManifest>(config.ManifestUrl, config.TimeoutSeconds);
            if (string.IsNullOrWhiteSpace(manifest.Url))
            {
                throw new InvalidOperationException("manifest does not contain a database url");
            }

            if (!NeedsDownload(databasePath, manifest, state))
            {
                Log("translate.db is already up to date");
                return 0;
            }

            Log($"downloading translate.db version {BlankToUnknown(manifest.Version)}");
            await InstallDatabaseAsync(manifest, databasePath, config.TimeoutSeconds, config.KeepBackup);

            await SaveJsonFileAsync(statePath, new UpdateState
            {
                Mode = "manifest",
                ManifestUrl = config.ManifestUrl,
                Url = manifest.Url,
                Version = manifest.Version ?? "",
                Sha256 = manifest.Sha256 ?? "",
                UpdatedAt = DateTimeOffset.UtcNow.ToString("O"),
            });

            Log("translate.db updated");
        }
        catch (Exception ex)
        {
            Log(ex.Message);
            Log("starting OpenBatoru with the existing translate.db");
        }

        return 0;
    }

    private string ResolveGamePath(string? path)
    {
        var configured = string.IsNullOrWhiteSpace(path) ? "translate.db" : path;
        return Path.IsPathRooted(configured) ? configured : Path.Combine(_baseDirectory, configured);
    }

    private bool NeedsDownload(string databasePath, TranslateManifest manifest, UpdateState? state)
    {
        if (!File.Exists(databasePath))
        {
            Log("local translate.db was not found");
            return true;
        }

        if (!string.IsNullOrWhiteSpace(manifest.Sha256))
        {
            var localHash = Sha256File(databasePath);
            var remoteHash = manifest.Sha256.Trim().ToLowerInvariant();
            Log($"local sha256: {localHash}");
            Log($"remote sha256: {remoteHash}");
            return !string.Equals(localHash, remoteHash, StringComparison.OrdinalIgnoreCase);
        }

        if (!string.IsNullOrWhiteSpace(manifest.Version))
        {
            var localVersion = state?.Version ?? "";
            Log($"local version: {localVersion}");
            Log($"remote version: {manifest.Version}");
            return !string.Equals(localVersion, manifest.Version, StringComparison.Ordinal);
        }

        Log("manifest has no sha256 or version; skipping update");
        return false;
    }

    private async Task InstallDatabaseAsync(TranslateManifest manifest, string databasePath, int timeoutSeconds, bool keepBackup)
    {
        var tempPath = databasePath + ".download";
        var backupPath = databasePath + ".bak";
        DeleteIfExists(tempPath);

        var bytes = await DownloadBytesAsync(manifest.Url!, timeoutSeconds);
        AssertSqliteDatabase(bytes);
        await File.WriteAllBytesAsync(tempPath, bytes);

        if (!string.IsNullOrWhiteSpace(manifest.Sha256))
        {
            var actualSha256 = Sha256File(tempPath);
            var expected = manifest.Sha256.Trim().ToLowerInvariant();
            if (!string.Equals(actualSha256, expected, StringComparison.OrdinalIgnoreCase))
            {
                DeleteIfExists(tempPath);
                throw new InvalidOperationException($"downloaded translate.db hash mismatch. expected={expected} actual={actualSha256}");
            }
        }

        if (File.Exists(databasePath) && keepBackup)
        {
            File.Copy(databasePath, backupPath, overwrite: true);
        }

        File.Move(tempPath, databasePath, overwrite: true);
    }

    private async Task<T> DownloadJsonAsync<T>(string url, int timeoutSeconds)
    {
        var text = await DownloadTextAsync(url, timeoutSeconds);
        var value = JsonSerializer.Deserialize<T>(StripBom(text), JsonOptions());
        return value ?? throw new InvalidOperationException("downloaded JSON is empty");
    }

    private static async Task<string> DownloadTextAsync(string url, int timeoutSeconds)
    {
        using var client = CreateClient(timeoutSeconds);
        return await client.GetStringAsync(url);
    }

    private static async Task<byte[]> DownloadBytesAsync(string url, int timeoutSeconds)
    {
        using var client = CreateClient(timeoutSeconds);
        return await client.GetByteArrayAsync(url);
    }

    private static HttpClient CreateClient(int timeoutSeconds)
    {
        var handler = new HttpClientHandler
        {
            AutomaticDecompression = DecompressionMethods.All,
            AllowAutoRedirect = true,
        };
        var client = new HttpClient(handler)
        {
            Timeout = TimeSpan.FromSeconds(timeoutSeconds <= 0 ? 20 : timeoutSeconds),
        };
        client.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("open-batoru-translate-updater", "1.0"));
        client.DefaultRequestHeaders.CacheControl = new CacheControlHeaderValue { NoCache = true };
        return client;
    }

    private static void AssertSqliteDatabase(byte[] bytes)
    {
        var header = Encoding.ASCII.GetBytes("SQLite format 3\0");
        if (bytes.Length < header.Length)
        {
            throw new InvalidOperationException("translate.db is too small");
        }

        for (var i = 0; i < header.Length; i++)
        {
            if (bytes[i] != header[i])
            {
                throw new InvalidOperationException("translate.db is not a SQLite database");
            }
        }
    }

    private static async Task<T?> ReadJsonFileAsync<T>(string path)
    {
        if (!File.Exists(path))
        {
            return default;
        }

        var text = StripBom(await File.ReadAllTextAsync(path, Encoding.UTF8));
        if (string.IsNullOrWhiteSpace(text))
        {
            return default;
        }

        return JsonSerializer.Deserialize<T>(text, JsonOptions());
    }

    private static async Task SaveJsonFileAsync<T>(string path, T value)
    {
        var json = JsonSerializer.Serialize(value, JsonOptions()) + Environment.NewLine;
        await File.WriteAllTextAsync(path, json, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
    }

    private static JsonSerializerOptions JsonOptions() => new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    private static string Sha256File(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }

    private static string StripBom(string text)
    {
        return text.Length > 0 && text[0] == '\uFEFF' ? text[1..] : text;
    }

    private static string BlankToUnknown(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? "unknown" : value;
    }

    private static void DeleteIfExists(string path)
    {
        if (File.Exists(path))
        {
            File.Delete(path);
        }
    }

    private void Log(string message)
    {
        var line = $"[translate-db] {message}";
        Console.WriteLine(line);
        try
        {
            File.AppendAllText(_logPath, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {line}{Environment.NewLine}", Encoding.UTF8);
        }
        catch
        {
            // Logging must never block the game from starting.
        }
    }
}

internal sealed class UpdaterConfig
{
    public bool Enabled { get; set; }
    public string Mode { get; set; } = "manifest";
    public string ManifestUrl { get; set; } = "";
    public string DatabasePath { get; set; } = "translate.db";
    public int TimeoutSeconds { get; set; } = 20;
    public bool KeepBackup { get; set; } = true;
}

internal sealed class TranslateManifest
{
    public string? Version { get; set; }
    public string? Url { get; set; }
    public string? Sha256 { get; set; }
}

internal sealed class UpdateState
{
    public string? Mode { get; set; }
    public string? ManifestUrl { get; set; }
    public string? Url { get; set; }
    public string? Version { get; set; }
    public string? Sha256 { get; set; }
    public string? UpdatedAt { get; set; }
}
