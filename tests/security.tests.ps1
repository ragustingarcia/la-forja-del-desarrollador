# Pruebas sin Pester, red, UAC, instaladores ni credenciales reales.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$scriptText = [IO.File]::ReadAllText((Join-Path $repoRoot 'forja-del-desarrollador.bat'))
$parseErrors = $null; $tokens = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($scriptText, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
foreach ($definition in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    . ([scriptblock]::Create($definition.Extent.Text))
}
function Invoke-ForjaTool { param([string]$Name) & $Name @args }
$passed = 0
function Assert { param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FALLO: $Message" }
    $script:passed++
    Write-Host "PASS $Message"
}
function Assert-Throws { param([scriptblock]$Action, [string]$Message)
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Assert $threw $Message
}
function global:winget {
    $script:wingetArgs = @($args)
    if ($script:wingetQueue -and $script:wingetQueue.Count -gt 0) {
        $response=$script:wingetQueue.Dequeue()
        $global:LASTEXITCODE=$response.Code
        $response.Output
        return
    }
    $global:LASTEXITCODE = $script:mockWingetExit
    $script:mockWingetOutput
}
function global:npm {
    $script:npmCalls += ,@($args)
    switch ($args[0]) {
        'list' { $global:LASTEXITCODE = $script:npmListExit; $script:npmListOutput }
        'view' { $global:LASTEXITCODE = $script:npmViewExit; $script:npmViewOutput }
        'install' { $global:LASTEXITCODE = $script:npmInstallExit; 'installer output' }
        default { throw 'npm fuera de lo permitido por la prueba' }
    }
}
function global:git {
    $script:gitCalls += ,@($args)
    $global:LASTEXITCODE = $script:mockGitExit
    if ($args -contains 'rev-parse') { $script:mockGitHead }
}
function global:snyk {
    $script:snykArgs = @($args)
    $global:LASTEXITCODE = $script:mockSnykExit
    'DO_NOT_DISPLAY_CREDENTIAL_SENTINEL'
}
function global:Read-Host { param($Prompt) $script:mockAnswer }

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('forja-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($sandbox) | Out-Null
$previousLocal = $env:LOCALAPPDATA
$env:LOCALAPPDATA = Join-Path $sandbox 'LocalAppData'
$script:ForjaWorkspaces = @{}
$script:WINGET_SIN_UPDATE = -1978335189
try {
    $script:mockWingetExit = 5; $script:mockWingetOutput = 'Git.Git error de red'
    Assert (-not (Test-WingetPkg 'Git.Git')) 'winget con error no detecta paquete instalado'
    Assert ((Get-WingetUpdateState 'Git.Git') -eq 'error') 'error de red no informa actualizado'
    $result = @(Install-Winget 'Git.Git' 'Git')
    Assert ($result.Count -eq 1 -and $result[0] -eq $false) 'stdout del instalador no convierte fallo en exito'
    $result = @(Invoke-WingetUpdate 'Git.Git' 'Git')
    Assert ($result.Count -eq 1 -and $result[0] -eq 'error') 'updater propaga error de consulta'
    $script:mockWingetExit = 0; $script:mockWingetOutput = 'Git.Git 2.0 2.1 winget'
    Assert ((Get-WingetUpdateState 'Git.Git') -eq 'update') 'update disponible por ID exacto'
    $result = @(Install-Winget 'Git.Git' 'Git')
    Assert ($result.Count -eq 1 -and $result[0] -eq $true) 'instalacion correcta retorna solo booleano'
    Assert (($script:wingetArgs -contains '--exact') -and ($script:wingetArgs -contains '--source')) 'winget restringe ID y fuente'
    $script:mockWingetOutput = 'GitXGit 2.0 2.1'
    Assert ((Get-WingetUpdateState 'Git.Git') -eq 'error') 'regex no confunde otro identificador'
    $script:mockWingetOutput = ''
    Assert ((Get-WingetUpdateState 'Git.Git') -eq 'error') 'salida vacia no se celebra'
    $script:mockWingetExit = -1978335212
    Assert ((Get-WingetUpdateState 'Git.Git') -eq 'missing') 'inventario ausente no se presenta como al dia'
    $script:mockWingetExit = -1978335189
    Assert ((Get-WingetUpdateState 'Git.Git') -eq 'error') 'codigo de upgrade no se atribuye al inventario list'
    $script:mockWingetExit = 0; $script:mockWingetOutput = 'Git  Git.Git 2.56.0.3'
    $info = Get-WingetPackageInfo 'Git.Git'
    Assert ($info.State -eq 'installed' -and $info.Version -eq '2.56.0.3' -and -not $info.Available) 'fila real de Git actualizado conserva version instalada'
    Assert ((Get-WingetUpdateState 'Git.Git') -eq 'aldia') 'segunda pasada sin columna Available se reconoce al dia'
    Assert (-not ($script:wingetArgs -contains '--source') -and -not ($script:wingetArgs -contains '--upgrade-available')) 'inventario evita filtros que ocultan instalaciones actualizadas'
    $script:mockWingetOutput = 'PowerShell 7.6.9.0-x64 Microsoft.PowerShell 7.6.9.0 winget'
    Assert ((Get-WingetPackageInfo 'Microsoft.PowerShell').Version -eq '7.6.9.0') 'PowerShell registrado sin filtrar fuente se reconoce'
    $script:mockWingetOutput = 'No installed package found matching input criteria.'
    Assert ((Get-WingetUpdateState 'Git.Git') -eq 'error') 'una consulta normal sin fila no inventa version instalada'
    $script:ForjaWingetInventory=$null
    $script:wingetQueue=New-Object 'System.Collections.Generic.Queue[object]'
    $script:wingetQueue.Enqueue(@{Code=-1978335212;Output='No installed package found matching input criteria.'})
    $script:wingetQueue.Enqueue(@{Code=0;Output="Name Id Version Source`r`nPowerShell 7 Microsoft.PowerShell 7.6.9.0 winget"})
    Assert ((Get-WingetPackageInfo 'Microsoft.PowerShell').Version -eq '7.6.9.0') 'inventario general rescata PowerShell oculto por filtro exacto'
    $script:wingetQueue.Enqueue(@{Code=0;Output='Git Git.Git 1.0.0 2.0.0 winget'})
    $script:wingetQueue.Enqueue(@{Code=0;Output='Successfully installed'})
    $script:wingetQueue.Enqueue(@{Code=0;Output='Git Git.Git 2.0.0'})
    Assert ((Invoke-WingetUpdate 'Git.Git' 'Git') -eq 'ok') 'actualizacion confirma version instalada con otra consulta'
    $script:wingetQueue.Enqueue(@{Code=0;Output='Git Git.Git 1.0.0 2.0.0 winget'})
    $script:wingetQueue.Enqueue(@{Code=0;Output='Successfully installed'})
    $script:wingetQueue.Enqueue(@{Code=0;Output='Git Git.Git 1.0.0'})
    Assert ((Invoke-WingetUpdate 'Git.Git' 'Git') -eq 'error') 'exit cero sin version nueva no se presenta como actualizado'


    $script:npmCalls = @(); $script:npmListExit = 1; $script:npmListOutput = 'snyk@1.0.0 error'
    Assert (-not (Test-NpmPkg 'snyk')) 'npm list fallido no marca instalado'
    $script:npmListExit = 0; $script:npmListOutput = 'snyk@1.0.0'
    $script:npmViewExit = 1; $script:npmViewOutput = 'registro caido'
    Assert ((Invoke-NpmUpdate 'snyk' 'Snyk') -eq 'error') 'no instala cuando falla el registro npm'
    Assert (@($script:npmCalls | Where-Object { $_[0] -eq 'install' }).Count -eq 0) 'consulta npm fallida produce cero instalaciones'
    $script:npmViewExit = 0; $script:npmViewOutput = '1.0.0'
    Assert ((Invoke-NpmUpdate 'snyk' 'Snyk') -eq 'aldia') 'version npm igual se saltea'
    $script:npmViewOutput = '2.0.0'; $script:npmInstallExit = 1
    $result = @(Invoke-NpmUpdate 'snyk' 'Snyk')
    Assert ($result.Count -eq 1 -and $result[0] -eq 'error') 'fallo npm preserva estado error'
    Assert ($script:npmCalls[-1] -contains 'snyk@2.0.0') 'instala la version consultada y no una etiqueta mutable'
    $result = @(Install-Npm 'snyk' 'Snyk')
    Assert ($result.Count -eq 1 -and $result[0] -eq $false) 'Install-Npm no oculta fallo si paquete previo sigue presente'
    $script:npmInstallExit=0
    Assert ((Invoke-NpmUpdate 'snyk' 'Snyk') -eq 'error') 'npm exit cero con version previa no afirma actualizacion'

    foreach ($answer in @('','no','salir','si y borrar','yes')) {
        $script:mockAnswer = $answer
        Assert (-not (Ask-SN 'Confirmar')) "respuesta '$answer' no autoriza"
    }
    $script:mockAnswer = ' S '
    Assert (Ask-SN 'Confirmar') 'confirmacion explicita S'

    $script:mockSnykExit = 1
    Assert (-not (Test-SnykAuth)) 'Snyk fallido permanece pendiente'
    $script:mockSnykExit = 0
    $result = @(Test-SnykAuth)
    Assert ($result.Count -eq 1 -and $result[0] -eq $true) 'verificacion Snyk no expone la salida sensible'
    Assert (($script:snykArgs -join ' ') -eq 'whoami --experimental') 'verificacion no lee config api'

    $w1 = New-ForjaWorkspace; $w2 = New-ForjaWorkspace
    Assert ($w1 -ne $w2) 'temporales unicos para ejecuciones concurrentes'
    $outside = Join-Path $sandbox 'outside'
    [IO.Directory]::CreateDirectory($outside) | Out-Null
    $sentinel = Join-Path $outside 'keep.txt'; [IO.File]::WriteAllText($sentinel, 'KEEP')
    Assert-Throws { Remove-ForjaWorkspace $outside } 'no borra un directorio ajeno'
    Assert-Throws { Remove-ForjaWorkspace ([IO.Path]::GetDirectoryName($w1)) } 'no borra la raiz de temporales'
    $junction = Join-Path $w1 'escape'
    New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
    Assert-Throws { Remove-ForjaWorkspace $w1 } 'cleanup rechaza junction antes de borrar'
    Assert (([IO.File]::ReadAllText($sentinel)) -eq 'KEEP') 'archivo externo sigue intacto'
    [IO.Directory]::Delete($junction)
    $brokenTarget = Join-Path $sandbox 'broken-target'
    [IO.Directory]::CreateDirectory($brokenTarget) | Out-Null
    New-Item -ItemType Junction -Path $junction -Target $brokenTarget | Out-Null
    [IO.Directory]::Delete($brokenTarget)
    Assert-Throws { Assert-NoReparsePath $junction } 'rechaza junction incluso con destino inexistente'
    [IO.Directory]::Delete($junction)
    Remove-ForjaWorkspace $w1
    Assert (-not (Test-Path -LiteralPath $w1)) 'borra solo temporal propio validado'

    $source = Join-Path $sandbox 'source'; [IO.Directory]::CreateDirectory($source) | Out-Null
    [IO.File]::WriteAllText((Join-Path $source 'SKILL.md'), '# Credito original')
    [IO.Directory]::CreateDirectory((Join-Path $source 'scripts')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $source 'scripts/example.txt'), 'example')
    $destination = Join-Path $sandbox 'profile\skills'
    Assert (Install-ReviewedSkill $source $destination 'sample' 'Adaptador') 'instala skill completa en ruta nueva'
    Assert ([IO.File]::Exists((Join-Path $destination 'sample\scripts\example.txt'))) 'copia recursos de subcarpetas'
    $before = [IO.File]::ReadAllText((Join-Path $destination 'sample\SKILL.md'))
    Assert ($before.Contains('# Credito original') -and $before.Contains('Adaptada para: Adaptador')) 'conserva autoria y agrega adaptacion'
    Assert (-not (Install-ReviewedSkill $source $destination 'sample' 'Otro')) 'segunda ejecucion no pisa skill'
    Assert (([IO.File]::ReadAllText((Join-Path $destination 'sample\SKILL.md'))) -eq $before) 'contenido existente intacto'
    Assert-Throws { Install-ReviewedSkill $source $destination '..\escape' '' } 'rechaza traversal en nombre de skill'
    Assert-Throws { Install-ReviewedSkill $source $destination 'invalid-adapter' "nombre`ninstruccion" } 'rechaza adaptador multilinea antes de copiar'
    Assert (-not (Test-Path (Join-Path $destination 'invalid-adapter'))) 'entrada invalida no deja skill parcial'
    $junction = Join-Path $source 'linked'
    New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
    Assert-Throws { Install-ReviewedSkill $source $destination 'evil' '' } 'rechaza enlace en recursos de skill'
    Assert (-not (Test-Path (Join-Path $destination 'evil'))) 'skill rechazada no aparece instalada'
    [IO.Directory]::Delete($junction)
    $lock = [IO.File]::Open((Join-Path $source 'SKILL.md'), [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try { Assert-Throws { Install-ReviewedSkill $source $destination 'locked' '' } 'fallo de copia se propaga' }
    finally { $lock.Dispose() }
    Assert (-not (Test-Path (Join-Path $destination 'locked'))) 'fallo a mitad de copia no publica skill parcial'
    $junction = Join-Path $sandbox 'linked-destination'
    New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
    Assert-Throws { Install-ReviewedSkill $source (Join-Path $junction 'skills') 'sample' '' } 'rechaza junction en padres del destino'
    [IO.Directory]::Delete($junction)

    $revision = '1234567890abcdef1234567890abcdef12345678'
    $script:gitCalls = @(); $script:mockGitExit = 1; $script:mockGitHead = $revision
    Assert-Throws { Get-ReviewedSkills 'https://github.com/anthropics/skills.git' $revision $w2 } 'fallo Git detiene instalacion'
    Assert ($script:gitCalls.Count -eq 1) 'no continua checkout despues de init fallido'
    $script:mockGitExit = 0; $script:mockGitHead = ('a' * 40); $script:gitCalls = @()
    Assert-Throws { Get-ReviewedSkills 'https://github.com/anthropics/skills.git' $revision $w2 } 'revision distinta se rechaza'
    $script:mockGitHead = $revision; $script:gitCalls = @()
    $download = Get-ReviewedSkills 'https://github.com/anthropics/skills.git' $revision $w2
    Assert ($download -eq (Join-Path $w2 'repo')) 'revision exacta aceptada'
    $fetch = @($script:gitCalls | Where-Object { $_ -contains 'fetch' })[0]
    Assert (($fetch -contains $revision) -and ($fetch -contains 'protocol.file.allow=never')) 'fetch usa revision fija y bloquea transporte local'
    Assert-Throws { Get-ReviewedSkills 'https://example.com/evil.git' $revision $w2 } 'rechaza proveedor no permitido'
    Assert-Throws { Get-ReviewedSkills 'https://github.com/anthropics/skills.git' 'main' $w2 } 'rechaza rama mutable'
    Remove-ForjaWorkspace $w2
    Assert ($script:ForjaWorkspaces.Count -eq 0) 'no quedan temporales propios tras casos normales y fallidos'

    # Prueba nativa de CMD + Windows PowerShell usando SOLO un payload inerte.
    $special = Join-Path $sandbox "Forja a ' & ! (test) % demo"
    [IO.Directory]::CreateDirectory($special) | Out-Null
    $bat = Join-Path $special 'forja-test.bat'
    $marker = ': end batch / begin PowerShell #>'
    $header = $scriptText.Substring(0, $scriptText.IndexOf($marker) + $marker.Length)
    [IO.File]::WriteAllText($bat, ($header + "`r`nWrite-Output 'LAUNCH_OK'; exit 7`r`n"), (New-Object Text.UTF8Encoding($false)))
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $psi.Arguments = '/d /c ""' + $bat + '""'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $special
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($psi)
    $process.StandardInput.WriteLine(''); $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd(); $stderr = $process.StandardError.ReadToEnd()
    if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Timeout del launcher inerte' }
    Assert ($stdout.Contains('LAUNCH_OK')) 'launcher acepta espacios, apostrofe y metacaracteres de ruta'
    Assert ($process.ExitCode -eq 7) 'BAT conserva exit code del payload'
    Assert ($stderr.Length -eq 0) 'launcher sin errores de parseo nativo'

    Assert ($scriptText -notmatch 'SetEnvironmentVariable|Read-Host[^\r\n]*token|snyk config set|npx -y @modelcontextprotocol') 'sin captura ni persistencia propia de tokens'
    Assert ($scriptText -notmatch 'getadmin\.vbs|forja_setup\.ps1|ExecutionPolicy Bypass|Rename-Item|Start-Process cmd') 'sin bootstrap temporal ni borrados de instalaciones'
    $elevations = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Start-Process' -and $node.Extent.Text -match '-Verb RunAs' }, $true))
    Assert ($elevations.Count -eq 1 -and $elevations[0].Extent.Text.Contains('$wslExe')) 'elevacion limitada a WSL con argumentos fijos'
    $adminGuard = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.IfStatementAst] -and $node.Extent.Text -match '^if \(\$principal.IsInRole' }, $true))
    Assert ($adminGuard.Count -eq 1 -and $adminGuard[0].Extent.Text.Contains('exit 1') -and $adminGuard[0].Extent.StartOffset -lt $scriptText.IndexOf('$modoSel =')) 'guard de administrador detiene el producto antes del menu'
    Write-Host "RESULTADO: $passed PASS / 0 FAIL"
} finally {
    $env:LOCALAPPDATA = $previousLocal
    # Raiz creada exclusivamente por este test, absoluta, con nombre aleatorio comprobado.
    $fullSandbox = [IO.Path]::GetFullPath($sandbox)
    $expectedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($fullSandbox) -eq $expectedParent -and [IO.Path]::GetFileName($fullSandbox) -match '^forja-tests-[0-9a-f]{32}$') {
        # Si un test se interrumpio con una junction, conservar y fallar cerrado.
        $null = @(Get-ForjaTree $fullSandbox)
        Remove-Item -LiteralPath $fullSandbox -Recurse -Force
    }
    foreach ($name in @('winget','npm','git','snyk','Read-Host')) { Remove-Item -LiteralPath "Function:\$name" -ErrorAction SilentlyContinue }
}
