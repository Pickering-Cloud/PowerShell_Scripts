<#
    .SYNOPSIS
        Forces a Windows client to check in against its configured WSUS server,
        collecting diagnostic information and optionally remediating common
        synchronisation and installation errors automatically.

    .DESCRIPTION
        Collects the currently configured WSUS server/status server from Group
        Policy, verifies name resolution, network reachability, and (if HTTPS)
        certificate trust. Checks for a pending reboot, low disk space, and
        disabled prerequisite services. Attempts synchronisation against WSUS,
        retrying up to a configured number of times. Reviews update history for
        errors that occurred during this run and, if -AutomaticallyRemediate is
        set, attempts known fixes for recognised error codes before retrying
        synchronisation once more.

        Designed to run unattended, including via PowerShell remoting across
        many machines simultaneously. If $loggingLevel is left unset and the
        script detects it is not running in a remote session, it will prompt
        interactively; otherwise it defaults to Info level automatically.

    .PARAMETER AutomaticallyRemediate
        If set, attempts to automatically fix recognised issues (disabled
        services, corrupted component store, stale caches, etc.) rather than
        only reporting them. Some detected issues (policy-managed settings)
        are never auto-remediated regardless of this switch, since doing so
        would override a deliberate administrative decision.

    .PARAMETER CustomLogPath
        Path to the log file. Defaults to C:\tmp\WSUS\WSUS-ClientSync.log.

    .EXAMPLE
        .\WSUS-ClientSync.ps1

        Runs diagnostics and a sync attempt, reporting any issues found without
        changing anything.

    .EXAMPLE
        .\WSUS-ClientSync.ps1 -AutomaticallyRemediate -CustomLogPath D:\Logs\wsus.log

        Runs diagnostics, attempts automatic remediation of recognised issues,
        and retries synchronisation once afterward.

    .OUTPUTS
        None. Writes progress and results to the configured log file and the
        Application event log (source: "WSUS Client Sync Script"). See the
        project README for the full event ID map.

    .NOTES
        Author: Bradley Pickering
        GitHub: https://github.com/Pickering-Cloud
        Requires: PKI module is NOT required for this script (unlike
        FileSigning). No special module dependencies beyond built-in Windows
        Update Agent COM APIs.
#>

[CmdletBinding()]
param (
    [switch]$AutomaticallyRemediate,
    [string]$CustomLogPath
)

########## Script Variable Definitions ##########
$Script:startTime = Get-Date
[string]$Script:logPath = if ($CustomLogPath) { $CustomLogPath.Replace("/", "\") } else { "C:\tmp\WSUS\WSUS-ClientSync.log" }
[string]$Script:eventLogSource = "WSUS Client Sync Script"
[string]$Script:eventLogName = "Application"
[Nullable[int]]$loggingLevel = $null
if ($PSSenderInfo -and $null -eq $loggingLevel) { $loggingLevel = 3 }
$logLevelMap = @{
    "NONE"     = 0
    "DEBUG"    = 1
    "VERBOSE"  = 2
    "INFO"     = 3
    "WARN"     = 4
    "ERROR"    = 5
    "CRITICAL" = 6
}
[int]$Script:minimumRequiredGB = 10
$Script:syncAttempts = 3
$Script:updateErrors = @()
$Script:sfcAlreadyRun = $false
$Script:dismAlreadyRun = $false
$Script:sdFolderResetAlreadyRun = $false
$Script:bitsQueueResetAlreadyRun = $false
$Script:bitsQueueFileResetAlreadyRun = $false

########## Configure Logging ##########

# Log file config
if (-not (Test-Path -Path $logPath)) {
    $logFolder = Split-Path -Path $logPath -Parent

    if (-not (Test-Path -Path $logFolder)) {
        New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
    }

    New-Item -ItemType File -Path $logPath -Force | Out-Null
    Set-ItemProperty -Path $logPath -Name IsReadOnly -Value $true
}

# Sets logging level for this session - can be overwritten by assigning a value to $loggingLevel
while ($null -eq $loggingLevel) {
    Write-Host "Please define logging level: Debug (1), Verbose (2), Info (3), Warn (4), Error (5), Critical (6), None (0)"
    Write-Host "Default logging level is Info"
    $response = (Read-Host).ToUpper().Trim()

    if ([string]::IsNullOrWhiteSpace($response)) {
        $loggingLevel = 3
        break
    }

    if ($logLevelMap.ContainsKey($response)) {
        $loggingLevel = $logLevelMap[$response]
        break
    }

    if ($response -match '^\d+$' -and [int]$response -ge 0 -and [int]$response -le 6) {
        $loggingLevel = [int]$response
        break
    }

    Write-Host "Not a valid response, please enter a number or write your required log level"
}

# Writes to defined log file
function Write-LogFile {
    param (
        [Parameter(Mandatory)]
        [string]$message,

        [Parameter(Mandatory)]
        [ValidateSet("Debug", "Verbose", "Info", "Warn", "Error", "Critical")]
        [string]$level
    )

    $logPath = $Script:logPath
    $level = $level.ToUpper()

    $levelValue = $logLevelMap[$level]

    if ($levelValue -ge $loggingLevel) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $line = "$timestamp | [$level] | $message"
        Add-Content -Path $logPath -Value $line -Force
    }
}

# Configures Event Viewer Source if it doesn't exist
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($Script:eventLogSource)) {
        New-EventLog -LogName $Script:eventLogName -Source $Script:eventLogSource
    }
}
catch {
    Write-LogFile -level Warn -message "Could not register event log source '$Script:eventLogSource': $($_.Exception.Message). Event log writes will fail until this is resolved (requires an elevated session)."
}

