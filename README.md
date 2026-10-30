# Stuffs

A simple damage, healing and threat meter for the World of Warcraft 1.12.1
client and Unreal Azeroth. It has two windows, and the same code runs on both
clients.

## Status

Early development. The damage meter and the threat calculation have been tried
on Unreal Azeroth, solo, with a hunter and a pet. Not tried in game yet: the
1.12.1 client, group play and threat sync. Threat for the other classes is
calculated but not confirmed.

## Damage window

- Modes: Damage, DPS, Healing, HPS and Total healing. Healing and HPS count
  effective healing; Total healing includes overheal and shows it as a darker
  part of the bar.
- Data for the current fight and overall, since the last reset. Data is kept
  in memory only.
- Per-second values use active fight time, so the time between fights does not
  lower them.
- Pets have their own row, or can be merged with their owner.
- Hovering a bar shows the totals and a breakdown by spell.

Title bar clicks:

| Click | Action |
|---|---|
| Left-click | Next mode |
| Right-click | Current or overall |
| Shift + left-click | Reset the data |

## Threat window

- Lists the group's threat on your target, highest first. If your target is
  friendly, it shows your target's target, so a healer targeting the tank sees
  the tank's mob.
- The tank's row is marked `(tank)`; every other row shows its share of the
  tank's threat.
- Your own row is highlighted and always visible.
- Threat is estimated from the combat log, because neither client has a threat
  API. Other group members' values arrive over the addon channel, in party,
  raid and battleground groups.
- An aggro warning shows a message and plays a sound as you approach the point
  of pulling aggro: more than 110% of the tank's threat in melee range, 130%
  farther away. By default it fires at 80% of that point. The message, sound,
  threshold and minimum threat can be set in the options.

## Commands

| Command | Action |
|---|---|
| `/stuffs` | Open the options window |
| `/stuffs damage` | Show or hide the damage window |
| `/stuffs threat` | Show or hide the threat window |
| `/stuffs reset` | Clear the current and overall data |
| `/stuffs lock` | Lock both windows |
| `/stuffs unlock` | Allow moving (title bar) and resizing (bottom right corner) |
| `/stuffs debug` | Print recognized combat log lines |
| `/stuffs debug all` | Also print unrecognized lines |
| `/stuffs debug threat` | Print every threat change |

Any other argument prints the version and this list.

## Limits

These affect the threat window unless noted:

- Mobs are identified by name, so two mobs with the same name share one entry,
  and one of them dying removes it.
- You only see another player's threat if they run an addon with
  LibVanillaThreat-1.0, such as Stuffs or ElvUI-UA.
- The group needs one client language for synced values to match, because mob
  names differ per language.
- Spell, buff and talent names in the threat data are English. On other client
  languages the combat log still parses, but threat modifiers and ability
  bonuses do not apply.
- The combat log names no spell rank, so a spell counts at the highest rank in
  your spellbook.
- Set bonuses and some talents are not counted yet.
- Damage meter: the combat log has a limited range, so a distant group member's
  damage can be missed.

## Building

A plain checkout does not run: `Libs/` only contains LibStub, and the other
libraries are listed in `.pkgmeta` as externals. Package the addon with a
packager that reads `.pkgmeta`, then copy the resulting `Stuffs` folder to
`Interface\AddOns`.
