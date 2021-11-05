<#
.EXAMPLE
PS C:\repos\Template> .\bootstrap.ps1
#>
$requiredmodules = @(
    [PSCustomObject]@{
        Name    = 'dbatools'
        Version = [version]'1.1.31'
    },
    [PSCustomObject]@{
        Name    = 'invokebuild'
        Version = [version]'5.8.4'
    }
)
[int]$newmodules = 0
foreach ($m in $requiredmodules) {
    if (Get-Module -ListAvailable -Name $m.Name | ? {$_.Version -eq $m.Version}) {
        import-module $m.Name -RequiredVersion $m.Version
        write-host "Module [$($m.Name), version $($m.Version)] loaded" -ForegroundColor Green
    } 
    else {
        $newmodules++
        Install-Module $m.Name -RequiredVersion $m.Version
        write-host "Module [$($m.Name), version $($m.Version)] installed" -ForegroundColor Cyan
    }
}
if ($newmodules -gt 0) {
    Write-Host 'Restart your IDE and run again to make sure modules are properly available'
}
else {
    Push-Location .\Template_DbUp
    dotnet restore -v m #restore dotnet libraries required for dbup
    if( -not (Test-Path .\SchemaMigration)){
        New-Item -ItemType Directory -Name SchemaMigration
    }
    Pop-Location
    Push-Location .\Template_Tests
    if( -not (Test-Path .\Template.UnitTests.publish.xml)){
@"
<?xml version="1.0" encoding="utf-8"?>
<Project ToolsVersion="Current" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
    <IncludeCompositeObjects>True</IncludeCompositeObjects>
    <TargetDatabaseName>Template_UnitTests</TargetDatabaseName>
    <DeployScriptFileName>Template.UnitTests.sql</DeployScriptFileName>
    <TargetConnectionString></TargetConnectionString>
    <ProfileVersionNumber>1</ProfileVersionNumber>
    </PropertyGroup>
</Project>
"@ | Out-File .\Template.UnitTests.publish.xml
    }
    Pop-Location
    Write-Host 'Ready -- All nuget packages restored and all powershell modules are available'
}

