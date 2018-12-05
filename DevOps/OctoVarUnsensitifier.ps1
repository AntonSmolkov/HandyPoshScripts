#Requires -Version 5.0
#Requires -PSEdition Desktop
<#
.SYNOPSIS
  Decript sensitive values of octopus varibles.
.DESCRIPTION
  This script gets encryted values of variables from database, decrypts them with master-key, push variables back via REST API (for consistency).
  Don't forget to make database backup/snapshot before run.
.EXAMPLE
Unsensitify ALL sensitive variables in ALL projects and library variable sets.
.\OctoVarUnsensitifier.ps1 -OctoMasterKey 'sdflaj84hjlsd==' -OctoDbConnectionString 'Data Source=srv-sql-01;integrated Security=False;User ID=octopus_user;Password=octopus_password;Initial Catalog=Octopus;TrustServerCertificate=True' -OctoApiKey 'API-XSD9MSDKLFJSDLKFLSFSDFS84' -OctoApiUri 'https://myocto.org.su/'
Unsensitify ALL sensitive variables in variable set FancyLibraryVariableSet1 and project FancyProject1.
.\OctoVarUnsensitifier.ps1 -OctoTargetVariableSetsAndOrProjectsNames 'FancyLibraryVariableSet1', 'FancyProject1' -OctoMasterKey 'sdflaj84hjlsd==' -OctoDbConnectionString 'Data Source=srv-sql-01;integrated Security=False;User ID=octopus_user;Password=octopus_password;Initial Catalog=Octopus;TrustServerCertificate=True' -OctoApiKey 'API-XSD9MSDKLFJSDLKFLSFSDFS84' -OctoApiUri 'https://myocto.org.su/'
Unsensitify all sensitive variables with names 'VariableOne' or 'VariableTwo' in variable set FancyLibraryVariableSet1 and project FancyProject1.
.\OctoVarUnsensitifier.ps1 -OctoTargetVariableSetsAndOrProjectsNames 'FancyLibraryVariableSet1', 'FancyProject1' -OctoTargetVariablesNames 'VariableOne', 'VariableTwo' -OctoMasterKey 'sdflaj84hjlsd==' -OctoDbConnectionString 'Data Source=srv-sql-01;integrated Security=False;User ID=octopus_user;Password=octopus_password;Initial Catalog=Octopus;TrustServerCertificate=True' -OctoApiKey 'API-XSD9MSDKLFJSDLKFLSFSDFS84' -OctoApiUri 'https://myocto.org.su/' 
Unsensitify sensitive variables with names 'VariableOne' or 'VariableTwo' in ALL variable sets.
.\OctoVarUnsensitifier.ps1 -OctoTargetVariablesNames 'VariableOne', 'VariableTwo' -OctoMasterKey 'sdflaj84hjlsd==' -OctoDbConnectionString 'Data Source=srv-sql-01;integrated Security=False;User ID=octopus_user;Password=octopus_password;Initial Catalog=Octopus;TrustServerCertificate=True' -OctoApiKey 'API-XSD9MSDKLFJSDLKFLSFSDFS84' -OctoApiUri 'https://myocto.org.su/'
.NOTES
    Author: Anton Smolkov
    Date:   December 05, 2018
Decryption function is based on this linqpad snippet - https://github.com/ronnieoverby/linqpad-utils/blob/master/octopus%20sensitive%20variables.linq
#>

[CmdletBinding()]
   param(
    [Parameter(Mandatory=$true)]
    [String]$OctoMasterKey,

    [Parameter(Mandatory=$true)]
    [String]$OctoDbConnectionString,

    [Parameter(Mandatory=$true)]
    [String]$OctoApiKey,

    [Parameter(Mandatory=$true)]
    [String]$OctoApiUri,

    [Parameter(Mandatory=$false)]
    [String[]]$OctoTargetVariableSetsAndOrProjectsNames,

    [Parameter(Mandatory=$false)]
    [String[]]$OctoTargetVariablesNames
  )


$ErrorActionPreference = "Stop"



[byte[]]$OctoMasterKey = [Convert]::FromBase64String($OctoMasterKey)

#Helper functions
function DecodeSensitive ($EncodedValue) {
    #This function is based on https://github.com/ronnieoverby/linqpad-utils/blob/master/octopus%20sensitive%20variables.linq
    $Cipher = [Convert]::FromBase64String($EncodedValue.Split('|')[0])
    $Salt = [Convert]::FromBase64String($EncodedValue.Split('|')[1])
    
    # Create AesCryptoServiceProvider, put key and salt to it, extract decryptor
    [System.Security.Cryptography.AesCryptoServiceProvider]$Algorithm = [System.Security.Cryptography.AesCryptoServiceProvider]::new()
    $Algorithm.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $Algorithm.KeySize = 128
    $Algorithm.Key = $OctoMasterKey
    $Algorithm.BlockSize = 128
    $Algorithm.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $Algorithm.IV = $Salt
    $Decryptor = $Algorithm.CreateDecryptor()

    # New memory stream, decoded value will be putten in there
    $MemoryStream = [IO.MemoryStream]::new()
  
    # Create new CryptoStream from MemoryStream, put encoded value(cipher) and decryptor in there, exctract decrypted value.
    $CryptoStream = [Security.Cryptography.CryptoStream]::new($MemoryStream, $Decryptor, 'Write') 
    $CryptoStream.Write($Cipher, 0, $Cipher.Length);
    try {
        $CryptoStream.FlushFinalBlock()
    }
    catch {Write-Error "Can't decode value. Probably the master-key is wrong."}
    
    $DecryptedValue = [System.Text.UTF8Encoding]::UTF8.GetString($MemoryStream.ToArray())
    
    #Clean up the memory
    $MemoryStream.Close()  
    $CryptoStream.Close() 
    $Decryptor.Dispose() 
    $Algorithm.Clear() 

    return $DecryptedValue 
}