# Writes to Event Log
function Write-LogEvent {
    param (
        [string]$logSource = $Script:eventLogSource,

        [string]$logName = $Script:eventLogName,

        [Parameter(Mandatory)]
        [string]$message,

        [Parameter(Mandatory)]
        [int]$eventID,

        [Parameter(Mandatory)]
        [System.Diagnostics.EventLogEntryType]$entryType
    )

    Write-EventLog -LogName $logName -Source $logSource -EntryType $entryType -Category 0 -EventId $eventID -Message $message
}

Write-LogFile -level Verbose -message "Logging has been configured"
Write-LogFile -level Debug -message "logPath=$Script:logPath; eventLogSource=$Script:eventLogSource; eventLogName=$Script:eventLogName"
Write-LogFile -level Info -message "Script is running - logging level is $loggingLevel"

########## Collate Existing Configuration ##########

Write-LogFile -level Verbose -message "Beginning configuration collection"

# WSUS server info
[System.Uri]$initialWUServer = (Get-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate -ErrorAction SilentlyContinue).WUServer
[System.Uri]$initialWUStatusServer = (Get-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate -ErrorAction SilentlyContinue).WUStatusServer
Write-LogFile -level Debug -message "Pre-gpupdate WUServer=$initialWUServer; WUStatusServer=$initialWUStatusServer"

Write-LogFile -level Verbose -message "Forcing Group Policy update"
$groupPolicyResult = gpupdate /force /target:computer 2>&1
Write-LogFile -level Debug -message "gpupdate output: $($groupPolicyResult -join ' | ')"
if ($groupPolicyResult -match 'failed|error') {
    Write-LogFile -level Warn -message "gpupdate output suggests a possible failure, review debug log output above."
}

[System.Uri]$WUServer = (Get-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate -ErrorAction SilentlyContinue).WUServer
[System.Uri]$WUStatusServer = (Get-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate -ErrorAction SilentlyContinue).WUStatusServer
Write-LogFile -level Debug -message "Post-gpupdate WUServer=$WUServer; WUStatusServer=$WUStatusServer"

if ($initialWUServer -ne $WUServer) {
    Write-LogFile -level Info -message "Group Policy update amended configured WSUS server"
}
if ($initialWUStatusServer -ne $WUStatusServer) {
    Write-LogFile -level Info -message "Group Policy update amended configured WSUS Status server"
}

if ($null -eq $WUServer) {
    Write-LogFile -level Critical -message "No WSUS server configured - please review Group Policy/Registry configuration"
    Write-LogEvent -eventID 1002 -entryType Error -message "No WSUS server configured - please review Group Policy/Registry configuration"
    exit 1
}
if ($null -eq $WUStatusServer) {
    Write-LogFile -level Critical -message "No WSUS Status server configured - please review Group Policy/Registry configuration"
    Write-LogEvent -eventID 1003 -entryType Error -message "No WSUS Status server configured - please review Group Policy/Registry configuration"
    exit 1
}

