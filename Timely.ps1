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

.FEATURES
    * Developer Synopsis (Language, Frequency, Peak Time, Consistency)
    * Visual Analytics (ASCII Activity Charts)
    * Watchlist Management
    * Hyperlink Support for Repositories (opens in browser)
    * Custom Time Zone Settings (User-defined UTC offset)
#>

# --- CONFIGURATION & STORAGE ---

$ConfigPath = "$HOME\.timely_config.json"

if (-not (Test-Path $ConfigPath)) {
    $DefaultConfig = [PSCustomObject]@{
        Token = ""
        Watchlist = @()
        TimeZoneOffset = 8 # Default to PHT (UTC + 8)
    }
    $DefaultConfig | ConvertTo-Json | Out-File $ConfigPath -Encoding utf8
}

function Get-Config {
    if (-not (Test-Path $ConfigPath)) {
        return [PSCustomObject]@{
            Token = ""
            Watchlist = @()
            TimeZoneOffset = 8
        }
    }

    # Load the JSON data
    $Data = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    
    # Create a new, fully mutable PSCustomObject and transfer values (V2.14 Fix)
    $Config = [PSCustomObject]@{
        Token = $Data.Token
        Watchlist = @()
        TimeZoneOffset = 8 # Default value
    }

    # 1. Transfer Watchlist, ensuring it is an array
    if ($Data.Watchlist -ne $null) {
        $Config.Watchlist = @($Data.Watchlist)
    }
    
    # 2. Transfer TimeZoneOffset, ensuring it's a number.
    if ($Data.TimeZoneOffset -ne $null -and $Data.TimeZoneOffset -is [int]) {
        $Config.TimeZoneOffset = $Data.TimeZoneOffset
    }
    
    return $Config
}

