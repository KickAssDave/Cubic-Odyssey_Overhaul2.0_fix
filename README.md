# Cosmic Overhaul Repair Script

This is a small PowerShell script I put together to help repair `COSMIC OVERHAUL 2.0` for newer versions of Cubic Odyssey.

It is not an official update to the mod, and it is not a replacement for the original author coming back and updating things properly. It is just a practical workaround for people who want the mod working again right now, especially if they already have a save using it.

## What This Fixes

The main confirmed issue I identified was the broken ship shield setup.

Older mod files were still using:

```text
SHIELD_CAPACITY
```

Current game files use:

```text
SHIELD_CAPACITY_SHIP
```

That mismatch appears to be why ship shields were getting stuck at `0`.

The script also rebuilds the stack-size changes in a safer way:

- it sets stack sizes to `999` for normal stackable items
- it skips hidden/system items
- it restores hidden/system item definitions back to current vanilla values if needed

That matters because some internal platform-style items should not be touched by a blanket stack-size pass.

## What The Script Can Do

The script can:

- repair the extracted Cosmic Overhaul mod files
- accept the mod as a `.zip`, extracted folder, or direct `data` folder
- handle the common `modded\data\...` layout automatically
- optionally build a clean `stack-size only` pack
- optionally install the repaired mod straight into your game folder

## What You Need

- PowerShell
- a downloaded copy of the mod
- a clean copy of the game files, or access to the current game install

The script uses the current game data as the reference so it can rebuild safe overrides against the latest files you have.

## Files

Main script:

- `repair_cosmic_overhaul.ps1`

Optional output the script can generate:

- `STACK_SIZE_ONLY_999_CLEAN`

## Quick Use

If you want the simplest route, point the script at:

- the mod zip
- the game folder as the reference
- the same game folder as the install target

Example:

```powershell
.\repair_cosmic_overhaul.ps1 `
  -ModRoot "C:\Path\To\COSMIC OVERHAUL 2.0 MAIN-26-2-0-1752800472_fixed.zip" `
  -OriginalGameRoot "D:\SteamLibrary\steamapps\common\Cubic Odyssey" `
  -InstallToGameRoot "D:\SteamLibrary\steamapps\common\Cubic Odyssey"
```

That will:

1. extract the zip to a temporary folder
2. patch the mod files
3. copy the repaired mod contents into the game folder
4. remove the temporary extraction folder

## Supported Input Paths

`-ModRoot` can point to:

- the mod `.zip`
- the extracted mod folder
- the mod `data` folder

`-OriginalGameRoot` can point to:

- the game root folder
- the game `data` folder
- a clean backup copy of the game files

`-InstallToGameRoot` can point to:

- the game root folder
- the game `data` folder

If the mod uses a top-level `modded` folder, the script handles that automatically and copies the contents of `modded` into the game root the way a normal manual install would.

## Examples

### 1. Repair an extracted mod folder only

```powershell
.\repair_cosmic_overhaul.ps1 `
  -ModRoot "C:\Mods\COSMIC OVERHAUL 2.0 MAIN-26-2-0-1752800472" `
  -OriginalGameRoot "C:\Backups\CubicOdyssey"
```

### 2. Repair and install directly into the game

```powershell
.\repair_cosmic_overhaul.ps1 `
  -ModRoot "C:\Mods\COSMIC OVERHAUL 2.0 MAIN-26-2-0-1752800472" `
  -OriginalGameRoot "D:\SteamLibrary\steamapps\common\Cubic Odyssey" `
  -InstallToGameRoot "D:\SteamLibrary\steamapps\common\Cubic Odyssey"
```

### 3. Use the mod zip directly and install in one go

```powershell
.\repair_cosmic_overhaul.ps1 `
  -ModRoot "C:\Downloads\COSMIC OVERHAUL 2.0 MAIN-26-2-0-1752800472_fixed.zip" `
  -OriginalGameRoot "D:\SteamLibrary\steamapps\common\Cubic Odyssey" `
  -InstallToGameRoot "D:\SteamLibrary\steamapps\common\Cubic Odyssey"
```

### 4. Build the clean stack-size-only pack as well

```powershell
.\repair_cosmic_overhaul.ps1 `
  -ModRoot "C:\Downloads\COSMIC OVERHAUL 2.0 MAIN-26-2-0-1752800472_fixed.zip" `
  -OriginalGameRoot "D:\SteamLibrary\steamapps\common\Cubic Odyssey" `
  -CreateStackOnlyPack `
  -InstallToGameRoot "D:\SteamLibrary\steamapps\common\Cubic Odyssey"
```

### 5. Build the clean stack-only pack into a custom folder

```powershell
.\repair_cosmic_overhaul.ps1 `
  -ModRoot "C:\Mods\COSMIC OVERHAUL 2.0 MAIN-26-2-0-1752800472" `
  -OriginalGameRoot "C:\Backups\CubicOdyssey" `
  -CreateStackOnlyPack `
  -StackOnlyOutputRoot "C:\Mods\STACK_SIZE_ONLY_999_CLEAN"
```

## What The Script Changes

### Ship shields

The script updates shield component configs from:

```text
SHIELD_CAPACITY
```

to:

```text
SHIELD_CAPACITY_SHIP
```

### Stack sizes

The script expands stack sizes to `999` for normal stackable items based on the current vanilla files you provide.

It does not blindly set everything to `999`.

It skips hidden/system items because those are more likely to be internal objects, platform-style objects, menu-related objects, or other things that should stay on current vanilla definitions.

## About The Customization / Platform Issue

There was also a reported issue with the character customization menu platform getting deleted.

I could not prove one single exact root-cause file for that from the original mod package, but I did identify that hidden/system items were unsafe to include in the broad stack-size expansion. Because of that, the script now restores those files back to current vanilla definitions instead of leaving them modified.

That means this script is more conservative than the first rough workaround version, which is intentional.

## Safety Notes

- Back up your save before using this.
- Back up your game `data` folder if you want an easy rollback.
- This is still an unofficial workaround.
- I still recommend waiting for the mod author to return and publish a proper update if possible.

## Useful Flags

PowerShell supports `-WhatIf` here because the script uses `SupportsShouldProcess`.

So if you want to preview what it would do:

```powershell
.\repair_cosmic_overhaul.ps1 `
  -ModRoot "C:\Path\To\Mod.zip" `
  -OriginalGameRoot "D:\SteamLibrary\steamapps\common\Cubic Odyssey" `
  -InstallToGameRoot "D:\SteamLibrary\steamapps\common\Cubic Odyssey" `
  -WhatIf
```

## Why I Made This

I made this because the mod author appears to be away, people were reporting broken shields and other weird issues after recent game patches, and I wanted a repeatable way to repair the mod instead of doing it by hand every time.

## Final Note

If the original author comes back and updates the mod properly, use that instead.

This script is mainly here to help people keep existing setups alive until then.
