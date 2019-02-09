#Set versions to building assemblies. Relevant only for old-fasioned projects. 
#New ProjectSDK .csproj's do not use AssemblyInfo.cs anymore, it takes assembly versions as msbuld project parameters.
Get-ChildItem "AssemblyInfo.cs" -Recurse  | % {
    $Content = get-content -Path $_.FullName

    #CalculatedAssemblyVersion
    if ($Content -match '^\[assembly\:\s+AssemblyVersion\(.*?\)\]$'){
        $Content = $Content -replace '\[assembly\:\s+AssemblyVersion\(.*?\)\]', "[assembly: AssemblyVersion(`"%CalculatedAssemblyVersion%`")]"
    }else{
        $Content = $Content += "[assembly: AssemblyVersion(`"%CalculatedAssemblyVersion%`")]"
    }

    #CalculatedAssemblyFileVersion
    if ($Content -match '^\[assembly\:\s+AssemblyFileVersion\(.*?\)\]$'){
        $Content = $Content -replace '\[assembly\:\s+AssemblyFileVersion\(.*?\)\]', "[assembly: AssemblyFileVersion(`"%CalculatedAssemblyFileVersion%`")]"
    }else{
        $Content = $Content += "[assembly: AssemblyFileVersion(`"%CalculatedAssemblyFileVersion%`")]"
    }

    #CalculatedAssemblyInformationalVersion
    if ($Content -match '^\[assembly\:\s+AssemblyInformationalVersion\(.*?\)\]$'){
        $Content = $Content -replace '^\[assembly\:\s+AssemblyInformationalVersion\(.*?\)\]$', "[assembly: AssemblyInformationalVersion(`"%CalculatedAssemblyInformationalVersion%`")]"
    }else{
        $Content = $Content += "[assembly: AssemblyInformationalVersion(`"%CalculatedAssemblyInformationalVersion%`")]"
    }

    Set-Content -Path $_.FullName -Value $Content -Encoding UTF8
    
    }