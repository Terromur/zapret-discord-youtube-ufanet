Param(
    [string]$TargetsFile = "targets.txt",
    [int]$TimeoutSeconds = 5,
    [int]$ParallelThreads = 8,
    [switch]$BatchMode = $false
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] Запустите скрипт от имени Администратора!" -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit
}

$RootDir = Split-Path $PSScriptRoot
$ListsDir = Join-Path $RootDir "lists"
$UtilsDir = Join-Path $RootDir "utils"
if (-not (Test-Path $ListsDir)) { $ListsDir = Join-Path $PSScriptRoot "..\lists" }

class StrategyStats {
    [int]$Ok = 0
    [int]$Fail = 0
    [int]$Blocked = 0
    [int]$Unsupported = 0
    [int]$Total = 0
    [double] GetScore() {
        if ($this.Total -eq 0) { return 0.0 }
        return [math]::Round(($this.Ok / $this.Total) * 100, 2)
    }
    [string] GetStatusLabel() {
        $score = $this.GetScore()
        if ($score -ge 90) { return "EXCELLENT" }
        if ($score -ge 70) { return "GOOD" }
        if ($score -ge 40) { return "UNSTABLE" }
        return "BAD"
    }
}

class ConfigResult {
    [string]$ConfigName
    [string]$TestType
    [StrategyStats]$Stats
    [array]$Details
    ConfigResult($name, $type) {
        $this.ConfigName = $name
        $this.TestType = $type
        $this.Stats = [StrategyStats]::new()
        $this.Details = @()
    }
}

function Write-Color {
    param([string]$Text, [string]$Color = "Gray", [switch]$NoNewLine)
    if ($NoNewLine) { Write-Host $Text -ForegroundColor $Color -NoNewline }
    else { Write-Host $Text -ForegroundColor $Color }
}

function Get-ShortPath {
    param([string]$Path)
    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        if (Test-Path $Path -PathType Container) {
            return $fso.GetFolder($Path).ShortPath
        } else {
            return $fso.GetFile($Path).ShortPath
        }
    } catch {
        return "`"$Path`""
    }
}

function Select-Configs {
    param([array]$Files)
    while ($true) {
        Write-Host "`nДоступные стратегии:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $Files.Count; $i++) {
            $num = $i + 1
            $numStr = "[$($num.ToString().PadLeft(2))]" 
            Write-Host "  $numStr $($Files[$i].Name)" -ForegroundColor Gray
        }

        Write-Host "`nВведите номера через запятую (напр. 1,3,5) или '0' для выбора ВСЕХ." -ForegroundColor Yellow
        $selection = Read-Host "Ваш выбор"
        
        if ($selection -eq '0' -or $selection -eq '') { return $Files }
        try {
            $indexes = $selection -split "[, ]+" | 
                       Where-Object { $_ -match '^\d+$' } | 
                       ForEach-Object { [int]$_ - 1 } | 
                       Where-Object { $_ -ge 0 -and $_ -lt $Files.Count } | 
                       Select-Object -Unique

            if ($indexes.Count -gt 0) {
                return $Files[$indexes]
            }
            Write-Color "[!] Неверный ввод, попробуйте еще раз." "Red"
        } catch {
            Write-Color "[!] Ошибка ввода." "Red"
        }
    }
}

function Set-IpsetMode {
    param([string]$Mode)
    $listFile = Join-Path $ListsDir "ipset-all.txt"
    $backupFile = Join-Path $ListsDir "ipset-all.test-backup.txt"
    if (-not (Test-Path $ListsDir)) { return }
    if ($Mode -eq "any") {
        if (Test-Path $listFile) { Copy-Item $listFile $backupFile -Force }
        else { "" | Out-File $backupFile -Encoding UTF8 }
        "" | Out-File $listFile -Encoding UTF8
    } elseif ($Mode -eq "restore") {
        if (Test-Path $backupFile) { Move-Item $backupFile $listFile -Force }
    }
}

function Stop-WinWS {
    Get-Process -Name "winws" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 200
}

