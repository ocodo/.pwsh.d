$PROFILE_DIR = Split-Path -Parent $profile
$env:Path = "$HOME/.local/bin;$env:Path"

// Required dependencies
$req = @('cargo', 'go', 'oh-my-posh','fnm','uvx','git')
$missing = $req.Where({!(Get-Command $_ -EA 0)})
if ($missing) {
    $missing | % { Write-Warning "Missing: $_" }
    throw 'Install missing commands and restart'
}

if (Get-Command fnm -ErrorAction SilentlyContinue) {
    try {
        fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
    } catch {
        Write-Host "Error initializing fnm"
    }
}

try {
    $start = Get-Date

    oh-my-posh init pwsh --config "$HOME/.pwsh.d/ocodo.omp.yaml" | Invoke-Expression

    $end = Get-Date
    Write-Host "Oh-My-Posh initialized in $($end - $start).TotalSeconds seconds."
} catch {
    Write-Host "Error initializing oh-my-posh: $_"
}

Set-PSReadLineOption -EditMode Emacs

function cd {
  param([string[]]$Path)
  switch ($Path.Count) {
    0       { Set-Location ~ }                          # 'cd' → home
    1       {
      if ($Path[0] -eq "-") { Pop-Location }            # 'cd -' → last dir
      else { Set-Location $Path[0] }                    # Normal cd
    }
    default { Set-Location @Path }                      # All other cases
  }
}

function unix_ls { gci -fo @args | select Name | fw -AutoSize }
function l { (gci -fo).Name }
function ll { gci -fo | ft -w Mode, LastWriteTime, Length, Name -HideTableHeaders }

Function remove_force { rm -Force $args }
Function msys($platform="ucrt64") { C:/msys64/msys2_shell.cmd -defterm -here -no-start "-${platform}" -shell zsh }

Function edit {
    code $args
}
Function edit_here { edit . }
Function edit_config { edit $profile }
Function print_config { get-content $profile }

function symlink {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Target,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$LinkPath
    )

    try {
        # Check if the link already exists
        if (Test-Path -Path $LinkPath) {
            throw "A symbolic link already exists at $LinkPath."
        }

        # Create the symbolic link
        New-Item -ItemType SymbolicLink -Path $LinkPath -Target $Target
        Write-Output "Symbolic link created successfully: $LinkPath -> $Target"
    } catch {
        Write-Error "An error occurred: $_"
    }
}

function disks {
    Get-WmiObject Win32_Volume -Filter "DriveType='3'" | ForEach-Object {
        $total_size = [Math]::Round($_.Capacity / 1GB, 2)
        $free_space = [Math]::Round($_.FreeSpace / 1GB, 2)
        $used_space = [Math]::Round(($_.Capacity / 1GB) - ($_.FreeSpace / 1GB), 2)
        $free_space_ratio = [Math]::Round(($_.FreeSpace / 1GB) / ($_.Capacity / 1GB), 2) * 100

        New-Object PSObject -Property @{
            Name       = $_.Name
            Label      = $_.Label
            FreeSpace = "${free_space} GB"
            UsedSpace = "${used_space} GB"
            FreeSpaceRatio = "${free_space_ratio}%"
            TotalSize = "${total_size} GB"
        }
    }
}

Function enable-msys-clang {
    $env:PATH = "${env:PATH};C:\msys64\clang64\bin;C:\msys64\usr\bin"
}

Function enable-msys-ucrt {
    $env:PATH = "${env:PATH};C:\msys64\ucrt64\bin;C:\msys64\usr\bin"
}

function DownloadDirectory {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$SSHAlias,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$DirectoryPath
    )

    # Check if directory and SSH alias are provided
    if ($null -eq $SSHAlias -or $null -eq $DirectoryPath) {
        Write-Host "Usage: DownloadDirectory <SSHAlias> <DirectoryPath>"
        exit 1
    }

    # Extract the directory name from the full path
    $DirectoryName = [System.IO.Path]::GetFileName($DirectoryPath)

    # Define the output archive name
    $ArchiveName = "$DirectoryName.7z"

    # Define the SSH and SCP commands
    $SSHCommand = "ssh $SSHAlias"

    # Step 1: Compress the directory on PC B using 7zip with best compression
    Write-Host "Compressing..."
    Invoke-Expression "$SSHCommand 7z a -mmt=on -mx3 ~/$ArchiveName $DirectoryPath"

    # Step 2: Transfer the archive from PC B to PC A using SCP
    Write-Host "Downloading..."
    Invoke-Expression "scp ${SSHAlias}:~/$ArchiveName ./$ArchiveName"

    # Step 3: Extract the archived directory on PC B in current working directory
    Write-Host "Extracting..."
    Invoke-Expression "7z x ./$ArchiveName"

    Write-Host "Cleaning up..."
    Remove-Item "./$ArchiveName" -Force
    Invoke-Expression "$SSHCommand rm ~/$ArchiveName"

    Write-Host "Done!"
}

