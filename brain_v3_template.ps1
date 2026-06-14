# AutoDev Brain v3 - Full Autonomous Loop with GitHub PR
# Finance Check -> Monitor Reports -> DeepSeek Evaluate -> Trigger Canvas -> Wait -> Deploy -> GitHub PR
# Layer 2 (Decision) + Layer 4 (Finance) + Layer 3 (Execution) integrated

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Config =====
$SILICONFLOW_KEY = "PLACEHOLDER_SF_KEY"
$SILICONFLOW_URL = "https://api.siliconflow.cn/v1/chat/completions"
$MODEL = "deepseek-ai/DeepSeek-V3"
$GITEE_TOKEN = "PLACEHOLDER_GITEE_TOKEN"
$GITEE_API = "https://gitee.com/api/v5/repos/liu-shu-sheng/autodev-delivery/contents"
$GH_TOKEN = "PLACEHOLDER_GH_TOKEN"
$GH_USER = "autodev-botbit"
$GH_API = "https://api.github.com"
$GH_HEADERS = @{
    Authorization = "token $GH_TOKEN"
    Accept = "application/vnd.github.v3+json"
    "User-Agent" = "AutoDev-Bot"
}
$CANVAS_URL = "http://localhost:8000"
$REPORT_DIR = "C:\Users\Administrator\projects"
$QUEUE_FILE = "C:\Users\Administrator\autodev_queue.json"
$LOG_FILE = "C:\Users\Administrator\autodev_brain.log"
$SHUTDOWN_FLAG = "$REPORT_DIR\autodev_shutdown.flag"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    echo $line
    Add-Content -Path $LOG_FILE -Value $line -Encoding UTF8
}