function Get-DpiSuite {
    return @(
        @{ Name="US.Cloudflare.1"; Url="https://cdn.cookielaw.org/scripttemplates/202501.2.0/otBannerSdk.js" }
        @{ Name="US.Cloudflare.2"; Url="https://genshin.jmp.blue/characters/all#" }
        @{ Name="US.Cloudflare.3"; Url="https://api.frankfurter.dev/v1/2000-01-01..2002-12-31" }
        @{ Name="US.DigitalOcean"; Url="https://genderize.io/" }
        @{ Name="DE.Hetzner.1";    Url="https://j.dejure.org/jcg/doctrine/doctrine_banner.webp" }
        @{ Name="FI.Hetzner.2";    Url="https://tcp1620-01.dubybot.live/1MB.bin" }
        @{ Name="FI.Hetzner.3";    Url="https://tcp1620-02.dubybot.live/1MB.bin" }
        @{ Name="FI.Hetzner.4";    Url="https://tcp1620-05.dubybot.live/1MB.bin" }
        @{ Name="FI.Hetzner.5";    Url="https://tcp1620-06.dubybot.live/1MB.bin" }
        @{ Name="FR.OVH.1";        Url="https://eu.api.ovh.com/console/rapidoc-min.js" }
        @{ Name="FR.OVH.2";        Url="https://ovh.sfx.ovh/10M.bin" }
        @{ Name="SE.Oracle";       Url="https://oracle.sfx.ovh/10M.bin" }
        @{ Name="DE.AWS.1";        Url="https://tms.delta.com/delta/dl_anderson/Bootstrap.js" }
        @{ Name="US.AWS.2";        Url="https://corp.kaltura.com/wp-content/cache/min/1/wp-content/themes/airfleet/dist/styles/theme.css" }
        @{ Name="US.GoogleCloud";  Url="https://api.usercentrics.eu/gvl/v3/en.json" }
        @{ Name="US.Fastly.1";     Url="https://openoffice.apache.org/images/blog/rejected.png" }
        @{ Name="US.Fastly.2";     Url="https://www.juniper.net/etc.clientlibs/juniper/clientlibs/clientlib-site/resources/fonts/lato/Lato-Regular.woff2" }
        @{ Name="PL.Akamai.1";     Url="https://www.lg.com/lg5-common-gp/library/jquery.min.js" }
        @{ Name="PL.Akamai.2";     Url="https://media-assets.stryker.com/is/image/stryker/gateway_1?$max_width_1410$" }
        @{ Name="US.CDN77";        Url="https://cdn.eso.org/images/banner1920/eso2520a.jpg" }
        @{ Name="DE.Contabo";      Url="https://cloudlets.io/wp-content/themes/Avada/includes/lib/assets/fonts/fontawesome/webfonts/fa-solid-900.woff2" }
        @{ Name="FR.Scaleway";     Url="https://renklisigorta.com.tr/teklif-al" }
        @{ Name="US.Constant";     Url="https://cdn.xuansiwei.com/common/lib/font-awesome/4.7.0/fontawesome-webfont.woff2?v=4.7.0" }
    )
}

function Get-Targets {
    param($Path)
    $targets = @()
    $realPath = $Path
    if (-not (Test-Path $realPath)) {
        $utilsPath = Join-Path $global:UtilsDir $Path
        if (Test-Path $utilsPath) {
            $realPath = $utilsPath
        } else {
            Write-Color "[WARN] Файл '$Path' не найден ни в корне, ни в папке utils." "Yellow"
            Write-Color "[INFO] Используются встроенные цели по умолчанию (Discord/Youtube)." "DarkGray"
            return @(
                @{ Name="Youtube"; Url="https://www.youtube.com"; PingTarget="www.youtube.com"; IsPingOnly=$false },
                @{ Name="Discord"; Url="https://discord.com"; PingTarget="discord.com"; IsPingOnly=$false }
            )
        }
    }

    Write-Color "[INFO] Загрузка целей из файла: $realPath" "Cyan"
    $lines = Get-Content $realPath
    foreach ($line in $lines) {
        if ($line -match '^\s*#|^\s*$') { continue }
        if ($line -match '^\s*([A-Za-z0-9_]+)\s*=\s*"(.+)"\s*$') {
            $name = $matches[1]
            $val = $matches[2]
            if ($val -like "PING:*") {
                $pingT = $val -replace '^PING:\s*', ''
                $targets += @{ Name=$name; Url=$null; PingTarget=$pingT; IsPingOnly=$true }
            } else {
                try {
                    $uri = [System.Uri]$val
                    $pingT = $uri.Host
                } catch {
                    $pingT = $val
                }
                $targets += @{ Name=$name; Url=$val; PingTarget=$pingT; IsPingOnly=$false }
            }
        }
    }
    Write-Color "[INFO] Загружено целей: $($targets.Count)" "Green"
    return $targets
}