Write-LogFile -level Verbose -message "Configured WSUS server is $WUServer. Configured WSUS Status server is $WUStatusServer"

########## Test Configurations ##########

Write-LogFile -level Verbose -message "Beginning configuration testing"

# Attempt to resolve DNS name
Write-LogFile -level Verbose -message "Attempting to resolve DNS name"
$parsedIP = $null
if ([System.Net.IPAddress]::TryParse($WUServer.Host, [ref]$parsedIP)) {
    Write-LogFile -level Info -message "WSUS server is configured as an IP address"
}
else {
    try {
        $dnsCheck = Resolve-DnsName -Name $WUServer.Host -ErrorAction Stop
        Write-LogFile -level Verbose -message "DNS resolution succeeded"
        Write-LogFile -level Debug -message "DNS resolution result: $($dnsCheck | Out-String)"
    }
    catch {
        Write-LogFile -level Critical -message "Unable to resolve DNS name for WSUS server: $($WUServer.Host). $($_.Exception.Message)"
        Write-LogEvent -eventID 1004 -entryType Error -message "Unable to resolve DNS name for WSUS server: $($WUServer.Host)"
        exit 1
    }
}

# Test network connectivity
Write-LogFile -level Verbose -message "Testing network connections"
$pingCheck = Test-Connection -ComputerName $WUServer.Host -Quiet -ErrorAction SilentlyContinue
$portCheck = Test-NetConnection -ComputerName $WUServer.Host -Port $WUServer.Port -InformationLevel Quiet -ErrorAction SilentlyContinue
Write-LogFile -level Debug -message "pingCheck=$pingCheck; portCheck=$portCheck"

if (-not $portCheck) {
    Write-LogFile -level Critical -message "Unable to reach WSUS server on port $($WUServer.Port)."
    Write-LogEvent -eventID 1005 -entryType Error -message "Unable to reach WSUS server on port $($WUServer.Port)."
    exit 1
}
if (-not $pingCheck) {
    Write-LogFile -level Warn -message "ICMP ping to WSUS server failed, this may be normal if ICMP is blocked by firewall policy."
}

# Check IIS certificate is trusted
$certTrustResult = [PSCustomObject]@{
    IsTrusted   = $true
    Subject     = $null
    Issuer      = $null
    Thumbprint  = $null
    NotAfter    = $null
    ChainStatus = @()
}

if ($WUServer.Scheme -eq 'https') {
    Write-LogFile -level Verbose -message "Checking for certificate trust"
    $tcpClient = $null
    $sslStream = $null
    $Script:capturedCert = $null

    try {
        $tcpClient = [System.Net.Sockets.TcpClient]::new()
        $tcpClient.Connect($WUServer.Host, $WUServer.Port)

        $validationCallback = {
            param($senderObj, $certificate, $chain, $sslPolicyErrors)
            $script:capturedCert = $certificate
            return $true
        }

        $sslStream = [System.Net.Security.SslStream]::new(
            $tcpClient.GetStream(),
            $false,
            $validationCallback
        )

        $sslStream.AuthenticateAsClient($WUServer.Host)

        if (-not $script:capturedCert) {
            throw "No certificate was presented by $($WUServer.Host):$($WUServer.Port)."
        }

        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($script:capturedCert)

        $chain = [System.Security.Cryptography.X509Certificates.X509Chain]::new()
        $chain.ChainPolicy.RevocationMode = 'NoCheck'
        $chain.ChainPolicy.VerificationFlags = [System.Security.Cryptography.X509Certificates.X509VerificationFlags]::NoFlag

        $isValid = $chain.Build($cert)

        $certTrustResult = [PSCustomObject]@{
            IsTrusted   = $isValid
            Subject     = $cert.Subject
            Issuer      = $cert.Issuer
            Thumbprint  = $cert.Thumbprint
            NotAfter    = $cert.NotAfter
            ChainStatus = $chain.ChainStatus | ForEach-Object { "$($_.Status): $($_.StatusInformation.Trim())" }
        }
    }
    catch {
        $certTrustResult = [PSCustomObject]@{
            IsTrusted   = $false
            Subject     = $null
            Issuer      = $null
            Thumbprint  = $null
            NotAfter    = $null
            ChainStatus = @("Connection or handshake failed: $($_.Exception.Message)")
        }
    }
    finally {
        if ($sslStream) { $sslStream.Dispose() }
        if ($tcpClient) { $tcpClient.Dispose() }
    }
}
else {
    Write-LogFile -level Verbose -message "WUServer $WUServer is not using HTTPS, skipping certificate trust check."
}