function Invoke-SQL {
    param(
        [Parameter(Mandatory = $true)]
        [string] $query
    )
    $Connection = new-object system.data.SqlClient.SQLConnection($OctoDbConnectionString)
    $Command = new-object system.data.sqlclient.sqlcommand($query, $connection)
    $Command.CommandTimeout = 45000
    $Connection.Open()
    $Adapter = New-Object System.Data.sqlclient.sqlDataAdapter $command
    $Dataset = New-Object System.Data.DataSet
    $Adapter.Fill($dataSet) | Out-Null

    $Connection.Close()
    return @($DataSet.Tables)
}


$SqlQuery = @"
select vs.Id as Id, vs.OwnerID as OwnerID, owners.name as OwnerName, vs.JSON as VarSetJson from VariableSet vs 
inner join (select id, name from Project UNION select id, name from LibraryVariableSet) owners on vs.OwnerId=owners.Id
where  vs.IsFrozen='FALSE' AND vs.JSON like '%"Sensitive"%'
"@

#Append additional condition to sql query if OctoTargetVariableSetsAndOrProjectsNames parameter exists
if ($OctoTargetVariableSetsAndOrProjectsNames -ne $null) {
    $OctoTargetVariableSetsAndOrProjectsNames = $OctoTargetVariableSetsAndOrProjectsNames | % {"'$_'"}
    $SqlQuery += " AND owners.name in `($($OctoTargetVariableSetsAndOrProjectsNames -join ',')`)"
}

#Get variable sets with encrypted values of sensitive variables from databases
#This information can't be gathered via REST-API
$VariableSetSqlEntries = Invoke-Sql -Query $SqlQuery


#Iterate over variables sets gathered from database, decrypt necessary variables, push changed variable sets via rest API
foreach ($VariableSetSqlEntry in $VariableSetSqlEntries) {
    #Get JSON field of SQL entry and convert it to object
    $VariableSetObj = $VariableSetSqlEntry.VarSetJson | ConvertFrom-Json

    #Write variables objects, that were obtained from database and will be unsensitive, to array
    $VariableObjectsToUnsensitive = @()
    $VariableObjectsToUnsensitive += $VariableSetObj.Variables | where {$_.Type -eq 'Sensitive'}
    
    #Filter only required ones if filter array exists
    if ($OctoTargetVariablesNames -ne $null) {
        $VariableObjectsToUnsensitive = $VariableObjectsToUnsensitive | where {$OctoTargetVariablesNames -contains $_.name} 
    }

    #Fill hashtable with variable id and unencrypted value
    $UnsensitifiedVariablesHT = @{}
    $VariableObjectsToUnsensitive | % {
        $UnsensitifiedVariablesHT.Add($_.id, $(DecodeSensitive -EncodedValue $_.Value))
        echo "Variable `'$($_.Name)$($_.Scope | ConvertTo-Json -Depth 99 -Compress)`' from set `'$($VariableSetSqlEntry.OwnerName)`($($VariableSetSqlEntry.Id)`)`' has been unsensitified."
    }

  
    #To gather maximum consistensy, behave just like a browser does.
    #Use api call to get actual state of variable set, replace sensistive variables to unsesitive ones, push variable set back to API
    $RestHeaders = @{
        "X-Octopus-ApiKey" = "$OctoApiKey"
        "Content-Type"     = "application/json"
        "Accept"           = "application/json"
        "User-Agent"       = "PowerShell octopus variables unsensitifier"
    }
    $RestUri = "$OctoApiUri/api/variables/$($VariableSetSqlEntry.Id)"
    $VariableSetRestResource = Invoke-RestMethod -Headers $RestHeaders -Uri $RestUri  -Method Get -UseBasicParsing 
    
    if ($UnsensitifiedVariablesHT.count -gt 0) {
        #Get unsensistified values by id from $UnsensitifiedVariablesHT hashtable, and put it to the  
        $VariableSetRestResource.Variables | % {
            if ($UnsensitifiedVariablesHT.ContainsKey($_.id)) {
                $_.Value = $UnsensitifiedVariablesHT[$_.id]
                $_.Type = 'String' 
                $_.IsSensitive = $false
            } }
        $ChangedVariableSetRestBody = $($VariableSetRestResource|ConvertTo-Json -Depth 99)
        Invoke-RestMethod -Headers $RestHeaders -Uri $RestUri -Method Put -Body $ChangedVariableSetRestBody -UseBasicParsing | Out-Null
        echo "#############`r`n'$($VariableSetSqlEntry.OwnerName)' have been sucessfully saved via REST API.`r`n#############"
    }

}
