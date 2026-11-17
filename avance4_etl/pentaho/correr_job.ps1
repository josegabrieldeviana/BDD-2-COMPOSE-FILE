# G8 · Avance 4 · Ejecuta el job j00_cargar_datamart.kjb con Kitchen (sin abrir Spoon).
# Uso:  powershell -ExecutionPolicy Bypass -File correr_job.ps1 [-Archivo t01_dim_tiempo.ktr]
#   sin -Archivo corre el job completo; con un .ktr corre solo esa transformación (Pan).
param([string]$Archivo = "j00_cargar_datamart.kjb", [string]$Nivel = "Basic")
$pdi = "C:\Users\Usuario\pentaho\data-integration"
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:PENTAHO_JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-17.0.17.10-hotspot"
$env:NoDefaultCurrentDirectoryInExePath = $null   # los .bat de PDI llaman a Spoon.bat desde su carpeta
$ruta = Join-Path $aqui $Archivo
New-Item -ItemType Directory -Force (Join-Path $aqui "logs") | Out-Null
$log = Join-Path $aqui ("logs\" + [IO.Path]::GetFileNameWithoutExtension($Archivo) + ".log")
if ($Archivo -like "*.kjb") { $bat = "Kitchen.bat" } else { $bat = "Pan.bat" }
cmd /c "`"$pdi\$bat`" -file=`"$ruta`" -level=$Nivel > `"$log`" 2>&1"
$codigo = $LASTEXITCODE
"$bat terminó con código $codigo · log: $log"
exit $codigo