function PreFlight-Checks {
    $admin = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Запустите скрипт от имени Администратора!"
    }
    if (-not (Get-Command "curl.exe" -ErrorAction SilentlyContinue)) {
        throw "Не найден curl.exe! Установите его или добавьте в PATH."
    }
    if (Get-Service -Name "zapret" -ErrorAction SilentlyContinue) {
        Write-Color "[CRITICAL] Обнаружена служба 'zapret'! Удалите её (service_remove.bat)." "Red"
        throw "Служба zapret мешает тестам."
    }
    $flagFile = Join-Path $global:UtilsDir "ipset_switched.flag"
    if (Test-Path $flagFile) {
        Write-Color "[WARN] Обнаружен признак некорректного завершения прошлого теста." "Yellow"
        Write-Color "[INFO] Принудительное восстановление IPSet..." "DarkGray"
        Set-IpsetMode -Mode "restore"
        Remove-Item $flagFile -ErrorAction SilentlyContinue
    }
}

function Get-WinwsSnapshot {
    try {
        return Get-CimInstance Win32_Process -Filter "Name='winws.exe'" | 
               Select-Object ProcessId, CommandLine, ExecutablePath
    } catch {
        return @()
    }
}

function Restore-WinwsSnapshot {
    param($Snapshot)
    if (-not $Snapshot) { return }
    Write-Color "[INFO] Восстановление исходного состояния WinWS..." "DarkGray"
    $currentCmds = @()
    try { $currentCmds = (Get-WinwsSnapshot).CommandLine } catch {}
    foreach ($proc in $Snapshot) {
        if (-not $proc.ExecutablePath) { continue }
        if ($currentCmds -contains $proc.CommandLine) { continue }
        $exe = $proc.ExecutablePath
        $argsList = ""
        $quotedExe = '"' + $exe + '"'
        if ($proc.CommandLine.StartsWith($quotedExe)) {
            $argsList = $proc.CommandLine.Substring($quotedExe.Length).Trim()
        } elseif ($proc.CommandLine.StartsWith($exe)) {
            $argsList = $proc.CommandLine.Substring($exe.Length).Trim()
        }
        Start-Process -FilePath $exe -ArgumentList $argsList -WorkingDirectory (Split-Path $exe -Parent) -WindowStyle Minimized
    }
}

