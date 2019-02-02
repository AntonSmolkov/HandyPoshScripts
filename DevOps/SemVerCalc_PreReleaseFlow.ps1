#requires -version 5
<#
.SYNOPSIS
SemVer calculator for Release-flow with pre-release branches
.DESCRIPTION
Calculation algorithm:
* pre-release branch
    Schema - {BaseVersion}-VersionsTail
    BaseVersion - from branch name.
    CommitsCounter - count of commits to merge-base with master. (In branch and not in master)
    VersionsTail - BranchName-c{CommitsCounter}.
    Example - 3.2.0-pre-release-c0012. Means that branch pre-release-3.2.0 has merge base to master 12 commits ago. 
* release branch
    Schema - {BaseVersion}
    BaseVersion - from branch name. Patch semver part equals to CommitsCounter
    CommitsCounter - count of commits to merge-base with relative pre-release tag. This commits are actually HotFix'es, normally you don't want to make commits to this branch 
    VersionsTail - No tail. In SemVer release versions have no tail.
    Example - 3.2.3. Means that branch release-3.2.0 has merge-base with master 12 commits ago.
* master
    Schema - {BaseVersion}-{VersionsTail}
    BaseVersion - + 1 Minor to latest available pre-release's version.
    CommitsCounter - count of commits to merge-base with latest available pre-release branch.
    VersionsTail - BranchName-c{CommitsCounter}.
    Example - 3.3.0-master-c0009. Means that branch master has merge-base to branch pre-release-3.2.0 9 commits ago
* all other branches (future/topic)
    Schema - {BaseVersion}-{VersionsTail}
    BaseVersion - + 1 Minor to lates available pre-release's version.
    CommitsCounter - Don't use it, because developers always rewrite commits history in future/topic-branches.
    BuildCounter - Constantly growing build counter from build server.
    VersionsTail - BranchName-b{BuildCounter}.
    Example - 3.3.0-JIRA4313-b1829. Means that branch JIRA4313 has merge-base to branch pre-release-3.2.0.



Для использования в хвосте версии, из названий веткой удаляются недопустимые символы, название усекается до 14-ти символов (оставшиеся 6 для "-[c|b]4ЦифрыСчетчика[Коммитов|Билдов]").
Если в хвосте версии используется счетчик коммитов, счетчик обозначается префиксом - 'c', если счетчик билдов TeamCity - 'b'.
#>


#%teamcity.git.fetchAllHeads% - плейсхолдер делающий обязательным параметр в TeamCity. Параметр создает локальные ветки для всех удаленных. К сожалению, всех кроме pull-request.

