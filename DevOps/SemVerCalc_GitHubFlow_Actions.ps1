#requires -version 5
<#
.SYNOPSIS
Скрипт калькуляции версии для GitHubFlow(?). В master всегда стабильный код. Версия обозначается тегами на master.
.NOTES
Author: Anton Smolkov - https://github.com/AnSmol
.DESCRIPTION
 Алгоритм калькуляции:
* Ветка master - взять теги с версиями, которые доступны по истории и выбрать наивысший по значению. Присвоить версию тега, в patch-часть версии указать количество коммитов от текущего коммита до тега с версией.
* Прочие ветки - взять теги с версиями, которые доступны по истории и выбрать наивысший по значению. 
  Найти общего предка (merge-base) с master, посчитать количество коммитов от этого общего предка до до тега с версией. Это количество использовать в patch-части версии.
  Добавить Пре-релизный тег(хвост версии) построенный по маске ИмяВетки.sha.ShortCommitSha

#>

#Настроить среду для корректного отображения вывода git-bash
$env:LC_ALL = 'C.UTF-8'
[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding("utf-8")


$CurrentBranchName = (git branch | where {$_.trim().startswith('*')}).trimstart('*').trim()
$CurrentCommit = git rev-parse HEAD

echo $CurrentBranchName 

$CurrentCommitShort = $CurrentCommit.Substring(0,7)

#Приведем имя теги в пригодный для использоваия в версии вид
$MangledBranchName = $CurrentBranchName
if ($MangledBranchName -cmatch '^((pre-)?release)-\d+\.\d+$') {$MangledBranchName = "$($Matches.1)"}
if ($MangledBranchName -cmatch 'pull\/(\d+)\/merge') {$MangledBranchName = "PR-$($Matches.1)"}
if ($MangledBranchName -cmatch '^\(-)?(HEAD detached at \w+\)$') {$MangledBranchName = 'DetachedHead'}
$MangledBranchName = ($MangledBranchName -replace '[^a-zA-Z0-9-]', '-')


#Находим все версионные теги (теги - источники версий),записываем в массив Имятега:ОбъектВерсии сортируем по убыванию объекта версии.
#Простая сортировка строк с именами версий не сработала бы. При такой сортировке, например,  версия 2.0.0 оказывалась бы выше версии 10.0.0 просто из-а того, что первая цифра в строке больше.
    
$VersionFromTag = git tag --list 'v*' --merged | % {$_.trimstart('*').trim()} | ? {$_ -cmatch '^v(?<Major>\d+)\.?(?<Minor>\d+)?\.?(?<Patch>\d+)?$'} | `
    select  @{n = 'TagName'; e = {$_}}, @{n = 'BaseVersion'; e = {[System.Version]("$([int]$Matches.Major).$([int]$Matches.Minor).$([int]$Matches.Patch)")}} | `
    Sort-Object BaseVersion -Unique -Descending | select -First 1
    
if ($VersionFromTag -ne $null) {
    $BaseVersion = $VersionFromTag.BaseVersion    
    #Master - версия из доступного тега с наивысшим значением версии, нет хвоста версии, cчетчик коммитов до версионного тега помещается в Patch часть версии.
    if ($CurrentBranchName -cmatch '^master$') {
        $CommitsCounter = git rev-list --count "$CurrentCommit" "^$($VersionFromTag.TagName)"
        $($BaseVersion.GetType().GetField('_Build', 'static,nonpublic,instance')).setvalue($BaseVersion, [int32]$CommitsCounter)
        $CalculatedNugetVersion = [string]$BaseVersion
        Write-Output "::debug::master branch has been found. Version will be taken from version tag, version tail(semver pre-release-tag) will be erased. Commit count sinse merge-base with version tag, will be putted into patch-part of version"
        #Feature-ветки - счетчик билдов
 
    #Фича-ветки - Хвост из имени ветки и счетчика билдов. В path-части счетчик коммитов от merge-base с мастер до версионного тега.
    }else {
        #Количество коммитов от merge-base с master до тега с версией. Бампинг path-части.
        $CommonAnchestorWithMaster = git merge-base origin/master $CurrentCommit
        $CommitsCounter = git rev-list --count "$CommonAnchestorWithMaster" "^$($VersionFromTag.TagName)"
        $($BaseVersion.GetType().GetField('_Build', 'static,nonpublic,instance')).setvalue($BaseVersion, [int32]$CommitsCounter)
        $CalculatedNugetVersion = "$($BaseVersion.Major).$($BaseVersion.Minor).$($BaseVersion.Build)-$MangledBranchName.Sha.$CurrentCommitShort"
        Write-Output "::debug::Feature branch has been found. Version will be taken from the past closest version tag, version tail(semver pre-release-tag) will contain branch name and build counter"
    }
} else {
    #Fallback-версия и счетчик коммитов
    $BaseVersion = [version]'0.1.0'
    $CommitsCounter = '0'
    $CalculatedNugetVersion = "$($BaseVersion.Major).$($BaseVersion.Minor).$($BaseVersion.Build)-$MangledBranchName.Sha.$CurrentCommitShort"
}

#Согласно Best-Practics, AssemblyVersion всегда с нулевым Patch. Для взаимозаменяемости сборок с незначительными изменениями.
$CalculatedAssemblyVersion = "$($BaseVersion.Major).$($BaseVersion.Minor)"
$CalculatedAssemblyFileVersion = "$($BaseVersion.Major).$($BaseVersion.Minor).$($BaseVersion.Build)"
$CalculatedAssemblyInformationalVersion = "$CalculatedNugetVersion.$CommitsCounter+Branch.$CurrentBranchName.Sha.$CurrentCommit"

#Выставить параметры с версиями в GitHub Actions
Write-Host "::set-output name=calculated_nuget_version::$CalculatedNugetVersion"
Write-Host "::set-output name=calculated_assembly_version::$CalculatedAssemblyVersion"
Write-Host "::set-output name=calculated_assembly_file_version::$CalculatedAssemblyFileVersion"
Write-Host "::set-output name=calculated_assembly_informational_version::$CalculatedAssemblyInformationalVersion"

Write-Host "::set-output name=calculated_version::$CalculatedNugetVersion"

