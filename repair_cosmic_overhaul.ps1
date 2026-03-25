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
Path to the mod .zip file, the extracted mod folder, or directly to its data folder.

.PARAMETER OriginalGameRoot
Path to a clean copy of the game's files, or directly to its data folder.

.PARAMETER CreateStackOnlyPack
Also generates a separate stack-size-only pack based on the clean original files.

.PARAMETER InstallToGameRoot
Optional path to the actual Cubic Odyssey install folder. If provided, the script copies
the patched mod contents into the game folder after applying fixes. This accepts either
the game root folder or the game's data folder.

.PARAMETER StackOnlyOutputRoot
Output folder for the stack-size-only pack. If omitted, a folder named
STACK_SIZE_ONLY_999_CLEAN will be created next to the mod folder.

.EXAMPLE
.\repair_cosmic_overhaul.ps1 `
  -ModRoot ".\COSMIC OVERHAUL 2.0 MAIN-26-2-0-1752800472.zip" `
  -OriginalGameRoot ".\ORIGINAL_GAME" `
  -InstallToGameRoot "D:\SteamLibrary\steamapps\common\Cubic Odyssey"

.EXAMPLE
.\repair_cosmic_overhaul.ps1 `
  -ModRoot ".\COSMIC OVERHAUL 2.0 MAIN-26-2-0-1752800472" `
  -OriginalGameRoot ".\ORIGINAL_GAME" `
  -CreateStackOnlyPack

.EXAMPLE
.\repair_cosmic_overhaul.ps1 `
  -ModRoot ".\COSMIC OVERHAUL 2.0 MAIN-26-2-0-1752800472" `
  -OriginalGameRoot ".\ORIGINAL_GAME" `
  -InstallToGameRoot "D:\SteamLibrary\steamapps\common\Cubic Odyssey"

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

    [string]$InstallToGameRoot,

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
    $moddedDataCandidate = Join-Path (Join-Path $resolvedPath "modded") "data"
    $configsUnderRoot = Join-Path $resolvedPath "configs"
    $configsUnderData = Join-Path $dataCandidate "configs"
    $configsUnderModdedData = Join-Path $moddedDataCandidate "configs"

    if (Test-Path -LiteralPath $configsUnderData -PathType Container) {
        return $dataCandidate
    }

    if (Test-Path -LiteralPath $configsUnderModdedData -PathType Container) {
        return $moddedDataCandidate
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

     $preferredCandidates = @(
         $nestedCandidates |
         Where-Object { $_ -imatch '[\\/]modded[\\/]data$' }
     )

     if ($preferredCandidates.Count -eq 1) {
         return $preferredCandidates[0]
     }

     if ($nestedCandidates.Count -eq 1) {
         return $nestedCandidates[0]
     }

     if ($nestedCandidates.Count -gt 1) {
         $candidateList = $nestedCandidates -join [Environment]::NewLine
         throw "$Label matched more than one nested data folder. Please point directly to the correct folder.`n$candidateList"
     }

     throw "$Label must point to either a folder that contains a 'data' directory, or directly to a 'data' directory."
 }

function Expand-ModArchiveIfNeeded {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $item = Get-Item -LiteralPath $resolvedPath

    if ($item.PSIsContainer) {
        return [pscustomobject]@{
            WorkingPath = $resolvedPath
            Extracted   = $false
            TempRoot    = $null
        }
    }

    if ($item.Extension -ine ".zip") {
        throw "$Label must point to a .zip file, an extracted mod folder, or directly to a data folder."
    }

    $baseDir = Split-Path -Path $resolvedPath -Parent
    $zipStem = [System.IO.Path]::GetFileNameWithoutExtension($item.Name)
    $tempRoot = Join-Path $baseDir ("_repair_tmp_" + $zipStem + "_" + [guid]::NewGuid().ToString("N"))
    $extractRoot = Join-Path $tempRoot "extracted"

    [void][System.IO.Directory]::CreateDirectory($extractRoot)
    Expand-Archive -LiteralPath $resolvedPath -DestinationPath $extractRoot -Force

    $directories = @(Get-ChildItem -LiteralPath $extractRoot -Directory)
    if ($directories.Count -eq 1) {
        $workingPath = $directories[0].FullName
    }
    else {
        $workingPath = $extractRoot
    }

    return [pscustomobject]@{
        WorkingPath = $workingPath
        Extracted   = $true
        TempRoot    = $tempRoot
    }
}

function Resolve-GameRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $dataCandidate = Join-Path $resolvedPath "data"
    $configsUnderRoot = Join-Path $resolvedPath "configs"

    if (Test-Path -LiteralPath $dataCandidate -PathType Container) {
        return $resolvedPath
    }

    if (Test-Path -LiteralPath $configsUnderRoot -PathType Container) {
        return (Split-Path -Path $resolvedPath -Parent)
    }

    throw "$Label must point to either the game root folder or directly to the game's data folder."
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

