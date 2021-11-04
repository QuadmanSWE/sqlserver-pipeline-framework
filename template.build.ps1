#Requires -Module invokebuild, dbatools
<#
.EXAMPLE
# Creates the database installation/update exe file
PS C:\repos\Template> Invoke-Build CreateOutput

.EXAMPLE
# Sets up the sql server development environment on docker
PS C:\repos\Template> Invoke-Build Up

.EXAMPLE
# Incrementally deploys the project on the dev environment
PS C:\repos\Template> Invoke-Build Deploy

.EXAMPLE
# Recreates the entire solution from scratch on the dev environment
PS C:\repos\Template> Invoke-Build refresh -Force
#>
param(
    [Parameter()][string]$DbUpRuntime = 'win-x64',
    [Parameter()][ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [ValidateSet('quiet', 'minimal', 'normal', 'detailed', 'diagnostic')][string]$Verbosity = 'minimal',
    [switch]$Force,
    [Parameter()][string]$settingsfile = '.\settings.xml'
)
try {
    if (Test-Path $settingsfile) {
        $settings = Import-Clixml $settingsfile
        $settingsFromFile = $true
    }
    else {
        throw
    }
}
catch {
    Write-Warning "Could not read settings from file [$settingsfile]"
    $settingsFromFile = $false
}

$rootdir = git rev-parse --show-toplevel
$outputdir = "$rootdir\output"
$slnpath = "$rootdir\Template\Template.sln"
$dbupdir = "$rootdir\Template_DbUp"
$unittestProjPath = "$Rootdir\Template_Tests\Template_Tests.sqlproj"
$dotnetVersion = 'netcoreapp3.1'
$DbUpPublishDir = "$dbupdir\bin\$Configuration\$dotnetVersion\$DbUpRuntime\publish\"
$TestResultsDir = "$outputdir\Tests"

Set-Alias MSBuild (Resolve-MSBuild)

#Region sql server on docker

task Up {
    docker-compose up -d --remove-orphans
}

task Down {
    docker-compose down
}

#endregion

#Region Dev database

task RemoveDevDatabase -If ($Force -and $settingsFromFile) {
    Remove-DbaDatabase -SqlInstance $settings.SqlInstance -SqlCredential $settings.SqlCredential -Database $settings.DatabaseName
}

task CreateDevDatabase -If ($settingsFromFile) RemoveDevDatabase, {
    if (Get-DbaDatabase -SqlInstance $settings.SqlInstance -SqlCredential $settings.SqlCredential -ExcludeSystem -Database $settings.DatabaseName) {
        Write-Warning 'Database already exists, use -Force to recreate (the old one will be permanently removed)'
    }
    else {
        New-DbaDatabase -SqlInstance $settings.SqlInstance -SqlCredential $settings.SqlCredential -Name $settings.DatabaseName
    }
}

#EndRegion

#Region building artifacts

task Clean {
    if (Test-Path $outputdir) {
        Remove-Item $outputdir -Recurse -Force | Out-Null
    }
    dotnet clean $dbupdir --configuration $Configuration
}

task OutputDir {
    if (-not (Test-Path $outputdir)) {
        New-Item -Path $outputdir -ItemType Directory | Out-Null
    }
}


task GetDependencies {
    dotnet restore $slnpath -v $Verbosity
}

task Build Clean, GetDependencies, {
    exec { MSBuild $slnpath /t:Rebuild /p:Configuration=$Configuration /v:$Verbosity }
    dotnet publish $dbupdir --configuration $Configuration --self-contained true --runtime $DbUpRuntime -p:PublishSingleFile=true -v $Verbosity
}

#Creates all files required to set up the solution on any sql server
task CreateOutput Clean, Build, OutputDir, {
    $DbUpExePath = Get-ChildItem $DbUpPublishDir -Filter '*.exe' | Select-Object -ExpandProperty FullName
    Copy-Item -Path $DbUpExePath -Destination $outputdir
}

task CopyDacpac Build, OutputDir, {
    Copy-Item -Path "$Rootdir/Template/bin/$Configuration/*.dacpac" -Destination $outputdir
}

task CompareDbUpWithDacpac -If ($settingsFromFile) {
    $DbUpExePath = Get-ChildItem $DbUpPublishDir -Filter '*.exe' | Select-Object -ExpandProperty FullName
    $dacpacpath = Get-Item "$Rootdir/Template/bin/$Configuration/*.dacpac" | Select-Object -First 1 -ExpandProperty FullName
    New-Item -ItemType Directory -Path "$outputdir/TEMP" | out-null
    $TempDir = resolve-path  "$outputdir/TEMP" | Select-Object -ExpandProperty Path

    try {        
        $dbname = "DbUpTest"
        $sqlparams = @{SqlInstance = $settings.SqlInstance; Database = $dbname; SqlCredential = $settings.SqlCredential}

        New-DbaDatabase @sqlparams
        $connectionstring = New-DbaConnectionString @sqlparams -ApplicationIntent ReadWrite -ClientName 'Template.build.ps1 - CompareDbUpWithDacpac' -Legacy
        $DbUpExePath = Get-ChildItem $DbUpPublishDir -Filter '*.exe' | Select-Object -ExpandProperty FullName
        & $DbUpExePath $connectionstring

        Start-Job -ArgumentList $sqlparams, $dacpacpath, $TempDir {
            param ($sqlparams, $dacpacpath, $TempDir)
            $options = New-DbaDacOption -Type Dacpac -Action Publish
            Publish-DbaDacPackage @sqlparams -Path $dacpacpath -DacOption $options -OutputPath $TempDir -ScriptOnly -GenerateDeploymentReport
        } | Wait-Job | Receive-Job 
            
        $deploymentreport = Get-ChildItem $TempDir -Filter "*$($sqlparams.Database)*DeploymentReport*.xml" | Select-Object -ExpandProperty FullName
        $operations = Select-Xml -Path $deploymentreport -XPath "/*[local-name() = 'DeploymentReport']/*[local-name() = 'Operations']"
            
        if ($operations.Count -gt 0) {
            "descrepencies:"
            $operations.Node.InnerXml
            exit(1)
        }
        else {
            "Upgrade scripts valid!"
        }
    }
    catch {
        Write-Error -ErrorRecord $_
    }
    finally {
        Remove-Item $TempDir -Recurse -Force -ea 0
        Remove-DbaDatabase @sqlparams -Confirm:$false
    }
}

task tsqlt -If ($settingsFromFile)  {
    #rewrite publish profile for our settings
    $publishfilename = 'Template.UnitTests.publish.xml'
    $sqlparams = @{SqlInstance = $settings.SqlInstance; SqlCredential = $settings.SqlCredential}
    $connectionstring = New-DbaConnectionString @sqlparams -ApplicationIntent ReadWrite -ClientName 'Template.build.ps1 - CompareDbUpWithDacpac' -Legacy
    $publishprofilepath = "$($unittestProjPath | Split-Path -Parent)\$publishfilename"
    [xml]$publishprofile = get-content $publishprofilepath
    $publishprofile.Project.PropertyGroup.TargetConnectionString = $connectionstring
    $publishprofile.Save($publishprofilepath)

    #run the tsqlt project with the new publish profile
    exec { MSBuild $unittestProjPath `
         /t:Publish `
         /p:SqlPublishProfilePath=$publishfilename `
         /p:Configuration=$Configuration `
         /v:$Verbosity
    }
}

task formatTestOutput {
    exec {
        New-Item -Path $TestResultsDir -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
        $sqlparams = @{SqlInstance = $DatabaseTestSqlInstance; Database = "Template_UnitTests"; }
        Invoke-DbaQuery @sqlparams -Query 'EXEC tSQLt.XmlResultFormatter' -As SingleValue | Out-File "$TestResultsDir/TEST-Template_Database.xml"
    }
}


#EndRegion


#run incremental update to the target sql server database.
task Deploy -If ($settingsFromFile) Build, {
    if (Get-DbaDatabase -SqlInstance $settings.SqlInstance -SqlCredential $settings.SqlCredential -ExcludeSystem -Database $settings.DatabaseName) {    
        $connectionstring = New-DbaConnectionString -SqlInstance $settings.SqlInstance -Credential $settings.SqlCredential -Database $settings.DatabaseName -ApplicationIntent ReadWrite -ClientName 'Template.build.ps1 - Deploy' -Legacy
        $DbUpExePath = Get-ChildItem $DbUpPublishDir -Filter '*.exe' | Select-Object -ExpandProperty FullName
        & $DbUpExePath $connectionstring
    }
    else {
        'Create the dev database first and write your settings to settings.xml'
    }
}

#create migration style sql upgrade script
task NewSqlFile {
    $userinput = Read-Host -Prompt 'Enter file description'
    $filename = (Get-Date -Format yyyyMMdd_HHmmss_) + $userinput.Replace(' ', '_') + '.sql'
    New-Item -Path "$dbupdir\SchemaMigration" -Name $filename -Value "-- $userinput"
}

#drops database, creates database, builds, and deploys the entire solution, validating that it can be deployed and lets you verify the application.
task refresh RemoveDevDatabase, CreateDevDatabase, Deploy

#Run database tests, this validates that the database code adheres to business rules.
task Test Clean, Build, tsqlt, formatTestOutput

#validates migration scripts, this validates the schema integrity of the current database before leaving development.
task DbUpValidation Clean, Build, CompareDbUpWithDacpac

#default, starts sql server on docker.
task . Up