#Настроить среду для корректного отображения вывода git-bash
$env:LC_ALL='C.UTF-8'
[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding("utf-8")


$CurrentBranchName = (git branch | where {$_.trim().startswith('*')}).trimstart('*').trim()
$CurrentCommit = git rev-parse HEAD

#Так как teamcity при сборке пулл-реквсетов просто делает чекаут на sha коммита получаемого из origin приходится делать вот такой костыль.
if ('%teamcity.build.branch%' -match '^pull\/\d+\/merge$'){
$  = '%teamcity.build.branch%'
}



#Приведем имя ветки в пригодный для использоваия в версии вид
$MangledBranchName = $CurrentBranchName
if ($MangledBranchName  -cmatch '^((pre-)?release)-\d+\.\d+$') {$MangledBranchName = "$($Matches.1)"}
if ($MangledBranchName  -cmatch 'pull\/(\d+)\/merge'){$MangledBranchName = "pr-$($Matches.1)"}
if ($MangledBranchName  -cmatch '^\(HEAD detached at \w+\)$'){$MangledBranchName = 'DetachedHead'}
if ($MangledBranchName.Length -ge 15){ $MangledBranchName = $MangledBranchName.Substring(0,13)}
$MangledBranchName  = ($MangledBranchName  -replace '[^a-zA-Z0-9-]', '-')

#
#Ветвление в котором производится непосредственно калькуляция версии.
#

#Пре-релизная ветка - в хвосте имя бренча и счечик коммитов. Версия берется прямо из имени текущей ветки.
if ($CurrentBranchName -cmatch '^pre-release-(?<Major>\d+)\.?(?<Minor>\d+)?\.?(?<Patch>\d+)?$'){
    $BaseVersion=[System.Version]("$([int]$Matches.Major).$([int]$Matches.Minor).$([int]$Matches.Patch)")
    $CommitsCounter = $(git rev-list --count "$CurrentCommit" "^master")
    $CommitsCounterPadded =  $CommitsCounter.PadLeft(4,'0')
    $CalculatedNugetVersion = "$BaseVersion-$MangledBranchName-c$CommitsCounterPadded"
    Write-Output "##teamcity[message text='Pre-release branch has been found. Version will be taken from branch name, version tail(semver pre-release-tag) will contain branch name and commit count sinse merge-base with master' status='NORMAL']"
}
#Релизная ветка - хвоста нет. Счетчик коммитов в patch-части версии. Версия берется прямо из из имени текущей ветки.
elseif ($CurrentBranchName -cmatch '^release-(?<Major>\d+)\.?(?<Minor>\d+)?\.?(?<Patch>\d+)?$'){
    $la = "$([int]$Matches.Major).$([int]$Matches.Minor).$([int]$Matches.Patch)"
    $BaseVersion=[System.Version]("$([int]$Matches.Major).$([int]$Matches.Minor).$([int]$Matches.Patch)")
 #Если существует пререлизный бранч - считать коммиты от общего предка с ним, иначе - от общего предка с мастером.
 #Нужно так как концепция пре-релизных веток появилась недавно, может потребоваться считать коммиты для старых релизных веток.
    if (git branch --list "pre-$CurrentBranchName"){
    $CommitsCounter = git rev-list --count "$CurrentCommit" "^pre-$CurrentBranchName"
    }else{
    $CommitsCounter = git rev-list --count "$CurrentCommit" "^master"
    }

    #Специально для release-веток - записать в Patch счетчик коммитов, хвост версии не добавлять.
    $($BaseVersion.GetType().GetField('_Build','static,nonpublic,instance')).setvalue($BaseVersion, [int32]$CommitsCounter)
    $CalculatedNugetVersion = [string]$BaseVersion
    Write-Output "##teamcity[message text='Release branch has been found. Version will be taken from branch name, version tail(semver pre-release-tag) will be erased. Commit count sinse merge-base with pre-release branch (or master), will be putted into patch-part of version.' status='NORMAL']"
}
#Фича-ветки и master.  Фича ветки - в хвосте имя бренча и счетчик билдов из TeamCity. master - в хвосте имя бренача и счетчик коммитов.
else{
    #Fallback-версия и счетчик коммитов
    $BaseVersion = [version]'0.1.0'
    $CommitsCounter = '0'

    #Находим все версионные ветки (ветки - источники версий),записываем в массив ИмяВетки:ОбъектВерсии сортируем по убыванию объекта версии.
    #Простая сортировка строк с именами версий не сработала бы. При такой сортировке, например,  версия 2.0.0 оказывалась бы выше версии 10.0.0 просто из-а того, что первая цифра в строке больше.
    #Так как концепция пре-релизных веток появилась недавно, за версионные ветки будем считать и релизные и пре-релизные ветки, версия в названии и общий предок с master у них идентичны, поэтому это валидно.
    #В дальнейшем, для порядка имеет смысл убрать релизные ветки из glob-шаблона/регулярного выражения и оставить только пре-релизные. На скорость работы скрипта сильно влиять не должно, так как ветки с дубликаты версий очищаются в процессе обработки
    $VersionSources = @()
    $VersionSources += git branch --list 'release-*' 'pre-release-*' | % {$_.trimstart('*').trim()} | ? {$_ -cmatch '^(pre-)?release-(?<Major>\d+)\.?(?<Minor>\d+)?\.?(?<Patch>\d+)?$'} | `
        select  @{n = 'VersionBranchName'; e = {$_}}, @{n='BaseVersion'; e={[System.Version]("$([int]$Matches.Major).$([int]$Matches.Minor).$([int]$Matches.Patch)")}} | `
        sort BaseVersion -Unique -Descending

    #Искать по массиву подходящую версию до первого совпадения
    #Для каждой ищем merge-base с master. Приндалежность коммита к той или иной версии по тому, если ли этот merge-base в его истории.
    foreach ($VersionSource in $VersionSources) {
        
            #Ищем коммит являющийся merge-base текущей релизной ветки с master.
            $VersionBranchCommonAnchestorWithMaster = git merge-base master $VersionSource.VersionBranchName
        #Если общий предок версионной ветки с master является предком текущего коммита, присвоить коммиту эту версию.
        if ( $(git merge-base --is-ancestor $VersionBranchCommonAnchestorWithMaster $CurrentCommit ; $LASTEXITCODE) -eq 0) {
            $BaseVersion = $VersionSource.BaseVersion
            #Так как подразумевается, что после одного релиза начинается работа над другим, произведем инкремент Minor'ной части.
            $($BaseVersion.GetType().GetField('_Minor', 'static,nonpublic,instance')).setvalue($BaseVersion, [int]$BaseVersion.Minor + 1)
            #Счечик коммитов = Количество коммитов которые присутсвуют в истории текущего коммита и отсуствую в истории общего предка с версионной веткой.
            $CommitsCounter = git rev-list --count "$CurrentCommit" "^$VersionBranchCommonAnchestorWithMaster"
            #Прекратить поиск после первого совпадения
            break
        }
    }

    
    #Ad-hoc. Уродливо, но лучше пока не придумал.
    #Ветки у которых должен быть счетчик коммитов, вместо счетчика билдов. Пока тут только master
    if ($CurrentBranchName -cmatch '^master$') {
        $CommitsCounterPadded = $CommitsCounter.PadLeft(4, '0')
        $CalculatedNugetVersion = "$($BaseVersion.Major).$($BaseVersion.Minor).$($BaseVersion.Build)-$MangledBranchName-c$CommitsCounterPadded"
        Write-Output "##teamcity[message text='Master branch has been found. Version will be taken from past closest (pre-)release branch, version tail(semver pre-release-tag) will contain branch name and commit count sinse merge-base with (pre-)release branch' status='NORMAL']"
    #Feature-ветки - счетчик билдов
    }else{
        $TCBuildCounterPadded = "%build.counter%".PadLeft(4, '0')
        #На случай если счетчик билдов превышает 4 цифры - оставить только последние 4 разряда.  Таким образом не придется сбрасывать счетчик почти никогда.
        $TCBuildCounterPadded =  $TCBuildCounterPadded.Substring($TCBuildCounterPadded.Length - 4)

        $CalculatedNugetVersion = "$($BaseVersion.Major).$($BaseVersion.Minor).$($BaseVersion.Build)-$MangledBranchName-b$TCBuildCounterPadded"
        Write-Output "##teamcity[message text='Feature branch has been found. Version will be taken from past closest (pre-)release branch, version tail(semver pre-release-tag) will contain branch name and build counter from TeamCity' status='NORMAL']"
    }

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