if ($certTrustResult.IsTrusted) {
    Write-LogFile -level Verbose -message "WSUS server certificate trust check passed (or not applicable)."
}
else {
    Write-LogFile -level Error -message "WSUS server certificate is not trusted. Issuer: $($certTrustResult.Issuer). Detail: $($certTrustResult.ChainStatus -join ' | ')"
    Write-LogEvent -eventID 1006 -entryType Warning -message "WSUS server certificate is not trusted. Issuer: $($certTrustResult.Issuer)"
}

# Check for pending reboot
Write-LogFile -level Verbose -message "Testing if machine is in pending reboot state"
$rebootPending = $false
$rebootReasons = @()

if (Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
    $rebootPending = $true
    $rebootReasons += "Component Based Servicing"
}

if (Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
    $rebootPending = $true
    $rebootReasons += "Windows Update"
}

$pfro = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
if ($pfro) {
    $rebootPending = $true
    $rebootReasons += "Pending File Rename Operations"
}

$activeName = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName" -Name "ComputerName" -ErrorAction SilentlyContinue).ComputerName
$pendingName = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName" -Name "ComputerName" -ErrorAction SilentlyContinue).ComputerName
if ($activeName -and $pendingName -and $activeName -ne $pendingName) {
    $rebootPending = $true
    $rebootReasons += "Pending computer rename"
}

if (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon" -Name "JoinDomain" -ErrorAction SilentlyContinue) {
    $rebootPending = $true
    $rebootReasons += "Pending domain join"
}
if (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon" -Name "AvoidSpnSet" -ErrorAction SilentlyContinue) {
    $rebootPending = $true
    $rebootReasons += "Pending domain rename"
}

$ccmClientSDK = Get-CimInstance -Namespace "ROOT\ccm\ClientSDK" -ClassName CCM_ClientUtilities -ErrorAction SilentlyContinue
if ($ccmClientSDK) {
    $ccmResult = Invoke-CimMethod -Namespace "ROOT\ccm\ClientSDK" -ClassName CCM_ClientUtilities -MethodName DetermineIfRebootPending -ErrorAction SilentlyContinue
    if ($ccmResult -and ($ccmResult.RebootPending -or $ccmResult.IsHardRebootPending)) {
        $rebootPending = $true
        $rebootReasons += "SCCM client"
    }
}

if ($rebootPending) {
    Write-LogFile -level Warn -message "Reboot pending: $($rebootReasons -join ', ')"
}
else {
    Write-LogFile -level Verbose -message "No reboot pending."
}

# Check for available space on system drive
Write-LogFile -level Verbose -message "Checking available space on system drive"
$systemDrive = $env:SystemDrive.TrimEnd(':')

try {
    $diskInfo = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$systemDrive`:'" -ErrorAction Stop
    $totalSpaceGB = [math]::Round($diskInfo.Size / 1GB, 2)
    $freeSpaceGB = [math]::Round($diskInfo.FreeSpace / 1GB, 2)
    Write-LogFile -level Debug -message "Raw disk info: Size=$($diskInfo.Size) FreeSpace=$($diskInfo.FreeSpace)"

    if ($freeSpaceGB -lt $Script:minimumRequiredGB) {
        Write-LogFile -level Warn -message "Low disk space on $systemDrive`: $freeSpaceGB GB free out of $totalSpaceGB GB. Minimum recommended: $Script:minimumRequiredGB GB."
    }
    else {
        Write-LogFile -level Info -message "$systemDrive`: $freeSpaceGB GB free out of $totalSpaceGB GB."
    }
}
catch {
    Write-LogFile -level Error -message "Failed to query disk space for $systemDrive`: $($_.Exception.Message)"
}

