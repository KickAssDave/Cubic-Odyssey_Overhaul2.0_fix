<#
.SYNOPSIS
Repairs the current Cosmic Overhaul mod files for recent Cubic Odyssey data changes.

.DESCRIPTION
 This script applies the two fixes that were verified in the local comparison:

 1. Updates ship shield component configs from SHIELD_CAPACITY to SHIELD_CAPACITY_SHIP.
 2. Expands stack sizes to 999 for every item that is already stackable in a clean copy
   of the game's data files, while skipping hidden/system items.

It can patch the extracted mod in place and can also build a separate clean
"stack-size only" mini-mod from the supplied original game data.

.PARAMETER ModRoot
Path to the extracted mod folder, or directly to its data folder.

.PARAMETER OriginalGameRoot
Path to a clean copy of the game's files, or directly to its data folder.

.PARAMETER CreateStackOnlyPack
Also generates a separate stack-size-only pack based on the clean original files.

.PARAMETER StackOnlyOutputRoot
Output folder for the stack-size-only pack. If omitted, a folder named
STACK_SIZE_ONLY_999_CLEAN will be created next to the mod folder.

.EXAMPLE
.\repair_cosmic_overhaul.ps1 `
  -ModRoot ".\COSMIC OVERHAUL 2.0 MAIN-26-2-0-1752800472" `
  -OriginalGameRoot ".\ORIGINAL_GAME" `
  -CreateStackOnlyPack

.EXAMPLE
.\repair_cosmic_overhaul.ps1 `
  -ModRoot "D:\Mods\Cosmic Overhaul\data" `
  -OriginalGameRoot "D:\CubicOdysseyBackup\data" `
  -CreateStackOnlyPack `
  -StackOnlyOutputRoot "D:\Mods\STACK_SIZE_ONLY_999_CLEAN"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$ModRoot,

    [Parameter(Mandatory = $true)]
    [string]$OriginalGameRoot,

    [switch]$CreateStackOnlyPack,

    [string]$StackOnlyOutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

 function Resolve-DataRoot {
     param(
         [Parameter(Mandatory = $true)]
         [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $dataCandidate = Join-Path $resolvedPath "data"
    $configsUnderRoot = Join-Path $resolvedPath "configs"
    $configsUnderData = Join-Path $dataCandidate "configs"

    if (Test-Path -LiteralPath $configsUnderData -PathType Container) {
        return $dataCandidate
    }

     if (Test-Path -LiteralPath $configsUnderRoot -PathType Container) {
         return $resolvedPath
     }

     $nestedCandidates = @(
         Get-ChildItem -LiteralPath $resolvedPath -Directory -Recurse |
         Where-Object {
             $_.Name -ieq "data" -and
             (Test-Path -LiteralPath (Join-Path $_.FullName "configs") -PathType Container)
         } |
         Select-Object -ExpandProperty FullName -Unique
     )

     if ($nestedCandidates.Count -eq 1) {
         return $nestedCandidates[0]
     }

     if ($nestedCandidates.Count -gt 1) {
         $candidateList = $nestedCandidates -join [Environment]::NewLine
         throw "$Label matched more than one nested data folder. Please point directly to the correct folder.`n$candidateList"
     }

     throw "$Label must point to either a folder that contains a 'data' directory, or directly to a 'data' directory."
 }

function Read-FileText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return [System.IO.File]::ReadAllText($Path)
}

function Write-FileTextIfChanged {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    if (Test-Path -LiteralPath $Path) {
        $existingContent = Read-FileText -Path $Path
        if ($existingContent -ceq $Content) {
            return $false
        }
    }

    $parent = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void][System.IO.Directory]::CreateDirectory($parent)
    }

    [System.IO.File]::WriteAllText($Path, $Content, $script:Utf8NoBom)
    return $true
}

function Get-StackSizeFromContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $match = [regex]::Match($Content, '(?m)^\s*stack_size\s+(\d+)\s*$')
    if (-not $match.Success) {
        return $null
    }

    return [int]$match.Groups[1].Value
}

function Test-IsHiddenItemContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    return [regex]::IsMatch($Content, '(?m)^\s*isHidden\s+TRUE\s*$')
}

function Set-StackSizeTo999 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $pattern = '(?m)^(\s*stack_size\s+)\d+(\s*)$'
    if ($Content -notmatch $pattern) {
        return $null
    }

    return [regex]::Replace($Content, $pattern, '${1}999${2}', 1)
}

function Update-ShieldComponents {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComponentsPath
    )

    $shieldFiles = @(Get-ChildItem -LiteralPath $ComponentsPath -Filter "*SHIELD*.cfg" -File)
    $updatedCount = 0

    foreach ($file in $shieldFiles) {
        $content = Read-FileText -Path $file.FullName
        $updatedContent = [regex]::Replace($content, '\bSHIELD_CAPACITY\b', 'SHIELD_CAPACITY_SHIP')

        if ($updatedContent -cne $content) {
            if ($PSCmdlet.ShouldProcess($file.FullName, "Update shield capacity attribute")) {
                if (Write-FileTextIfChanged -Path $file.FullName -Content $updatedContent) {
                    $updatedCount++
                }
            }
        }
    }

    return [pscustomobject]@{
        Scanned = $shieldFiles.Count
        Updated = $updatedCount
    }
}

