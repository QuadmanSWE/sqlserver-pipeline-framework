Write-Host
Write-Host 'You are running the sqlserver project intiation script.'
Write-Host 'This script will ask you for a name and a path, then copy the template project to a new directory in that path, rename everything to your chosen name, and then repoint any references'
Write-Host 'Lastly it will initialize the new git repo, and make the first commit!'
Write-Host
try {
    $UserErrorActionPreference = $ErrorActionPreference
    $resp = Read-Host 'Type Y to continue. By continuing, make sure you have read the documentation, accepted your own liability, and know the jist of what is going to happen on your harddrive. [N]'
    if ($resp -ne 'Y') {
        throw 'User did not accept the terms'
    }

    $reponame = Read-Host -Prompt "Provide a name for your repo"
    $illegal = [Regex]::Escape( -join [System.Io.Path]::GetInvalidFileNameChars())
    $pattern = "[$illegal]"
    if ([string]::IsNullOrWhiteSpace($reponame) -or $reponame -match $pattern) {
        throw "[$reponame] Is not a legal name for your repository"
    }

    #Where this script is running, the root of the template repo
    $currentscriptpath = $MyInvocation.MyCommand.Source | Split-Path -Parent

    #where the user wants their new repo, we suggest the parent of the template root, but they can set whatever they want
    $reporoot = $currentscriptpath | Split-Path -Parent
    $UserInput = Read-Host -Prompt "Provide the root path for your repositories. Leave blank for [$reporoot]"

    if ([string]::IsNullOrWhiteSpace($UserInput) -eq $false) {
        $reporoot = $UserInput
    }

    if (!(test-path $reporoot)) {
        throw 'The directory for your repo is not valid'
    }
    elseif (test-path $reporoot\$reponame ) {
        throw "The file or folder [$reporoot\$reponame] already exists"
    }
    $repopath = "$reporoot\$reponame"
    mkdir $repopath | Out-Null

    $filestoexclude = @('*.jfm','*.dbmdl', '*.sqlproj.user', 'LICENSE', 'README.md','Create Git Repo from Template.ps1')
    $dirstoexclude = @('bin', 'obj')

    $dirfilter = ($dirstoexclude | foreach-object { "\\$_\\" }) -join '|'
    Get-ChildItem $currentscriptpath -Recurse -Exclude ($filestoexclude + $dirstoexclude) | where-object FullName -notmatch $dirfilter  | Copy-Item -Destination { Join-Path $repopath $_.FullName.Substring($currentscriptpath.length) }

    #Make it so
    Set-Location $repopath

    $filesToModify = @(
        ".\Template\Template.sln",
        ".\Template\Template.sqlproj",
        ".\Template_Tests\Template_Tests.sqlproj",
        ".\Template_DbUp\program.cs",
        ".\Template.Build.ps1",
        ".\bootstrap.ps1"
    )
    if (test-path $filesToModify) {
        foreach ($file in $filesToModify) {
            (Get-Content $file) -replace 'Template', $reponame | Set-Content $file
        }
    }

    $ItemsToRename = @(
        ".\Template\Template.sln",
        ".\Template\Template.sqlproj",
        ".\Template_Tests\Template_Tests.sqlproj",
        ".\Template_DbUp\Template_DbUp.csproj",
        ".\Template",
        ".\Template_Tests",
        ".\Template_DbUp",
        ".\Template.Build.ps1"
        
    )
    if (test-path $ItemsToRename) {
        foreach ($item in $ItemsToRename) {
            $newitemName = (Get-Item $item | select-object -ExpandProperty Name) -replace 'Template', $reponame
            Rename-Item -Path $item -NewName $newitemName
        }
    }

    #let there be git
    git init
    git add .
    git commit -m "Copied from https://github.com/QuadmanSWE/sqlserver-pipeline-framework"
    Write-Host 'Repo cloning successful!'
    Write-Host 'To start developing run .\bootstrap.ps1 in your new repo.'
}

catch {
    if($repopath){
        if(test-path $repopath){
            remove-item $repopath -Recurse
        }
    }
    Write-Error -ErrorRecord $_ -ErrorAction $UserErrorActionPreference
}
finally {
    Write-Host -NoNewLine 'Press any key to exit...';
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
}