function CallDeepSeek($prompt) {
    if (-not $SILICONFLOW_KEY) { Log "ERROR: SILICONFLOW_KEY not set"; return $null }
    $body = @{
        model = $MODEL
        messages = @(
            @{role="system"; content="You are a business decision AI. Analyze freelance tasks and decide if worth taking. Be strict: reject suspicious/low-value tasks. Respond in JSON only."},
            @{role="user"; content=$prompt}
        )
        temperature = 0.3
        max_tokens = 500
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

function TriggerAgentCanvas($taskPrompt) {
    Log "Triggering Agent Canvas with task..."
    
    $payload = @{message=$taskPrompt; agent="CodeAct"} | ConvertTo-Json -Depth 3
    $endpoints = @(
        @{url="$CANVAS_URL/api/automation/run"; method="Post"},
        @{url="$CANVAS_URL/api/automation/events"; method="Post"},
        @{url="$CANVAS_URL/api/chat"; method="Post"},
        @{url="$CANVAS_URL/api/conversations"; method="Post"},
        @{url="$CANVAS_URL/api/submit"; method="Post"}
    )
    
    foreach ($ep in $endpoints) {
        try {
            $resp = Invoke-RestMethod -Uri $ep.url -Method $ep.method `
                -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) `
                -ContentType "application/json; charset=utf-8" -TimeoutSec 15
            Log "Triggered via: $($ep.url) -> $($resp | ConvertTo-Json -Depth 2 -Compress)"
            return @{success=$true; endpoint=$ep.url; response=$resp}
        } catch {
            Log "Endpoint $($ep.url) not available: $($_.Exception.Message)"
        }
    }
    
    # Fallback: write task file + open browser
    Log "API not available, using task file + browser fallback"
    $taskFile = "$REPORT_DIR\pending_task.txt"
    $taskPrompt | Set-Content $taskFile -Encoding UTF8
    Start-Process $CANVAS_URL
    return @{success=$false; endpoint="browser"; response="Opened browser, task saved to $taskFile"}
}

function WaitForCanvasOutput($maxWaitMinutes) {
    Log "Waiting for Agent Canvas output (max ${maxWaitMinutes}min)..."
    $before = Get-Date
    $knownFiles = @(Get-ChildItem -Path "C:\Users\Administrator\workspace" -Filter "index.html" -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    
    while (((Get-Date) - $before).TotalMinutes -lt $maxWaitMinutes) {
        Start-Sleep -Seconds 30
        $currentFiles = @(Get-ChildItem -Path "C:\Users\Administrator\workspace" -Filter "index.html" -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        
        foreach ($f in $currentFiles) {
            if ($knownFiles -notcontains $f.FullName -and $f.LastWriteTime -gt $before) {
                Log "New output detected: $($f.FullName)"
                return $f.FullName
            }
        }
        $recent = $currentFiles | Where-Object { $_.LastWriteTime -gt $before } | Select-Object -First 1
        if ($recent) {
            Log "Updated output detected: $($recent.FullName)"
            return $recent.FullName
        }
        Log "Still waiting... ($([math]::Round(((Get-Date) - $before).TotalMinutes, 1))min elapsed)"
    }
    Log "Timeout waiting for Canvas output"
    return $null
}

function DeployToGitee($filePath) {
    if (-not (Test-Path $filePath)) { Log "Deploy file not found: $filePath"; return $false }
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($filePath))
    $sha = $null
    try {
        $r = Invoke-RestMethod -Uri "$GITEE_API/index.html?access_token=$GITEE_TOKEN&ref=master" -Method Get -TimeoutSec 15
        $sha = $r.sha
    } catch {}
    $body = @{access_token=$GITEE_TOKEN; content=$b64; message="AutoDev deploy $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"}
    if ($sha) { $body["sha"] = $sha }
    $j = $body | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri "$GITEE_API/index.html" -Method Put `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($j)) `
            -ContentType "application/json; charset=utf-8" -TimeoutSec 30
        Log "Deployed to Gitee OK - https://liu-shu-sheng.gitee.io/autodev-delivery"
        return $true
    } catch {
        Log "Deploy failed: $_"
        return $false
    }
}

function DeployToGitHubPages($filePath) {
    if (-not (Test-Path $filePath)) { Log "Deploy file not found: $filePath"; return $false }
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($filePath))
    $ghPagesApi = "$GH_API/repos/$GH_USER/autodev-scripts/contents/index.html"
    $existingSha = $null
    try {
        $r = Invoke-RestMethod -Uri "$ghPagesApi?ref=main" -Method Get -Headers $GH_HEADERS -TimeoutSec 15
        $existingSha = $r.sha
    } catch {}
    $commitBody = @{message="AutoDev deploy $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"; content=$b64; branch="main"}
    if ($existingSha) { $commitBody["sha"] = $existingSha }
    $json = $commitBody | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri $ghPagesApi -Method Put -Headers $GH_HEADERS `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) `
            -ContentType "application/json; charset=utf-8" -TimeoutSec 30 | Out-Null
        Log "Deployed to GitHub Pages OK - https://autodev-botbit.github.io/autodev-scripts/"
        return $true
    } catch {
        Log "GitHub Pages deploy failed: $_"
        return $false
    }
}

