#!/bin/sh


# Set up our $PATH so we can get to all required binaries / scripts
PATH="/usr/local/bin:${PATH}"
PATH="$(dirname "${0}")/bin:${PATH}"
export PATH
# Log all stdout and stderr
log.sh --start "/Library/Management/Logs/$(date '+%Y-%m-%d-%H-%M-%S') XX System Setup.log"
exec >> "$(log.sh --file)"; exec 2>&1

log.sh "Starting $(dirname "${0}")"

# Convenience Functions
asuser() { user="$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )"; uid="$(id -u "$user")"; launchctl asuser "${uid}" sudo -u "${user}" "${@}"; }
wait_for_process_to_start() { until pgrep "${1}" >/dev/null; do sleep 1; done; }
wait_for_process_to_stop() { while pgrep "${1}" >/dev/null; do sleep 1; done; }
wait_until_file_exists() { until [ -e "${1}" ]; do sleep 1; done }
wait_until_string_is_added_to_file() { ( tail -f -n0 "${2}" & ) | grep -q "${1}"; }
ibm_notify() { asuser "/Library/Management/Applications/IBM Notifier.app/Contents/MacOS/IBM Notifier" -type "popup" -bar_title "XX Org" -help_button_cta_type infopopup -help_button_cta_payload "If you encounter any problems please email MacSupport@vodafone.com.au or call 1300 860 293" -silent -always_on_top -timeout 1800 "${@}"; }
#
#    Run any command as the currently logged in user:
#         asuser <command>
#    e.g. asuser printenv
#
#    Block until a process is running:
#         wait_for_process_to_start <process_name>
#    e.g. wait_for_process_to_start "Dock"
#
#    Block until a process has stopped:
#         wait_for_process_to_stop <process_name>
#    e.g. wait_for_process_to_stop "JamfAAD"
#
#    Block until a file at specified path exists:
#         wait_until_file_exists <file_path>
#         wait_until_file_exists "/var/log/jamf.log"
#
#    Block until a string has been written to a text file:
#         wait_until_string_is_added_to_file <string> <file_path>
#    e.g. wait_until_string_is_added_to_file /var/log/jamf.log "Downloading"
#