function Install-ModContentToGameRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,

        [Parameter(Mandatory = $true)]
        [string]$TargetGameRoot
    )

    $normalizedSource = [System.IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
    $normalizedTarget = [System.IO.Path]::GetFullPath($TargetGameRoot).TrimEnd('\')

    if ($normalizedSource -ieq $normalizedTarget) {
        return [pscustomobject]@{
            SourceRoot      = $normalizedSource
            TargetGameRoot  = $normalizedTarget
            ItemsCopied     = 0
            SkippedSamePath = $true
        }
    }

    $itemsCopied = 0
    $topLevelItems = @(Get-ChildItem -LiteralPath $SourceRoot -Force)

    foreach ($item in $topLevelItems) {
        $destinationPath = Join-Path $TargetGameRoot $item.Name
        if ($PSCmdlet.ShouldProcess($destinationPath, "Copy patched mod content into game folder")) {
            if ($item.PSIsContainer -and (Test-Path -LiteralPath $destinationPath -PathType Container)) {
                foreach ($child in Get-ChildItem -LiteralPath $item.FullName -Force) {
                    $childDestinationPath = Join-Path $destinationPath $child.Name
                    Copy-Item -LiteralPath $child.FullName -Destination $childDestinationPath -Recurse -Force
                }
            }
            else {
                Copy-Item -LiteralPath $item.FullName -Destination $destinationPath -Recurse -Force
            }
            $itemsCopied++
        }
    }

    return [pscustomobject]@{
        SourceRoot      = $normalizedSource
        TargetGameRoot  = $normalizedTarget
        ItemsCopied     = $itemsCopied
        SkippedSamePath = $false
    }
}
$modSource = Expand-ModArchiveIfNeeded -Path $ModRoot -Label "ModRoot"

try {
    $modDataRoot = Resolve-DataRoot -Path $modSource.WorkingPath -Label "ModRoot"
    $originalDataRoot = Resolve-DataRoot -Path $OriginalGameRoot -Label "OriginalGameRoot"
    $modContentRoot = Split-Path -Path $modDataRoot -Parent

    $modConfigsPath = Join-Path $modDataRoot "configs"
    $originalConfigsPath = Join-Path $originalDataRoot "configs"
    $modComponentsPath = Join-Path $modConfigsPath "components"
    $modItemsPath = Join-Path $modConfigsPath "items"
    $originalItemsPath = Join-Path $originalConfigsPath "items"
    $installSummary = $null

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

    if (-not [string]::IsNullOrWhiteSpace($InstallToGameRoot)) {
        $InstallToGameRoot = Resolve-GameRoot -Path $InstallToGameRoot -Label "InstallToGameRoot"
    }

     Write-Host "Mod data root: $modDataRoot"
     Write-Host "Mod content root: $modContentRoot"
     Write-Host "Original data root: $originalDataRoot"
    if ($modSource.Extracted) {
        Write-Host "Mod archive extracted to temporary folder: $($modSource.WorkingPath)"
    }
    if ($CreateStackOnlyPack.IsPresent) {
        Write-Host "Stack-only output: $StackOnlyOutputRoot"
    }
    if (-not [string]::IsNullOrWhiteSpace($InstallToGameRoot)) {
        Write-Host "Install target game root: $InstallToGameRoot"
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

    if (-not [string]::IsNullOrWhiteSpace($InstallToGameRoot)) {
        $installSummary = Install-ModContentToGameRoot -SourceRoot $modContentRoot -TargetGameRoot $InstallToGameRoot
    }

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

    if ($null -ne $installSummary) {
        Write-Host "Installed top-level mod entries into game root: $($installSummary.ItemsCopied)"
        if ($installSummary.SkippedSamePath) {
            Write-Host "Install copy skipped because the mod content root already matches the target game root."
        }
    }

    [pscustomobject]@{
        ModInputPath                 = $ModRoot
        ModInputWasZip               = $modSource.Extracted
        ModDataRoot                  = $modDataRoot
        ModContentRoot               = $modContentRoot
        OriginalDataRoot             = $originalDataRoot
        ShieldFilesScanned           = $shieldSummary.Scanned
        ShieldFilesUpdated           = $shieldSummary.Updated
        BaseGameStackableItems       = $stackSummary.Eligible
        MainModItemFilesCreated      = $stackSummary.Created
        MainModItemFilesUpdated      = $stackSummary.Updated
        HiddenSystemItemsScanned     = $hiddenItemSummary.HiddenItemsScanned
        MainModHiddenItemsRestored   = $hiddenItemSummary.MainModFilesRestored
        StackOnlyPackCreated         = $CreateStackOnlyPack.IsPresent
        StackOnlyPackOutputRoot      = if ($null -ne $stackOnlySummary) { $stackOnlySummary.OutputRoot } else { $null }
        StackOnlyPackEligibleItems   = if ($null -ne $stackOnlySummary) { $stackOnlySummary.Eligible } else { 0 }
        StackOnlyPackFilesWritten    = if ($null -ne $stackOnlySummary) { $stackOnlySummary.FilesWritten } else { 0 }
        StackOnlyHiddenItemsRestored = if ($null -ne $stackOnlySummary) { $hiddenItemSummary.StackOnlyFilesRestored } else { 0 }
        InstallTargetGameRoot        = if ($null -ne $installSummary) { $installSummary.TargetGameRoot } else { $null }
        InstalledTopLevelEntries     = if ($null -ne $installSummary) { $installSummary.ItemsCopied } else { 0 }
        InstallCopySkippedSamePath   = if ($null -ne $installSummary) { $installSummary.SkippedSamePath } else { $false }
    }
}
finally {
    if ($modSource.Extracted -and -not [string]::IsNullOrWhiteSpace($modSource.TempRoot) -and (Test-Path -LiteralPath $modSource.TempRoot)) {
        Remove-Item -LiteralPath $modSource.TempRoot -Recurse -Force
        Write-Host "Temporary extraction folder removed."
    }
}