function DownloadTempFile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

	$fileName = [System.IO.Path]::GetFileName($Url)
    $filePath = [System.IO.Path]::GetTempPath() + $fileName

    try {
        Write-Host "Downloading ${Url}"
        Write-Host "Destination: ${filePath}"
        Invoke-WebRequest -Uri $Url -OutFile $filePath -ErrorAction Stop
    } catch {
        Write-Error "Failed to download file from ${Url}: $_"
        return $null
    }

    return $filePath
}

function DownloadAndVerifyFile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$ChecksumUrl
    )

    try {
        # Download the file
        $filePath = DownloadTempFile $Url

        # Download the checksum file
        $hashPath = DownloadTempFile $ChecksumUrl

        # Extract checksum from .sha256sum file
        $expectedChecksum = Get-Content -Path $hashPath -TotalCount 1
        if (-not $expectedChecksum) {
            Write-Error "Checksum file is empty or contains no valid checksum."
			Remove-Item -Path $filePath -Recurse -Force -ErrorAction SilentlyContinue
			Remove-Item -Path $hashPath -Recurse -Force -ErrorAction SilentlyContinue
            return $null
        }

        # Calculate the actual checksum of the downloaded file
        $actualChecksum = (Get-FileHash -Path $filePath -Algorithm SHA256 | Select-Object -ExpandProperty Hash).ToUpper()
		$expectedChecksum = ($expectedChecksum -split ' ', 2 | % { $_.ToUpper() })[0]

        # Verify checksum
        if ($actualChecksum -eq $expectedChecksum) {
            Write-Host "Checksum verified successfully."
			Remove-Item -Path $hashPath -Recurse -Force -ErrorAction SilentlyContinue
            return $filePath
        } else {
            Write-Error "Checksum verification failed. Expected: ${expectedChecksum}, Got: ${actualChecksum}"
            Remove-Item -Path $filePath -Recurse -Force -ErrorAction SilentlyContinue
			Remove-Item -Path $hashPath -Recurse -Force -ErrorAction SilentlyContinue
            return $null
        }
    } finally {
        # Ensure cleanup on error
        if (-not $?) {
			Remove-Item -Path $filePath -Recurse -Force -ErrorAction SilentlyContinue
			Remove-Item -Path $hashPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function UninstallApp {
	param (
        [Parameter(Mandatory = $true)]
        [string]$AppName
    )

	$uninstall32 = gci "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall" | foreach { gp $_.PSPath } | ? { $_ -match "$AppName" } | select UninstallString
	$uninstall64 = gci "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" | foreach { gp $_.PSPath } | ? { $_ -match "$AppName" } | select UninstallString

	if ($uninstall64) {
	$uninstall64 = $uninstall64.UninstallString -Replace "msiexec.exe","" -Replace "/I","" -Replace "/X",""
	$uninstall64 = $uninstall64.Trim()
	Write "Uninstalling..."
	start-process "msiexec.exe" -arg "/X $uninstall64 /qb" -Wait}
	if ($uninstall32) {
	$uninstall32 = $uninstall32.UninstallString -Replace "msiexec.exe","" -Replace "/I","" -Replace "/X",""
	$uninstall32 = $uninstall32.Trim()
	Write "Uninstalling..."
	start-process "msiexec.exe" -arg "/X $uninstall32 /qb" -Wait}
}

function New-ManualService {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ServiceName,

        [Parameter(Mandatory=$true)]
        [string]$Command,

        [string]$DisplayName = $ServiceName,
        [string]$Description = "Manually started service with sourced profile and command.",
        [string]$ProfilePath = $PROFILE,

        [string[]]$Arguments = @(),

        [switch]$Force
    )

    # Validate parameters
    if (-Not (Test-Path -Path $ProfilePath -PathType Leaf)) {
        Write-Error "Profile path '$ProfilePath' does not exist."
        return
    }

    # Generate the script name
    $scriptName = "Start$ServiceName.ps1"
    $scriptPath = Join-Path -Path (Split-Path -Path $PROFILE -Parent) -ChildPath $scriptName

    # Check if the script already exists
    if (Test-Path -Path $scriptPath) {
        if ($Force) {
            Remove-Item -Path $scriptPath -Force
        } else {
            Write-Error "Script '$scriptPath' already exists. Use -Force to overwrite."
            return
        }
    }

    # Create the script content
    $scriptContent = @"
# Start$ServiceName.ps1
# Source the profile
. '$ProfilePath'

# Run the command with arguments
Invoke-Expression -Command $Command $Arguments
"@

    # Save the script
    Set-Content -Path $scriptPath -Value $scriptContent -Force

    # Register the service
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        Write-Output "Service '$ServiceName' already exists. Skipping installation."
    } else {
        New-Service -Name $ServiceName `
                   -BinaryPathName "powershell.exe -File `"$scriptPath`"" `
                   -DisplayName $DisplayName `
                   -Description $Description `
                   -StartupType Manual

        Write-Output "Service '$ServiceName' has been created and set to start manually with sourced profile and command."
    }
}

