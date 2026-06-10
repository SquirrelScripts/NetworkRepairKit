<#
.SYNOPSIS
    Internet borked? The squirrel fixes it one careful step at a time — and
    stops the moment it's back.

.DESCRIPTION
    Diagnoses your connection (gateway, raw internet, DNS, web), then walks an
    escalation ladder of repairs from gentlest to bluntest — flush DNS,
    re-register DNS, renew DHCP, restart the adapter — re-testing after every
    step and stopping as soon as things work. Nothing is run blindly.

    The blunt instruments (Winsock reset, TCP/IP stack reset) are opt-in via
    -Deep, warn before they run (they can break VPN clients and need a
    reboot), and your network state is snapshotted to a receipts file before
    anything is touched.

    Supports -WhatIf: diagnoses (read-only) and shows the repair plan without
    fixing anything.

.EXAMPLE
    .\Repair-SquirrelNet.ps1 -WhatIf
    Diagnose and show what would run. Fixes nothing.

.EXAMPLE
    .\Repair-SquirrelNet.ps1
    The Friday fix. Run elevated for the full ladder.

.EXAMPLE
    .\Repair-SquirrelNet.ps1 -Deep
    Adds the Winsock and TCP/IP stack resets (elevated, reboot required,
    prompts before each).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Deep,     # include Winsock / TCP-IP stack resets (admin, reboot)
    [switch]$Force     # skip the are-you-sure prompts on the blunt steps
)

# ---------------------------------------------------------------- helpers ----
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-TcpPort {
    param([string]$TargetHost, [int]$Port, [int]$TimeoutMs = 3000)
    $tcp = New-Object Net.Sockets.TcpClient
    try {
        $iar = $tcp.BeginConnect($TargetHost, $Port, $null, $null)
        ($iar.AsyncWaitHandle.WaitOne($TimeoutMs) -and $tcp.Connected)
    }
    catch  { $false }
    finally { $tcp.Close() }
}

function Get-NetHealth {
    <# Four checks, cheapest first. Gateway is informational only — plenty of
       routers drop ICMP, so it never fails the overall verdict on its own. #>
    $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
           Sort-Object -Property RouteMetric | Select-Object -First 1).NextHop

    $gatewayOk = $false
    if ($gw -and $gw -ne '0.0.0.0') {
        ping.exe -n 1 -w 1500 $gw | Out-Null
        $gatewayOk = ($LASTEXITCODE -eq 0)
    }

    # raw internet: ICMP first, TCP 443 fallback for ping-blocking networks
    ping.exe -n 1 -w 2000 1.1.1.1 | Out-Null
    $internetOk = ($LASTEXITCODE -eq 0)
    if (-not $internetOk) { $internetOk = Test-TcpPort -TargetHost '1.1.1.1' -Port 443 }

    $dnsOk = $false
    try {
        $null = Resolve-DnsName -Name 'example.com' -Type A -DnsOnly -QuickTimeout -ErrorAction Stop
        $dnsOk = $true
    } catch { }

    # name + route + port in one go — what a browser actually needs
    $webOk = Test-TcpPort -TargetHost 'www.microsoft.com' -Port 443

    [pscustomobject]@{
        GatewayIp = $gw
        Gateway   = $gatewayOk
        Internet  = $internetOk
        Dns       = $dnsOk
        Web       = $webOk
        Healthy   = ($internetOk -and $dnsOk -and $webOk)
    }
}

function Show-Health {
    param($Health)
    $rows = @(
        [pscustomobject]@{ Name = 'Gateway';  Detail = $(if ($Health.GatewayIp) { "($($Health.GatewayIp))" } else { '(no default route!)' }); Ok = $Health.Gateway }
        [pscustomobject]@{ Name = 'Internet'; Detail = '(1.1.1.1)';     Ok = $Health.Internet }
        [pscustomobject]@{ Name = 'DNS';      Detail = '(example.com)'; Ok = $Health.Dns }
        [pscustomobject]@{ Name = 'Web';      Detail = '(port 443)';    Ok = $Health.Web }
    )
    foreach ($r in $rows) {
        Write-Host ("  {0,-10} {1,-20} " -f $r.Name, $r.Detail) -NoNewline
        if ($r.Ok) { Write-Host 'OK'   -ForegroundColor Green }
        else       { Write-Host 'FAIL' -ForegroundColor Red }
    }
}

