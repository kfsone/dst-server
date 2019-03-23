#! /usr/bin/pwsh

[CmdletBinding(SupportsShouldProcess=$true)]

Param(
    [Parameter(Mandatory=$true,
        HelpMessage="The location of the Steam Library containing your game, usually C:\Program Files(x86)\Steam\SteamApps\Common on Windows, or /home/steam/steamapps on Linux")]
    [String]
    $Library,

    [Parameter(HelpMessage="The path/name of your 'steamcmd' if 'steamcmd' is not in your path. E.g. on Linux it might be '/usr/games/steamcmd'")]
    [String]
    $SteamCmd       =   "steamcmd",

    [Parameter(HelpMessage="Name of the game folder within the Library directory.")]
    [String]
    $GameFolder     =   "DontStarveTogether",

    [Parameter(HelpMessage="Name of the configuration folder in which you will store your cluster folders, within the Library")]
    [String]
    $ConfigFolder   =   "Servers",

    [Parameter(HelpMessage="Name of the cluster and the folder under ConfigFolder where the Cluster folder will be placed.")]
    [String]
    $Cluster        =   "Cluster",

    [Parameter(HelpMessage="Server and cluster-folder name for the Overworld server")]
    [String]
    $Overworld      =   "Overworld",

    [Parameter(HelpMessage="Server and cluster-folder name for the Caves server")]
    [String]
    $Caves          =   "Caves",

    # Config settings
    [Parameter(HelpMessage="Desired gameplay mode")]
    [ValidateSet("survival", "wilderness", "endless")]
    [Alias("Mode")]
    $GameMode = "survival",

    [Parameter(HelpMessage="The intent of this game server")]
    [ValidateSet("cooperative", "competitive", "social", "madness")]
    $GameIntent = "cooperative",

    [Parameter(HelpMessage="Enable PVP?")]
    [Alias("PVP")]
    [Switch]
    $EnablePVP,

    [Parameter(HelpMessage="Maximum number of players to support")]
    [Int]
    $MaxPlayers = 16,

    [Parameter(HelpMessage="Gives your server a description")]
    [Alias("Description")]
    [String]
    $ClusterDescription = "My server",

    [Parameter(HelpMessage="If set, specifies a password for the server")]
    [String]
    [Alias("Password")]
    $ClusterPassword,

    [Parameter(HelpMessage="Specify name of the server's executable")]
    [String]
    $Executable = "dontstarve_dedicated_server_nullrenderer",

    [Parameter(HelpMessage="Specify port Master will listen for shards on")]
    [Int]
    $ShardPort = 0,

    [Parameter(HelpMessage="Specify base Server port")]
    [Int]
    $ServerPort = 10999,

    [Parameter(HelpMessage="Specify base Master port")]
    [Int]
    $MasterPort = 27016,

    [Parameter(HelpMessage="Specify base Auth port")]
    [Int]
    $AuthPort = 8766,
    
    [Parameter(HelpMessage="Disable updating the game")]
    [Switch]
    $NoUpdate
)


##############################################################################
# Static config

$ServerAppId  = 343050
$ClusterToken = "cluster_token.txt"
$ClusterIniFile = "cluster.ini"
$ServerIniFile = "server.ini"
$LaunchScript = "run-dst-server"


##############################################################################
# Helper functions

Function Do-Update()
{
    if ($NoUpdate) {
        $pscmdlet.WriteVerbose("Skipping update")
        return
    }

    if ($pscmdlet.ShouldProcess($SteamAppId, "Install/Update")) {
        & $SteamCmd `
            +@ShutdownOnFailedCommand 1 `
            +@NoPromptForPassword 1 `
            +login anonymous `
            +force_install_dir "${GamePath}" `
            +app_update $ServerAppId validate `
            +quit
    }
}


Function Make-Folder
{
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="High")]
    Param(
        [Parameter(Mandatory=$true)][String]$Path, 
        [Parameter(Mandatory=$true)][String]$Role
    )

    if (!(Test-Path $Path)) {
        $pscmdlet.WriteVerbose("'$Path' $Role folder does not exist.")
        if ($pscmdlet.ShouldProcess($Path, "Create $Role folder")) {
            New-Item -ItemType Directory -Path $Path | Out-Null
        }
    }
}


