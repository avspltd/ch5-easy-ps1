# ch5-easy: simple ch5 build and upload script in PowerShell - Chris Poole, AVSP chris@avsp.co.uk
# v1.0 - initial revision

param (
    [Parameter(Mandatory)]
    [string]$projectName,
    [Parameter(Mandatory)]
    [string]$sourceDirectory,
    [string]$hostname,
    [string]$username,
    [string]$password)

# example, to build a project called "test" in a directory call "html-ch5" and upload it:
# .\ch5-easy -projectName "test" -sourceDirectory "html-ch5" -hostname "panel" -username "crestron" -password ""
# to just build the ch5z, leave out the hostname or username:
# # .\ch5-easy -projectName "test" -sourceDirectory "html-ch5"


# configuration variables
# $projectName = name in manifest, intermediate ch5 and final ch5z to output
# $sourceDirectory = subdirectory containing the ch5 files and an appui/manifest file
# $hostname = hostname of panel to upload to
# $username = username on panel
# $password = password on panel

# the following tools must be in the path:
# 7z (from 7-Zip)
# pscp (from PuTTY / KiTTY) - this is needed so we can specifiy password on command line
# plink (from PuTTY / KiTTY) - this is needed so we can specify password on command line

# we use 7z because the built-in PowerShell zip support generates an incorrect file
# we use pscp / plink so we can provide a password on the command line
# this is not directly possible with the Windows built-in ssh / scp clients

# I use scoop as my package manager on Windows, to install the above tools using scoop:

# install scoop:
#   Set-ExecutionPolicy RemoteSigned -scope CurrentUser
#   iwr -useb get.scoop.sh | iex

# install the dependencies:
#   scoop install 7zip putty

$dotdotch5Path = ("..\" + $projectName + ".ch5")
$ch5Path = (".\" + $projectName + ".ch5")
$manifestPath = (".\" + $projectName + "_manifest.json")
$ch5zPath = (".\" + $projectName + ".ch5z")

if (Test-Path $ch5Path) {
    Remove-Item $ch5Path
}

if (Test-Path $manifestPath) {
    Remove-Item $manifestPath
}

if (Test-Path $ch5zPath) {
    Remove-Item $ch5zPath
}

Push-Location $sourceDirectory

if (-Not (Test-Path ".\appui\manifest")) {
    Write-Output "ch5 appui\manifest is missing, creating file"

    if (-Not (Test-Path -PathType Container ".\appui")) {
        New-Item -ItemType Directory -Force -Path ".\appui"
    }

    Add-Content -Path ".\appui\manifest" -Value "apptype:ch5"
}

Write-Output "Running 7z to compress source folder"
# compress entire source folder into ch5 file
7z a -bso0 -bsp0 -tzip $dotdotch5Path *

if (!$?) {
    throw "7z failed, please check it is installed on the path"    
}

Pop-Location

Write-Output "Constructing manifest..."

$hash = (get-filehash -algorithm sha256 $ch5Path).Hash.ToLower()

$modified = (Get-Item $ch5Path).LastWriteTime

$modifiedStamp = Get-Date $modified -UFormat '+%Y-%m-%dT%H:%M:%S.000Z'

$from = "{""projectname"":""" + $projectName + ".ch5"",""modifiedtime"":""" + $modifiedStamp + """,""sha-256"":""" + $hash + """,""samplesource"":""" + $projectName + """}"

Add-Content -Path $manifestPath -Value $from

Write-Output "Running 7z to write ch5z file"
7z a -bso0 -bsp0 -tzip $ch5zPath $manifestPath $ch5Path

if (!$?) {
    throw "7z failed, please check it is installed on the path"    
}

if (Test-Path $ch5Path) {
    Remove-Item $ch5Path
}

if (Test-Path $manifestPath) {
    Remove-Item $manifestPath
}

if ([string]::IsNullOrEmpty($hostname) -Or [string]::IsNullOrEmpty($username)) {
    Write-Output "Skipping upload, hostname or username is missing"
} else {
    if ([string]::IsNullOrEmpty($password)) {
        Write-Output "No password provided, ssh keys must be provided by Pageant"
        # upload then load project
        $quotedHostpath = """" + $hostname + ":/display/" + """"
        $quotedHostname = """" + $hostname + """"
        $quotedUsername = """"+$username+""""
        $quotedCh5zPath = """"+$ch5zPath+""""

        Write-Output "Uploading with pscp"
        pscp -batch -l $quotedUsername $quotedCh5zPath $quotedHostpath

        if (!$?) {
            throw "pscp failed"
        }

        Write-Output "Running PROJECTLOAD with plink"
        plink -ssh -batch -l $quotedUsername $quotedHostname PROJECTLOAD

        if (!$?) {
            throw "plink failed"
        }
    } else {
        # upload then load project
        $quotedHostpath = """" + $hostname + ":/display/" + """"
        $quotedHostname = """" + $hostname + """"
        $quotedUsername = """"+$username+""""
        $quotedPassword = """"+$password+""""
        $quotedCh5zPath = """"+$ch5zPath+""""

        Write-Output "Uploading with pscp"
        pscp -batch -l $quotedUsername -pw $quotedPassword $quotedCh5zPath $quotedHostpath

        if (!$?) {
            throw "pscp failed"
        }

        Write-Output "Running PROJECTLOAD with plink"
        plink -ssh -batch -l $quotedUsername -pw $quotedPassword $quotedHostname PROJECTLOAD

        if (!$?) {
            throw "plink failed"
        }
    }
}