function Expand-ModStackSizes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OriginalItemsPath,

        [Parameter(Mandatory = $true)]
        [string]$ModItemsPath
    )

    if (-not (Test-Path -LiteralPath $ModItemsPath -PathType Container)) {
        [void][System.IO.Directory]::CreateDirectory($ModItemsPath)
    }

    $eligibleCount = 0
    $createdCount = 0
    $updatedCount = 0

    foreach ($originalFile in Get-ChildItem -LiteralPath $OriginalItemsPath -Filter "*.cfg" -File) {
        $originalContent = Read-FileText -Path $originalFile.FullName
        $originalStackSize = Get-StackSizeFromContent -Content $originalContent

        if (($null -eq $originalStackSize) -or ($originalStackSize -le 1)) {
            continue
        }

        if (Test-IsHiddenItemContent -Content $originalContent) {
            continue
        }

        $eligibleCount++

        $targetPath = Join-Path $ModItemsPath $originalFile.Name
        $targetExists = Test-Path -LiteralPath $targetPath
        $baseContent = if ($targetExists) { Read-FileText -Path $targetPath } else { $originalContent }
        $updatedContent = Set-StackSizeTo999 -Content $baseContent

        if ($null -eq $updatedContent) {
            continue
        }

        if ($updatedContent -cne $baseContent) {
            if ($PSCmdlet.ShouldProcess($targetPath, "Set stack_size to 999 in main mod")) {
                if (Write-FileTextIfChanged -Path $targetPath -Content $updatedContent) {
                    if ($targetExists) {
                        $updatedCount++
                    }
                    else {
                        $createdCount++
                    }
                }
            }
        }
    }

    return [pscustomobject]@{
        Eligible = $eligibleCount
        Created  = $createdCount
        Updated  = $updatedCount
    }
}

function New-StackOnlyPack {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OriginalItemsPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputRoot
    )

    $outputItemsPath = Join-Path $OutputRoot "data\configs\items"
    if (-not (Test-Path -LiteralPath $outputItemsPath -PathType Container)) {
        [void][System.IO.Directory]::CreateDirectory($outputItemsPath)
    }

    $eligibleCount = 0
    $writtenCount = 0

    foreach ($originalFile in Get-ChildItem -LiteralPath $OriginalItemsPath -Filter "*.cfg" -File) {
        $originalContent = Read-FileText -Path $originalFile.FullName
        $originalStackSize = Get-StackSizeFromContent -Content $originalContent

        if (($null -eq $originalStackSize) -or ($originalStackSize -le 1)) {
            continue
        }

        if (Test-IsHiddenItemContent -Content $originalContent) {
            continue
        }

        $eligibleCount++
        $updatedContent = Set-StackSizeTo999 -Content $originalContent
        $targetPath = Join-Path $outputItemsPath $originalFile.Name

        if ($PSCmdlet.ShouldProcess($targetPath, "Write stack-only override")) {
            if (Write-FileTextIfChanged -Path $targetPath -Content $updatedContent) {
                $writtenCount++
            }
        }
    }

    return [pscustomobject]@{
        Eligible   = $eligibleCount
        FilesWritten = $writtenCount
        OutputRoot = $OutputRoot
    }
}

