# Hey, rid of these pests! – Game Loop Draft (Godot 4.7)

## 1. What is already in your project (created via Godot MCP)

```
res://scenes/
  lobby.tscn   Control > Menu(VBox) > QuickMatchButton, CreateRoomButton, RoomCodeEdit, JoinRoomButton, StatusLabel
  match.tscn   Node2D > Yard, Kitchen(DiningTable[Area2D], SpawnLeft/Top/Bottom[Marker2D]),
                        Players, Enemies, PlayerSpawner, EnemySpawner (MultiplayerSpawner)
  player.tscn  CharacterBody2D > CollisionShape2D, Sprite2D, HitArea(Area2D > CollisionShape2D), MultiplayerSynchronizer
  enemy.tscn   CharacterBody2D > CollisionShape2D, Sprite2D, AttackArea(Area2D > CollisionShape2D)
```
The MCP tools can create scenes/nodes but cannot write script files or set Resource properties
(collision shapes, textures), so the scripts below are delivered separately.
Characters/enemies are drawn with `_draw()` placeholders – no art needed to test.

## 2. Install (5 minutes)

1. Copy the `scripts/` folder into `res://scripts/`.
2. **Project > Project Settings > Globals (Autoload)** – add in this order:
   - `res://scripts/game_data.gd` as **GameData**
   - `res://scripts/network.gd` as **Network**
3. Attach scripts (select node > Attach Script > "Load" existing):

| Scene | Node | Script |
|---|---|---|
| lobby.tscn | root | `lobby.gd` |
| match.tscn | root | `match_manager.gd` |
| match.tscn | Kitchen/DiningTable | `dining_table.gd` |
| player.tscn | root | `player.gd` |
| enemy.tscn | root | `enemy.gd` |

4. **Project Settings > Application > Run > Main Scene** = `res://scenes/lobby.tscn`.
5. Test: **Debug > Customize Run Instances > Enable Multiple Instances (2–3)**.
   Instance 1: *Create Private Room* → note the code. Instance 2/3: type code → *Join Room* (or *Quick Match*).
   Host presses *Start Match*. Solo test: host + Start with one player works.
   Controls: WASD move · mouse aim · LMB attack · Q skill 1 · E skill 2.

`combat.gd`, `skills.gd` use `class_name` (no setup needed).

## 3. Architecture

```
Host peer (id 1) = authoritative server              Clients
 ├ Network (lobby, rooms, roster)  ◄── rpc ──►        Network
 ├ MatchManager  (phases, spawns, wallets, rewards) ─ cl_phase/cl_timer/cl_wallet/cl_result ─► HUD
 ├ Enemy AI + damage + telegraph RPCs  ───────────── position/hp replicated ──────────────► draw
 └ Player: validates attack/skill requests ◄──────── srv_attack / srv_skill (aim + mouse) ── input
Movement is client-authoritative (owner peer); everything that affects balance is server-side.
```

## 4. Matchmaking flow
`Lobby` → **Quick Match**: broadcast `RIDPESTS?:*` → join first open room, else host a new one and wait.
**Private**: host gets a 4-letter code; friends send `RIDPESTS?:CODE` → host answers with its IP → ENet connect.
Client sends `srv_register(profile)`; server caps the room at 3, broadcasts the roster, host picks difficulty
and presses Start → `cl_start` loads `match.tscn` on all peers → each client reports `srv_loaded` →
server spawns the 3 players and runs the loop.
> Currently LAN-only. For true online play, swap `_find_room()` / host registration for a matchmaking
> service (HTTP) that returns `{ip, port, code}`, or move to Steam/EOS lobbies. The rest is unchanged.

## 5. The match loop (match_manager.gd)

