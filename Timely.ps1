# Title: ALA for Finals
# Requires PowerShell version 5.1 or higher

<#
.SYNOPSIS
    TIMELY - An Activity Time Tracking Utility Using PowerShell
    A robust tool to track GitHub interactions

.DESCRIPTION
    TIMELY is a CLI utility developed for CCS 236.
    It fetches GitHub user activity, visualizes data volume with ASCII charts,
    manages user watchlists, and supports authentication tokens.
#>

# --- CONFIGURATION & STORAGE ---

$ConfigPath = "$HOME\.timely_config.json"

if (-not (Test-Path $ConfigPath)) {
    $DefaultConfig = @{
        Token = ""
        Watchlist = @()
    }
    $DefaultConfig | ConvertTo-Json | Out-File $ConfigPath -Encoding utf8
}

function Get-Config {
    $Data = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    # Ensure Watchlist is always an array
    if ($Data.Watchlist -is [string]) {
        $Data.Watchlist = @($Data.Watchlist)
    }
    return $Data
}

function Save-Config ($ConfigObj) {
    $ConfigObj | ConvertTo-Json | Out-File $ConfigPath -Encoding utf8
}

function Get-AuthHeaders {
    $Config = Get-Config
    $Headers = @{ "User-Agent" = "Timely-CLI" }
    if (-not [string]::IsNullOrWhiteSpace($Config.Token)) {
        $Headers["Authorization"] = "token $($Config.Token)"
    }
    return $Headers
}

# --- SYNOPSIS & ANALYTICS ---

function Show-UserSynopsis ($TargetUser, $Events) {
    # 1. Calculate Frequency (Events per Week)
    $WeeklyFreq = "N/A"
    if ($Events.Count -ge 1) {
        $Newest = [DateTime]$Events[0].created_at
        $Oldest = [DateTime]$Events[-1].created_at
        
        $DaysDiff = ($Newest - $Oldest).TotalDays
        if ($DaysDiff -lt 1) { $DaysDiff = 1 }
        
        $RawFreq = ($Events.Count / ($DaysDiff / 7))
        $WeeklyFreq = "{0:N1}" -f $RawFreq
    }

    # 2. Identify Most Used Language (Fetch top 20 recent repos)
    $LangUrl = "https://api.github.com/users/$TargetUser/repos?sort=updated&per_page=20"
    $TopLang = "Unknown"
    
    try {
        $Repos = Invoke-RestMethod -Uri $LangUrl -Headers (Get-AuthHeaders) -ErrorAction SilentlyContinue
        if ($Repos) {
            $TopLangObj = $Repos | Where-Object { $_.language -ne $null } | Group-Object language | Sort-Object Count -Descending | Select-Object -First 1
            if ($TopLangObj) { $TopLang = $TopLangObj.Name }
        }
    } catch {
        $TopLang = "Limit Reached"
    }

    # 3. Identify Peak Activity Time (Manila Time UTC+8)
    $PeakTime = "N/A"
    if ($Events.Count -ge 1) {
        # Convert all timestamps to Manila Time (+8) and extract the Hour
        $Hours = $Events | ForEach-Object { 
            ([DateTime]$_.created_at).AddHours(8).Hour 
        }
        # Find the most frequent hour
        $TopHourGrp = $Hours | Group-Object | Sort-Object Count -Descending | Select-Object -First 1
        
        if ($TopHourGrp) {
            $H = [int]$TopHourGrp.Name
            # Format as a time range (e.g. 14:00 - 15:00)
            $PeakTime = "{0:00}:00 - {0:00}:59 (PHT)" -f $H
        }
    }

    # 4. Print Synopsis Box
    Write-Host "------------------------------------------------" -ForegroundColor DarkGray
    Write-Host " USER SYNOPSIS: $TargetUser" -ForegroundColor White
    Write-Host " Primary Language: " -NoNewline; Write-Host "$TopLang" -ForegroundColor Yellow
    Write-Host " Est. Frequency:   " -NoNewline; Write-Host "$WeeklyFreq events/week" -ForegroundColor Cyan
    Write-Host " Peak Activity:    " -NoNewline; Write-Host "$PeakTime" -ForegroundColor Green
    Write-Host "------------------------------------------------" -ForegroundColor DarkGray
}

