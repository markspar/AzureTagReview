<#PSScriptInfo

.USAGE
    read all subs/rgs/objects that are in scope, compare to list of standards, fix where direct matches are easy,
    output all potential issues to a file (in storage account?), write potential issues to log as warnings
    e.g. Environment not environment, CostCenter not cost center
    e.g. Environment has approved values of Dev, Test, Staging, Prod, any other value is a warning, fix simple errors

    read variables - subscription list, RG only, -whatif flag, object types to check, tag list, value list
    iterate through subscriptions
        get all rgs
        if not rg only, get all other objects
        for each object, get environment tags
            for each tag, get tag name and tag value
                temptagname = lowercase and trim and remove internal spaces from tag name
                    if temp tag name in lowercase tag list, and tag name not equal to tag list name
                        create new tag with tag list name and tag value
                    if lowercase tag value 

    PARAMETER AzSubscriptionIDs
    The Azure subscription IDs to operate against. By default, it will use the Variable setting named "AutoStartStop Subscriptions"
	Enter as a command-delimited list of IDs (e.g. aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa,bbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb)
    PARAMETER Simulate
    If $true, the runbook will not perform any power actions and will only simulate evaluating the tagged schedules. Use this
    to test your runbook to see what it will do when run normally (Simulate = $false).
	PARAMETER Debug
	If $true, debug-level of logging will be output
    
.PROJECTURI https://github.com/markspar/AzureTagReview
.TAGS
    Azure, Automation, Runbook, Start, Stop, Machine
.OUTPUTS
    Human-readable informational and error messages produced during the job. Not intended to be consumed by another runbook.
.CREDITS
    Written by Mark Sparling
#>

param(
    [parameter(Mandatory = $false)]
    [String] $AzSubscriptionIDs = "Use Variable Value",
    [parameter(Mandatory = $false)]
    [String] $TagNames = "Use Variable Value",
    [parameter(Mandatory = $false)]
    [String] $TagValues = "Use Variable Value",
    [parameter(Mandatory = $false)]
    [bool]$Simulate = $false,
    [parameter(Mandatory = $false)]
    [bool]$DebugLogs = $false
)

$VERSION = "0.1"
$script:DoNotStart = $false

# Main runbook content
try {
    # Ensures you do not inherit an AzContext in your runbook
    Disable-AzContextAutosave -Scope Process
    # Retrieve Subscription ID(s) from variable asset if not specified
    if ($AzSubscriptionIDs -eq "Use Variable Value") {
        $AzSubscriptionIDs = Get-AutomationVariable -Name "AzureTagReview Subscriptions" -ErrorAction Ignore
    }
    # Retrieve environment tag includes from variable asset if not specified
    if ($TagNames -eq "Use Variable Value") {
        $TagNames = Get-AutomationVariable -Name "AzureTagReview Tags" -ErrorAction Ignore
    }
    # Retrieve environment tag excludes from variable asset if not specified
    if ($TagValues -eq "Use Variable Value") {
        $TagValues = Get-AutomationVariable -Name "AzureTagReview Values" -ErrorAction Ignore
    }
    
    $tz = "Eastern Standard Time"
    $startTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date), $tz)

    Write-Output "Runbook started. Version: $VERSION"
	Write-Output "Start time $($startTime)"
    Write-Output "Subscription IDs: [$AzSubscriptionIDs]"
	Write-Output "Tag Names: $($TagNames)"
	Write-Output "Tag Values: $($TagValues)"
    if ($Simulate -eq $true) { Write-Output "*** Running in SIMULATE mode. No power actions will be taken. ***" }
    else { Write-Output "*** Running in LIVE mode. Schedules will be enforced. ***" }
	if ($DebugLogs -eq $true) {	Write-Output "Debug level of logging enabled" }

	$AzIDs = $AzSubscriptionIDs.Split(",")
	foreach ($AzID in $AzIDs) {
		Write-Output "Processing Subscription ID: [$AzId]"
		Connect-AzAccount -Identity -Subscription $AzId > $null
		if ($DebugLogs -eq $true) { Write-Output " Authenticated" }
		Set-AzContext -SubscriptionId $AzId > $null
		if ($DebugLogs -eq $true) { Write-Output " Context set" }
		$CurrentSub = (Get-AzContext).Subscription.Id
		If ($CurrentSub -ne $AzID) { Throw "Could not switch to SubscriptionID: $AzID" }

		# Get a list of all virtual machines in subscription, excluding some environment tags
		$vms = Get-AzVM -Status | Where-Object {(($_.tags.Autostartstop -notin @($null,'')) -and ($_.tags.Environment -notin $EnvironmentExclude))} | Sort-Object Name
		# Get a list of all virtual machines in subscription, including only some environment tags
		#$vms = Get-AzVM -Status | Where-Object {(($_.tags.Autostartstop -ne $null) -and ($_.tags.Environment -in $EnvironmentInclude))} | Sort-Object Name

		Write-Output " Processing [$($vms.Count)] virtual machines found in subscription"
		foreach ($vm in $vms) {
			Write-Output " Processing VM - $($vm.Name)"
			$vmTags = $vm.tags
			if ($DebugLogs -eq $true) {
				Write-Output "  Environment - $($vm.tags.Environment)"
#				Write-Output "  value - $($vmTags)"
			}
		} #foreach vm
		Write-Output " Finished processing subscription"
	} # foreach azsubid
    Write-Output "Finished processing virtual machine schedules"
} # try
catch {
    $errorMessage = $_.Exception.Message
    $line = $_.InvocationInfo.ScriptLineNumber
    throw "Unexpected exception: $errorMessage at $line"
}
finally {
    $EndTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date), $tz)
    Write-Output "Runbook finished (Duration: $(("{0:hh\:mm\:ss}" -f ($EndTime - $startTime))))"
}