param([string]$FlowCase, [string]$Evidence)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if ($FlowCase) {
    $script:calls = New-Object 'System.Collections.Generic.List[string]'
    $script:answers = 0
    $script:text = [IO.File]::ReadAllText((Join-Path $repoRoot 'forja-del-desarrollador.bat'))
    # Fixture en memoria: CI puede ser administrador. Solo se omite el guard de identidad
    # para recorrer modos con herramientas simuladas. El archivo del producto no se modifica.
    $script:text = $script:text.Replace('if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {', 'if ($false) {')
    $parseErrors=$null; $tokens=$null
    $tree=[Management.Automation.Language.Parser]::ParseInput($script:text,[ref]$tokens,[ref]$parseErrors)
    $runner=$tree.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-ForjaTool' },$true)
    if ($parseErrors.Count -gt 0 -or -not $runner) { throw 'No se pudo aislar la ejecucion de CLIs en la fixture' }
    $script:text=$script:text.Replace($runner.Extent.Text, 'function Invoke-ForjaTool { param([string]$Name) Invoke-FakeTool -Name $Name -Arguments $args }')
    $libraries=$tree.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-ForjaPythonLibraries' },$true)
    if (-not $libraries) { throw 'Falta frontera de librerias Python' }
    $script:text=$script:text.Replace($libraries.Extent.Text, 'function Invoke-ForjaPythonLibraries { param([switch]$Update,[string]$Profile) if ($FlowCase -in @(''setup-fail'',''update-fail'')) { return [pscustomobject]@{ State=''error''; SharedConflict=$false } }; return [pscustomobject]@{ State=''aldia''; SharedConflict=($FlowCase -eq ''python-conflict'') } }')
    $store=$tree.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ForjaStoreApp'},$true)
    $script:text=$script:text.Replace($store.Extent.Text, 'function Get-ForjaStoreApp {param($Tool) return [pscustomobject]@{State=''absent'';Version=$null}}')
    $native=$tree.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ForjaStackCommand'},$true)
    $script:text=$script:text.Replace($native.Extent.Text, 'function Get-ForjaStackCommand {param($Name) return $null}')
    $archive=$tree.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-ForjaArchiveTool'},$true)
    $script:text=$script:text.Replace($archive.Extent.Text, 'function Invoke-ForjaArchiveTool {param($Tool,[switch]$Update) $script:calls.Add((''archive ''+$Tool.Id)); if($Update){return ''saltado''};if($FlowCase -eq ''setup-fail''){return ''error''};return ''ok''}')
    foreach($boundary in @('Invoke-ForjaCommand','Save-ForjaToolArchive')){
        $definition=$tree.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $boundary},$true)
        $script:text=$script:text.Replace($definition.Extent.Text, ('function '+$boundary+' { throw ''PROHIBIDO ejecutar binarios o descargar en estos flujos'' }'))
    }
    if($FlowCase -eq 'fresh-setup'){
        $resolver=$tree.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ForjaToolPath'},$true)
        $script:text=$script:text.Replace($resolver.Extent.Text, 'function Get-ForjaToolPath {param($Name) if($Name -eq ''supabase''){return $null};return ''C:\fixture\tool.cmd''}')
    }
    function global:Clear-Host {}
    function global:Read-Host { param($Prompt)
        $script:answers++
        if ($script:answers -eq 1) {
            switch ($FlowCase) {
                'setup-ok' { return '1' }
                'fresh-setup' { return '1' }
                'stack-selected' { return '1' }
                'setup-fail' { return '1' }
                'update-fail' { return '2' }
                'update-current' { return '2' }
                'cleanup-fail' { return '2' }
                'python-conflict' { return '2' }
                'cancel' { return '1' }
                'diagnostic' { return '3' }
                'project-guide' { return '4' }
                'catalog' { return '5' }
                'catalog-return' { return '5' }
                default { return '' }
            }
        }
        if ($script:answers -eq 2 -and $FlowCase -eq 'catalog-return') { return '0' }
        if ($script:answers -eq 2 -and $FlowCase -ne 'cancel') { return 'S' }
        if ($FlowCase -eq 'cleanup-fail' -and $Prompt -like '*Eliminar la instalacion npm*') { return 'S' }
        if ($FlowCase -eq 'stack-selected' -and ($Prompt -like '*Incluir Codex CLI?*' -or $Prompt -like '*Incluir Flask + OpenCV*' -or $Prompt -like '*Incluir Render CLI*')) { return 'S' }
        return 'N'
    }
    function global:Start-Process { throw 'PROHIBIDO iniciar procesos reales en estos flujos' }
    function global:Test-Path { param([string]$Path,[string]$LiteralPath,[string]$PathType)
        $candidate=$Path; if ($LiteralPath) { $candidate=$LiteralPath }
        if ($FlowCase -eq 'cleanup-fail' -and ($candidate -like '*\npm\claude*' -or $candidate -like '*\.local\bin\claude.exe')) { return $true }
        Microsoft.PowerShell.Management\Test-Path @PSBoundParameters
    }
    function Invoke-FakeTool { param([string]$Name, [object[]]$Arguments)
        $script:calls.Add(($Name + ' ' + ($Arguments -join ' ')))
        $global:LASTEXITCODE = 0
        if ($FlowCase -eq 'cleanup-fail' -and $Name -eq 'npm' -and $Arguments[0] -eq 'uninstall') { throw 'SIMULATED_START_FAILURE' }
        if ($FlowCase -eq 'setup-fail') { $global:LASTEXITCODE = 1; return 'SIMULATED_ERROR' }
        if ($FlowCase -eq 'update-fail') {
            if ($Name -eq 'winget' -and $Arguments[0] -eq 'list' -and $Arguments -notcontains '--disable-interactivity') {
                $i = [array]::IndexOf($Arguments, '--id'); return "$($Arguments[$i+1]) 1.0.0"
            }
            if ($Name -eq 'npm' -and $Arguments[0] -eq 'list') { return "$($Arguments[2])@1.0.0" }
            if ($Name -eq 'cmd' -and ($Arguments -join ' ') -match 'wsl --status') { return '' }
            if ($Name -eq 'pip' -and $Arguments[0] -eq '--version') { return 'pip 24.0' }
            $global:LASTEXITCODE = 5; return 'SIMULATED_ERROR'
        }
        if ($Arguments -contains '--version') { return '1.0.0' }
        switch ($Name) {
            'npm' { if ($Arguments[0] -eq 'list') { return "$($Arguments[2])@1.0.0" }; return '1.0.0' }
            'winget' { $i = [array]::IndexOf($Arguments, '--id'); if ($i -ge 0) { return "$($Arguments[$i+1]) 1.0.0" }; return 'v1.0.0' }
            'git' { return 'fixture identity' }
            'python' { if ($Arguments -contains 'pip') { return 'pip 24.0' }; return 'Python 3.13.0' }
            'pip' { return 'pip 24.0' }
            'netlify' { return 'Logged in' }
            'vercel' { return 'fixture-user' }
            'supabase' { return 'Name ID' }
            'docker' { return 'Server Version: 1.0' }
            default { return '1.0.0' }
        }
    }
    foreach ($name in @('winget','npm','python','pip','git','claude','gh','netlify','vercel','supabase','snyk','docker','wsl','cmd','pwsh','node','pnpm','ffmpeg','mongosh','ollama','code','reg')) {
        $body = 'Invoke-FakeTool -Name ''' + $name + ''' -Arguments $args'
        Set-Item -Path ("Function:global:$name") -Value ([scriptblock]::Create($body))
    }
    try { & ([scriptblock]::Create($script:text)) }
    finally { [IO.File]::WriteAllLines($Evidence, $script:calls.ToArray()) }
    exit 99 # el producto tiene que salir con su propio codigo
}

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('forja-flows-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($sandbox) | Out-Null
$shellExe = (Get-Process -Id $PID).Path
$passed = 0
try {
    foreach ($case in @('setup-ok','fresh-setup','stack-selected','setup-fail','update-fail','update-current','cleanup-fail','python-conflict','cancel','diagnostic','project-guide','catalog','catalog-return','invalid')) {
        $evidencePath = Join-Path $sandbox ($case + '.txt')
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $shellExe
        $psi.Arguments = '-NoProfile -ExecutionPolicy RemoteSigned -File "' + $PSCommandPath + '" -FlowCase ' + $case + ' -Evidence "' + $evidencePath + '"'
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $p = [Diagnostics.Process]::Start($psi)
        $stdoutTask = $p.StandardOutput.ReadToEndAsync(); $stderrTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(30000)) { $p.Kill(); throw "Timeout $case" }
        $stdout = $stdoutTask.Result; $stderr = $stderrTask.Result
        $expected = 0
        if ($case -in @('setup-fail','update-fail','cleanup-fail')) { $expected = 1 }
        if ($p.ExitCode -ne $expected -or $stderr) { throw "$case : exit=$($p.ExitCode) esperado=$expected`n$stderr`n$stdout" }
        $calls = @(Get-Content -LiteralPath $evidencePath)
        if ($case -eq 'project-guide' -and ($calls.Count -gt 0 -or $stdout -notmatch 'STACK POR PROYECTO')) { throw 'La guia de stack debe funcionar sin ejecutar herramientas' }
        if ($case -eq 'stack-selected' -and ($stdout -notmatch 'Codex CLI' -or @($calls | Where-Object {$_ -like '*@openai/codex*'}).Count -eq 0)) { throw 'La seleccion de agentes no recorrio Codex CLI' }
        if ($case -eq 'stack-selected') {
            $summary=($stdout -split 'RESUMEN DE INSTALACION',2)[1]
            if($summary -notmatch '\[OK\]\s+Codex CLI' -or $summary -notmatch '\[OK\]\s+Flask \+ OpenCV' -or $summary -notmatch '\[OK\]\s+Render CLI'){throw 'El resumen no conserva nombre y estado de las herramientas seleccionadas'}
        }
        if($case -eq 'fresh-setup' -and $calls -notcontains 'archive supabase-native'){throw 'No se probo Supabase ausente con el instalador nativo simulado'}
        if ($case -in @('cancel','diagnostic','project-guide','catalog','catalog-return','invalid') -and $calls.Count -ne 0) { throw "$case ejecuto herramientas: $calls" }
        if($case -eq 'catalog' -and ($stdout -notmatch 'CATALOGO COMPLETO' -or $stdout -notmatch 'Cloudflare Wrangler' -or $stdout -notmatch 'Miniforge3')){throw 'Catalogo incompleto o paginacion interrumpida'}
        if($case -in @('catalog','catalog-return') -and @([regex]::Matches($stdout,'FORJA DEL DESARROLLADOR')).Count -ne 2){throw 'El catalogo no regresa al menu principal'}
        if($case -eq 'invalid'){
            $menuLines=@($stdout -split '\r?\n' | Where-Object {$_})
            if(@($menuLines | Where-Object {$_.Length -gt 80}).Count -gt 0 -or $menuLines.Count -gt 26){throw 'El menu principal supera el ancho o alto esperado'}
            foreach($name in @('Cursor','Antigravity','Grok Bot','ChatGPT/Codex','Neon','Resend','Render','Wrangler','PostgreSQL','Miniforge')){if($stdout -notmatch [regex]::Escape($name)){throw "El menu omite $name"}}
        }
        if ($case -eq 'update-fail' -and @($calls | Where-Object { $_ -match '^npm install' }).Count -gt 0) { throw 'Se instalo a pesar de fallar el registro' }
        if ($case -eq 'setup-fail' -and $stdout -notmatch '\[X\]') { throw 'No mostro errores de instalacion' }
        if ($case -eq 'update-current' -and $stdout -notmatch 'instalada: 1.0.0') { throw 'No muestra la version de segunda pasada' }
        if ($case -eq 'cleanup-fail') {
            $uninstall=[array]::FindIndex([string[]]$calls,[Predicate[string]]{ param($line) $line -match '^npm uninstall' })
            $claude=[array]::FindIndex([string[]]$calls,[Predicate[string]]{ param($line) $line -match '^claude update' })
            if ($uninstall -lt 0 -or $claude -le $uninstall -or $stdout -notmatch 'RESUMEN DE ACTUALIZACION') { throw 'No continua al fallar limpieza de Claude' }
        }
        if ($case -in @('update-current','cleanup-fail','python-conflict')) {
            $updated=[regex]::Match($stdout,'Actualizados:\s*(\d+)').Groups[1].Value
            $current=[regex]::Match($stdout,'Ya al dia:\s*(\d+)').Groups[1].Value
            $errors=[regex]::Match($stdout,'Con errores:\s*(\d+)').Groups[1].Value
            $pending=[regex]::Match($stdout,'Pendientes:\s*(\d+)').Groups[1].Value
            $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $repoRoot 'catalog\stack-ia.json')))
            $expectedCurrent=19+@($catalog | Where-Object {$_.Method -in @('winget','npm') -and -not $_.Core}).Count
            if ($updated -ne '0' -or $current -ne [string]$expectedCurrent) { throw "Contadores incorrectos $case : $updated/$current esperado 0/$expectedCurrent" }
            if ($case -eq 'cleanup-fail' -and $errors -ne '1') { throw 'La limpieza fallida no quedo en el resumen' }
            $warnings=[regex]::Match($stdout,'Con avisos:\s*(\d+)').Groups[1].Value
            if ($case -eq 'python-conflict' -and ($pending -ne '0' -or $warnings -ne '1')) { throw 'El conflicto compartido debe quedar como aviso separado, sin afirmar que se reparo' }
        }
        $passed++
        Write-Host "PASS flujo $case / exit $expected / $($calls.Count) invocaciones simuladas"
    }
    Write-Host "RESULTADO FLUJOS: $passed PASS / 0 FAIL"
} finally {
    $full = [IO.Path]::GetFullPath($sandbox)
    $parent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($full) -ne $parent -or [IO.Path]::GetFileName($full) -notmatch '^forja-flows-[0-9a-f]{32}$') { throw 'Raiz de prueba inesperada' }
    # Solo archivos planos creados por este arnes; sin borrado recursivo.
    foreach ($file in @(Get-ChildItem -LiteralPath $full -File)) { Remove-Item -LiteralPath $file.FullName }
    [IO.Directory]::Delete($full)
}
