using System.Text.Json;

namespace FifaStreetLauncher;

// Launcher rooms: when someone joins this player's room, the launcher starts the game itself (once per room). The game
// covers itself with its loading page and walks to the friend match set-up on its own (game DLL room driver); the
// server closes the room once both players are in the lobby, which removes it from both launchers.
public partial class LauncherForm
{
    private long roomLaunchedFor;  // room id the game was started for

    // Called with the player's current room on every social refresh (null when not in a room).
    private void OnRoomState(JsonElement? room)
    {
        if (room is not { ValueKind: JsonValueKind.Object } r) return;
        long id = r.TryGetProperty("id", out var idv) && idv.ValueKind == JsonValueKind.Number ? idv.GetInt64() : 0;
        int players = r.TryGetProperty("players", out var pv) && pv.ValueKind == JsonValueKind.Array ? pv.GetArrayLength() : 0;
        int seats = r.TryGetProperty("seats", out var sv) && sv.ValueKind == JsonValueKind.Number ? sv.GetInt32() : 2;
        if (players < seats || id == roomLaunchedFor || !onlineModeBox.Checked) return;
        BeginInvoke(async () =>
        {
            // Two overlapping refreshes can both see the full room: the second must not kill the game the first started.
            if (id == roomLaunchedFor) return;
            roomLaunchedFor = id;
            // A game that is already open sits on some menu the room driver cannot walk from (it starts at the
            // title screen), so the match is never created: close it and start it again for the room. The page
            // tells the player (launcher.html roomSteps).
            if (gameRunning && gameProcess is { } running)
            {
                try { running.Kill(); }
                catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception) { }
                for (int i = 0; i < 100 && gameRunning; ++i) await Task.Delay(100);  // LaunchGame's finally clears it
            }
            // The same for a game opened outside the launcher from this install.
            if (OtherGameFromHere() is { } other)
            {
                using var _ = other;  // a killed process stays listed while a handle to it is open
                try { other.Kill(); await other.WaitForExitAsync(); }
                catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception) { }
            }
            if (!gameRunning) LaunchGame();
        });
    }
}