# --- VISUALIZATION HELPERS ---

function Show-ActivityChart ($Events) {
    if ($Events.Count -eq 0) { return }

    Write-Host ""
    Write-Host "ACTIVITY VOLUME (Last 30 Events)" -ForegroundColor DarkCyan
    
    # Group events by Date
    $Grouped = $Events | Group-Object { ([DateTime]$_.created_at).ToString("yyyy-MM-dd") } | Sort-Object Name

    foreach ($Day in $Grouped) {
        $Count = $Day.Count
        $BarLength = $Count * 2 
        $Bar = "#" * $BarLength 
        
        $Color = "Green"
        if ($Count -gt 5) { $Color = "Yellow" }
        if ($Count -gt 10) { $Color = "Red" }

        Write-Host ("  " + $Day.Name + " | ") -NoNewline -ForegroundColor Gray
        Write-Host ("{0} ({1})" -f $Bar, $Count) -ForegroundColor $Color
    }
    Write-Host ""
}

# --- UI HELPERS ---
function Show-Logo {
    Clear-Host
    Write-Host '888888888888  88  88b           d88  88888888888  88      8b        d8' -ForegroundColor Magenta
    Write-Host '     88       88  888b         d888  88           88       Y8,    ,8P' -ForegroundColor Magenta
    Write-Host '     88       88  88`8b       d8''88  88           88        Y8,  ,8P' -ForegroundColor Magenta
    Write-Host '     88       88  88 `8b     d8'' 88  88aaaaa      88         "8aa8"' -ForegroundColor Magenta
    Write-Host '     88       88  88  `8b   d8''  88  88"""""      88          `88''' -ForegroundColor Magenta
    Write-Host '     88       88  88   `8b d8''   88  88           88           88' -ForegroundColor Magenta
    Write-Host '     88       88  88    `888''    88  88           88           88' -ForegroundColor Magenta
    Write-Host '     88       88  88     `8''     88  88888888888  88888888888  88' -ForegroundColor Magenta
    Write-Host ''
    Write-Host ':::::::::::::::  A GITHUB ACTIVITY TRACKER v2.3   :::::::::::::::' -ForegroundColor White
    Write-Host '-----------------------------------------------------------------' -ForegroundColor Gray
    Write-Host ''
}

