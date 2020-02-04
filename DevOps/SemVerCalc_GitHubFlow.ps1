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
  Добавить Пре-релизный тег(хвост версии) построенный по маске ИмяВетки-СчетчикБилдовИзTeamCity

Для использования в хвосте версии, из названий веткой удаляются недопустимые символы.
Если в хвосте версии используется счетчик коммитов, счетчик обозначается префиксом - 'c', если счетчик билдов TeamCity - 'b'.
#>


#%teamcity.git.fetchAllHeads% - плейсхолдер делающий обязательным параметр в TeamCity. Параметр создает локальные теги для всех удаленных. К сожалению, всех кроме pull-request.

#Настроить среду для корректного отображения вывода git-bash
$env:LC_ALL = 'C.UTF-8'
[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding("utf-8")


$CurrentBranchName = (git branch | where {$_.trim().startswith('*')}).trimstart('*').trim()
$CurrentCommit = git rev-parse HEAD

#Так как teamcity при сборке пулл-реквсетов просто делает чекаут на sha коммита получаемого из origin приходится делать вот такой костыль.
if ('%teamcity.build.branch%' -match '^pull\/\d+\/merge$') {
    $CurrentBranchName = '%teamcity.build.branch%'
}



#Приведем имя теги в пригодный для использоваия в версии вид
$MangledBranchName = $CurrentBranchName
if ($MangledBranchName -cmatch '^((pre-)?release)-\d+\.\d+$') {$MangledBranchName = "$($Matches.1)"}
if ($MangledBranchName -cmatch 'pull\/(\d+)\/merge') {$MangledBranchName = "pr-$($Matches.1)"}
if ($MangledBranchName -cmatch '^\(HEAD detached at \w+\)$') {$MangledBranchName = 'DetachedHead'}
$MangledBranchName = ($MangledBranchName -replace '[^a-zA-Z0-9-]', '-')


#Счетчик билдов из TeamCity. Нужен почти всегда
$TCBuildCounterPadded = "%build.counter%".PadLeft(4, '0')
#На случай если счетчик билдов превышает 4 цифры - оставить только последние 4 разряда.  Таким образом не придется сбрасывать счетчик почти никогда.
$TCBuildCounterPadded = $TCBuildCounterPadded.Substring($TCBuildCounterPadded.Length - 4)




#Находим все версионные теги (теги - источники версий),записываем в массив Имятега:ОбъектВерсии сортируем по убыванию объекта версии.
#Простая сортировка строк с именами версий не сработала бы. При такой сортировке, например,  версия 2.0.0 оказывалась бы выше версии 10.0.0 просто из-а того, что первая цифра в строке больше.
    
$VersionFromTag = git tag --list 'v-*' --merged | % {$_.trimstart('*').trim()} | ? {$_ -cmatch '^v-(?<Major>\d+)\.?(?<Minor>\d+)?\.?(?<Patch>\d+)?$'} | `
    select  @{n = 'TagName'; e = {$_}}, @{n = 'BaseVersion'; e = {[System.Version]("$([int]$Matches.Major).$([int]$Matches.Minor).$([int]$Matches.Patch)")}} | `
    sort BaseVersion -Unique -Descending | select -First 1
    
if ($VersionFromTag -ne $null) {
    $BaseVersion = $VersionFromTag.BaseVersion    
    #Master - версия из доступного тега с наивысшим значением версии, нет хвоста версии, cчетчик коммитов до версионного тега помещается в Patch часть версии.
    if ($CurrentBranchName -cmatch '^master$') {
        $CommitsCounter = git rev-list --count "$CurrentCommit" "^$($VersionFromTag.TagName)"
        $($BaseVersion.GetType().GetField('_Build', 'static,nonpublic,instance')).setvalue($BaseVersion, [int32]$CommitsCounter)
        $CalculatedNugetVersion = [string]$BaseVersion
        Write-Output "##teamcity[message text='master branch has been found. Version will be taken from version tag, version tail(semver pre-release-tag) will be erased. Commit count sinse merge-base with version tag, will be putted into patch-part of version.' status='NORMAL']"
        #Feature-ветки - счетчик билдов
 
    #Фича-ветки - Хвост из имени ветки и счетчика билдов. В path-части счетчик коммитов от merge-base с мастер до версионного тега.
    }else {
        #Количество коммитов от merge-base с master до тега с версией. Бампинг path-части.
        $CommonAnchestorWithMaster = git merge-base master $CurrentCommit
        $CommonAnchestorWithMasterCommitsCounter = git rev-list --count "$CommonAnchestorWithMaster" "^$($VersionFromTag.TagName)"
        $($BaseVersion.GetType().GetField('_Build', 'static,nonpublic,instance')).setvalue($BaseVersion, [int32]$CommonAnchestorWithMasterCommitsCounter)
        $CalculatedNugetVersion = "$($BaseVersion.Major).$($BaseVersion.Minor).$($BaseVersion.Build)-$MangledBranchName-b$TCBuildCounterPadded"
        Write-Output "##teamcity[message text='Feature branch has been found. Version will be taken from the past closest version tag, version tail(semver pre-release-tag) will contain branch name and build counter from TeamCity' status='NORMAL']"
    }
} else {
    #Fallback-версия и счетчик коммитов
    $BaseVersion = [version]'0.1.0'
    $CommitsCounter = '0'
    $CalculatedNugetVersion = "$($BaseVersion.Major).$($BaseVersion.Minor).$($BaseVersion.Build)-$MangledBranchName-b$TCBuildCounterPadded"
}



#
#
#




#Согласно Best-Practics, AssemblyVersion всегда с нулевым Patch. Для взаимозаменяемости сборок с незначительными изменениями.
$CalculatedAssemblyVersion = "$($BaseVersion.Major).$($BaseVersion.Minor)"
$CalculatedAssemblyFileVersion = "$($BaseVersion.Major).$($BaseVersion.Minor).$($BaseVersion.Build)"
$CalculatedAssemblyInformationalVersion = "$CalculatedNugetVersion.$CommitsCounter+Branch.$CurrentBranchName.Sha.$CurrentCommit"

#Выставить параметры с версиями в TeamCity
Write-Host "##teamcity[setParameter name='CalculatedNugetVersion' value='$CalculatedNugetVersion']"
Write-Host "##teamcity[setParameter name='CalculatedAssemblyVersion' value='$CalculatedAssemblyVersion']"
Write-Host "##teamcity[setParameter name='CalculatedAssemblyFileVersion' value='$CalculatedAssemblyFileVersion']"
Write-Host "##teamcity[setParameter name='CalculatedAssemblyInformationalVersion' value='$CalculatedAssemblyInformationalVersion']"

#Выставить версию билда в TeamCity
Write-Host "##teamcity[buildNumber '$CalculatedNugetVersion']"
