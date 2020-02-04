#requires -version 5
<#
.SYNOPSIS
SemVer calculator for Release-flow with pre-release branches (Pre-Release-flow)
.NOTES
Author: Anton Smolkov - https://github.com/AnSmol
.DESCRIPTION
Calculation algorithm:
* pre-release branch:
    Schema - {BaseVersion}-VersionsTail
    BaseVersion - from branches name.
    CommitsCounter - count of commits to merge-base with master. (Which are in the branch and not in master)
    VersionsTail - BranchName-c{CommitsCounter}.
    
    Example - 3.2.0-pre-release-c0012. Means that branch pre-release-3.2.0 has merge base to master 12 commits ago. 

* release branch:
    Schema - {BaseVersion}
    BaseVersion - from branch name. Patch SemVer part is equals to CommitsCounter.
    CommitsCounter - count of commits to merge-base with relative pre-release branch or with master-branch if there is no such pre-release branch. This commits are actually HotFix'es, normally you don't want to make commits to this branch. 
    VersionsTail - No tail. In SemVer release versions have no tails.

    Example - 3.2.3. Means that branch release-3.2.0 ahead of pre-release-3.2.0 for 3 commits (has 3 hotfix-commits).

* master branch:
    Schema - {BaseVersion}-{VersionsTail}
    BaseVersion - + 1 Minor to latest available (pre-)release branches version.
    CommitsCounter - count of commits to merge-base with latest available (pre-)release branch.
    VersionsTail - BranchName-c{CommitsCounter}.

    Example - 3.3.0-master-c0009. Means that branch master has merge-base to branch pre-release-3.2.0 9 commits ago.

* all other branches (future/topic):
    Schema - {BaseVersion}-{VersionsTail}
    BaseVersion - + 1 Minor to latest available (pre-)release branches verson.
    CommitsCounter - Don't use it, because developers always rewrite commits history in future/topic-branches.
    BuildCounter - Constantly growing build counter from build server.
    VersionsTail - BranchName-b{BuildCounter}.

    Example - 3.3.0-JIRA4313-b1829. Means that branch JIRA4313 has merge-base to branch pre-release-3.2.0, 
    and this merge-base is more recent than merge-bases with another (pre-)release branches.



According to nuget specification, package version tail should maximum be 20 characters long.
So, script leaves only first 14 symbols from branch name and reserve another 6 for "-[c|b]4Digits[Commits|Builds]counter".
Script also cleans branch-name from unsupported characters.
  
#>


#%teamcity.git.fetchAllHeads% - placeholder makes such parameter mandatory to have in TeamCity.  Paramater makes TeamCity to create local branches for all thre remotes, while checkout. Unfortunately, not for pull-requests