```
 LOADING → for wave 1..5:
   YARD (60s)         spawn pests (cap 18); kill = Ether to ALL 3 wallets; death = auto-revive after 10s
   dinner bell        yard pests cleared, dead players revived (100%), everyone teleported to kitchen
   KITCHEN_PREP (10s) workbench window: press F at the Workbench to buy Commons / craft Rares+Epics (also usable in SIEGE + FEAST)
   SIEGE              3 sub-waves; spawn vectors by difficulty (Normal: L | Hard: 2 rotating | Hell: all 3)
                      sub-wave 3 adds the miniboss; dead players stay dead until it dies (revive @50%)
                      wave 5: after miniboss → Trash King (phase 2 at 50%: leaps on table, eats food)
   FEAST              bank wave rewards, bonus Ether to all, 5s → next wave
 DEFEAT = all 3 dead in siege OR food = 0.   VICTORY = Trash King dead.
```

## 6. Attack (offence)
- **Basic attack**: client sends aim → server checks ASPD cooldown → melee = cone, ranged = line hit-scan
  (`Combat.cone/line`), crit roll, lifesteal. Skewer's "next 2 crits" is a counter.
- **Skills**: `GameData.CHARACTERS[id].skill1/2` carry a `kind`; `Skills.cast()` executes it
  (zones, dashes, volley, vortex, dome, teleport, taunt, heal, team buff, trap).
  Damage = `(base × level_mult + coef × ATK) × (1 + skill power)`.
- Status effects on enemies: stun, slow, root/pin, armour shred (+% damage taken), push, taunt. Bosses ignore stun/root/push.

## 7. Defence
- **Table**: `DiningTable.take_damage()`; Dome makes it invulnerable; aura heals players 3% max HP/s within 3 tiles.
- **Player**: shield → HP; dome/untargetable immunity; yard vs siege death rules in `MatchManager._on_player_died`.
- **Enemy targeting**: kitchen pests walk to the table and only switch to a player within 150px;
  Clank's taunt overrides. Yard pests chase the nearest player within 400px.

## 8. Character behaviour design
| Archetype | Characters | Basic attack | Role in the loop |
|---|---|---|---|
| Melee bruiser | Nanay Tala, Skewer | cone | burst / stun (Tala), execute-style crits (Skewer) |
| Tank / CC | Broomsworth, Clank | wide cone | push, vortex, taunt + shield keep pests off the food |
| Ranged DPS | Pip, Snap | line | volley / long-range pierce & pin |
| Mage / zone | Suds, Flick, Goo | line | slow floors, fire zones, root traps, table dome |
| Support | Whisker | line | targeted heal + team buff |
Enemy archetypes share one loop: `CHASE → TELEGRAPH (0.7–1.2s by difficulty) → STRIKE → RECOVER`;
each attack kind draws its own red/yellow indicator (line, circle, cone) on all clients.

## 9. Assumptions I made (please confirm)
1. **Ether**: the enemy table says "per-player amount", so each kill adds that amount to every wallet (no ÷3).
2. **Feast Bonus Ether** has no numbers in the GDD → placeholder `[50, 75, 100, 140, 180]`.
3. **Wave 5 miniboss**: GDD says Wave 5 has a miniboss before the Trash King; I reuse Ratatouille (max HP).
4. **Food Integrity** persists across waves (GDD quest implies this) and never regenerates. Is that intended?
5. **Yard death**: revive at the yard entrance (I treated "Kitchen doorway" as the yard's entry door).
6. **Skill scaling**: "180% DMG" interpreted as 1.8 × ATK plus the flat base.
7. Skills that need persistent objects (Snap's tripwire) are approximated as a one-shot line.

## 10. Not yet built (next steps)
Item polish (Workbench itself is done): Cockroach Spray / Zapper wide-cone art, Turbo Vacuum Boots phasing
(needs collisions), Fridge-door aura slowing enemy attack speed. Also: 3 passives + emblem
loadout (`on_basic_attack` hook in `srv_attack`), lobby passive/emblem icons, Spirit Crumb spectator ping,
procedural yard, real sprites/animations + collision shapes, save system for levels/currencies/gacha,
energy + backend payout, skill-cooldown HUD.
