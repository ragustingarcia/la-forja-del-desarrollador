$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$text=[IO.File]::ReadAllText((Join-Path $root 'forja-del-desarrollador.bat'))
$errors=$null;$tokens=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
foreach($f in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){. ([scriptblock]::Create($f.Extent.Text))}
$passed=0
function Assert {param([bool]$Condition,[string]$Message) if(-not $Condition){throw "FALLO: $Message"};$script:passed++;Write-Host "PASS $Message"}
function Assert-Fails {param([scriptblock]$Action,[string]$Message) $failed=$false;try{& $Action}catch{$failed=$true};Assert $failed $Message}
$all=@(Get-ForjaToolCatalog)
$base=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $root 'catalog\base.json')))
Assert ((@(Get-ForjaBaseCatalog) | ConvertTo-Json -Depth 6 -Compress) -ceq ($base | ConvertTo-Json -Depth 6 -Compress)) 'catalogo base embebido coincide con su archivo'
Assert ($all.Count -eq 49 -and @($all | Group-Object Code | Where-Object Count -gt 1).Count -eq 0) '49 opciones individuales con codigos unicos'
Assert (@($all | Where-Object {[string]::IsNullOrWhiteSpace($_.Description)}).Count -eq 0) 'cada herramienta tiene explicacion simple'
Assert (@($all | Where-Object Id -eq 'supabase').Count -eq 1 -and @($all | Where-Object Id -eq 'supabase-native').Count -eq 0) 'Supabase no aparece duplicado en el selector'
Assert (($all | Where-Object Id -eq 'postgis-guide').Method -eq 'guidance' -and ($all | Where-Object Id -eq 'frontend-guide').Method -eq 'guidance') 'las recetas se distinguen de instaladores'
foreach($width in @(40,60,80)){
    foreach($tool in $all){
        $rows=@(Get-ForjaToolCard $tool $width)
        if(@($rows | Where-Object {$_.Length -gt $width}).Count){throw "Tarjeta excede ancho $width : $($tool.Id)"}
    }
    Assert $true "nombres y explicaciones respetan ancho $width"
}
Assert ((Format-ForjaProgress 'ZIP' 50 100) -match '50%') 'descarga con total muestra porcentaje real'
Assert ((Format-ForjaProgress 'ZIP' 100 100) -match '99%') 'no muestra 100 antes de confirmar fin del stream'
Assert ((Format-ForjaProgress 'ZIP' 100 100 -Completed) -match '100%') 'muestra 100 al completar una descarga conocida'
Assert ((Format-ForjaProgress 'npm' 10 -1) -notmatch '%') 'gestor sin total usa actividad sin porcentaje inventado'
Assert ((Format-ForjaProgress 'ZIP' 5 100 -Failed) -match 'Interrumpido') 'fallo no se presenta como descarga completa'
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('forja-progress-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($sandbox) | Out-Null
try {
    $script:frames=@()
    function Write-ForjaProgress {param($Label,$Bytes,$Total,$Frame,[switch]$Completed,[switch]$Failed) $script:frames+=[pscustomobject]@{Bytes=$Bytes;Total=$Total;Completed=[bool]$Completed;Failed=[bool]$Failed}}
    $bytes=[Text.Encoding]::UTF8.GetBytes(('inert content '*10000))
    foreach($case in @('known','unknown','short','long')){
        $target=Join-Path $sandbox ($case+'.bin');$inputStream=New-Object IO.MemoryStream(,$bytes)
        $total=[long]$bytes.Length
        if($case -eq 'unknown'){$total=-1};if($case -eq 'short'){$total+=100};if($case -eq 'long'){$total=100}
        $script:frames=@()
        try {
            if($case -in @('short','long')){
                Assert-Fails {Copy-ForjaDownloadStream $inputStream $target $total 'Fixture'} "$case rechaza tamano inconsistente"
                Assert (@($script:frames | Where-Object Completed).Count -eq 0 -and @($script:frames | Where-Object Failed).Count -eq 1) "$case nunca informa descarga completa"
            } else {
                Copy-ForjaDownloadStream $inputStream $target $total 'Fixture'
                Assert ((Get-Item -LiteralPath $target).Length -eq $bytes.Length) "$case conserva bytes descargados"
                Assert (@($script:frames | Where-Object Completed).Count -eq 1) "$case completa una sola vez"
            }
        } finally {$inputStream.Dispose()}
    }
    $existing=Join-Path $sandbox 'existing.bin';[IO.File]::WriteAllText($existing,'PRESERVE')
    $inputStream=New-Object IO.MemoryStream(,$bytes)
    try {Assert-Fails {Copy-ForjaDownloadStream $inputStream $existing $bytes.Length 'Fixture'} 'descarga no pisa un archivo existente'}finally{$inputStream.Dispose()}
    Assert ([IO.File]::ReadAllText($existing) -eq 'PRESERVE') 'contenido existente intacto'
    Assert-Fails {Save-ForjaDownload 'http://example.invalid/file' (Join-Path $sandbox 'never.bin')} 'rechaza HTTP antes de abrir una conexion'
    Assert-Fails {Save-ForjaDownload 'https://user:sentinel@example.invalid/file' (Join-Path $sandbox 'never2.bin')} 'rechaza credenciales en URL antes de descargar'
    $shell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $source="Write-Output 'FIXTURE_OUT'; [Console]::Error.WriteLine('FIXTURE_ERR'); exit 1603"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($source))
    $result=Invoke-ForjaPackageProcess $shell @('-NoProfile','-EncodedCommand',$encoded) 'Fixture fallida'
    Assert ($result.ExitCode -eq 1603) 'barra conserva exit code real del proceso'
    Assert (($result.Output -join ' ') -match 'FIXTURE_OUT' -and ($result.Output -join ' ') -match 'FIXTURE_ERR') 'barra conserva stdout y stderr para diagnostico'
    Assert (@($script:frames | Where-Object Failed).Count -gt 0) 'proceso fallido muestra estado interrumpido'
    $python=Get-Command python.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $values=@('C:\folder with spaces\','a"b','x&y','%PATH%','bang!','')
    $result=Invoke-ForjaPackageProcess $python.Source (@('-c','import json,sys; print(json.dumps(sys.argv[1:]))')+$values) 'Fixture argumentos'
    $received=ConvertFrom-Json -InputObject ($result.Output -join "`n")
    Assert ($result.ExitCode -eq 0 -and ($received | ConvertTo-Json -Compress) -ceq ($values | ConvertTo-Json -Compress)) 'argumentos con espacios comillas porcentajes y vacios se pasan literalmente'
    $npm=Get-Command npm.cmd -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $result=Invoke-ForjaPackageProcess $npm.Source @('--version') 'Fixture npm version'
    Assert ($result.ExitCode -eq 0 -and ($result.Output -join ' ') -match '\d+\.\d+\.\d+') 'npm usa Node directamente sin instalar paquetes ni invocar cmd'
    Write-Host "RESULTADO PROGRESO/INDIVIDUAL: $passed PASS / 0 FAIL"
} finally {
    $full=[IO.Path]::GetFullPath($sandbox);$parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if([IO.Path]::GetDirectoryName($full) -ne $parent -or [IO.Path]::GetFileName($full) -notmatch '^forja-progress-[0-9a-f]{32}$'){throw 'Raiz de prueba invalida'}
    $null=@(Get-ForjaTree $full);Remove-Item -LiteralPath $full -Recurse -Force
}