function Save-Config ($ConfigObj) {
    # Ensure the object being saved is treated as JSON-serializable structure
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

# V2.15: This function now only retrieves the data; it does NOT print it.
function Get-LanguageData ($TargetUser) {
    $LangUrl = "https://api.github.com/users/$TargetUser/repos?sort=updated&per_page=30"
    $LangData = @{} # Dictionary to hold language size and percentage
    $PrimaryLanguage = "Not Found (No coded repos)"
    $TotalSize = 0
    
    try {
        $Repos = Invoke-RestMethod -Uri $LangUrl -Headers (Get-AuthHeaders) -ErrorAction Stop

        if ($Repos) {
            $Repos | ForEach-Object { 
                # Use repository size as a simple proxy for contribution weight
                if ($_.language -ne $null) {
                    $LangName = $_.language
                    $Size = $_.size
                    $TotalSize += $Size
                    
                    if ($LangData.ContainsKey($LangName)) {
                        $LangData[$LangName] += $Size
                    } else {
                        $LangData[$LangName] = $Size
                    }
                }
            }

            if ($TotalSize -gt 0) {
                $TopLangs = $LangData.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
                
                # Capture the actual top language
                if ($TopLangs.Count -gt 0) {
                    $PrimaryLanguage = $TopLangs[0].Name
                }
            }
        }
    }
    catch {
        # Silent fail if rate limit hit, return defaults
    }
    
    # Return the analysis object
    return [PSCustomObject]@{
        LanguageData = $LangData
        PrimaryLanguage = $PrimaryLanguage
        TotalSize = $TotalSize
    }
}

# V2.15: This function now handles the printing of the language breakdown.
function Print-LanguageBreakdown ($LangAnalysisObj) {
    $LangData = $LangAnalysisObj.LanguageData
    $TotalSize = $LangAnalysisObj.TotalSize
    
    if ($TotalSize -gt 0) {
        Write-Host " LANGUAGE BREAKDOWN (Top 5 of 30 recent repos)" -ForegroundColor DarkGray
        
        $TopLangs = $LangData.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5
        
        foreach ($Lang in $TopLangs) {
            $Percent = [math]::Round(($Lang.Value / $TotalSize) * 100, 1)
            $BarLength = [math]::Floor($Percent / 5) # Bar length 20 max
            $Bar = "=" * $BarLength 

            # V2.13 Formatting
            $Output = "  {0,-18} {1,6}% | {2}" -f $Lang.Name, $Percent, $Bar
            
            $Color = "White"
            if ($Percent -gt 50) { $Color = "Green" }
            elseif ($Percent -gt 25) { $Color = "Yellow" }
            Write-Host $Output -ForegroundColor $Color
        }
        Write-Host ""
    }
}

function Show-UserSynopsis ($TargetUser, $Events, $PrimaryLanguage) {
    $Config = Get-Config
    $Offset = $Config.TimeZoneOffset # User-defined offset (e.g., 8, -5, 0)

    # 1. Calculate Frequency (Events per Week)
    $WeeklyFreq = "N/A"
    $Consistency = "N/A"
    $EventsCount = $Events.Count
    
    if ($EventsCount -ge 1) {
        $Newest = [DateTime]$Events[0].created_at
        $Oldest = [DateTime]$Events[-1].created_at
        
        $DaysDiff = ([DateTime]::Now - $Oldest).TotalDays
        if ($DaysDiff -lt 1) { $DaysDiff = 1 }
        
        $RawFreq = ($EventsCount / ($DaysDiff / 7))
        $WeeklyFreq = "{0:N1}" -f $RawFreq

        # 2. Activity Consistency 
        $ActiveDays = $Events | ForEach-Object { ([DateTime]$_.created_at).Date } | Select-Object -Unique
        $TotalDays = [math]::Ceiling($DaysDiff)
        $ConsistencyRaw = ($ActiveDays.Count / $TotalDays) * 100
        $Consistency = "{0:N0}% ({1}/{2} days active)" -f $ConsistencyRaw, $ActiveDays.Count, $TotalDays
    }

    # 3. Identify Most Used Language 
    $TopLang = $PrimaryLanguage

    # 4. Identify Peak Activity Time
    $PeakTime = "N/A"
    $TimeZoneStr = "UTC"
    if ($Offset -gt 0) { $TimeZoneStr = "UTC +$Offset" }
    elseif ($Offset -lt 0) { $TimeZoneStr = "UTC $Offset" }
    if ($Offset -eq 8) { $TimeZoneStr += " (PHT)" } # Add PHT context
    if ($Offset -eq 0) { $TimeZoneStr = "UTC (GMT/Zulu)" }


    if ($EventsCount -ge 1) {
        $Hours = $Events | ForEach-Object { 
            ([DateTime]$_.created_at).AddHours($Offset).Hour 
        }
        $TopHourGrp = $Hours | Group-Object | Sort-Object Count -Descending | Select-Object -First 1
        
        if ($TopHourGrp) {
            $H = [int]$TopHourGrp.Name
            $PeakTime = "{0:00}:00 - {0:00}:59 ({1})" -f $H, $TimeZoneStr
        }
    }

    # 5. Print Synopsis Box
    Write-Host "------------------------------------------------" -ForegroundColor DarkGray
    Write-Host " USER SYNOPSIS: $TargetUser" -ForegroundColor White
    Write-Host " Primary Language: " -NoNewline; Write-Host "$TopLang" -ForegroundColor Yellow
    Write-Host " Est. Frequency:   " -NoNewline; Write-Host "$WeeklyFreq events/week" -ForegroundColor Cyan
    Write-Host " Consistency:      " -NoNewline; Write-Host "$Consistency" -ForegroundColor Green
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
    
    # 1. Define the logo lines (using the largest, cleanest format from V2.11)
    $LogoLines = @(
        '88888888888 8888888 888b     d888 8888888888 888    Y88b   d88P'
        '    888       888   8888b   d8888 888        888     Y88b d88P '
        '    888       888   88888b.d88888 888        888      Y88o88P  '
        '    888       888   888Y88888P888 8888888    888       Y888P   '
        '    888       888   888 Y888P 888 888        888        888    '
        '    888       888   888  Y8P  888 888        888        888    '
        '    888       888   888   "   888 888        888        888    '
        '    888     8888888 888       888 8888888888 88888888   888    '
    )
    
    # 2. Get terminal width and calculate padding
    $ConsoleWidth = $Host.UI.RawUI.WindowSize.Width
    $MaxLogoWidth = ($LogoLines | Measure-Object -Maximum -Property Length).Maximum

    # Calculate padding for centering
    $Padding = [math]::Floor(($ConsoleWidth - $MaxLogoWidth) / 2)
    if ($Padding -lt 0) { $Padding = 0 }
    $PadString = " " * $Padding

    # 3. Print the centered logo
    foreach ($Line in $LogoLines) {
        # Use PadRight to align the logo's right edge, then apply left padding.
        $PaddedLine = ($Line).PadRight($MaxLogoWidth)
        Write-Host "$PadString$PaddedLine" -ForegroundColor Magenta
    }

    Write-Host ""
    
    # 4. Center the divider text (V2.15)
    $DividerText = 'A GITHUB ACTIVITY TRACKER v2.15'
    $DividerLine = '-----------------------------------------------------------------'
    
    # Use PadLeft with the center calculation to dynamically center these lines
    $PaddedDividerText = $DividerText.PadLeft(([math]::Floor(($ConsoleWidth + $DividerText.Length) / 2)))
    $PaddedDividerLine = $DividerLine.PadLeft(([math]::Floor(($ConsoleWidth + $DividerLine.Length) / 2)))

    Write-Host "$PaddedDividerText" -ForegroundColor White
    Write-Host "$PaddedDividerLine" -ForegroundColor Gray
    Write-Host ""
}

function Pause-Script {
    Write-Host ''
    Write-Host 'Press any key to return to menu...' -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Open-RepoLink ($RepoName) {
    if (-not [string]::IsNullOrWhiteSpace($RepoName)) {
        $Url = "https://github.com/$RepoName"
        Write-Host "Opening $Url..." -ForegroundColor DarkGray
        Start-Process $Url
    }
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
            # 1. Fetch language data without printing (V2.15 FIX)
            $LangAnalysis = Get-LanguageData -TargetUser $TargetUser 
            $TopLang = $LangAnalysis.PrimaryLanguage 

            # 2. Display the Synopsis (PRIORITY - V2.15 FIX)
            Show-UserSynopsis -TargetUser $TargetUser -Events $Response -PrimaryLanguage $TopLang
            
            # 3. Display Language Breakdown (SECOND - V2.15 FIX)
            Print-LanguageBreakdown -LangAnalysisObj $LangAnalysis 

            Show-ActivityChart -Events $Response
            
            Write-Host ("RECENT ACTIVITY ({0} events):" -f $Response.Count) -ForegroundColor Green
            Write-Host "----------------------------------------" 
            Write-Host " [Click] - Open Repository Link" -ForegroundColor DarkGray
        } else {
            Write-Host "User: $TargetUser" -ForegroundColor Magenta
        }

        $Limit = if ($BriefMode) { 3 } else { 10 }
        $RepoLinks = @{} # Store repos for quick access

        foreach ($Event in $Response | Select-Object -First $Limit) {
            $Repo = $Event.repo.name
            $Date = [DateTime]$Event.created_at
            $TimeStr = $Date.ToString("MM-dd")
            
            # Map a short number to the repository name for easy selection
            $LinkIndex = $RepoLinks.Count + 1
            $RepoLinks[$LinkIndex] = $Repo

            Write-Host "[$LinkIndex] " -NoNewline -ForegroundColor White
            
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
        
        if (-not $BriefMode) {
            Write-Host ""
            $LinkChoice = Read-Host "Enter the number next to a repo to open its link, or press Enter"
            if ($RepoLinks.ContainsKey([int]$LinkChoice)) {
                Open-RepoLink -RepoName $RepoLinks[[int]$LinkChoice]
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
    Write-Host "------------------------------------------------" -ForegroundColor DarkGray
    
    # --- Auth Token Status ---
    Write-Host "Current Token Status: " -NoNewline
    if ([string]::IsNullOrWhiteSpace($Config.Token)) { 
        Write-Host "Not Set (Limited to 60 req/hr)" -ForegroundColor Red 
    } else { 
        Write-Host "******** (Active)" -ForegroundColor Green 
    }

    # --- Time Zone Setting Display ---
    $Offset = $Config.TimeZoneOffset
    $TZDesc = "UTC"
    if ($Offset -gt 0) { $TZDesc = "UTC +$Offset" }
    elseif ($Offset -lt 0) { $TZDesc = "UTC $Offset" }
    
    # Add common names for clarity
    if ($Offset -eq 8) { $TZDesc += " (PHT)" }
    if ($Offset -eq 0) { $TZDesc = "UTC (GMT/Zulu)" }


    Write-Host "Current Time Zone for Analysis: " -NoNewline; Write-Host "$TZDesc" -ForegroundColor Cyan

    Write-Host "`n[1] Update GitHub Personal Access Token"
    Write-Host "[2] Set Time Zone Offset (UTC +/- X)"
    Write-Host "[3] Back to Main Menu"

    $Choice = Read-Host "`nSelect"
    switch ($Choice) {
        "1" {
            Write-Host "`nTo increase rate limits, generate a Classic Token (repo/user_info scope)" -ForegroundColor DarkGray
            Write-Host "at https://github.com/settings/tokens" -ForegroundColor DarkGray
            
            $NewToken = Read-Host "`nEnter new Token (or press Enter to keep current)"
            if (-not [string]::IsNullOrWhiteSpace($NewToken)) {
                $Config.Token = $NewToken
                Save-Config $Config
                Write-Host "Token saved successfully!" -ForegroundColor Green
                Start-Sleep -Seconds 1
            }
        }
        "2" {
            Write-Host "------------------------------------------------" -ForegroundColor DarkGray
            Write-Host "   Set your Time Zone Offset (Enter the number only)" -ForegroundColor Yellow
            Write-Host "------------------------------------------------" -ForegroundColor DarkGray
            Write-Host "Common Presets:" -ForegroundColor DarkGray
            Write-Host "    +8 (Philippine Standard Time, Manila)"
            Write-Host "    +5 (Pakistan Standard Time, Karachi)"
            Write-Host "    +1 (Central European Time, Berlin)"
            Write-Host "    -4 (Atlantic Standard Time, Puerto Rico)"
            Write-Host "    -5 (Eastern Standard Time, New York)"
            Write-Host "    -8 (Pacific Standard Time, Los Angeles)"
            Write-Host "    +10 (Australian Eastern Time, Sydney)"
            Write-Host "    -3 (Argentina Standard Time, Buenos Aires)"
            Write-Host "     0 (Coordinated Universal Time / GMT, London)"
            Write-Host "    +4 (Gulf Standard Time, Dubai)"
            Write-Host ""
            
            $NewOffsetInput = Read-Host "`nEnter the UTC Offset (e.g., +8, -5, or 0)"
            
            # --- Input Validation ---
            if ($NewOffsetInput -match '^[+-]?\d+$') {
                $NewOffset = [int]$NewOffsetInput
                if ($NewOffset -ge -12 -and $NewOffset -le 14) { # Standard UTC limits
                    $Config.TimeZoneOffset = $NewOffset
                    Save-Config $Config
                    
                    $NewTZDesc = "UTC"
                    if ($NewOffset -gt 0) { $NewTZDesc += " +$NewOffset" }
                    elseif ($NewOffset -lt 0) { $NewTZDesc += " $NewOffset" }
                    if ($NewOffset -eq 8) { $NewTZDesc += " (PHT)" }
                    
                    Write-Host "Time Zone set to $NewTZDesc successfully." -ForegroundColor Green
                } else {
                    Write-Host "Invalid offset. Must be between -12 and +14." -ForegroundColor Red
                }
            } else {
                Write-Host "Invalid input format. Please use a number like +8 or -5." -ForegroundColor Red
            }
            Start-Sleep -Seconds 2
        }
        "3" {
            # Back to Main Menu (handled by the loop)
        }
        Default {
            Write-Host "Invalid option. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}

# --- MAIN PROGRAM LOOP ---
do {
    Show-Logo
    Write-Host "Welcome to TIMELY. Please select an option:"
    Write-Host " [1] Check Single User" -ForegroundColor Green
    Write-Host " [2] Watchlist" -ForegroundColor Cyan
    Write-Host " [3] Settings (Auth/TZ)" -ForegroundColor Yellow
    Write-Host " [4] About TIMELY" -ForegroundColor Gray
    Write-Host " [5] Exit" -ForegroundColor Red
    Write-Host ""
    
    $RawChoice = Read-Host "Enter option number"
    $Choice = $RawChoice.Trim() 

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
            # --- About TIMELY with Hyperlink Feature and Short Description ---
            Write-Host ""
            Write-Host "TIMELY CLI v2.15 (Display Order Fix)" -ForegroundColor Cyan
            Write-Host "TIMELY is a PowerShell Command Line Utility that serves as a GitHub Activity Tracker. It analyzes a developer's public activity to provide instant insights,"
            Write-Host "including their Primary Language, Commit Frequency, and Peak Activity Hour, visualized with ASCII charts and manageable via a Watchlist."
            Write-Host ""
            
            # Display GitHub Link (Domenic Taganahan / Syntax404-coder)
            Write-Host "For more CLI Tools, visit: " -NoNewline -ForegroundColor DarkGray
            Write-Host "https://github.com/Syntax404-coder" -ForegroundColor Yellow
            Write-Host ""

            Write-Host "Made by: Domenic R. Taganahan" -ForegroundColor DarkGray
            Write-Host "Submitted to: Mr. Orlando Cabillos" -ForegroundColor DarkGray
            Write-Host "Subject: CCS 236 / Operating System" -ForegroundColor DarkGray
            
            # Prompt to open the link
            $Launch = Read-Host "`nWould you like to open the GitHub page? (y/n)"
            if ($Launch -eq 'y') {
                Start-Process "https://github.com/Syntax404-coder"
            }
            
            Pause-Script
        }
        "5" {
            # --- Exit Command ---
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
