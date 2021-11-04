$sapassword = read-host -Prompt 'Enter sa password for DEV (will be stored in plain text)'
$sqlcred = new-object pscredential -ArgumentList 'sa', ($sapassword | ConvertTo-SecureString -AsPlainText -Force)
$dbname = 'Template'
$s = @{
    SqlInstance = 'localhost,<sqlextport>'
    SqlCredential = $sqlcred
    DatabaseName = $dbname
}
$s | Export-Clixml .\settings.xml
$sapassword | out-file 'sapassword.env'