function Get-Diagnosis {
    param($Health)
    if     (-not $Health.Internet) { "can't reach the internet at all — adapter, router, or upstream" }
    elseif (-not $Health.Dns)      { "you're online but DNS is down — names won't resolve" }
    elseif (-not $Health.Web)      { 'DNS and routing look fine but web connections fail — firewall or proxy?' }
    else                           { 'all checks pass' }
}

# Pre-load the network modules with WhatIf masked — on Windows PowerShell 5.1,
# module auto-load under -WhatIf spams "What if: New Alias" for module aliases
$realWhatIf = $WhatIfPreference
$WhatIfPreference = $false
Import-Module NetTCPIP, DnsClient, NetAdapter -ErrorAction SilentlyContinue
$WhatIfPreference = $realWhatIf

# ------------------------------------------------------------------ banner ----
# 🐿️ only struts on PS 7+ — Windows PowerShell 5.1's conhost renders him as tofu
$ShowMascot = $PSVersionTable.PSVersion.Major -ge 7
$Mascot     = if ($ShowMascot) { '🐿️  ' } else { '' }
$MascotEnd  = if ($ShowMascot) { '  🐿️' } else { '' }

Write-Host ""
Write-Host "  ${Mascot}SquirrelScripts — Network Repair Kit" -ForegroundColor DarkYellow
Write-Host "  -------------------------------------" -ForegroundColor DarkGray
Write-Host ""

$isAdmin = Test-IsAdmin
if (-not $isAdmin) {
    Write-Warning "Not elevated — only the gentle steps are available. Re-run elevated for the full kit."
}
if ($Deep -and -not $isAdmin) {
    Write-Warning "-Deep needs an elevated session. Skipping the deep steps."
    $Deep = $false
}

# --------------------------------------------------------------- diagnose ----
Write-Host "  Checking what's actually broken..." -ForegroundColor DarkGray
$health = Get-NetHealth
Show-Health $health
Write-Host ""
Write-Host "  Verdict: $(Get-Diagnosis $health)" -ForegroundColor $(if ($health.Healthy) { 'Green' } else { 'Yellow' })
Write-Host ""

if ($health.Healthy) {
    Write-Host "  Nothing to fix — the squirrel naps.$MascotEnd" -ForegroundColor Green
    Write-Host ""
    return
}

# --------------------------------------------------------------- receipts ----
# Snapshot state BEFORE touching anything, so there's a record of what the
# config looked like when it worked-ish. Winsock catalog included because
# that's the one a reset rewrites.
if (-not $WhatIfPreference) {
    $receipts = Join-Path $env:TEMP ("SquirrelNet-receipts-{0:yyyyMMdd-HHmmss}.txt" -f (Get-Date))
    & {
        '===== ipconfig /all ====='
        ipconfig.exe /all
        '===== route print -4 ====='
        route.exe print -4
        '===== winsock catalog ====='
        netsh.exe winsock show catalog
    } *> $receipts
    Write-Host "  Receipts (state before repairs): $receipts" -ForegroundColor DarkGray
    Write-Host ""
}