# Easy Jamf Connect Notify
#
nlog="/var/tmp/depnotify.log"
start() { s="STARTING SETUP"; echo "${s}" > "${nlog}"; echo "${s}"; }
image() { s="Command: Image: ${1}"; echo "${s}" >> "${nlog}"; echo "${s}"; }
title() { s="Command: MainTitle: ${1}"; echo "${s}" >> "${nlog}"; echo "${s}"; }
text() { s="Command: MainText: ${1}"; echo "${s}" >> "${nlog}"; echo "${s}"; }
text_image() { s="Command: MainTextImage: ${1}"; echo "${s}" >> "${nlog}"; echo "${s}"; }
status() { s="Status: ${1}"; echo "${s}" >> "${nlog}"; echo "${s}"; }
quit() { s="Command: Quit"; echo "${s}" >> "${nlog}"; sleep 1; rm -f "${nlog}"; echo "${s}"; }
determinate() { s="Command: Determinate: $(grep -o '^status "' "${0}" | wc -l | xargs)"; echo "${s}" >> "${nlog}"; echo "${s}"; }
#
#
#	 Notify Commands
#
#    start              Start logging to DEPNotify.
#    image <path>       Replaces the default notify image with an image at a specified path.
#    title <text>       Changes the main title displayed to users
#    text <text>        Changes the main text displayed to users
#    text_image <path>  Replaces the main text with a custom icon at a specified path.
#    status <text>      Set status text.
#    determinate        Sets the progress bar to be determinate. Length is set automatically.
#    quit               Stop DEPNotify
#


start
determinate
image "/Library/Management/Branding/XX_Org_Logo_RGB.png"
title "Welcome to your new Mac!"
text "We are installing some apps and setting up a few things for you. This process takes approximately 30 minutes, although it could take longer on a slow internet connection."

status "Setting up your Mac..."

# Monitor the Jamf log for connection failures, if connection fails then reboot.
build_attempts="$(defaults read /Library/Management/.build.plist attempts 2>/dev/null)"
if [ -z "${build_attempts}" ]; then
    build_attempts=0
fi
defaults write "/Library/Management/.build.plist" attempts -string "$((${build_attempts}+1))"
if [ ${build_attempts} -gt 3 ]; then
    touch /Library/Management/.buildFailed
    status "Restarting..."
	log.sh "Deleting this script"
	rm -fr "${0}"
	log.sh "Activating Jamf Connect Login Window"
	/usr/local/bin/authchanger -reset -JamfConnect
	log.sh "Sending quit signal to Jamf Connect Notify"
	quit

	# Reboot
	shutdown -r now
fi
(wait_until_file_exists "/var/log/jamf.log"; wait_until_string_is_added_to_file "Could not connect to the JSS" "/var/log/jamf.log"; shutdown -r now) &

log.sh "Setting timezone to Australia/Sydney"
/usr/sbin/systemsetup -settimezone "Australia/Sydney"

log.sh "Setting automatic timezone"
set_automatic_timezone.sh

log.sh "Getting serial number"
serial="$( system_profiler SPHardwareDataType | grep 'Serial Number (system)' | awk '{print $NF}' )"
log.sh "Setting computer name to: VODA-${serial}"
jamf setComputerName -name "VODA-${serial}"

log.sh "Unloading Jamf Check-in LaunchDaemon"
launchctl bootout system /Library/LaunchDaemons/com.jamfsoftware.task.1.plist

if [ "$(uname -m)" = "arm64" ]; then
	log.sh "Installing Rosetta for M1 Macs"
	jamf policy -forceNoRecon -event "install-rosetta"
fi
if codesign -v "/Library/Management/IBM Notifier.app"; then
    log.sh "IBM Notifier is installed and codesigned"
else
    log.sh "Installing IBM Notifier"
    jamf policy -forceNoRecon -event "install-ibm-notifier"
fi

status "Installing Company Portal..."
if [ ! -d "/Applications/Company Portal.app" ]; then
    log.sh "Installing Company Portal..."
	jamf policy -forceNoRecon -event "cportal"
fi

status "Installing Microsoft Defender..."
if [ ! -d "/Applications/Microsoft\ Defender\ ATP.app" ]; then
    log.sh "Installing Microsoft Defender..."
	jamf policy -forceNoRecon -event "mdefender"
fi

status "Installing Microsoft Edge..."
if [ ! -d "/Applications/Microsoft Edge.app" ]; then
	log.sh "Installing Microsoft Edge..."
	jamf policy -forceNoRecon -event "install-microsoft-edge"
fi

status "Installing Microsoft Excel..."
if [ ! -d "/Applications/Microsoft Excel.app" ]; then
	log.sh "Installing Microsoft Excel..."
	jamf policy -forceNoRecon -event "install-microsoft-excel"
fi

status "Installing Microsoft OneNote..."
if [ ! -d "/Applications/Microsoft OneNote.app" ]; then
	log.sh "Installing Microsoft OneNote..."
	jamf policy -forceNoRecon -event "install-microsoft-onenote"
fi

status "Installing Microsoft Outlook..."
if [ ! -d "/Applications/Microsoft Outlook.app" ]; then
    log.sh "Installing Microsoft Outlook..."
	jamf policy -forceNoRecon -event "install-microsoft-outlook"
fi

status "Installing Microsoft PowerPoint..."
if [ ! -d "/Applications/Microsoft PowerPoint.app" ]; then
	log.sh "Installing Microsoft PowerPoint..."
	jamf policy -forceNoRecon -event "install-microsoft-powerpoint"
fi

status "Installing Microsoft Teams..."
if [ ! -d "/Applications/Microsoft Teams.app" ]; then
	log.sh "Installing Microsoft Teams..."
	jamf policy -forceNoRecon -event "mteams"
fi

status "Installing Microsoft Word..."
if [ ! -d "/Applications/Microsoft Word.app" ]; then
	log.sh "Installing Microsoft Word..."
	jamf policy -forceNoRecon -event "install-microsoft-word"
fi

status "Installing Microsoft Onedrive..."
if [ ! -d "/Applications/OneDrive.app" ]; then
	log.sh "Installing Microsoft Onedrive..."
	jamf policy -forceNoRecon -event "install-onedrive"
fi

status "Installing Privileges..."
log.sh "Installing Privileges..."
if [ ! -d "/Applications/Privileges.app" ]; then
	jamf policy -forceNoRecon -event "install-privileges"
fi

status "Installing Vodafone Corporate VPN..."
log.sh "Installing Vodafone Corporate VPN (BIG-IP)..."
if [ ! -d "/Applications/BIG-IP Edge Client.app" ]; then
	jamf policy -forceNoRecon -event "bvpn"
fi

jamf policy -forceNoRecon -event "XX_user_setup"

status "Restarting..."
log.sh "Deleting this script"
rm -fr "${0}"
log.sh "Activating Jamf Connect Login Window"
/usr/local/bin/authchanger -reset -JamfConnect
log.sh "Sending quit signal to Jamf Connect Notify"
quit

# Reboot
shutdown -r now

exit 0
