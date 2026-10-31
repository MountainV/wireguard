# 🛡️ WireGuard — FiveM Anticheat & Web Admin Panel

WireGuard is a self-contained FiveM anticheat inspired by FiveGuard. It bundles
real-time client detections, server-side enforcement, a trust-score system, a
ban-evasion-hardened ban system, Discord logging, screenshot evidence, an
in-game admin menu (NUI) and a standalone **web admin panel**.

> Built as a defensive security tool to keep your server fair. Tune everything
> in `config.lua`.

---

## ✨ Features

**Detections (client → server validated)**

| Category   | Checks |
|------------|--------|
| Combat     | Aimbot / Triggerbot, Rapid-fire, Explosive ammo, Weapon damage modifier, Infinite ammo |
| Player     | God mode (invincible / health / armour / regen), Invisible, No-clip, Speed hack, Teleport, Super jump, Fast run / swim, Ragdoll abuse |
| Spawning   | Blacklisted vehicles / objects / peds, Spawn rate limiting, Entity spam |
| Weapons    | Give-weapon, Blacklisted weapons |
| Explosions | Illegal / blacklisted explosion types |
| Visual     | Extended radar, Night / thermal vision, ESP player blips |
| Resources  | Protected-resource stop, Unexpected resource start, Menu injection, Lua executor |
| Misc       | Spectate, Blacklisted commands |

**Systems**

- **Trust score** — every detection subtracts points; crossing the threshold auto-bans.
- **Ban system** — JSON-persisted, matches on **every** identifier + hardware tokens (ban-evasion hardened).
- **Safe Events** — opt-in protection for your own server events (rate limit + validator) via exports.
- **Discord logging** — detection + ban webhooks with severity colours.
- **Screenshot evidence** — optional, via `screenshot-basic`.
- **In-game admin menu** — F6, player list, trust, flags, kick/ban/warn/spectate/teleport, live feed.
- **Web admin panel** — login-protected Node dashboard: overview, players, detections, bans, remote kick/ban/unban.

---

## 📁 Structure

```
wireguard/
├── fxmanifest.lua
├── config.lua                 ← all settings & thresholds
├── shared/                    enums + utils
├── client/
│   ├── main.lua               detection framework (flag/register/scheduler)
│   ├── nui.lua                in-game admin menu bridge
│   └── detections/            one file per detection category
├── server/
│   ├── main.lua               flag handling, trust, punishment, lifecycle
│   ├── bans.lua               JSON ban store + anti-evasion matching
│   ├── events.lua             Safe Events system (exports)
│   ├── admin.lua              in-game menu backend
│   ├── screenshot.lua         evidence capture
│   ├── discord.lua            webhook logging
│   └── api.lua                token-protected HTTP API
├── html/                      in-game NUI menu (HTML/CSS/JS)
├── data/bans.json             ban database
└── web-panel/                 standalone Node.js web dashboard
```

---

## 🚀 Installation

### 1. The FiveM resource

1. Copy the `wireguard` folder into your server's `resources/` directory.
2. In `server.cfg` add:
   ```
   ensure screenshot-basic   # optional, for screenshot evidence
   set wireguard_api_token "your-long-random-token"
   ensure wireguard
   ```
3. Edit **`config.lua`**:
   - Add your admins to `Config.Admins` (license identifiers) or grant the
     `wireguard.admin` ACE.
   - (Optional) enable Discord: set `Config.Discord.Enabled = true` + webhooks.
   - (Optional) enable screenshots: `Config.Screenshots.Enabled = true`.
4. Restart the server. Admins press **F6** (or `/wireguard`) in-game to open the menu.

### 2. The web panel

```bash
cd wireguard/web-panel
cp .env.example .env        # then edit .env
npm install
npm start
```

In `.env`:
- `FIVEM_API_URL` → `http://<your-server-ip>:30120/wireguard`
- `API_TOKEN` → **must match** `wireguard_api_token` in the FiveM server's `server.cfg`
- `PANEL_USER` / `PANEL_PASSWORD` → your dashboard login
- `SESSION_SECRET` → a long random string

Replace every `CHANGE_ME` value in `.env` before starting the panel. Keep `.env`
and the server.cfg token private; neither belongs in version control.

Open `http://localhost:3000` and log in.

> The FiveM HTTP endpoint is exposed by the resource itself via `SetHttpHandler`
> at `/<resource>/...`. Keep the port firewalled; only the web panel (holding the
> token) should reach it.

---

## 🧩 Using Safe Events in your own resources

Protect sensitive server events (money, admin, etc.):

```lua
-- register once (server)
exports.wireguard:registerSafeEvent('myserver:giveMoney', {
    rate = 2,  -- max calls / second / player
    validator = function(src, amount)
        return type(amount) == 'number' and amount > 0 and amount <= 10000
    end
})

-- guard the handler
RegisterNetEvent('myserver:giveMoney', function(amount)
    if not exports.wireguard:validateEvent('myserver:giveMoney', source, amount) then return end
    -- ... your logic
end)
```

Abuse → automatic kick/ban + logged to the feed, Discord and panel.

---

## ⚙️ Tuning

Everything lives in `config.lua`:
- `Config.Detections[...]` — toggle each check and set `action` (`ban`/`kick`/`warn`/`none`) and `penalty`.
- `Config.Thresholds` — speed/teleport/health/spawn-rate limits (raise if you get false positives).
- `Config.Blacklisted*` — weapons, vehicles, objects, commands, explosions.
- `Config.ProtectedResources` — resources clients must never stop.

---

## 🔧 Admin commands (console / in-game admin)

| Command | Description |
|---------|-------------|
| `/wireguard` or `/wg` or **F6** | open in-game admin menu |
| `wg_ban <serverId> <reason>` | ban a player |
| `wg_unban <banId>` | remove a ban |
| `wg_status` | print tracking stats |

---

## ⚠️ Notes & honest limitations

- Client-side detections are **signals**, not proof — hardened cheats can tamper
  with client Lua. WireGuard mirrors the important checks server-side
  (health heartbeat, ban enforcement, safe events, entity validation) and favours
  evidence (feed + screenshots) before harsh actions. Tune thresholds for your server.
- The live FiveGuard docs page blocks automated fetching (HTTP 403), so this
  implementation is modelled on FiveGuard's **published feature set**, not copied
  from it. WireGuard is original code.
- Test on a dev server first and start detections on `warn` before switching to
  `ban` to catch false positives for your specific resources.

---

Made as **WireGuard** 🛡️