function Invoke-ParallelCurl {
    param(
        [array]$Targets,
        [string]$Mode, 
        [int]$Timeout,
        [int]$MaxThreads = 16
    )

    $RunspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads)
    $RunspacePool.Open()
    $Tasks = @()
    $AuditRegistry = [System.Collections.Generic.HashSet[string]]::new()
    $WorkerScript = {
        param($Target, $Mode, $Timeout, $ProtocolData)
        
        function New-Res { param($stat, $det, $succ, $blk) 
            return [PSCustomObject]@{
                Name = $Target.Name; Protocol = $ProtocolData.Label; Status = $stat; Details = $det; IsSuccess = $succ; IsBlocked = $blk
            }
        }

        if ($Target.IsPingOnly) {
            try {
                $ping = Test-Connection -ComputerName $Target.PingTarget -Count 1 -ErrorAction Stop
                return New-Res "OK" "$($ping.ResponseTime) ms" $true $false
            } catch {
                return New-Res "FAIL" "Timeout" $false $false
            }
        }

        if ($Mode -eq "Standard") {
            $curlArgs = @("-I", "-s", "-L", "-m", $Timeout, "-o", "NUL", "-w", "%{http_code}") + $ProtocolData.Args
            try {
                $output = & curl.exe @curlArgs $Target.Url 2>&1
                $exitCode = $LASTEXITCODE
                $text = ($output | Out-String).Trim()

                if ($exitCode -eq 0 -and $text -match "^(200|301|302|403)") {
                    return New-Res "OK" "Code $text" $true $false
                } elseif ($exitCode -eq 6) {
                    return New-Res "ERR" "DNS Fail" $false $false
                } elseif ($text -match "timed out" -or $exitCode -eq 28) {
                    return New-Res "FAIL" "Timeout" $false $false
                } elseif ($text -match "refused" -or $exitCode -eq 7) {
                    return New-Res "ERR" "Refused" $false $false
                } elseif ($text -match "SSL|certificate" -or $exitCode -in 35,60) {
                    return New-Res "BLOCK" "SSL Err" $false $true
                } elseif ($text -match "reset" -or $exitCode -eq 56) {
                    return New-Res "BLOCK" "RST" $false $true
                } else {
                    $safeText = if ($text.Length -gt 8) { $text.Substring(0,8) } else { $text }
                    return New-Res "FAIL" "E:$exitCode $safeText" $false $false
                }
            } catch { return New-Res "CRIT" "ExeFail" $false $false }
        }
        elseif ($Mode -eq "DPI") {
            $range = "0-262144"
            $curlArgs = @("-L", "--range", $range, "-m", $Timeout, "-w", "%{http_code} %{size_download}", "-o", "NUL", "-s") + $ProtocolData.Args + $Target.Url
            try {
                $output = & curl.exe @curlArgs 2>&1
                $exitCode = $LASTEXITCODE
                $text = ($output | Out-String).Trim()
                if ($text -match '^(?<code>\d{3})\s+(?<size>\d+)$') {
                    $sizeKB = [math]::Round([int64]$matches['size'] / 1024, 0)
                    if ($exitCode -eq 0) {
                        return New-Res "OK" "${sizeKB} KB" $true $false
                    } else {
                        if ($sizeKB -ge 10 -and $sizeKB -le 50) {
                            return New-Res "BLOCK" "Freeze ${sizeKB}KB" $false $true
                        } else {
                            return New-Res "FAIL" "Cut ${sizeKB}KB" $false $false
                        }
                    }
                } elseif ($exitCode -eq 28) {
                    return New-Res "FAIL" "Timeout" $false $false
                } elseif ($exitCode -eq 6) {
                    return New-Res "ERR" "DNS Fail" $false $false
                } elseif ($exitCode -eq 7) {
                    return New-Res "ERR" "Refused" $false $false
                } else {
                    return New-Res "FAIL" "Err:$exitCode" $false $false
                }
            } catch { return New-Res "FAIL" "Error" $false $false }
        }
    }

    $protocols = @(
        @{ Label="HTTP";   Args=@("--http1.1") },
        @{ Label="TLS1.2"; Args=@("--tlsv1.2", "--tls-max", "1.2") },
        @{ Label="TLS1.3"; Args=@("--tlsv1.3", "--tls-max", "1.3") }
    )

    foreach ($target in $Targets) {
        if ($target.IsPingOnly) {
            $ps = [powershell]::Create().AddScript($WorkerScript)
            [void]$ps.AddArgument($target); [void]$ps.AddArgument($Mode); [void]$ps.AddArgument($Timeout)
            [void]$ps.AddArgument(@{ Label="ICMP"; Args=@() })
            $ps.RunspacePool = $RunspacePool
            
            $uid = "$($target.Name)_ICMP"
            [void]$AuditRegistry.Add($uid)
            
            $Tasks += [PSCustomObject]@{ Pipe = $ps; Result = $ps.BeginInvoke(); Name = $target.Name; ProtoLabel = "ICMP"; UID = $uid }
        } else {
            foreach ($proto in $protocols) {
                $ps = [powershell]::Create().AddScript($WorkerScript)
                [void]$ps.AddArgument($target); [void]$ps.AddArgument($Mode); [void]$ps.AddArgument($Timeout)
                [void]$ps.AddArgument($proto)
                $ps.RunspacePool = $RunspacePool
                
                $uid = "$($target.Name)_$($proto.Label)"
                [void]$AuditRegistry.Add($uid)
                
                $Tasks += [PSCustomObject]@{ Pipe = $ps; Result = $ps.BeginInvoke(); Name = $target.Name; ProtoLabel = $proto.Label; UID = $uid }
            }
        }
    }

    $FinalResults = @()
    $total = $Tasks.Count
    $done = 0
    $ProcessedUIDs = [System.Collections.Generic.HashSet[string]]::new()
    
    Write-Host "   TARGET                 PROTO   STATUS  DETAILS" -ForegroundColor DarkGray
    Write-Host "   ----------------------------------------------" -ForegroundColor DarkGray

    while ($Tasks.Count -gt 0) {
        $completed = $Tasks | Where-Object { $_.Result.IsCompleted }
        
        foreach ($task in $completed) {
            $res = $null
            try { 
                $res = $task.Pipe.EndInvoke($task.Result)
            } catch {
                $res = $null
            } finally {
                $task.Pipe.Dispose()
            }
            if (-not $res) {
                $res = [PSCustomObject]@{
                    Name = $task.Name
                    Protocol = $task.ProtoLabel
                    Status = "LOST"
                    Details = "ThreadDied"
                    IsSuccess = $false
                    IsBlocked = $false
                }
            }

            $FinalResults += $res
            [void]$ProcessedUIDs.Add($task.UID)
            $color = "Gray"
            if ($res.Status -eq "OK") { $color = "Green" }
            elseif ($res.Status -match "BLOCK") { $color = "Yellow" }
            elseif ($res.Status -match "FAIL|ERR|CRIT|LOST") { $color = "Red" }
            
            $tName = $res.Name.PadRight(22).Substring(0,22)
            $tProto = $res.Protocol.PadRight(7)
            $tStat = $res.Status.PadRight(7)
            Write-Host "   $tName $tProto " -NoNewline -ForegroundColor Gray
            Write-Host "$tStat " -NoNewline -ForegroundColor $color
            Write-Host "$($res.Details)" -ForegroundColor DarkGray
            
            $done++
        }
        
        $Tasks = $Tasks | Where-Object { -not $_.Result.IsCompleted }
        $percent = [math]::Round(($done / $total) * 100)
        Write-Progress -Activity "Testing Strategy..." -Status "$done / $total checks processed" -PercentComplete $percent
        Start-Sleep -Milliseconds 50
    }

    foreach ($uid in $AuditRegistry) {
        if (-not $ProcessedUIDs.Contains($uid)) {
            $parts = $uid -split "_"
            $pName = $parts[0]
            $pProto = $parts[1]
            if ($parts.Count -gt 2) { $pName = $parts[0..($parts.Count-2)] -join "_" ; $pProto = $parts[-1] }

            Write-Host "   WARN: Recovering lost result for $uid" -ForegroundColor Yellow
            
            $FinalResults += [PSCustomObject]@{
                Name = $pName
                Protocol = $pProto
                Status = "LOST"
                Details = "NotReturned"
                IsSuccess = $false
                IsBlocked = $false
            }
        }
    }

    Write-Progress -Activity "Testing Strategy..." -Completed
    $RunspacePool.Dispose()
    return $FinalResults
}

