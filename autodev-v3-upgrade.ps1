# autodev-v3-upgrade.ps1 - Download brain v3 from GitHub and inject keys
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$brainPath = "C:\Users\Administrator\autodev-brain.ps1"
$logFile = "C:\Users\Administrator\autodev_brain.log"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [V3-Upgrade] $msg"
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    echo $line
}

Log "Starting v3 upgrade..."

# Backup
if (Test-Path $brainPath) {
    Copy-Item $brainPath "$brainPath.v2.bak" -Force
    Log "Backed up to $brainPath.v2.bak"
}

# Extract keys from old brain
$sfKey = ""
$giteeToken = ""
if (Test-Path "$brainPath.v2.bak") {
    $old = Get-Content "$brainPath.v2.bak" -Raw -Encoding UTF8
    $m1 = [regex]::Match($old, '\$SILICONFLOW_KEY\s*=\s*"([^"]+)"')
    if ($m1.Success) { $sfKey = $m1.Groups[1].Value; Log "Extracted SILICONFLOW_KEY" }
    $m2 = [regex]::Match($old, '\$GITEE_TOKEN\s*=\s*"([^"]+)"')
    if ($m2.Success) { $giteeToken = $m2.Groups[1].Value; Log "Extracted GITEE_TOKEN" }
}

# Download brain v3 template from GitHub
$v3Url = "https://raw.githubusercontent.com/autodev-botbit/autodev-scripts/main/brain_v3_template.ps1"
$v3Temp = "$env:TEMP\brain_v3_template.ps1"
Log "Downloading brain v3 template from $v3Url"

try {
    Invoke-WebRequest -Uri $v3Url -OutFile $v3Temp -TimeoutSec 30
    Log "Downloaded template OK"
} catch {
    Log "Download failed: $_ - trying alternative..."
    # Fallback: try GitHub API
    try {
        $apiUrl = "https://api.github.com/repos/autodev-botbit/autodev-scripts/contents/brain_v3_template.ps1"
        $resp = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 15
        $bytes = [Convert]::FromBase64String($resp.content)
        [IO.File]::WriteAllBytes($v3Temp, $bytes)
        Log "Downloaded via API OK"
    } catch {
        Log "API download also failed: $_"
        Log "ABORT: Cannot download brain template"
        exit 1
    }
}

# Read template and inject keys
$content = Get-Content $v3Temp -Raw -Encoding UTF8
Log "Template loaded, injecting keys..."

if ($sfKey) {
    $content = $content -replace 'PLACEHOLDER_SF_KEY', $sfKey
    Log "Injected SILICONFLOW_KEY"
}
if ($giteeToken) {
    $content = $content -replace 'PLACEHOLDER_GITEE_TOKEN', $giteeToken
    Log "Injected GITEE_TOKEN"
}

# Write GitHub token (known, was added in v3)
$content = $content -replace 'PLACEHOLDER_GH_TOKEN', 'GH_TOKEN_PLACEHOLDER'
Log "Injected GITHUB_TOKEN"

# Save new brain
[IO.File]::WriteAllText($brainPath, $content, [System.Text.Encoding]::UTF8)
Log "Brain v3 written to $brainPath"

# Verify
$verify = Get-Content $brainPath -Raw -Encoding UTF8
$hasPR = $verify -match "GitHubForkCommitPR"
$hasGHPages = $verify -match "DeployToGitHubPages"
if ($hasPR -and $hasGHPages) {
    Log "VERIFIED: Brain v3 contains GitHubForkCommitPR + DeployToGitHubPages"
} else {
    Log "WARNING: Verification issue - PR=$hasPR GitHubPages=$hasGHPages"
}

# Update bat
$batPath = "C:\Users\Administrator\Desktop\AutoDev-Brain.bat"
$batContent = "@echo off`r`npowershell -ExecutionPolicy Bypass -File `"C:\Users\Administrator\autodev-brain.ps1`"`r`npause"
[IO.File]::WriteAllText($batPath, $batContent, [System.Text.Encoding]::ASCII)
Log "Updated AutoDev-Brain.bat"

# Cleanup
Remove-Item $v3Temp -Force -ErrorAction SilentlyContinue

Log "v3 UPGRADE COMPLETE!"
