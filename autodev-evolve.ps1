# AutoDev Layer 6: Evolution & Self-Update Engine
# Analyzes task history -> Extracts skills -> Adapts strategy
# Runs after each pipeline cycle

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Config =====
$SILICONFLOW_KEY = "sk-hmfhovqoluzfqjpmuqdcucbxmsqqwilixabtwgfdqqakjqsu"
$SILICONFLOW_URL = "https://api.siliconflow.cn/v1/chat/completions"
$MODEL = "deepseek-ai/DeepSeek-V3"
$PROJECTS_DIR = "C:\Users\Administrator\projects"
$SKILLS_DIR = "$PROJECTS_DIR\skills"
$STRATEGY_FILE = "$PROJECTS_DIR\strategy.json"
$EVOLVE_LOG = "$PROJECTS_DIR\evolve_log.md"
$QUEUE_FILE = "C:\Users\Administrator\autodev_queue.json"
$HISTORY_FILE = "$PROJECTS_DIR\task_history.json"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [Evolve] $msg"
    echo $line
    Add-Content -Path "$PROJECTS_DIR\evolve.log" -Value $line -Encoding UTF8
}

function CallDeepSeek($systemPrompt, $userPrompt, $maxTokens) {
    if (-not $maxTokens) { $maxTokens = 800 }
    $body = @{
        model = $MODEL
        messages = @(
            @{role="system"; content=$systemPrompt}
            @{role="user"; content=$userPrompt}
        )
        temperature = 0.3
        max_tokens = $maxTokens
    } | ConvertTo-Json -Depth 5
    try {
        $resp = Invoke-RestMethod -Uri $SILICONFLOW_URL -Method Post `
            -Headers @{Authorization="Bearer $SILICONFLOW_KEY"} `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
            -ContentType "application/json; charset=utf-8" -TimeoutSec 60
        return $resp.choices[0].message.content
    } catch {
        Log "DeepSeek API error: $_"
        return $null
    }
}

# ===== Ensure directories =====
if (-not (Test-Path $SKILLS_DIR)) { New-Item -ItemType Directory -Path $SKILLS_DIR -Force | Out-Null }
if (-not (Test-Path $PROJECTS_DIR)) { New-Item -ItemType Directory -Path $PROJECTS_DIR -Force | Out-Null }

Log "===== Layer 6 Evolution Start ====="

# ===== Step 1: Collect Data =====
Log "Step 1: Collecting task history and reports..."

