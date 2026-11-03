param(
    [string]$BundleDirectory = (Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\build\windows-distribution')
)

$ErrorActionPreference = 'Stop'
$bundle = (Resolve-Path -LiteralPath $BundleDirectory).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
if ($output.Equals($bundle, [StringComparison]::OrdinalIgnoreCase) -or
    $output.StartsWith($bundle + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw '输出目录不能放在待打包目录内。'
}
foreach ($item in @('bobomusic.exe', 'flutter_windows.dll', 'data\icudtl.dat', 'data\flutter_assets', 'data\app.so')) {
    if (-not (Test-Path -LiteralPath (Join-Path $bundle $item))) { throw "缺少发布文件：$item；请先由所有者完成 Release 构建。" }
}
$versionLine = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\pubspec.yaml') | Where-Object { $_ -match '^version:\s*(\S+)\s*$' } | Select-Object -First 1
if (-not $versionLine -or $versionLine -notmatch '^version:\s*([0-9A-Za-z.+-]+)\s*$') { throw '无法读取版本号。' }
$version = $Matches[1]
New-Item -ItemType Directory -Path $output -Force | Out-Null
$archive = Join-Path $output "bobomusic-$version-windows-x64.zip"
if (Test-Path -LiteralPath $archive) { throw "文件已存在，请换输出目录或由所有者处理旧产物：$archive" }

# 打包整个运行目录；单独分发 exe 会缺失 Flutter、解码器和插件 DLL。
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($bundle, $archive, [IO.Compression.CompressionLevel]::Optimal, $false)
$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $([IO.Path]::GetFileName($archive))" | Set-Content -LiteralPath "$archive.sha256" -Encoding ascii
Write-Output "便携包：$archive"
Write-Output "SHA256：$hash"
