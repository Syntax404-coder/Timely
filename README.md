# TIMELY - GitHub Activity Tracker

**Timely** is a robust Command Line Interface (CLI) utility built with PowerShell. It allows users to track, visualize, and analyze GitHub user activity directly from the terminal.

Designed as a lightweight alternative to web-based trackers, Timely provides instant insights into a developer's productivity, preferred languages, and peak activity hours without requiring external dependencies.

## Project Details

  * **Subject:** CCS 236 / Operating System
  * **Project Type:** CLI Tool / Utility Development
  * **Submitted by:** Domenic R. Taganahan
  * **Submitted to:** Mr. Orlando Cabillos

## Key Features

  * **Visual Analytics:** Renders ASCII-based bar charts (histograms) to visualize activity volume over the last 30 events.
  * **Developer Synopsis:** Generates a quick summary profile including:
      * **Primary Language:** Estimates preferred language based on recently updated repositories.
      * **Commit Frequency:** Calculates the average number of events per week.
      * **Peak Activity:** Identifies the user's most active hour of the day (converted to Manila Time/PHT).
  * **Watchlist Management:** Maintain a local list of users (e.g., teammates, friends) to track multiple profiles simultaneously.
  * **Smart Authentication:** Supports GitHub Personal Access Tokens (PAT) to bypass the default API rate limit (60 requests/hour).
  * **Zero Dependencies:** Runs entirely on native PowerShell (v5.1+) using `Invoke-RestMethod`.

## Prerequisites

  * **OS:** Windows 10/11 (or Linux/macOS via PowerShell Core).
  * **Shell:** PowerShell 5.1 or higher.
  * **Network:** Active internet connection to reach the GitHub API.

## Installation

1.  Clone this repository or download the script file.
    ```powershell
    git clone https://github.com/your-username/timely-cli.git
    ```
2.  Navigate to the directory.
    ```powershell
    cd timely-cli
    ```
3.  Run the script.
    ```powershell
    .\Timely.ps1
    ```

> **Note:** If you encounter a permission error, you may need to change your execution policy for the current session:
> `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process`

## Usage Guide

Upon launching `Timely.ps1`, you will be presented with the main interactive menu:

### 1\. Check Single User

Enter any valid GitHub username. The tool will fetch the latest public events and display:

  * A synopsis box (Language, Frequency, Peak Time).
  * An ASCII activity chart.
  * A chronological list of recent commits, PRs, and issues.

### 2\. Watchlist Management

Allows for batch tracking.

  * **Run Check:** rapidly scans all users in your list in "Brief Mode."
  * **Add User(s):** Add a single user or multiple users at once (separated by spaces or commas).
  * **Remove User:** Remove specific users or clear the entire list.

### 3\. Settings (Authentication)

By default, the GitHub API allows 60 requests per hour for anonymous users. To increase this limit to 5,000 requests per hour:

1.  Go to **GitHub Settings \> Developer Settings \> Personal Access Tokens (Classic)**.
2.  Generate a token with `repo` and `user` scopes.
3.  Paste the token into the **Settings** menu in Timely.

*The token is stored locally in `$HOME\.timely_config.json`.*

## Configuration

Timely creates a persistent JSON configuration file in your home directory to store your watchlist and API token.

  * **File Location:** `C:\Users\{YourName}\.timely_config.json`
  * **Format:**
    ```json
    {
      "Token": "your_github_pat_here",
      "Watchlist": [
        "torvalds",
        "microsoft"
      ]
    }
    ```

## Snapshot

```text
------------------------------------------------
 USER SYNOPSIS: torvalds
 Primary Language: C
 Est. Frequency:   3.2 events/week
 Peak Activity:    14:00 - 14:59 (PHT)
------------------------------------------------

ACTIVITY VOLUME (Last 30 Events)
  2023-11-25 | ######### (4)
  2023-11-26 | #################### (10)
  2023-11-27 | ########### (5)
```

## License

This project is developed for educational purposes under the CCS 236 curriculum.