# Load task history
$history = @()
if (Test-Path $HISTORY_FILE) {
    try { $history = @(Get-Content $HISTORY_FILE -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { $history = @() }
}

# Load current queue (contains recent task decisions)
$queueData = @()
if (Test-Path $QUEUE_FILE) {
    try { $queueData = @(Get-Content $QUEUE_FILE -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { $queueData = @() }
}

# Merge new queue items into history
$newHistoryItems = @()
foreach ($q in $queueData) {
    $exists = $false
    foreach ($h in $history) {
        if ($h.hash -eq $q.hash) { $exists = $true; break }
    }
    if (-not $exists) {
        $historyItem = @{
            hash = $q.hash
            source = $q.source
            created = $q.created
            decision = $q.decision
            reason = $q.reason
            estimated_value = $q.estimated_value
            task_type = $q.task_type
            effort_hours = $q.effort_hours
            status = $q.status
            evaluated_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        }
        if ($q.bounty_repo) { $historyItem.bounty_repo = $q.bounty_repo }
        if ($q.bounty_issue) { $historyItem.bounty_issue = $q.bounty_issue }
        if ($q.pr_url) { $historyItem.pr_url = $q.pr_url }
        $newHistoryItems += $historyItem
    }
}
$history = @($history) + @($newHistoryItems)

# Save updated history
$history | ConvertTo-Json -Depth 5 | Set-Content $HISTORY_FILE -Encoding UTF8
Log "Task history: $($history.Count) total ($($newHistoryItems.Count) new)"

# Collect report summaries
$reportSummaries = @()
$reportFiles = @(
    "$PROJECTS_DIR\github_bounty_report.md",
    "$PROJECTS_DIR\freelancer_report.md",
    "$PROJECTS_DIR\zhubajie_report.md",
    "$PROJECTS_DIR\proginn_report.md",
    "$PROJECTS_DIR\oschina_report.md"
)
foreach ($rf in $reportFiles) {
    if (Test-Path $rf) {
        $content = Get-Content $rf -Raw -Encoding UTF8
        if ($content -and $content.Trim().Length -gt 10) {
            $reportSummaries += @{file=[IO.Path]::GetFileName($rf); preview=$content.Substring(0, [math]::Min($content.Length, 300))}
        }
    }
}

# Load finance status
$financeSummary = "No finance data"
if (Test-Path "$PROJECTS_DIR\finance_status.json") {
    try {
        $fin = Get-Content "$PROJECTS_DIR\finance_status.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        $financeSummary = "Status: $($fin.status), Balance: $($fin.balance) CNY, Daily cost: $($fin.daily_cost_estimate) CNY"
    } catch {}
}

Log "Data collected: $($history.Count) tasks, $($reportSummaries.Count) reports"

# ===== Step 2: Reflective Analysis =====
Log "Step 2: Reflective analysis with DeepSeek..."

# Build summary for analysis
$acceptedCount = @($history | Where-Object { $_.decision -eq "ACCEPT" }).Count
$rejectedCount = @($history | Where-Object { $_.decision -eq "REJECT" }).Count
$deployedCount = @($history | Where-Object { $_.status -eq "deployed" -or $_.status -eq "pr_created" }).Count
$prCount = @($history | Where-Object { $_.status -eq "pr_created" }).Count
$failedCount = @($history | Where-Object { $_.status -like "*failed*" -or $_.status -eq "timeout" }).Count

$sourceBreakdown = $history | Group-Object source | ForEach-Object { "$($_.Name):$($_.Count)" }
$sourceBreakdownStr = $sourceBreakdown -join ", "

$analysisInput = @"
## Task History Summary
- Total tasks evaluated: $($history.Count)
- Accepted: $acceptedCount, Rejected: $rejectedCount
- Deployed: $deployedCount, PRs created: $prCount, Failed: $failedCount
- Source breakdown: $sourceBreakdownStr
- Finance: $financeSummary

## Recent Decisions (last 10)
$(foreach ($h in ($history | Select-Object -Last 10)) {
    "- [$($h.created)] $($h.source): $($h.decision) ($($h.reason)) [status: $($h.status)]"
} | Out-String)

## Current Reports Available
$(foreach ($r in $reportSummaries) {
    "### $($r.file)`n$($r.preview)`n"
} | Out-String)
"@

$reflectPrompt = @"
Analyze the AutoDev autonomous AI system's task history and performance data.
Provide insights in the following JSON structure:

1. "patterns": What patterns do you see? Which task types/sources have highest success?
2. "skills_to_add": Based on accepted task types, what reusable skills should be crystallized? Each skill: {name, description, task_type, code_template_hint}
3. "strategy_updates": What parameters should change? {github_weight, freelancer_weight, zhubajie_weight, proginn_weight, oschina_weight, min_bounty_usd, prefer_task_types, avoid_patterns}
4. "insights": Key insights and recommendations for improvement

$analysisInput

Respond in EXACT JSON format:
{"patterns":"...","skills_to_add":[...],"strategy_updates":{...},"insights":"..."}
"@

$analysisResult = CallDeepSeek "You are an AI system architect analyzing an autonomous AI agent's performance data. Provide actionable insights for self-improvement." $reflectPrompt 1000

# ===== Step 3: Extract Skills =====
Log "Step 3: Skill crystallization..."

if ($analysisResult) {
    Log "AI Analysis received"
    try {
        $jsonMatch = [regex]::Match($analysisResult, '\{[\s\S]+\}')
        if ($jsonMatch.Success) {
            $analysis = $jsonMatch.Value | ConvertFrom-Json
            
            # Crystallize skills
            if ($analysis.skills_to_add) {
                foreach ($skill in $analysis.skills_to_add) {
                    $skillName = $skill.name -replace '[^a-zA-Z0-9_-]', '_'
                    $skillFile = "$SKILLS_DIR\$skillName.json"
                    
                    $skillData = @{
                        name = $skill.name
                        description = $skill.description
                        task_type = $skill.task_type
                        code_template_hint = $skill.code_template_hint
                        created = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                        use_count = 0
                        success_count = 0
                        last_used = $null
                    }
                    
                    # Don't overwrite existing skills, just update
                    if (Test-Path $skillFile) {
                        $existing = Get-Content $skillFile -Raw -Encoding UTF8 | ConvertFrom-Json
                        $skillData.use_count = $existing.use_count
                        $skillData.success_count = $existing.success_count
                        $skillData.last_used = $existing.last_used
                        Log "Updated existing skill: $skillName"
                    } else {
                        Log "New skill crystallized: $skillName"
                    }
                    
                    $skillData | ConvertTo-Json -Depth 5 | Set-Content $skillFile -Encoding UTF8
                }
            }
            
            # ===== Step 4: Update Strategy =====
            Log "Step 4: Strategy adaptation..."
            
            # Load existing strategy or create default
            $strategy = $null
            if (Test-Path $STRATEGY_FILE) {
                try { $strategy = Get-Content $STRATEGY_FILE -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
            }
            if (-not $strategy) {
                $strategy = @{
                    github_weight = 1.0
                    freelancer_weight = 0.8
                    zhubajie_weight = 0.7
                    proginn_weight = 0.6
                    oschina_weight = 0.5
                    min_bounty_usd = 50
                    prefer_task_types = @("web", "app", "mini-program")
                    avoid_patterns = @("scam", "crypto-airdrop", "data-entry")
                    max_effort_hours = 8
                    pricing_model = "fixed"
                    evolve_version = 1
                    last_updated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                }
            }
            
            # Apply AI-recommended updates
            if ($analysis.strategy_updates) {
                $updates = $analysis.strategy_updates
                if ($updates.github_weight) { $strategy.github_weight = [double]$updates.github_weight }
                if ($updates.freelancer_weight) { $strategy.freelancer_weight = [double]$updates.freelancer_weight }
                if ($updates.zhubajie_weight) { $strategy.zhubajie_weight = [double]$updates.zhubajie_weight }
                if ($updates.proginn_weight) { $strategy.proginn_weight = [double]$updates.proginn_weight }
                if ($updates.oschina_weight) { $strategy.oschina_weight = [double]$updates.oschina_weight }
                if ($updates.min_bounty_usd) { $strategy.min_bounty_usd = [int]$updates.min_bounty_usd }
                if ($updates.prefer_task_types) { $strategy.prefer_task_types = @($updates.prefer_task_types) }
                if ($updates.avoid_patterns) { $strategy.avoid_patterns = @($updates.avoid_patterns) }
                Log "Strategy updated with AI recommendations"
            }
            
            $strategy.evolve_version = [int]$strategy.evolve_version + 1
            $strategy.last_updated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            
            $strategy | ConvertTo-Json -Depth 5 | Set-Content $STRATEGY_FILE -Encoding UTF8
            Log "Strategy v$($strategy.evolve_version) saved"
            
            # ===== Step 5: Generate Evolution Log =====
            Log "Step 5: Generating evolution report..."
            
            $evolveReport = @"
# AutoDev Evolution Report v$($strategy.evolve_version)
**Generated:** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Task Statistics
- Total evaluated: $($history.Count)
- Accepted: $acceptedCount | Rejected: $rejectedCount
- Deployed: $deployedCount | PRs: $prCount | Failed: $failedCount
- Source breakdown: $sourceBreakdownStr

## AI Analysis
### Patterns
$($analysis.patterns)

### Insights
$($analysis.insights)

## Strategy Parameters (v$($strategy.evolve_version))
| Parameter | Value |
|-----------|-------|
| GitHub weight | $($strategy.github_weight) |
| Freelancer weight | $($strategy.freelancer_weight) |
| Zhubajie weight | $($strategy.zhubajie_weight) |
| Proginn weight | $($strategy.proginn_weight) |
| OSChina weight | $($strategy.oschina_weight) |
| Min bounty (USD) | $($strategy.min_bounty_usd) |
| Max effort (hours) | $($strategy.max_effort_hours) |
| Prefer types | $($strategy.prefer_task_types -join ', ') |
| Avoid patterns | $($strategy.avoid_patterns -join ', ') |

## Crystallized Skills
$(foreach ($sf in (Get-ChildItem $SKILLS_DIR -Filter "*.json" -ErrorAction SilentlyContinue)) {
    $s = Get-Content $sf.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    "- **$($s.name)** ($($s.task_type)): $($s.description) [used: $($s.use_count)x, success: $($s.success_count)x]"
} | Out-String)

---
*Auto-evolved by Layer 6 Engine*
"@
            
            $evolveReport | Set-Content $EVOLVE_LOG -Encoding UTF8
            Log "Evolution report saved to $EVOLVE_LOG"
        }
    } catch {
        Log "Analysis parse error: $_"
        Log "Raw result: $($analysisResult.Substring(0, [math]::Min($analysisResult.Length, 500)))"
    }
} else {
    Log "DeepSeek analysis failed, skipping evolution this cycle"
    
    # Still update strategy timestamp and version
    if (Test-Path $STRATEGY_FILE) {
        try {
            $strategy = Get-Content $STRATEGY_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
            $strategy.evolve_version = [int]$strategy.evolve_version + 1
            $strategy.last_updated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            $strategy | ConvertTo-Json -Depth 5 | Set-Content $STRATEGY_FILE -Encoding UTF8
        } catch {}
    }
}

# ===== Step 6: Update skill use counts from recent task outcomes =====
Log "Step 6: Updating skill usage metrics..."

foreach ($h in $newHistoryItems) {
    if ($h.status -eq "deployed" -or $h.status -eq "pr_created") {
        # Find matching skills
        foreach ($sf in (Get-ChildItem $SKILLS_DIR -Filter "*.json" -ErrorAction SilentlyContinue)) {
            $s = Get-Content $sf.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($s.task_type -eq $h.task_type -or $h.source -like "*$($s.task_type)*") {
                $s.use_count = [int]$s.use_count + 1
                $s.success_count = [int]$s.success_count + 1
                $s.last_used = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                $s | ConvertTo-Json -Depth 5 | Set-Content $sf.FullName -Encoding UTF8
            }
        }
    }
}

Log "===== Layer 6 Evolution Complete ====="