#Poweshell envinronment setting to correct show git-bash's output
$env:LC_ALL='C.UTF-8'
[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding("utf-8")


$CurrentBranchName = (git branch | where {$_.trim().startswith('*')}).trimstart('*').trim()
$CurrentCommit = git rev-parse HEAD

#When teamcity builds pull request, it just put HEAD to appropriate commit, without getting ref.
#So we have to get branch name from teamcity parameter. - Why don't we do so always? Because for the master branch teamcity returns '<Default>' value over here. 
if ('%teamcity.build.branch%' -match '^pull\/\d+\/merge$'){
$CurrentBranchName  = '%teamcity.build.branch%'
}



#Make branch name pretty and appropriate
$MangledBranchName = $CurrentBranchName
if ($MangledBranchName  -cmatch '^((pre-)?release)-\d+\.\d+(\.\d+)?$') {$MangledBranchName = "$($Matches.1)"}
if ($MangledBranchName  -cmatch 'pull\/(\d+)\/merge'){$MangledBranchName = "pr-$($Matches.1)"}
if ($MangledBranchName  -cmatch '^\(HEAD detached at \w+\)$'){$MangledBranchName = 'DetachedHead'}
if ($MangledBranchName.Length -ge 15){ $MangledBranchName = $MangledBranchName.Substring(0,13)}
$MangledBranchName  = ($MangledBranchName  -replace '[^a-zA-Z0-9-_]', '-')

#
#Main calculation IF
#

#Pre-release branch - branches name and commits counter in SemVer tail. Version is getting from branch name.
if ($CurrentBranchName -cmatch '^pre-release-(?<Major>\d+)\.?(?<Minor>\d+)?\.?(?<Patch>\d+)?$'){
    $BaseVersion=[System.Version]("$([int]$Matches.Major).$([int]$Matches.Minor).$([int]$Matches.Patch)")
    $CommitsCounter = $(git rev-list --count "$CurrentCommit" "^master")
    $CommitsCounterPadded =  $CommitsCounter.PadLeft(4,'0') 
    $CalculatedNugetVersion = "$BaseVersion-$MangledBranchName-c$CommitsCounterPadded"
    Write-Output "##teamcity[message text='Pre-release branch has been found. Version will be taken from branch name, version tail(semver pre-release-tag) will contain branch name and commit count sinse merge-base with master' status='NORMAL']"
}
#Release branch. No tail. Commits counter in Patch SemVer part. Version is getting from branch name.
elseif ($CurrentBranchName -cmatch '^release-(?<Major>\d+)\.?(?<Minor>\d+)?\.?(?<Patch>\d+)?$'){
    $BaseVersion=[System.Version]("$([int]$Matches.Major).$([int]$Matches.Minor).$([int]$Matches.Patch)")
#If pre-release branch exists, count commits from merge-base with it, else from merge-base with master branch
#Generally, we have to count commits only from merge base with pre-release branch, 
#but as as its concept is new, it would be nice to be able to use merge-base with release branches too, for the first time or for the build from old snapshots 
    if (git branch --list "pre-$CurrentBranchName"){
    $CommitsCounter = git rev-list --count "$CurrentCommit" "^pre-$CurrentBranchName"
    }else{
    $CommitsCounter = git rev-list --count "$CurrentCommit" "^master"
    }

    #Put commits count to the Patch(_build) part of version
    $($BaseVersion.GetType().GetField('_Build','static,nonpublic,instance')).setvalue($BaseVersion, $BaseVersion.Build + [int32]$CommitsCounter)
    $CalculatedNugetVersion = [string]$BaseVersion
    Write-Output "##teamcity[message text='Release branch has been found. Version will be taken from branch name, version tail(semver pre-release-tag) will be erased. Commit count sinse merge-base with pre-release branch (or master), will be putted into patch-part of version.' status='NORMAL']"
}
#Feature-branches and master-branch.  Feature-branches - SemVer tail has branch name and build counter from TeamCity. Master-branch - SemVer tail has branch name and commits counter to merge-base with latest historicaly avalaiible (pre-)release-brach
else{
    #Fallback-version and commits counter
    $BaseVersion = [version]'0.1.0'
    $CommitsCounter = '0'

    #Find all version-containing branches, write them all into array BranchName:VersionObject, sort by version descending.
    #Its important to sort by BaseVersion objects, cause we use [System.Version] type sorting, instead of string sorting.
    #Cause pre-release brances concept is pretty new, for backwards compatibility will treat both pre-release and release branches as version sources 
    
    $VersionSources = @()
    $VersionSources += git branch --list 'release-*' 'pre-release-*' | % {$_.trimstart('*').trim()} | ? {$_ -cmatch '^(pre-)?release-(?<Major>\d+)\.?(?<Minor>\d+)?\.?(?<Patch>\d+)?$'} | `
        select  @{n = 'VersionBranchName'; e = {$_}}, @{n='BaseVersion'; e={[System.Version]("$([int]$Matches.Major).$([int]$Matches.Minor).$([int]$Matches.Patch)")}} | `
        sort BaseVersion -Unique -Descending

    #Look into array for appropriate version
    #Get merge-base between version branch and master branch. Try to find if we have this merge-base commit in current commits history.
    #If we have, than version is matching
    foreach ($VersionSource in $VersionSources) {
        
            #Get merge-base between verison brach with master 
            $VersionBranchCommonAnchestorWithMaster = git merge-base master $VersionSource.VersionBranchName
        #If common anchestor between version branch and master-branch is also an anchestor of current commit - assign version to this commit. 
        if ( $(git merge-base --is-ancestor $VersionBranchCommonAnchestorWithMaster $CurrentCommit ; $LASTEXITCODE) -eq 0) {
            $BaseVersion = $VersionSource.BaseVersion
            #Assume that after one release, work on second starts, increment SemVer minor part to +1
            $($BaseVersion.GetType().GetField('_Minor', 'static,nonpublic,instance')).setvalue($BaseVersion, [int]$BaseVersion.Minor + 1)
            #Commits counter = Count of commits wich exist in current snapshots history and does not exist in history of merge-base between version-branch and master-branch.
            $CommitsCounter = git rev-list --count "$CurrentCommit" "^$VersionBranchCommonAnchestorWithMaster"
            #Stop looking for version after first match
            break
        }
    }

    
    #Ad-hoc. Ugly, but could not make better
    #Branches must have commits counter instead of builds counter. Only master-branch is here yet.
    if ($CurrentBranchName -cmatch '^master$') {
        $CommitsCounterPadded = $CommitsCounter.PadLeft(4, '0')
        $CalculatedNugetVersion = "$($BaseVersion.Major).$($BaseVersion.Minor).$($BaseVersion.Build)-$MangledBranchName-c$CommitsCounterPadded"
        Write-Output "##teamcity[message text='Master branch has been found. Version will be taken from past closest (pre-)release branch, version tail(semver pre-release-tag) will contain branch name and commit count sinse merge-base with (pre-)release branch' status='NORMAL']"
    #Feature-branches - builds counter in version tail
    }else{
        $TCBuildCounterPadded = "%build.counter%".PadLeft(4, '0')
        #If builds counter from TeamCity exceeds 4 digits, let only last 4 positions.
        $TCBuildCounterPadded =  $TCBuildCounterPadded.Substring($TCBuildCounterPadded.Length - 4)

        $CalculatedNugetVersion = "$($BaseVersion.Major).$($BaseVersion.Minor).$($BaseVersion.Build)-$MangledBranchName-b$TCBuildCounterPadded"
        Write-Output "##teamcity[message text='Feature branch has been found. Version will be taken from past closest (pre-)release branch, version tail(semver pre-release-tag) will contain branch name and build counter from TeamCity' status='NORMAL']"
    }

}


#
#
#




#According to Best-Practics, AssemblyVersion should always have zeroed Patch part. It lets assemblies with insignificant differences interract each other.
$CalculatedAssemblyVersion = "$($BaseVersion.Major).$($BaseVersion.Minor)"
$CalculatedAssemblyFileVersion = "$($BaseVersion.Major).$($BaseVersion.Minor).$($BaseVersion.Build)"
$CalculatedAssemblyInformationalVersion = "$CalculatedNugetVersion.$CommitsCounter+Branch.$CurrentBranchName.Sha.$CurrentCommit"

#Pop calculated versions to TeamCity parameters
Write-Host "##teamcity[setParameter name='CalculatedNugetVersion' value='$CalculatedNugetVersion']"
Write-Host "##teamcity[setParameter name='CalculatedAssemblyVersion' value='$CalculatedAssemblyVersion']"
Write-Host "##teamcity[setParameter name='CalculatedAssemblyFileVersion' value='$CalculatedAssemblyFileVersion']"
Write-Host "##teamcity[setParameter name='CalculatedAssemblyInformationalVersion' value='$CalculatedAssemblyInformationalVersion']"

#Pop teamcity-ui build version
Write-Host "##teamcity[buildNumber '$CalculatedNugetVersion']"