function Pause-Script {
    Write-Host ''
    Write-Host 'Press any key to return to menu...' -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Get-UserActivity {
    param ( 
        [string]$TargetUser,
        [switch]$BriefMode 
    )

    $Url = "https://api.github.com/users/$TargetUser/events"
    
    if (-not $BriefMode) {
        Write-Host "TIMELY is fetching data for '$TargetUser'..." -ForegroundColor DarkGray
    }

    try {
        $Response = Invoke-RestMethod -Uri $Url -Headers (Get-AuthHeaders) -ErrorAction Stop

        if ($null -eq $Response -or $Response.Count -eq 0) {
            Write-Host " [!] No recent public activity found for $TargetUser." -ForegroundColor Yellow
            return
        }

        if (-not $BriefMode) {
            # Call the Synopsis Function
            Show-UserSynopsis -TargetUser $TargetUser -Events $Response
            
            Show-ActivityChart -Events $Response
            Write-Host ("RECENT ACTIVITY ({0} events):" -f $Response.Count) -ForegroundColor Green
            Write-Host "----------------------------------------" 
        } else {
            Write-Host "User: $TargetUser" -ForegroundColor Magenta
        }

        $Limit = if ($BriefMode) { 3 } else { 10 }

        foreach ($Event in $Response | Select-Object -First $Limit) {
            $Repo = $Event.repo.name
            $Date = [DateTime]$Event.created_at
            $TimeStr = $Date.ToString("MM-dd")
            
            switch ($Event.type) {
                "PushEvent" {
                    $Count = $Event.payload.commits.Count
                    Write-Host (" [$TimeStr] Pushed $Count commits to ") -NoNewline; Write-Host "$Repo" -ForegroundColor Cyan
                }
                "WatchEvent" {
                    Write-Host (" [$TimeStr] Starred ") -NoNewline; Write-Host "$Repo" -ForegroundColor Yellow
                }
                "IssuesEvent" {
                    $Action = $Event.payload.action
                    Write-Host (" [$TimeStr] $Action an issue in ") -NoNewline; Write-Host "$Repo" -ForegroundColor Magenta
                }
                "PullRequestEvent" {
                    $Action = $Event.payload.action
                    Write-Host (" [$TimeStr] $Action PR in ") -NoNewline; Write-Host "$Repo" -ForegroundColor White
                }
                "CreateEvent" {
                    $Type = $Event.payload.ref_type
                    Write-Host (" [$TimeStr] Created $Type in ") -NoNewline; Write-Host "$Repo" -ForegroundColor Cyan
                }
                "ForkEvent" {
                    Write-Host (" [$TimeStr] Forked ") -NoNewline; Write-Host "$Repo" -ForegroundColor DarkCyan
                }
                Default {
                    Write-Host (" [$TimeStr] " + $Event.type + " in ") -NoNewline; Write-Host "$Repo" -ForegroundColor Gray
                }
            }
        }
        if ($BriefMode) { Write-Host "..." -ForegroundColor DarkGray; Write-Host "" }
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq "NotFound") {
            Write-Host "Error: User '$TargetUser' does not exist." -ForegroundColor Red
        }
        elseif ($_.Exception.Response.StatusCode -eq "Forbidden") {
            Write-Host "Error: API Rate Limit Exceeded (403)." -ForegroundColor Red
            Write-Host "Tip: Go to Settings [3] and add a Token." -ForegroundColor DarkGray
        }
        else {
            Write-Host ("Error: " + $_.Exception.Message) -ForegroundColor Red
        }
    }
}

# --- SUB-MENUS ---

function Menu-Watchlist {
    do {
        Show-Logo
        $Config = Get-Config
        Write-Host "WATCHLIST MANAGEMENT" -ForegroundColor Yellow
        Write-Host "Current List: " -NoNewline
        
        if ($null -eq $Config.Watchlist -or $Config.Watchlist.Count -eq 0) { 
            Write-Host "Empty" -ForegroundColor DarkGray 
        } else { 
            Write-Host ($Config.Watchlist -join ", ") -ForegroundColor White 
        }
        
        Write-Host "`n[1] Run Watchlist Check (Brief)"
        Write-Host "[2] Add User(s)"
        Write-Host "[3] Remove Single User"
        Write-Host "[4] Remove ALL Users" -ForegroundColor Red
        Write-Host "[5] Back to Main Menu"
        
        $SubChoice = Read-Host "`nSelect"
        switch ($SubChoice) {
            "1" {
                Clear-Host
                if ($null -eq $Config.Watchlist -or $Config.Watchlist.Count -eq 0) { 
                    Write-Host "Watchlist is empty." -ForegroundColor Red 
                } else {
                    foreach ($User in $Config.Watchlist) {
                        Get-UserActivity -TargetUser $User -BriefMode
                    }
                }
                Pause-Script
            }
            "2" {
                Write-Host "Tip: You can add multiple users separated by commas or spaces." -ForegroundColor DarkGray
                $InputStr = Read-Host "Enter username(s) to add"
                
                $NewUsers = $InputStr -split '[, ]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                
                $AddedCount = 0
                foreach ($User in $NewUsers) {
                    if ($Config.Watchlist -notcontains $User) {
                        $Config.Watchlist += $User
                        $AddedCount++
                    }
                }
                
                if ($AddedCount -gt 0) {
                    Save-Config $Config
                    Write-Host "Added $AddedCount user(s) to watchlist." -ForegroundColor Green
                } else {
                    Write-Host "No new users added (duplicates or empty)." -ForegroundColor Yellow
                }
                Start-Sleep -Seconds 1
            }
            "3" {
                $RemUser = Read-Host "Enter username to remove"
                if ($Config.Watchlist -contains $RemUser) {
                    $Config.Watchlist = $Config.Watchlist | Where-Object { $_ -ne $RemUser }
                    Save-Config $Config
                    Write-Host "User removed." -ForegroundColor Green
                } else {
                    Write-Host "User not found in watchlist." -ForegroundColor Red
                }
                Start-Sleep -Seconds 1
            }
            "4" {
                $Confirm = Read-Host "Are you sure you want to delete the ENTIRE watchlist? (y/n)"
                if ($Confirm -eq 'y') {
                    $Config.Watchlist = @()
                    Save-Config $Config
                    Write-Host "Watchlist cleared successfully." -ForegroundColor Red
                    Start-Sleep -Seconds 1
                }
            }
        }
    } while ($SubChoice -ne "5")
}