function Start-ManualService {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ServiceName
    )

    # Check if the service exists
    if (-Not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) {
        Write-Error "Service '$ServiceName' does not exist."
        return
    }

    # Start the service
    Start-Service -Name $ServiceName

    Write-Output "Service '$ServiceName' has been started."
}

function Stop-ManualService {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ServiceName
    )

    # Check if the service exists
    if (-Not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) {
        Write-Error "Service '$ServiceName' does not exist."
        return
    }

    # Stop the service
    Stop-Service -Name $ServiceName -Force

    Write-Output "Service '$ServiceName' has been stopped."
}

function Delete-ManualService {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ServiceName
    )

    # Check if the service exists
    if (-Not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) {
        Write-Error "Service '$ServiceName' does not exist."
        return
    }

    # Stop the service if it is running
    if ((Get-Service -Name $ServiceName).Status -eq 'Running') {
        Stop-Service -Name $ServiceName -Force
    }

    # Delete the service
    Remove-Service -Name $ServiceName

    Write-Output "Service '$ServiceName' has been deleted."
}

function yt-dlp-update {
    $execPath = DownloadTempFile -Url "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
    $targetPath = "${env:USERPROFILE}\Apps\yt-dlp.exe"
	Remove-Item -Path $targetPath -Recurse -Force -ErrorAction SilentlyContinue
    mv $execPath $targetPath
}

Function yt-dlp-best {
    uvx yt-dlp `
    --progress `
    --console-title `
    --video-multistreams `
    --audio-multistreams `
    --format-sort "height:1440,fps" `
    --format "bestvideo+bestaudio/best" `
    --check-formats `
    --merge-output-format "mp4/mkv" `
    --recode-video "mp4/mkv" `
    --embed-thumbnail `
    --embed-metadata `
    --embed-chapters `
    --force-keyframes-at-cuts `
    --sponsorblock-mark "all" `
    $args
}

Function yt-dlp-with-subs {
    uvx yt-dlp-best --write-auto-subs --sub-lang "en.*" $args
}

Function ffmpeg-to-webm($input_file, $output_file, $crf = 30) {
    Write-Host "Encoding with CRF = ${crf}"
    ffmpeg -i "${input_file}" -c:v libvpx-vp9 -b:v 0 -crf $crf -deadline good -cpu-used 3 -threads 12 -b:a 128k -c:a copy "${output_file}.webm"
}

Function ffmpeg-cut($input_file, $output_file, $from, $to) {
    ffmpeg -ss $from -to $to -i $input_file -c copy $output_file
}

Function extract-clip($video_path, $output_path, $start, $duration) {
    ffmpeg -i $video_path -filter_complex "[0:v][0:s]overlay[v]" -map "[v]" -map 0:a -ss $start -t $duration $output_path
}

function gmm {
    git commit --verbose -m "$($args -join ' ')"
}

function gmma {
    git commit --all --verbose -m "$($args -join ' ')"
}

function gcq {
    git commit --all --amend --verbose --no-edit
}

function grr {
    git remote remove $args
}

function gp {
    git push
}

enable-msys-ucrt

Install-Module git-aliases -Scope CurrentUser -AllowClobber

Set-Alias -Name rmf -Value remove_force
Set-Alias -Name eh -Value edit_here
Set-Alias -Name e -Value edit
Set-Alias -Name econf -Value edit_config
Set-Alias -Name cconf -Value print_config
Set-Alias -Name ls -Value unix_ls

Import-Module PSReadLine
Set-PSReadLineKeyHandler -Chord Tab -Function MenuComplete
$scriptblock = {
    param($wordToComplete, $commandAst, $cursorPosition)
    $Env:_OPEN_WEBUI_COMPLETE = "complete_powershell"
    $Env:_TYPER_COMPLETE_ARGS = $commandAst.ToString()
    $Env:_TYPER_COMPLETE_WORD_TO_COMPLETE = $wordToComplete
    open-webui | ForEach-Object {
        $commandArray = $_ -Split ":::"
        $command = $commandArray[0]
        $helpString = $commandArray[1]
        [System.Management.Automation.CompletionResult]::new(
            $command, $command, 'ParameterValue', $helpString)
    }
    $Env:_OPEN_WEBUI_COMPLETE = ""
    $Env:_TYPER_COMPLETE_ARGS = ""
    $Env:_TYPER_COMPLETE_WORD_TO_COMPLETE = ""
}

Register-ArgumentCompleter -Native -CommandName open-webui -ScriptBlock $scriptblock