function Invoke-StrategyTest {
    param(
        [System.IO.FileInfo]$ConfigFile,
        [array]$Targets,
        [string]$TestType
    )

    $configName = $ConfigFile.Name
    Stop-WinWS 

    Write-Host "`n╔════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ STRATEGY: " -NoNewline -ForegroundColor Cyan
    Write-Host "$configName".PadRight(53) -NoNewline -ForegroundColor White
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

    $procArgs = "/c `"$($ConfigFile.FullName)`""
    try {
        $procInfo = Start-Process -FilePath "cmd.exe" -ArgumentList $procArgs -WorkingDirectory $ConfigFile.DirectoryName -PassThru -WindowStyle Minimized
    } catch {
        Write-Host "[ERROR] Не удалось запустить .bat файл!" -ForegroundColor Red
        return [ConfigResult]::new($configName, $TestType)
    }

    Write-Host "   [INIT] Запуск драйвера WinWS..." -NoNewline -ForegroundColor DarkGray
    for($i=0; $i -lt 5; $i++) { Write-Host "." -NoNewline -ForegroundColor DarkGray; Start-Sleep -Seconds 1 }
    Write-Host " OK" -ForegroundColor DarkGray
    Write-Host ""

    $rawResults = Invoke-ParallelCurl -Targets $Targets -Mode $TestType -Timeout $global:TimeoutSeconds -MaxThreads 4
    
    Stop-WinWS
    if (-not $procInfo.HasExited) { Stop-Process -Id $procInfo.Id -Force -ErrorAction SilentlyContinue }
    
    $ResultObj = [ConfigResult]::new($configName, $TestType)
    foreach ($item in $rawResults) {
        $ResultObj.Details += $item
        if ($item.IsSuccess) { 
            $ResultObj.Stats.Ok++ 
        } elseif ($item.IsBlocked) { 
            $ResultObj.Stats.Blocked++ 
        } elseif ($item.Status -match "FAIL|ERR|CRIT") { 
            $ResultObj.Stats.Fail++ 
        }
        $ResultObj.Stats.Total++
    }

    $col = "Red"
    if ($ResultObj.Stats.Ok -eq $ResultObj.Stats.Total) { $col = "Green" }
    elseif ($ResultObj.Stats.Ok -gt 0) { $col = "Yellow" }
    
    Write-Host "   ──────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "   RESULT: " -NoNewline -ForegroundColor Gray
    Write-Host "OK: $($ResultObj.Stats.Ok)" -NoNewline -ForegroundColor Green
    Write-Host " | " -NoNewline -ForegroundColor DarkGray
    Write-Host "FAIL: $($ResultObj.Stats.Fail)" -NoNewline -ForegroundColor Red
    Write-Host " | " -NoNewline -ForegroundColor DarkGray
    Write-Host "BLOCK: $($ResultObj.Stats.Blocked)" -ForegroundColor Yellow
    Write-Host ""

    return $ResultObj
}

function Show-Leaderboard {
    param([System.Collections.ArrayList]$Results)
    Write-Host "`n=== РЕЙТИНГ ЭФФЕКТИВНОСТИ (ТОП СТРАТЕГИЙ) ===" -ForegroundColor Cyan
    $sorted = $Results | Sort-Object -Property @{Expression={$_.Stats.GetScore()}} -Descending
    $rank = 1
    foreach ($res in $sorted) {
        if ($rank -gt 5) { break }
        $score = $res.Stats.GetScore()
        $label = $res.Stats.GetStatusLabel()
        $color = "Red"
        if ($label -eq "EXCELLENT") { $color = "Green" }
        elseif ($label -eq "GOOD") { $color = "Cyan" }
        elseif ($label -eq "UNSTABLE") { $color = "Yellow" }
        Write-Host "#$rank. $($res.ConfigName)" -ForegroundColor $color
        Write-Host "    Рейтинг: $score% ($label)" -ForegroundColor $color
        Write-Host "    Успешно: $($res.Stats.Ok)  |  Сбоев: $($res.Stats.Fail)  |  Блокировок: $($res.Stats.Blocked)" -ForegroundColor Gray
        Write-Host ""
        $rank++
    }

    return $sorted[0]
}