function Menu-Settings {
    Show-Logo
    $Config = Get-Config
    Write-Host "SETTINGS and AUTHENTICATION" -ForegroundColor Yellow
    Write-Host "Current Token Status: " -NoNewline
    
    if ([string]::IsNullOrWhiteSpace($Config.Token)) { 
        Write-Host "Not Set (Limited to 60 req/hr)" -ForegroundColor Red 
    } else { 
        Write-Host "******** (Active)" -ForegroundColor Green 
    }

    Write-Host "`nTo increase rate limits, generate a Classic Token (repo/user_info scope)"
    Write-Host "at https://github.com/settings/tokens"
    
    $NewToken = Read-Host "`nEnter new Token (or press Enter to cancel)"
    if (-not [string]::IsNullOrWhiteSpace($NewToken)) {
        $Config.Token = $NewToken
        Save-Config $Config
        Write-Host "Token saved successfully!" -ForegroundColor Green
        Start-Sleep -Seconds 1
    }
}

# --- MAIN PROGRAM LOOP ---
do {
    Show-Logo
    Write-Host "Welcome to TIMELY. Please select an option:"
    Write-Host " [1] Check Single User" -ForegroundColor Green
    Write-Host " [2] Watchlist" -ForegroundColor Cyan
    Write-Host " [3] Settings (Auth)" -ForegroundColor Yellow
    Write-Host " [4] About TIMELY" -ForegroundColor Gray
    Write-Host " [5] Exit" -ForegroundColor Red
    Write-Host ""
    
    $Choice = Read-Host "Enter option number"

    switch ($Choice) {
        "1" {
            Write-Host ""
            $InputUser = Read-Host "Enter GitHub Username"
            if (-not [string]::IsNullOrWhiteSpace($InputUser)) {
                Get-UserActivity -TargetUser $InputUser
            } else {
                Write-Host "Username cannot be empty." -ForegroundColor Red
            }
            Pause-Script
        }
        "2" {
            Menu-Watchlist
        }
        "3" {
            Menu-Settings
        }
        "4" {
            Write-Host ""
            Write-Host "TIMELY CLI v2.3" -ForegroundColor Cyan
            Write-Host "A robust tool to track GitHub interactions."
            Write-Host "Features: Synopsis, ASCII Charts, Watchlist, Auth Support."
            Write-Host ""
            Write-Host "Submitted by: Domenic R. Taganahan" -ForegroundColor DarkGray
            Write-Host "Submitted to: Mr. Orlando Cabillos" -ForegroundColor DarkGray
            Write-Host "Subject: CCS 236 / Operating System" -ForegroundColor DarkGray
            Write-Host "Description: CLI tool/utility development" -ForegroundColor DarkGray
            Write-Host "Requires PowerShell version 5.1 or higher" -ForegroundColor DarkGray
            Pause-Script
        }
        "5" {
            Write-Host "Closing TIMELY..." -ForegroundColor Cyan
            Start-Sleep -Seconds 1
            break
        }
        Default {
            Write-Host "Invalid option. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }

} while ($Choice -ne "5")