function GitHubForkCommitPR($repo, $branch, $files, $title, $body, $issueNumber) {
    Log "GitHub PR Flow: Fork + Commit + PR for $repo"
    
    # Step 1: Fork
    $forkResult = $null
    try {
        $forkResult = Invoke-RestMethod -Uri "$GH_API/repos/$repo/forks" -Method Post `
            -Headers $GH_HEADERS -ContentType "application/json; charset=utf-8" -TimeoutSec 30
        Log "Fork created: $($forkResult.full_name)"
        Start-Sleep -Seconds 3
    } catch {
        if ($_.Exception.Message -like "*422*" -or $_.Exception.Message -like "*already*") {
            Log "Fork exists, continuing..."
            $repoName = $repo -split '/' | Select-Object -Last 1
            try {
                $forkResult = Invoke-RestMethod -Uri "$GH_API/repos/$GH_USER/$repoName" -Method Get `
                    -Headers $GH_HEADERS -TimeoutSec 15
            } catch { Log "Could not find fork: $_"; return $null }
        } else {
            Log "Fork failed: $_"; return $null
        }
    }
    $forkRepo = $forkResult.full_name
    $defaultBranch = $forkResult.default_branch
    if (-not $branch) { $branch = "autodev-fix-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
    
    # Step 2: Get base SHA
    try {
        $refResult = Invoke-RestMethod -Uri "$GH_API/repos/$forkRepo/git/ref/heads/$defaultBranch" -Method Get `
            -Headers $GH_HEADERS -TimeoutSec 15
        $baseSha = $refResult.object.sha
    } catch { Log "Get ref failed: $_"; return $null }
    
    # Step 3: Create branch
    try {
        $branchBody = @{ref="refs/heads/$branch"; sha=$baseSha} | ConvertTo-Json
        Invoke-RestMethod -Uri "$GH_API/repos/$forkRepo/git/refs" -Method Post `
            -Headers $GH_HEADERS -Body ([System.Text.Encoding]::UTF8.GetBytes($branchBody)) `
            -ContentType "application/json; charset=utf-8" -TimeoutSec 15 | Out-Null
        Log "Branch $branch created"
    } catch {
        if ($_.Exception.Message -like "*422*") { Log "Branch exists, continuing..." }
        else { Log "Branch failed: $_"; return $null }
    }
    
    # Step 4: Commit files
    foreach ($fileEntry in $files) {
        $parts = $fileEntry -split '\|', 2
        if ($parts.Count -lt 2) { continue }
        $filePath = $parts[0]
        $fileContent = $parts[1]
        
        if (Test-Path $fileContent) {
            $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($fileContent))
        } else {
            $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($fileContent))
        }
        
        $existingSha = $null
        try {
            $ef = Invoke-RestMethod -Uri "$GH_API/repos/$forkRepo/contents/$filePath?ref=$branch" -Method Get `
                -Headers $GH_HEADERS -TimeoutSec 10
            $existingSha = $ef.sha
        } catch { }
        
        $commitBody = @{message="AutoDev: Add $filePath"; content=$b64; branch=$branch}
        if ($existingSha) { $commitBody["sha"] = $existingSha }
        $json = $commitBody | ConvertTo-Json
        
        try {
            Invoke-RestMethod -Uri "$GH_API/repos/$forkRepo/contents/$filePath" -Method Put `
                -Headers $GH_HEADERS -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) `
                -ContentType "application/json; charset=utf-8" -TimeoutSec 30 | Out-Null
            Log "Committed: $filePath"
        } catch { Log "Commit failed for $filePath : $_" }
        Start-Sleep -Seconds 1
    }
    
    # Step 5: Create PR
    $prTitle = $title
    if ($issueNumber -gt 0) { $prTitle = "$title (fixes #$issueNumber)" }
    
    $prBodyJson = @{
        title = $prTitle
        body = "$body`n`n---`n*This PR was created by [AutoDev Bot](https://github.com/$GH_USER) - an autonomous AI developer.*"
        head = "$GH_USER:$branch"
        base = $defaultBranch
    } | ConvertTo-Json -Depth 3
    
    try {
        $prResult = Invoke-RestMethod -Uri "$GH_API/repos/$repo/pulls" -Method Post `
            -Headers $GH_HEADERS -Body ([System.Text.Encoding]::UTF8.GetBytes($prBodyJson)) `
            -ContentType "application/json; charset=utf-8" -TimeoutSec 30
        Log "PR CREATED: $($prResult.html_url)"
        
        $prInfo = @{
            repo = $repo
            pr_url = $prResult.html_url
            pr_number = $prResult.number
            branch = $branch
            created = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        } | ConvertTo-Json
        $prInfo | Set-Content "$REPORT_DIR\last_pr.json" -Encoding UTF8
        
        return $prResult.html_url
    } catch {
        Log "PR creation failed: $_"
        return $null
    }
}

# ===== Layer 4: Finance Check =====
Log "===== AutoDev Brain v3 Start ====="
Log "Step 1: Finance check..."

if (Test-Path $SHUTDOWN_FLAG) {
    $flag = Get-Content $SHUTDOWN_FLAG -Encoding UTF8
    Log "SHUTDOWN FLAG ACTIVE: $flag"
    Log "Skipping all tasks. Top up balance and delete $SHUTDOWN_FLAG to resume."
    return
}

$financeFile = "$REPORT_DIR\finance_status.json"
if (Test-Path $financeFile) {
    try {
        $fin = Get-Content $financeFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($fin.status -eq "hibernate" -or $fin.status -eq "stopped") {
            Log "Finance status: $($fin.status) - $($fin.action)"
            Log "Skipping task evaluation. Resolve finance issue first."
            return
        }
        Log "Finance status: $($fin.status) (Balance: $($fin.balance) CNY)"
    } catch {
        Log "Could not parse finance file, continuing with caution"
    }
} else {
    Log "No finance data yet, run autodev-finance.ps1 first"
}