Function Copy-TokenFile
{
    [CmdletBinding()]
    Param()

    # First file: the cluster_token.
    Write-Host "To start, we need your Cluster token."
    Write-Host "Obtain this by running the game and going online, open the console (~)"
    Write-Host "Then type: TheNet:GenerateClusterToken()"
    Write-Host "This will create '${ClusterToken}' in your DST settings folder."
    Write-Host "On windows, this is usually under Documents > Klei > DoNotStarve"
    Write-Host
    Write-Host "Either enter the path to the file on this machine or copy it"
    Write-Host "to ${ClusterPath}/${ClusterToken} and hit enter here."
    Write-Host

    if (Test-Path $TokenFile) {
        Write-Host "NOTE: $TokenFile already exists, hit enter if you don't want"
        Write-Host "NOTE: to replace/overwrite it."
        Write-Host
    }

    $TokenSrc = Read-Host -Prompt "Enter path to cluster_token.txt file or hit enter."

    if ($TokenSrc) {
        # Support them providing a directory that contains the file instead
        # of the full path+file name.
        $AltSrc = Join-Path $TokenSrc $ClusterToken
        if (Test-Path $AltSrc) {
            $TokenSrc = $AltSrc
        }

        # Make sure it exists.
        if (!(Test-Path $TokenSrc -PathType Leaf)) {
            $pscmdlet.ThrowTerminatingError("'$TokenSrc': File not found.")
        }

        if (Test-Path $TokenFile) {
            if ($pscmdlet.ShouldProcess($TokenFile, "Remove existing")) {
                Remove-Item -Confirm:$false $TokenFile
            }
        }

        if ($pscmdlet.ShouldProcess($TokenFile, "Copy")) {
            Copy-Item $TokenSrc -Destination $TokenFile -ErrorAction Stop
        }
    }
}


Function Create-IniFiles
{
    if ($ShardPort) {
        $ShartMasterPort = "master_port = ${ShardPort}"
    }
    # Now create cluster.ini
    $IniFile = Join-Path $ClusterPath $ClusterIniFile
    if ($pscmdlet.ShouldProcess($IniFile, "Create")) {
        Out-File -FilePath $IniFile -Encoding utf8 -InputObject @"
[GAMEPLAY]
game_mode = ${GameMode}
pvp = ${PvpMode}
max_players = ${MaxPlayers}
pause_when_empty = true

[NETWORK]
cluster_name = ${Cluster}
cluster_description = ${ClusterDescription}
cluster_password = ${ClusterPassword}
cluster_intention = ${GameIntent}
autosaver_enabled = true
enable_snapshots = true
enable_vote_kick = false
tick_rate = 15
connection_timeout = 8000
lan_only_server = true

[MISC]
console_enabled = true

[SHARD]
shard_enabled = true
cluster_key   = ${Cluster}.${ClusterPassword}
bind_ip       = 127.0.0.1
master_ip     = 127.0.0.1
${ShardMasterPort}
"@
    }

    # Now create server.ini for the Overworld
    $IniFile = Join-Path $ClusterPath $Overworld $ServerIniFile
    if ($pscmdlet.ShouldProcess($IniFile, "Create")) {
        Out-File -FilePath $IniFile -Encoding utf8 -InputObject @"
[NETWORK]
lan_only_server = true
server_port = ${ServerPort}

[SHARD]
is_master = true
name = ${Overworld}

[STEAM]
master_server_port = ${MasterPort}
authentication_port = ${AuthPort}

[ACCOUNT]
encode_user_path = true
dedicated_lan_server = true
"@
    }

    # And finally, the caves file
    $IniFile = Join-Path $ClusterPath $Caves $ServerIniFile
    $CavesServerPort = $ServerPort + 1
    $CavesMasterPort = $MasterPort + 1
    $CavesAuthPort   = $AuthPort + 1
    if ($pscmdlet.ShouldProcess($IniFile, "Create")) {
        Out-File -FilePath $IniFile -Encoding utf8 -InputObject @"
[NETWORK]
lan_only_server = true
server_port = ${CavesServerPort}

[SHARD]
is_master = false
name = ${Caves}

[STEAM]
master_server_port = ${CavesMasterPort}
authentication_port = ${CavesAuthPort}

[ACCOUNT]
encode_user_path = true
dedicated_lan_server = true
"@
    }
}


