# AutoDev Scheduler v2 - Finance Check + Monitors + Brain + Evolve
# Full autonomous pipeline with financial safeguard + Layer 6 self-evolution

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

echo "========================================"
echo "  AutoDev Full Pipeline v2"
echo "  Finance -> Monitor(5源) -> Evaluate -> Execute"
echo "========================================"
echo ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Step 0: Finance check (Layer 4)
echo "[0/5] Finance check..."
powershell -ExecutionPolicy Bypass -File "$scriptDir\autodev-finance.ps1"
$financeExit = $LASTEXITCODE
if ($financeExit -eq 2) {
    echo "*** HIBERNATE MODE: Balance critical. All tasks stopped. ***"
    echo "Top up Silicon Flow account and delete autodev_shutdown.flag to resume."
    echo ""
    pause
    return
}
if ($financeExit -eq 1) {
    echo "*** LOW BALANCE: Skipping new tasks. Only free monitors running. ***"
    echo ""
}
echo ""

# Step 1-3: Run monitors
echo "[1/5] Running GitHub bounty monitor..."
powershell -ExecutionPolicy Bypass -File "$scriptDir\monitor_github.ps1"
echo ""

echo "[2/5] Running Freelancer monitor..."
powershell -ExecutionPolicy Bypass -File "$scriptDir\monitor_freelancer.ps1"
echo ""

echo "[3/7] Running Zhubajie monitor..."
powershell -ExecutionPolicy Bypass -File "$scriptDir\monitor_zhubajie.ps1"
echo ""

echo "[4/7] Running Proginn (程序员客栈) monitor..."
powershell -ExecutionPolicy Bypass -File "$scriptDir\monitor_progin.ps1"
echo ""

echo "[5/7] Running OSChina (开源众包) monitor..."
powershell -ExecutionPolicy Bypass -File "$scriptDir\monitor_oschina.ps1"
echo ""

# Step 6: Run brain
echo "[6/7] Running AutoDev Brain v3..."
powershell -ExecutionPolicy Bypass -File "$scriptDir\autodev-brain.ps1"
echo ""

# Step 7: Deploy any pending output
echo "[7/8] Deploying to GitHub Pages..."
powershell -ExecutionPolicy Bypass -File "$scriptDir\deploy.ps1"
echo ""

# Step 8: Layer 6 - Evolution & Self-Update
echo "[8/8] Layer 6: Evolution engine..."
powershell -ExecutionPolicy Bypass -File "$scriptDir\autodev-evolve.ps1"
echo ""

echo "========================================"
echo "  Pipeline v2 complete! (8 steps)"
echo "========================================"