# Service state
$requiredServices = @(
    "wuauserv",
    "bits",
    "cryptsvc"
)

Write-LogFile -level Verbose -message "Ensuring required services are not disabled"
foreach ($service in $requiredServices) {
    $svc = Get-Service -Name $service
    Write-LogFile -level Debug -message "Service '$service': StartType=$($svc.StartType), Status=$($svc.Status)"

    if ($svc.StartType -eq "Disabled") {
        if ($AutomaticallyRemediate) {
            try {
                Set-Service -Name $service -StartupType Manual -ErrorAction Stop
                Write-LogFile -level Warn -message "Service '$service' was Disabled, set to Manual."
            }
            catch {
                Write-LogFile -level Error -message "Failed to change startup type for '$service': $($_.Exception.Message)"
            }
        }
        else {
            Write-LogFile -level Warn -message "Service '$service' is Disabled. Run with -AutomaticallyRemediate to fix automatically."
        }
    }
}

$wuauservStatus = (Get-Service -Name "wuauserv").Status
if ($wuauservStatus -ne "Running") {
    if ($AutomaticallyRemediate) {
        try {
            Start-Service -Name "wuauserv" -ErrorAction Stop
            Write-LogFile -level Warn -message "wuauserv was not running - service started"
        }
        catch {
            Write-LogFile -level Error -message "wuauserv was not running - unable to start service: $($_.Exception.Message)"
        }
    }
    else {
        Write-LogFile -level Warn -message "wuauserv is not running. Run with -AutomaticallyRemediate to start it automatically."
    }
}
else {
    Write-LogFile -level Verbose -message "wuauserv is already running."
}