# ===== Load Queue =====
$queue = @()
if (Test-Path $QUEUE_FILE) {
    try { $queue = @(Get-Content $QUEUE_FILE -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { $queue = @() }
}

# ===== Read Monitor Reports =====
Log "Step 2: Reading monitoring reports..."

$newTasks = @()
$reportFiles = @(
    "$REPORT_DIR\github_bounty_report.md",
    "$REPORT_DIR\freelancer_report.md",
    "$REPORT_DIR\zhubajie_report.md"
)

foreach ($rf in $reportFiles) {
    if (Test-Path $rf) {
        $content = Get-Content $rf -Raw -Encoding UTF8
        if ($content -and $content.Trim().Length -gt 10) {
            $md5 = [System.Security.Cryptography.MD5]::Create()
            $hash = [BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($content))).Replace("-","")
            $alreadyQueued = $false
            foreach ($q in $queue) {
                if ($q.hash -eq $hash) { $alreadyQueued = $true; break }
            }
            if (-not $alreadyQueued) {
                $newTasks += @{
                    hash = $hash
                    source = [IO.Path]::GetFileName($rf)
                    content = $content
                    status = "new"
                    evaluated = $false
                    approved = $false
                    created = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                }
                Log "New task from $($rf)"
            }
        }
    }
}

if ($newTasks.Count -eq 0) {
    Log "No new tasks found"
    $queue | ConvertTo-Json -Depth 5 | Set-Content $QUEUE_FILE -Encoding UTF8
    return
}

Log "Found $($newTasks.Count) new tasks, evaluating..."

# ===== Layer 2: Evaluate Tasks =====
foreach ($task in $newTasks) {
    $snippet = $task.content
    if ($snippet.Length -gt 2000) { $snippet = $snippet.Substring(0, 2000) }
    
    $prompt = @"
Analyze this freelance task report. Decide if we should take it.
Criteria:
1. Real task vs scam/spam?
2. Can our AI do it? (web/app/mini-program development)
3. Effort vs reward?
4. Red flags?

Source: $($task.source)
Content:
$snippet

Respond in EXACT JSON format:
{"decision":"ACCEPT or REJECT","reason":"brief reason","estimated_value":"low/medium/high","task_type":"web/app/other","effort_hours":2,"bounty_repo":"owner/repo if github bounty","bounty_issue":123}
"@
    
    $result = CallDeepSeek $prompt
    if ($result) {
        Log "AI evaluation: $result"
        try {
            $jsonMatch = [regex]::Match($result, '\{[^}]+\}')
            if ($jsonMatch.Success) {
                $eval = $jsonMatch.Value | ConvertFrom-Json
                $task.evaluated = $true
                $task.decision = $eval.decision
                $task.reason = $eval.reason
                $task.estimated_value = $eval.estimated_value
                $task.task_type = $eval.task_type
                $task.effort_hours = $eval.effort_hours
                if ($eval.bounty_repo) { $task.bounty_repo = $eval.bounty_repo }
                if ($eval.bounty_issue) { $task.bounty_issue = $eval.bounty_issue }
                if ($eval.decision -eq "ACCEPT") {
                    $task.approved = $true
                    Log "APPROVED: $($eval.reason)"
                } else {
                    Log "REJECTED: $($eval.reason)"
                }
            }
        } catch {
            Log "Parse error: $_"
            $task.evaluated = $true
            $task.decision = "ERROR"
        }
    }
    $queue += $task
}

# ===== Execute Approved Tasks (Autonomous Loop) =====
$approvedTasks = @($queue | Where-Object { $_.approved -eq $true -and $_.status -eq "new" })

if ($approvedTasks.Count -gt 0) {
    Log "$($approvedTasks.Count) tasks approved - starting autonomous execution"
    
    foreach ($at in $approvedTasks) {
        Log "Executing: $($at.source) - $($at.task_type)"
        $at.status = "executing"
        
        # Build task prompt for Agent Canvas
        $taskPrompt = @"
You are AutoDev, an autonomous AI developer. Complete this task:

Source: $($at.source)
Type: $($at.task_type)
Estimated value: $($at.estimated_value)
$(if ($at.bounty_repo) { "GitHub Repo: $($at.bounty_repo)" })
$(if ($at.bounty_issue) { "Issue Number: #$($at.bounty_issue)" })

Task details from monitoring report:
$($at.content.Substring(0, [math]::Min($at.content.Length, 1500)))

Generate a complete, production-ready deliverable:
- For web tasks: single index.html with inline CSS/JS, responsive design
- For app tasks: complete working code with README
- Save the main deliverable as index.html in the workspace
- Make it professional and client-ready
"@
        
        # Trigger Agent Canvas
        $triggerResult = TriggerAgentCanvas $taskPrompt
        
        if ($triggerResult.success) {
            $at.status = "triggered"
            Log "Canvas triggered via API, waiting for output..."
            
            # Wait for output (up to 15 minutes)
            $outputFile = WaitForCanvasOutput 15
            
            if ($outputFile) {
                $at.status = "output_ready"
                $at.output_file = $outputFile
                Log "Output ready: $outputFile"
                
                # Auto deploy to GitHub Pages (primary) + Gitee (backup)
                Log "Auto-deploying to GitHub Pages..."
                $deployOk = DeployToGitHubPages $outputFile
                if ($deployOk) {
                    $at.status = "deployed"
                    Log "Deployed to GitHub Pages: https://autodev-botbit.github.io/autodev-scripts/"
                } else {
                    Log "GitHub Pages deploy failed, trying Gitee backup..."
                    $deployOk = DeployToGitee $outputFile
                    if ($deployOk) {
                        $at.status = "deployed"
                        Log "Deployed to Gitee backup: https://liu-shu-sheng.gitee.io/autodev-delivery"
                    } else {
                        $at.status = "deploy_failed"
                        Log "Both deploy targets failed"
                    }
                }
                    
                    # ===== GitHub PR for bounty tasks =====
                    if ($at.bounty_repo) {
                        Log "Bounty task detected - creating GitHub PR for $($at.bounty_repo)..."
                        $branch = "autodev-fix-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                        $prFiles = @("index.html|$outputFile")
                        $prTitle = "AutoDev: Fix for issue #$($at.bounty_issue)"
                        $prBody = "Automated fix by AutoDev Bot for issue #$($at.bounty_issue).`n`nDemo: https://autodev-botbit.github.io/autodev-scripts/"
                        
                        $prUrl = GitHubForkCommitPR -repo $at.bounty_repo -branch $branch -files $prFiles -title $prTitle -body $prBody -issueNumber $at.bounty_issue
                        
                        if ($prUrl) {
                            $at.status = "pr_created"
                            $at.pr_url = $prUrl
                            Log "FULL PIPELINE COMPLETE - PR: $prUrl"
                        } else {
                            $at.status = "pr_failed"
                            Log "PR creation failed, but task deployed to Gitee"
                        }
                    } else {
                        Log "Full pipeline complete for $($at.source) (no GitHub PR needed)"
                    }
                } else {
                    $at.status = "deploy_failed"
                    Log "Deploy failed, manual deploy needed"
                }
            } else {
                $at.status = "timeout"
                Log "Canvas output timeout - task may still be running"
            }
        } else {
            $at.status = "pending_manual"
            Log "Manual execution needed - browser opened with task description"
        }
    }
} else {
    Log "No tasks approved this round"
}

# ===== Save Queue =====
$queue | ConvertTo-Json -Depth 5 | Set-Content $QUEUE_FILE -Encoding UTF8

# ===== Summary =====
Log "===== Summary ====="
Log "Total: $($queue.Count)"
Log "Approved: $(@($queue | Where-Object {$_.approved -eq $true}).Count)"
Log "Deployed: $(@($queue | Where-Object {$_.status -eq 'deployed'}).Count)"
Log "PR Created: $(@($queue | Where-Object {$_.status -eq 'pr_created'}).Count)"
Log "Pending: $(@($queue | Where-Object {$_.status -like 'pending*'}).Count)"
Log "===== Brain v3 End ====="