Function Create-Launchers
{
    $Launcher = Join-Path $GamePath "${LaunchScript}.${Cluster}"

    # Now create the launcher scripts
    if ($pscmdlet.ShouldProcess("${Launcher}.ps1", "Create")) {
        Out-File -FilePath "${Launcher}.ps1" -Encoding utf8 -InputObject @"
#! /usr/bin/env pwsh
# Generated by configuration script

pushd "${GamePath}/bin"

& "./${Executable}" -only_update_server_mods
`$caves = Start-Job {
    & "./${Executable}" `
        -persistent_storage_root "${GamePath}" `
        -config_dir "${ConfigFolder}" `
        -cluster "${Cluster}" `
        -shard "${Caves}"
}
`$overworld = Start-Job {
    & "./${Executable}" `
        -persistent_storage_root "${GamePath}" `
        -config_dir "${ConfigFolder}" `
        -cluster "${Cluster}" `
        -shard "${Overworld}"
}


popd

Wait-Job `$caves,`$overworld
"@
    }

    if ($pscmdlet.ShouldProcess("${Launcher}.sh", "Create")) {
        Out-File -FilePath "${Launcher}.sh" -Encoding utf8 -InputObject @"
#! /usr/bin/env bash
# Generated by configuration script

# 'strict' mode in bash
set -euo pipefail

cd "${GamePath}/bin"
shared_params=("./${Executable}")
shared_params+=(-cluster "${Cluster}")
shared_params+=(-persistent_storage_root "${GamePath}")
shared_params+=(-config_dir "${ConfigFolder}")
shared_params+=(-monitor_parent_process `$$)

set -x
"`${shared_params[@]}" -shard "${Caves}" | sed "s:^:[${Cluster}.${Caves}] :" &
"`${shared_params[@]}" -shard "${Overworld}" | sed "s:^:[${Cluster}.${Overworld}] :" &
set +x

wait
"@
    }
}

##############################################################################
# Summarize the options

$GamePath = Join-Path $Library $GameFolder
$ConfigPath = Join-Path $GamePath $ConfigFolder
$ClusterPath = Join-Path $ConfigPath $Cluster
$OverworldPath = Join-Path $ClusterPath $Overworld
$CavesPath = Join-Path $ClusterPath $Caves
$TokenFile = Join-Path $ClusterPath $ClusterToken

if ($EnablePvP) {
    $PVPMode = "true"
} else {
    $PVPMode = "false"
}

$pscmdlet.WriteVerbose("Library: $Library")
$pscmdlet.WriteVerbose("SteamCmd: $SteamCmd")
$pscmdlet.WriteVerbose("GamePath: $GamePath")
$pscmdlet.WriteVerbose("ConfigPath: $ConfigPath")
$pscmdlet.WriteVerbose("ClusterPath: $ClusterPath")
$pscmdlet.WriteVerbose("OverworldPath: $OverworldPath")
$pscmdlet.WriteVerbose("CavesPath: $CavesPath")
$pscmdlet.WriteVerbose("TokenFile: $TokenFile")


# Check that 'steamcmd' is executable
Get-Command $SteamCmd -ErrorAction Stop | Out-Null

# Make sure the top-level steamapps folder exists
Make-Folder $Library "Steam apps folder"

# Make sure the game folder exists
Make-Folder $GamePath "Game folder"


# Save the user's current path so we don't wind up there by mistake
Push-Location $GamePath | Out-Null

try
{

    # Make sure the server is up-to date if the user hasn't opted out
    Do-Update

    # Create the folder hierarchy
    Make-Folder $ConfigPath      "Server's config folder"
    Make-Folder $ClusterPath     "Server's cluster folder"
    Make-Folder $OverworldPath   "Folder for the Overworld server"
    Make-Folder $CavesPath       "Folder for the Caves server"

    # Put the tokenfile in-place
    Copy-TokenFile
    if ($pscmdlet.ShouldProcess($TokenFile, "Check for") -And !(Test-Path $TokenFile)) {
        $pscmdlet.ThrowTerminatingError("'$TokenFile': File not found.")
    }

    # Create the various .ini files required
    Create-IniFiles

    # Create launcher scripts
    Create-Launchers

    # Done
    
} finally {
    Pop-Location | Out-Null
}