function Save-Report {
    param($Results)
    $dateStr = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $htmlFileName = "report_$dateStr.html"
    $htmlFile = Join-Path $global:UtilsDir $htmlFileName
    if (-not (Test-Path $global:UtilsDir)) { New-Item -ItemType Directory -Path $global:UtilsDir | Out-Null }
    $sorted = $Results | Sort-Object -Property @{Expression={$_.Stats.GetScore()}} -Descending
    $top5 = $sorted | Select-Object -First 5
    $css = @"
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #1e1e1e; color: #c0c0c0; margin: 20px; }
        h1, h2, h3 { color: #ffffff; margin-bottom: 5px; }
        .card { background-color: #2d2d2d; border-radius: 8px; padding: 20px; margin-bottom: 20px; box-shadow: 0 4px 6px rgba(0,0,0,0.3); }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #404040; }
        th { background-color: #333; color: #fff; }
        tr:hover { background-color: #383838; }
        .score-box { float: right; font-size: 1.2em; font-weight: bold; }
        .score-good { color: #4caf50; }
        .score-warn { color: #ff9800; }
        .score-bad { color: #f44336; }
        .status-ok { color: #4caf50; font-weight: bold; }
        .status-fail { color: #f44336; }
        .status-block { color: #ff9800; }
        .badge { padding: 4px 8px; border-radius: 4px; font-size: 0.85em; }
        .bg-ok { background-color: #1b5e20; color: #a5d6a7; }
        .bg-fail { background-color: #b71c1c; color: #ffcdd2; }
        .details-sub { font-size: 0.9em; color: #888; }
    </style>
"@

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("<!DOCTYPE html><html><head><meta charset='utf-8'><title>Zapret Report $dateStr</title>$css</head><body>")
    [void]$sb.AppendLine("<h1>Zapret Strategy Report</h1>")
    [void]$sb.AppendLine("<p style='color:#888'>Date: $dateStr</p>")
    [void]$sb.AppendLine("<div class='card'><h2>TOP 5 Strategies</h2>")
    [void]$sb.AppendLine("<table><thead><tr><th>Rank</th><th>Strategy Name</th><th>Score</th><th>Success</th><th>Fail/Block</th></tr></thead><tbody>")
    
    $rank = 1
    foreach ($res in $top5) {
        $score = $res.Stats.GetScore()
        $colorClass = if ($score -ge 90) {"score-good"} elseif ($score -ge 50) {"score-warn"} else {"score-bad"}
        [void]$sb.AppendLine("<tr><td>#$rank</td><td><b>$($res.ConfigName)</b></td><td class='$colorClass'>$score%</td>")
        [void]$sb.AppendLine("<td>$($res.Stats.Ok)</td><td>$($res.Stats.Fail + $res.Stats.Blocked)</td></tr>")
        $rank++
    }
    [void]$sb.AppendLine("</tbody></table></div>")
    [void]$sb.AppendLine("<h2>Detailed Analysis</h2>")
    foreach ($res in $sorted) {
        $score = $res.Stats.GetScore()
        $scoreClass = if ($score -ge 90) {"score-good"} elseif ($score -ge 50) {"score-warn"} else {"score-bad"}
        [void]$sb.AppendLine("<div class='card'>")
        [void]$sb.AppendLine("<div class='score-box $scoreClass'>Score: $score%</div>")
        [void]$sb.AppendLine("<h3>$($res.ConfigName) <span style='font-size:0.6em; color:#666'>($($res.TestType))</span></h3>")
        [void]$sb.AppendLine("<table><thead><tr><th>Target</th><th>Protocol</th><th>Status</th><th>Response/Error</th></tr></thead><tbody>")
        $grouped = $res.Details | Group-Object Name
        foreach ($g in $grouped) {
            foreach ($check in $g.Group) {
                $stClass = "status-fail"
                $bgClass = "bg-fail"
                if ($check.IsSuccess) { $stClass = "status-ok"; $bgClass = "bg-ok" }
                elseif ($check.IsBlocked) { $stClass = "status-block"; $bgClass = "bg-fail" }
                
                $det = $check.Details
                if ($check.Protocol -eq "ICMP") { $det = "📡 $det" }
                
                [void]$sb.AppendLine("<tr>")
                [void]$sb.AppendLine("<td>$($check.Name)</td>")
                [void]$sb.AppendLine("<td>$($check.Protocol)</td>")
                [void]$sb.AppendLine("<td class='$stClass'>$($check.Status)</td>")
                [void]$sb.AppendLine("<td><span class='badge $bgClass'>$det</span></td>")
                [void]$sb.AppendLine("</tr>")
            }
        }
        [void]$sb.AppendLine("</tbody></table></div>")
    }

    [void]$sb.AppendLine("</body></html>")
    $sb.ToString() | Out-File $htmlFile -Encoding UTF8
    Write-Color "`n[REPORT] HTML отчет сохранен: $htmlFileName" "Green"
    $jsonFileName = "report_$dateStr.json"
    $jsonFile = Join-Path $global:UtilsDir $jsonFileName
    $jsonPayload = $Results | Select-Object ConfigName, TestType, Stats, Details
    $jsonPayload | ConvertTo-Json -Depth 5 | Out-File $jsonFile -Encoding UTF8
    Write-Color "[REPORT] JSON данные сохранены: $jsonFileName" "Green"

    Start-Process $htmlFile
}

$global:Results = New-Object System.Collections.ArrayList
$snapshotWinWS = Get-WinwsSnapshot
$flagFile = Join-Path $global:UtilsDir "ipset_switched.flag"

try {
    PreFlight-Checks
    if (-not $BatchMode) {
        Write-Host "Выберите режим тестирования:" -ForegroundColor Cyan
        Write-Host "  [1] Standard  (Ютуб/Дискорд - для обычных сайтов)" 
        Write-Host "  [2] DPI Check (Cloudflare/AWS - технический тест блокировок)"
        $modeInput = Read-Host "Ваш выбор (1/2)"
    } else { $modeInput = "1" }

    $testType = "Standard"
    $targets = @()
    "" | Out-File $flagFile -Encoding UTF8 

    if ($modeInput -eq "2") {
        $testType = "DPI"
        $targets = Get-DpiSuite
        Write-Color "[SETUP] DPI Check: Фильтры IP отключены." "Yellow"
        Set-IpsetMode -Mode "any"
    } else {
        $testType = "Standard"
        $targets = Get-Targets -Path $TargetsFile
        Set-IpsetMode -Mode "any"
    }

    $batFiles = Get-ChildItem -Path $RootDir -Filter "general*.bat" | Sort-Object { 
        [regex]::Replace($_.Name, '\d+', { $args[0].Value.PadLeft(20, '0') }) 
    }
    
    if ($batFiles.Count -eq 0) { throw "Нет файлов general*.bat" }
    if (-not $BatchMode) {
        $batFiles = Select-Configs -Files $batFiles
    }

    Write-Host "`nБудет протестировано стратегий: $($batFiles.Count)" -ForegroundColor Cyan
    Write-Host "Запуск тестов...`n" -ForegroundColor DarkGray

    $counter = 1
    foreach ($bat in $batFiles) {
        $host.UI.RawUI.WindowTitle = "Testing [$counter/$($batFiles.Count)]: $($bat.Name)"
        $numStr = "[ $counter/$($batFiles.Count) ]"
        Write-Host $numStr -NoNewline -ForegroundColor Cyan
        
        $confName = " " + $bat.Name
        if ($confName.Length -gt 30) { $confName = $confName.Substring(0, 27) + "..." }
        Write-Host "$($confName.PadRight(32))" -NoNewline -ForegroundColor Gray

        $res = Invoke-StrategyTest -ConfigFile $bat -Targets $targets -TestType $testType
        [void]$global:Results.Add($res)

        $bracketColor = "DarkGray"
        if ($res.Stats.Blocked -gt 0) { $bracketColor = "Red" }
        elseif ($res.Stats.Ok -eq $res.Stats.Total) { $bracketColor = "Green" }

        Write-Host "[ " -NoNewline -ForegroundColor $bracketColor
        $resString = "$($res.Stats.Ok)/$($res.Stats.Total)"
        $okColor = if ($res.Stats.Ok -eq 0) {"Red"} elseif ($res.Stats.Ok -lt $res.Stats.Total) {"Yellow"} else {"Green"}
        
        Write-Host $resString -NoNewline -ForegroundColor $okColor
        
        Write-Host " | " -NoNewline -ForegroundColor DarkGray
        
        if ($res.Stats.Blocked -gt 0) {
             Write-Host "BLOCK: $($res.Stats.Blocked) " -NoNewline -ForegroundColor Red
        } else {
             Write-Host "BLOCK: 0 " -NoNewline -ForegroundColor DarkGray
        }

        Write-Host " ]" -ForegroundColor $bracketColor
        
        $counter++
    }

    $best = Show-Leaderboard -Results $global:Results
    Save-Report -Results $global:Results -BestConfig $best

    if (-not $BatchMode) { Read-Host "Enter для выхода..." }

} catch {
    Write-Host "`n[ERROR] $_" -ForegroundColor Red
} finally {
    Write-Host "`n[CLEANUP] Восстановление системы..." -ForegroundColor DarkGray
    Stop-WinWS
    Set-IpsetMode -Mode "restore"
    Restore-WinwsSnapshot -Snapshot $snapshotWinWS

    if (Test-Path $flagFile) { Remove-Item $flagFile -ErrorAction SilentlyContinue }
    
    Write-Host "Готово." -ForegroundColor Gray
}