########## Sync Attempt Logic ##########
function Invoke-SyncAttempt {
    if ($autoUpdate) {
        try {
            $autoUpdate.DetectNow()
            Write-LogFile -level Verbose -message "COM API DetectNow triggered."
        }
        catch {
            Write-LogFile -level Warn -message "COM API DetectNow failed: $($_.Exception.Message)"
        }
    }

    try {
        $usoResult = & "$env:SystemRoot\System32\UsoClient.exe" ScanInstallWait 2>&1
        Write-LogFile -level Verbose -message "UsoClient ScanInstallWait output: $($usoResult -join ' ')"
    }
    catch {
        Write-LogFile -level Warn -message "UsoClient ScanInstallWait failed: $($_.Exception.Message)"
    }

    try {
        & "$env:SystemRoot\System32\wuauclt.exe" /detectnow /reportnow
        Write-LogFile -level Verbose -message "wuauclt /detectnow /reportnow invoked."
    }
    catch {
        Write-LogFile -level Warn -message "wuauclt failed: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds 60

    $lastSuccess = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Detect" -Name "LastSuccessTime" -ErrorAction SilentlyContinue).LastSuccessTime
    Write-LogFile -level Debug -message "LastSuccessTime read as: $lastSuccess"

    return [bool]($lastSuccess -and ((Get-Date) - [DateTime]$lastSuccess).TotalMinutes -le 5)
}

########## Attempt Synchronisation ##########
[int]$syncs = 0
$syncSucceeded = $false

try {
    $autoUpdate = New-Object -ComObject "Microsoft.Update.AutoUpdate" -ErrorAction Stop
}
catch {
    Write-LogFile -level Error -message "Failed to create Microsoft.Update.AutoUpdate COM object: $($_.Exception.Message)"
}

do {
    Write-LogFile -level Verbose -message "Starting sync - attempt $($syncs + 1)"
    $syncSucceeded = Invoke-SyncAttempt
    $syncs += 1
    Write-LogFile -level Verbose -message "Sync $syncs finished. Success: $syncSucceeded"
}
until ($syncSucceeded -or $syncs -ge $Script:syncAttempts)

if ($syncSucceeded) {
    Write-LogFile -level Info -message "Sync succeeded after $syncs attempt(s)."
}
else {
    Write-LogFile -level Error -message "Sync did not succeed after $syncs attempt(s)."
    Write-LogEvent -eventID 1007 -entryType Error -message "WSUS sync failed after $syncs attempt(s)."
}

########## Identify Errors ##########
Write-LogFile -level Verbose -message "Reviewing update history for errors since $Script:startTime"

try {
    $updateSession = New-Object -ComObject "Microsoft.Update.Session" -ErrorAction Stop
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $historyCount = $updateSearcher.GetTotalHistoryCount()
    Write-LogFile -level Debug -message "Total update history entries on this machine: $historyCount"

    if ($historyCount -gt 0) {
        $history = $updateSearcher.QueryHistory(0, $historyCount)

        $Script:updateErrors = $history | Where-Object {
            $_.Date -ge $Script:startTime -and $_.ResultCode -in @(3, 4, 5)
        } | ForEach-Object {
            [PSCustomObject]@{
                Title      = $_.Title
                Date       = $_.Date
                Operation  = switch ($_.Operation) { 1 { "Installation" } 2 { "Uninstallation" } default { "Unknown" } }
                ResultCode = switch ($_.ResultCode) { 3 { "SucceededWithErrors" } 4 { "Failed" } 5 { "Aborted" } default { "Unknown" } }
                HResult    = '0x{0:X8}' -f $_.HResult
            }
        }
    }
    else {
        Write-LogFile -level Verbose -message "No update history entries found on this machine."
    }
}
catch {
    Write-LogFile -level Error -message "Failed to query update history: $($_.Exception.Message)"
}

if ($Script:updateErrors.Count -gt 0) {
    foreach ($err in $Script:updateErrors) {
        Write-LogFile -level Error -message "Update error: '$($err.Title)' - $($err.Operation) $($err.ResultCode) ($($err.HResult)) at $($err.Date)"
        Write-LogEvent -eventID 1008 -entryType Error -message "Update error: '$($err.Title)' - $($err.ResultCode) ($($err.HResult))"
    }
}
else {
    Write-LogFile -level Info -message "No update install/uninstall errors found since script start ($Script:startTime)."
}

########## Attempt Remediations ##########
Write-LogFile -level Verbose -message "Beginning remediation phase (AutomaticallyRemediate=$($AutomaticallyRemediate.IsPresent))"

# Repair actions - called by multiple repair functions

function Invoke-SFCScanOnce {
    if ($Script:sfcAlreadyRun) {
        Write-LogFile -level Verbose -message "sfc /scannow already run this session, skipping."
        return
    }
    Write-LogFile -level Verbose -message "Running sfc /scannow."
    $sfcOutput = sfc /scannow 2>&1
    Write-LogFile -level Verbose -message "sfc /scannow output: $($sfcOutput -join ' ')"
    $Script:sfcAlreadyRun = $true
}

function Invoke-DISMRestoreHealthOnce {
    if ($Script:dismAlreadyRun) {
        Write-LogFile -level Verbose -message "DISM /RestoreHealth already run this session, skipping."
        return
    }
    Write-LogFile -level Verbose -message "Running DISM /Online /Cleanup-Image /RestoreHealth."
    $dismOutput = DISM /Online /Cleanup-Image /RestoreHealth 2>&1
    Write-LogFile -level Verbose -message "DISM output: $($dismOutput -join ' ')"
    $Script:dismAlreadyRun = $true
}

function Invoke-ResetFolderCache {
    if ($Script:sdFolderResetAlreadyRun) {
        Write-LogFile -level Verbose -message "SoftwareDistribution/catroot2 reset already run this session, skipping."
        return
    }

    Write-LogFile -level Info -message "Resetting SoftwareDistribution and catroot2 folders."

    $sdServices = @("wuauserv", "bits", "cryptsvc")
    $foldersToReset = @(
        @{ Path = "$env:SystemRoot\SoftwareDistribution"; BackupName = "SoftwareDistribution.old" },
        @{ Path = "$env:SystemRoot\System32\catroot2"; BackupName = "catroot2.old" }
    )

    try {
        foreach ($service in $sdServices) {
            try {
                Stop-Service -Name $service -Force -ErrorAction Stop
                Write-LogFile -level Verbose -message "Stopped service '$service'."
            }
            catch {
                Write-LogFile -level Warn -message "Failed to stop service '$service': $($_.Exception.Message)"
            }
        }

        foreach ($folder in $foldersToReset) {
            $backupPath = Join-Path -Path (Split-Path -Path $folder.Path -Parent) -ChildPath $folder.BackupName

            if (Test-Path -Path $backupPath) {
                Write-LogFile -level Verbose -message "Removing existing backup at '$backupPath' from a previous run."
                Remove-Item -Path $backupPath -Recurse -Force -ErrorAction SilentlyContinue
            }

            if (Test-Path -Path $folder.Path) {
                try {
                    Rename-Item -Path $folder.Path -NewName $folder.BackupName -ErrorAction Stop
                    Write-LogFile -level Info -message "Renamed '$($folder.Path)' to '$($folder.BackupName)'."
                }
                catch {
                    Write-LogFile -level Error -message "Failed to rename '$($folder.Path)': $($_.Exception.Message)"
                }
            }
            else {
                Write-LogFile -level Warn -message "Folder not found at '$($folder.Path)', nothing to rename."
            }
        }
    }
    finally {
        foreach ($service in $sdServices) {
            try {
                Start-Service -Name $service -ErrorAction Stop
                Write-LogFile -level Verbose -message "Started service '$service'."
            }
            catch {
                Write-LogFile -level Error -message "Failed to restart service '$service': $($_.Exception.Message). This service may need manual attention."
                Write-LogEvent -eventID 1015 -entryType Error -message "Failed to restart service '$service' after remediation. Manual attention required."
            }
        }
    }

    $Script:sdFolderResetAlreadyRun = $true
}

function Invoke-BitsQueueReset {
    if ($Script:bitsQueueResetAlreadyRun) {
        Write-LogFile -level Verbose -message "BITS queue reset already run this session, skipping."
        return
    }

    Write-LogFile -level Info -message "Checking BITS transfer queue for stuck or errored jobs."

    try {
        $bitsJobs = Get-BitsTransfer -AllUsers -ErrorAction Stop
        $problemJobs = $bitsJobs | Where-Object { $_.JobState -in @('Error', 'TransientError', 'Suspended') }

        if ($problemJobs) {
            foreach ($job in $problemJobs) {
                Write-LogFile -level Warn -message "Removing BITS job '$($job.DisplayName)' (State: $($job.JobState))."
                try {
                    Remove-BitsTransfer -BitsJob $job -ErrorAction Stop
                }
                catch {
                    Write-LogFile -level Error -message "Failed to remove BITS job '$($job.DisplayName)': $($_.Exception.Message)"
                }
            }
        }
        else {
            Write-LogFile -level Verbose -message "No problem BITS jobs found in queue."
        }
    }
    catch {
        Write-LogFile -level Warn -message "Failed to query BITS transfer queue via API: $($_.Exception.Message). Escalating to file-level reset."
        Invoke-BitsQueueFileReset
    }

    $Script:bitsQueueResetAlreadyRun = $true
}

function Invoke-BitsQueueFileReset {
    if ($Script:bitsQueueFileResetAlreadyRun) {
        Write-LogFile -level Verbose -message "BITS queue file reset already run this session, skipping."
        return
    }

    Write-LogFile -level Verbose -message "Performing file-level BITS queue reset."

    $downloaderPath = "$env:ProgramData\Microsoft\Network\Downloader"

    try {
        Stop-Service -Name bits -Force -ErrorAction Stop

        Get-ChildItem -Path $downloaderPath -Filter "qmgr*" -ErrorAction SilentlyContinue | ForEach-Object {
            Write-LogFile -level Warn -message "Removing BITS queue file: $($_.Name)"
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-LogFile -level Error -message "File-level BITS queue reset failed: $($_.Exception.Message)"
    }
    finally {
        try {
            Start-Service -Name bits -ErrorAction Stop
        }
        catch {
            Write-LogFile -level Error -message "Failed to restart BITS service: $($_.Exception.Message). This service may need manual attention."
            Write-LogEvent -eventID 1015 -entryType Error -message "Failed to restart BITS service after remediation. Manual attention required."
        }
    }

    $Script:bitsQueueFileResetAlreadyRun = $true
}

# Error code repairs

function Repair-8000FFFF {
    Write-LogFile -level Info -message "Repair-8000FFFF: generic unexpected error, attempting component repair."
    Write-LogEvent -eventID 1009 -entryType Warning -message "Repair-8000FFFF invoked: generic unexpected error."
    Invoke-DISMRestoreHealthOnce
    Invoke-SFCScanOnce
}

function Repair-800F0831 {
    Write-LogFile -level Info -message "Repair-800F0831: component store corruption detected, attempting repair."
    Write-LogEvent -eventID 1010 -entryType Warning -message "Repair-800F0831 invoked: component store corruption."
    Invoke-DISMRestoreHealthOnce
    Invoke-SFCScanOnce
}

function Repair-80244022 {
    Write-LogFile -level Info -message "Repair-80244022: WSUS server reported overloaded/unavailable, resetting local cache."
    Write-LogEvent -eventID 1011 -entryType Warning -message "Repair-80244022 invoked: WSUS server overloaded/unavailable."
    Invoke-ResetFolderCache
    Invoke-BitsQueueReset
}

function Repair-80072EE2 {
    Write-LogFile -level Warn -message "Repair-80072EE2: timeout reaching WSUS server. This is typically network/firewall/server-load related, not locally repairable."
    Clear-DnsClientCache
    $retryPortCheck = Test-NetConnection -ComputerName $WUServer.Host -Port $WUServer.Port -InformationLevel Quiet -ErrorAction SilentlyContinue
    Write-LogFile -level Info -message "Retry port check result: $retryPortCheck"
    Write-LogEvent -eventID 1012 -entryType Warning -message "Timeout reaching WSUS server, may require network/firewall investigation."
}

function Repair-80072EE5 {
    Write-LogFile -level Error -message "Repair-80072EE5: WUServer URL appears malformed (check for a trailing slash). Current value: $($WUServer.OriginalString). This is a policy-managed setting and will not be modified automatically."
    Write-LogEvent -eventID 1013 -entryType Error -message "WSUS server URL is malformed, requires GPO/policy correction."
}

function Repair-8024002E {
    Write-LogFile -level Error -message "Repair-8024002E: Windows Update access is disabled by policy on this machine. This will not be overridden automatically."
    Write-LogEvent -eventID 1014 -entryType Error -message "Windows Update access disabled by policy on $env:COMPUTERNAME."
}

if ($AutomaticallyRemediate) {
    $uniqueErrorCodes = $Script:updateErrors.HResult | Select-Object -Unique
    Write-LogFile -level Debug -message "Unique error codes to remediate: $($uniqueErrorCodes -join ', ')"

    foreach ($hexErr in $uniqueErrorCodes) {
        $codeSuffix = $hexErr -replace '^0x', ''
        $repairFunctionName = "Repair-$codeSuffix"

        if (Get-Command -Name $repairFunctionName -ErrorAction SilentlyContinue) {
            try {
                Write-LogFile -level Info -message "Calling $repairFunctionName for error code $hexErr."
                & $repairFunctionName
            }
            catch {
                Write-LogFile -level Error -message "$repairFunctionName threw an error: $($_.Exception.Message)"
            }
        }
        else {
            Write-LogFile -level Warn -message "No remediation function exists for error code $hexErr."
        }
    }
}

########## Reattempt Synchronisation ##########
if ($AutomaticallyRemediate -and $Script:updateErrors.Count -gt 0 -and -not $syncSucceeded) {
    Write-LogFile -level Verbose -message "Starting sync attempt after remediations"
    $syncSucceeded = Invoke-SyncAttempt
    $syncs += 1
    Write-LogFile -level Verbose -message "Sync $syncs finished. Success: $syncSucceeded"

    if ($syncSucceeded) {
        Write-LogFile -level Info -message "Sync succeeded after remediation (attempt $syncs)."
    }
    else {
        Write-LogFile -level Error -message "Sync did not succeed after remediation (attempt $syncs)."
        Write-LogEvent -eventID 1016 -entryType Error -message "WSUS sync failed after $syncs attempt(s), including post-remediation retry."
    }
}

Write-LogFile -level Info -message "WSUS Client Sync script has completed"
Write-LogEvent -eventID 1001 -entryType Information -message "WSUS Client Sync script has completed"