# ------------------------------------------------------------- the ladder ----
# Gentlest first. After every step: re-test, and stop the moment it's back.
$steps = @(
    [pscustomobject]@{
        Name   = 'Flush DNS cache'
        Admin  = $false; Deep = $false; Reboot = $false; Settle = 2; Warn = $null
        Action = { ipconfig.exe /flushdns | Out-Null }
    }
    [pscustomobject]@{
        Name   = 'Re-register DNS'
        Admin  = $true; Deep = $false; Reboot = $false; Settle = 3; Warn = $null
        Action = { ipconfig.exe /registerdns | Out-Null }
    }
    [pscustomobject]@{
        Name   = 'Renew DHCP lease'
        Admin  = $true; Deep = $false; Reboot = $false; Settle = 5; Warn = $null
        # renew without release — re-requests the lease without dropping it first
        Action = { ipconfig.exe /renew | Out-Null }
    }
    [pscustomobject]@{
        Name   = 'Restart network adapter'
        Admin  = $true; Deep = $false; Reboot = $false; Settle = 12
        Warn   = 'This drops the connection for a few seconds (Wi-Fi and VPN will blip).'
        Action = { Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' } | Restart-NetAdapter }
    }
    [pscustomobject]@{
        Name   = 'Reset Winsock'
        Admin  = $true; Deep = $true; Reboot = $true; Settle = 2
        Warn   = 'This can break VPN clients and security agents that hook Winsock, and needs a reboot to finish.'
        Action = { netsh.exe winsock reset | Out-Null }
    }
    [pscustomobject]@{
        Name   = 'Reset TCP/IP stack'
        Admin  = $true; Deep = $true; Reboot = $true; Settle = 2
        Warn   = 'This rewrites IP stack settings back to defaults, and needs a reboot to finish.'
        Action = { netsh.exe int ip reset | Out-Null }
    }
)

$runnable = @($steps | Where-Object { (-not $_.Deep -or $Deep) -and (-not $_.Admin -or $isAdmin) })
$skipped  = @($steps | Where-Object { $_.Admin -and -not $isAdmin -and (-not $_.Deep -or $Deep) })

$fixedBy      = $null
$rebootNeeded = $false
$stepIdx      = 0

foreach ($step in $runnable) {
    $stepIdx++
    if (-not $PSCmdlet.ShouldProcess($step.Name, 'Repair')) { continue }
    if ($step.Warn -and -not $Force) {
        if (-not $PSCmdlet.ShouldContinue("$($step.Warn) Continue?", $step.Name)) {
            Write-Host "  [$stepIdx/$($runnable.Count)]  $($step.Name) — skipped" -ForegroundColor DarkGray
            continue
        }
    }

    Write-Host "  [$stepIdx/$($runnable.Count)]  $($step.Name)..." -ForegroundColor DarkYellow -NoNewline
    try {
        & $step.Action
        Write-Host ' done' -ForegroundColor Green
    }
    catch {
        Write-Host ' failed' -ForegroundColor Red
        Write-Verbose $_.Exception.Message
        continue   # a failed repair step is no reason to stop climbing
    }
    if ($step.Reboot) { $rebootNeeded = $true }

    Start-Sleep -Seconds $step.Settle
    Write-Host '           re-testing...' -ForegroundColor DarkGray
    $health = Get-NetHealth
    if ($health.Healthy) { $fixedBy = $step.Name; break }
}

# ------------------------------------------------------------------- flush ----
Write-Host ""
Write-Host "  -------------------------------------" -ForegroundColor DarkGray

if ($fixedBy) {
    Show-Health $health
    Write-Host ""
    Write-Host "  Fixed after: $fixedBy$MascotEnd" -ForegroundColor Green
    Write-Host "  Stopped there — no need to keep poking a working network." -ForegroundColor DarkGray
}
elseif ($WhatIfPreference) {
    Write-Host "  That was the plan — run again without -WhatIf to fix for real." -ForegroundColor Yellow
}
else {
    Show-Health $health
    Write-Host ""
    Write-Host "  Still borked after the ladder." -ForegroundColor Yellow
    if ($rebootNeeded) {
        Write-Host "  A reset step ran — reboot to let it finish, then re-test." -ForegroundColor Yellow
    }
    if ($skipped.Count -gt 0) {
        Write-Host "  $($skipped.Count) step$(if ($skipped.Count -eq 1) { '' } else { 's' }) needed admin — re-run elevated." -ForegroundColor DarkGray
    }
    elseif (-not $Deep) {
        Write-Host "  Next rung: -Deep adds the Winsock and TCP/IP stack resets (elevated, reboot)." -ForegroundColor DarkGray
    }
    else {
        Write-Host "  That's everything software can do — cable, router, or ISP territory now." -ForegroundColor DarkGray
    }
}
Write-Host ""
