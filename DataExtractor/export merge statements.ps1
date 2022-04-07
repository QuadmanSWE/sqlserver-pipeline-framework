param(
    [Parameter()][string]$SqlInstance = 'localhost',
    [Parameter()][string]$Database = 'Template',
    [Parameter()][pscredential]$SqlCredential,
    [Parameter()][string[]]$TableFilters,
    [switch]$Updates
)
Push-Location $PSScriptRoot
$targetdir = ".\exported"
Get-ChildItem $targetdir | Remove-Item | Out-Null 
mkdir "$targetdir" -Force | Out-Null

$sp = @{
    sqlinstance = $SqlInstance
    Database = $DatabaseName
}

if($SqlCredential){
    $sp += @{
        SqlCredential = $SqlCredential
    }
}

#add the proc that exportd mergestatement for one table
Invoke-DbaQuery @sp -File ".\create usp_Generate_Merge_For_Table.sql"

#get list of tables in order of data insertion required to run against the procedure
$i = 0
$cursor = Invoke-DbaQuery @sp -File  ".\table cursor.sql" -As DataTable
:cur foreach($t in $cursor){
    if($null -ne $TableFilters){
        if(-not ($TableFilters | Where-Object {$t.TableName -like $_})){
            continue cur;
        }
    }
    $i++;
    #arguments for the procedure
    $params = @{
        CurrTable = $t.TableName
        CurrSchema = $t.SchemaName
        delete_unmatched_rows = 0
        update_existing_rows = [bool]($Updates)
        insert_new_rows = 1
        debug_mode = 0
        include_timestamp = 0
        ommit_computed_cols = 1
        top_clause = 'TOP 100 PERCENT'
    }
    #set file name so that scripts run in the correct order and end up in the target dir
    $filename = "$targetdir\{0:d3}_$($t.SchemaName).$($t.TableName).sql" -f $i
    invoke-dbaquery @sp -CommandType StoredProcedure -Query 'dbo.usp_Generate_Merge_For_Table' -SqlParameters $params -As SingleValue | Out-File $filename -Encoding utf8
}

Pop-Location