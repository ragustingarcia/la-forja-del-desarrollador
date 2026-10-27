$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$raw=[IO.File]::ReadAllText((Join-Path $root 'forja-del-desarrollador.bat'))
$errors=$null;$tokens=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($raw,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach($f in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){. ([scriptblock]::Create($f.Extent.Text))}
$bytes=[Text.Encoding]::ASCII.GetBytes(('inert MSI fixture '*256))
$digest=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-','')
function Get-MongoshRepairPackage { param($Version)
    if ($script:case -eq 'unknown-version') { return $null }
    [pscustomobject]@{Version=$Version;Uri='https://downloads.mongodb.com/compass/mongosh-2.14.0-x64.msi';Sha256=$digest}
}
function Test-ForjaRepairAccount { return ($script:case -ne 'other-account') }
function Test-MongoshBusy { return ($script:case -eq 'busy') }
function Test-MongoshRuntime { param($Version) return ($script:case -ne 'runtime-failure') }
function Save-ForjaRepairPackage { param($Uri,$Destination)
    if ($script:case -eq 'network-failure') { throw 'fixture network failure' }
    if ($script:case -eq 'hash-mismatch') { [IO.File]::WriteAllText($Destination,'altered fixture'); return }
    [IO.File]::WriteAllBytes($Destination,$bytes)
}
function Get-AuthenticodeSignature { param($LiteralPath,$ErrorAction)
    $script:signatures++
    $status='Valid';$subject='CN=MongoDB Inc'
    if ($script:case -eq 'unsigned') { $status='NotSigned' }
    if ($script:case -eq 'wrong-publisher') { $subject='CN=Other publisher' }
    [pscustomobject]@{Status=$status;SignerCertificate=[pscustomobject]@{Subject=$subject}}
}
function Start-Process { param($FilePath,$ArgumentList,[switch]$Wait,[switch]$PassThru,$Verb,$ErrorAction)
    $script:launches++
    if ($FilePath -ne (Join-Path ([Environment]::SystemDirectory) 'msiexec.exe') -or $Verb -ne 'RunAs') { throw 'Unexpected elevation target' }
    if (-not $Wait -or -not $PassThru -or $ArgumentList -notcontains '/norestart') { throw 'Missing lifecycle guard' }
    $msi=$ArgumentList[1].Trim('"')
    $locked=$false
    try { $writer=[IO.File]::Open($msi,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$writer.Dispose() }
    catch [IO.IOException] { $locked=$true }
    if (-not $locked -or $script:signatures -ne 1) { throw 'Package is not locked or signature not checked' }
    if ($script:case -eq 'cancel') { throw [ComponentModel.Win32Exception]::new(1223) }
    $code=0
    if ($script:case -eq 'installer-failure') { $code=1603 }
    if ($script:case -eq 'reboot') { $code=3010 }
    [pscustomobject]@{ExitCode=$code}
}
function Get-WingetPackageInfo { param($Id)
    $version='2.14.0'
    if ($script:case -eq 'not-confirmed') { $version='2.9.2' }
    [pscustomobject]@{State='installed';Version=$version}
}
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('forja-msi-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($sandbox) | Out-Null
$previous=$env:USERPROFILE;$passed=0
try {
    $denyOnly='"Administradores","Alias","S-1-5-32-544","Deny only"'
    if (-not (Test-ForjaAdminGroupList $denyOnly)) { throw 'No reconoce SID administrador en token filtrado' }
    $passed++;Write-Host 'PASS MSI cuenta administradora con grupo deny-only'
    if (Test-ForjaAdminGroupList '"Usuarios","Alias","S-1-5-32-545","Enabled"') { throw 'Acepta cuenta no administradora' }
    $passed++;Write-Host 'PASS MSI cuenta no administradora no autoriza cambio de cuenta'
    if (Test-ForjaAdminGroupList '"Otro","Alias","S-1-5-32-5440","Enabled"') { throw 'SID sin coincidencia exacta' }
    $passed++;Write-Host 'PASS MSI compara SID exacto sin depender del idioma'
    foreach($case in @('success','hash-mismatch','unsigned','wrong-publisher','network-failure','installer-failure','reboot','cancel','not-confirmed','runtime-failure','other-account','busy','unknown-version')) {
        $env:USERPROFILE=Join-Path $sandbox $case
        $script:ForjaWorkspaces=@{};$script:launches=0;$script:signatures=0
        $result=@(Invoke-MongoshRepair '2.14.0')
        $expected='error'
        if ($case -eq 'success') { $expected='ok' }
        if ($case -in @('reboot','cancel','not-confirmed','runtime-failure','other-account','busy','unknown-version')) { $expected='pendiente' }
        if ($result.Count -ne 1 -or $result[0] -ne $expected) { throw "$case : retorno inesperado $result" }
        $shouldLaunch=$case -in @('success','installer-failure','reboot','cancel','not-confirmed','runtime-failure')
        if (($script:launches -eq 1) -ne $shouldLaunch) { throw "$case : elevacion inesperada o faltante" }
        if ($case -eq 'success' -and $script:ForjaWorkspaces.Count -ne 0) { throw 'No limpio el temporal propio tras verificar exito' }
        if ($case -in @('hash-mismatch','unsigned','wrong-publisher','network-failure') -and $script:ForjaWorkspaces.Count -ne 0) { throw 'Se retuvo un MSI no confiable' }
        $passed++;Write-Host "PASS MSI $case / $expected / elevaciones simuladas=$($script:launches)"
    }
    Write-Host "RESULTADO MSI: $passed PASS / 0 FAIL"
} finally {
    $env:USERPROFILE=$previous
    $full=[IO.Path]::GetFullPath($sandbox)
    $parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($full) -ne $parent -or [IO.Path]::GetFileName($full) -notmatch '^forja-msi-[0-9a-f]{32}$') { throw 'Unsafe fixture root' }
    $null=@(Get-ForjaTree $full)
    Remove-Item -LiteralPath $full -Recurse -Force
}