function Restore-HiddenItemDefinitions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OriginalItemsPath,

        [Parameter(Mandatory = $true)]
        [string]$ModItemsPath,

        [string]$StackOnlyItemsPath
    )

    $hiddenItemCount = 0
    $modRestoredCount = 0
    $stackOnlyRestoredCount = 0

    foreach ($originalFile in Get-ChildItem -LiteralPath $OriginalItemsPath -Filter "*.cfg" -File) {
        $originalContent = Read-FileText -Path $originalFile.FullName
        if (-not (Test-IsHiddenItemContent -Content $originalContent)) {
            continue
        }

        $hiddenItemCount++

        $modTargetPath = Join-Path $ModItemsPath $originalFile.Name
        if (Test-Path -LiteralPath $modTargetPath) {
            if ($PSCmdlet.ShouldProcess($modTargetPath, "Restore hidden item definition from vanilla")) {
                if (Write-FileTextIfChanged -Path $modTargetPath -Content $originalContent) {
                    $modRestoredCount++
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($StackOnlyItemsPath)) {
            $stackOnlyTargetPath = Join-Path $StackOnlyItemsPath $originalFile.Name
            if (Test-Path -LiteralPath $stackOnlyTargetPath) {
                if ($PSCmdlet.ShouldProcess($stackOnlyTargetPath, "Restore hidden item definition in stack-only pack")) {
                    if (Write-FileTextIfChanged -Path $stackOnlyTargetPath -Content $originalContent) {
                        $stackOnlyRestoredCount++
                    }
                }
            }
        }
    }

    return [pscustomobject]@{
        HiddenItemsScanned      = $hiddenItemCount
        MainModFilesRestored    = $modRestoredCount
        StackOnlyFilesRestored  = $stackOnlyRestoredCount
    }
}

$modDataRoot = Resolve-DataRoot -Path $ModRoot -Label "ModRoot"
$originalDataRoot = Resolve-DataRoot -Path $OriginalGameRoot -Label "OriginalGameRoot"

$modConfigsPath = Join-Path $modDataRoot "configs"
$originalConfigsPath = Join-Path $originalDataRoot "configs"
$modComponentsPath = Join-Path $modConfigsPath "components"
$modItemsPath = Join-Path $modConfigsPath "items"
$originalItemsPath = Join-Path $originalConfigsPath "items"

if (-not (Test-Path -LiteralPath $modComponentsPath -PathType Container)) {
    throw "Could not find the mod components folder: $modComponentsPath"
}

if (-not (Test-Path -LiteralPath $originalItemsPath -PathType Container)) {
    throw "Could not find the original game items folder: $originalItemsPath"
}

 if ($CreateStackOnlyPack.IsPresent -and [string]::IsNullOrWhiteSpace($StackOnlyOutputRoot)) {
     $modParent = Split-Path -Path (Split-Path -Path $modDataRoot -Parent) -Parent
     $StackOnlyOutputRoot = Join-Path $modParent "STACK_SIZE_ONLY_999_CLEAN"
 }

 if ($CreateStackOnlyPack.IsPresent) {
     $StackOnlyOutputRoot = [System.IO.Path]::GetFullPath($StackOnlyOutputRoot)
 }

 Write-Host "Mod data root: $modDataRoot"
 Write-Host "Original data root: $originalDataRoot"
if ($CreateStackOnlyPack.IsPresent) {
    Write-Host "Stack-only output: $StackOnlyOutputRoot"
}

$shieldSummary = Update-ShieldComponents -ComponentsPath $modComponentsPath
$stackSummary = Expand-ModStackSizes -OriginalItemsPath $originalItemsPath -ModItemsPath $modItemsPath
$stackOnlySummary = $null
$stackOnlyItemsPath = $null

if ($CreateStackOnlyPack.IsPresent) {
    $stackOnlySummary = New-StackOnlyPack -OriginalItemsPath $originalItemsPath -OutputRoot $StackOnlyOutputRoot
    $stackOnlyItemsPath = Join-Path $StackOnlyOutputRoot "data\configs\items"
}

$hiddenItemSummary = Restore-HiddenItemDefinitions -OriginalItemsPath $originalItemsPath -ModItemsPath $modItemsPath -StackOnlyItemsPath $stackOnlyItemsPath

Write-Host ""
Write-Host "Completed."
Write-Host "Shield files scanned: $($shieldSummary.Scanned)"
Write-Host "Shield files updated: $($shieldSummary.Updated)"
Write-Host "Base-game stackable items found: $($stackSummary.Eligible)"
Write-Host "Main mod item files created: $($stackSummary.Created)"
Write-Host "Main mod item files updated: $($stackSummary.Updated)"
Write-Host "Hidden/system item files restored in main mod: $($hiddenItemSummary.MainModFilesRestored)"

if ($null -ne $stackOnlySummary) {
    Write-Host "Stack-only pack eligible items: $($stackOnlySummary.Eligible)"
    Write-Host "Stack-only pack files written: $($stackOnlySummary.FilesWritten)"
    Write-Host "Hidden/system item files restored in stack-only pack: $($hiddenItemSummary.StackOnlyFilesRestored)"
}

[pscustomobject]@{
    ModDataRoot                 = $modDataRoot
    OriginalDataRoot            = $originalDataRoot
    ShieldFilesScanned          = $shieldSummary.Scanned
    ShieldFilesUpdated          = $shieldSummary.Updated
    BaseGameStackableItems      = $stackSummary.Eligible
    MainModItemFilesCreated     = $stackSummary.Created
    MainModItemFilesUpdated     = $stackSummary.Updated
    HiddenSystemItemsScanned    = $hiddenItemSummary.HiddenItemsScanned
    MainModHiddenItemsRestored  = $hiddenItemSummary.MainModFilesRestored
    StackOnlyPackCreated        = $CreateStackOnlyPack.IsPresent
    StackOnlyPackOutputRoot     = if ($null -ne $stackOnlySummary) { $stackOnlySummary.OutputRoot } else { $null }
    StackOnlyPackEligibleItems  = if ($null -ne $stackOnlySummary) { $stackOnlySummary.Eligible } else { 0 }
    StackOnlyPackFilesWritten   = if ($null -ne $stackOnlySummary) { $stackOnlySummary.FilesWritten } else { 0 }
    StackOnlyHiddenItemsRestored = if ($null -ne $stackOnlySummary) { $hiddenItemSummary.StackOnlyFilesRestored } else { 0 }
}
