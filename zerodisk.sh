#!/bin/bash

# Name:         zerodisk
# Description:  Writes zeros to all the free space on your drives
# By:           Kenneth Aaron , flyingrhino AT orcon DOT net DOT nz
# Github:       https://github.com/flyingrhinonz/
# License:      GPLv3

#   Write a huge file of zeros on each of your mounted partitions and the deletes it.
#       This is useful if you want to make a backup of your disk with:  dd  and you
#       want maximum compression.


set -o nounset      # Crash when an unset variable is used
set -o errtrace     # Capture errors in functions, command substitutions and subshells
set -o errexit      # Exit when a command fails
set -o pipefail     # Capture and crash when pipes failed anywhere in the pipe


declare -r ScriptVersion="ZeroDisk script v1.1.0 , 2022-05-29 , by Kenneth Aaron"

declare -r ProcID="$(echo $$)"          # Script process ID for logging purposes
    # ^ Script process ID for logging purposes
    #   Note - in systemd / journalctl the PID of logger is displayed and not this!
    #   Therefore I log it separately in rhinolib.

declare -r ScriptName="zerodisk"       # Keep this 10 or less characters to ensure log file formatting
    # ^ Script name for logging purposes

declare -r CurrentUser="$( /usr/bin/id -un )"

declare -r ScriptMaxLogLevel="debug"
    # ^ Max log level lines that will be logged (case insensitive)
    #   Supported values - none, critical, error, warning, info, debug
    #   For example - if you set it to "WARNING" then INFO and DEBUG
    #   level lines will not get logged (only CRITICAL, ERROR, WARNING
    #   lines will get logged).
    #   Use "NONE" to disable logging.
    #   Check rhinolib for details on how a typo in this variable is handled.

declare -r SyslogProgName="zerodisk" # This is 'programname' in syslog line
    # ^ This is 'ProgramName' in syslog line (just before the PID value)
    #   Different from ScriptName because ProgramName allows syslog to filter
    #       and log lines with this value in different files.
    #   So you can configure syslog to log all your programs to your
    #       own log file by using your own ProgramName here.
    #   In journalctl use this for tailing based on ProgramName:
    #     journalctl -fa -o short-iso -t ProgramName

declare -r OriginalIFS="${IFS}"
    # ^ In case we need to change it along the way


if ! . /usr/local/lib/rhinolib.sh; then
    echo "CRITICAL - Cannot source:  /usr/local/lib/rhinolib.sh  . Aborting!"
    logger -t "${SyslogProgName}" "CRITICAL - Cannot source:  /usr/local/lib/rhinolib.sh  . Aborting!"
    exit 150
fi


# Setup error traps that send debug information to rhinolib for logging:
trap 'ErrorTrap "$LINENO" "$?" "$BASH_COMMAND" "$_" "${BASH_SOURCE[*]}" "${FUNCNAME[*]:-FUNCNAME_is_unset}" "${BASH_LINENO[*]}"' ERR
    # ^ In RH I found that this trap gives an error: FUNCNAME[*]: unbound variable
    #     so I'm mitigating that by checking for unset and supplying text 'FUNCNAME_is_unset'
trap 'ExitScript' EXIT


SymLinkResolved="(Symlink resolved: $( /bin/readlink --quiet --no-newline $0 )) " || SymLinkResolved=""
LogWrite info "${ScriptVersion}"
LogWrite info "Invoked commandline: $0 $* ${SymLinkResolved}, from directory: ${PWD:-unknown} , by user: $UID: ${CurrentUser:-unknown} , ProcID: ${ProcID} , PPID: ${PPID:-unknown} , Script max log level: ${ScriptMaxLogLevel}"
LogWrite info "Fields explained: PID: Script PID , MN: Module (script) Name , FN: Function Name , LI: LIne number"
    # ^ The reason we have a PID in here is because journalctl logs the PID of the 'logger' command
    #       (that is used to do the actual logging, and this changes every time a line is logged)
    #       and not the PID of the actual script.
    #   MN field is present to keep this log line identical to the log line I use in my python code.


# Setup variables here:

declare InfoOnly="true"
    # ^ Display info only - without actually zeroing anything
declare -a ExcludePaths=( "/share" "/nfs" )
    # ^ An array of paths to exclude from the zeroing process
    #       Eg: declare -a ExcludePaths=( "/share" "/nfs" )

declare -i ProcessPriority="17"

declare Looper
declare FreeMB
declare -i MinFreeMB=100        # Do not proceed if less than this many Mb free
declare -i MinUntouchedMb=50    # Keep this many Mb untouched during the zeroing process
declare ZeroFile="ZerofilE.000.file.zerOFile"
declare -i StartTime=0
declare -i EndTime=0
declare -i ZeroTime=0
declare ErrorMessage="None"
declare DfOut=""


function CheckUser {
LogWrite debug "Function CheckUser started"

if [[ "${CurrentUser}" != "root" ]]; then
    ExitScript error 150 "This script must be run as root"
fi

LogWrite debug "Function CheckUser ended"
}


function ScriptHelp {
cat <<EOF

$ScriptVersion
Script takes 2 arguments:
  arg1: Untouched free space in Mb (write zeros to partition size minus this value)
    miniumum value == 2 Mb
  arg2: Minimum free space in Mb per partition for zerodisk to run
Example: zerodisk 10 25

You can further control the script via these vars:
  InfoOnly=[true|false] - show info only or actually write zeros

EOF
}


function CheckArgsCount {
LogWrite debug "Function CheckArgsCount started. Received args $*"
if (( $# != 2 ))
    then
    ScriptHelp
    ExitScript error 150 "Not enough arguments"
fi
LogWrite debug "Function CheckArgsCount ended"

MinUntouchedMb="${1}"
MinFreeMB="${2}"

if (( MinUntouchedMb < 2 )); then
    echo "Leave minimum 2Mb untouched space"
    ExitScript error 150 "Leave minimum 2Mb untouched space"
fi

if (( MinFreeMB < 3 )); then
    echo "Need at least 3Mb free space to proceed"
    ExitScript error 150 "Need at least 3Mb free space to proceed"
fi

LogWrite debug "Script will run with MinUntouchedMb=${MinUntouchedMb} , MinFreeMB=${MinFreeMB}"
}


function RunZeroDisk {
LogWrite debug "Function RunZeroDisk started"

local SkipMount="false"

cat <<EOF

*** This will load your system ***
*** It may cause latency or packet loss ***

If you CTRL-C during the process you could be left with huge
zeros file(s). If this happens - either delete the file(s) manually,
or start the zerodisk process again and the file(s) will be
deleted for you.

EOF

LogWrite -t info "InfoOnly == ${InfoOnly} , ExcludePaths == ${ExcludePaths[*]}"
echo

DoYouWantToProceed || ExitScript -t info 0 "User aborted zerodisk process before it begun"

# Zero the free diskspace:

echo
DfOut="$( df -lh )"
LogWrite -t debug "Output of:  df   before processing:\n${DfOut}"

echo
echo

for Looper in $( df -l | tail -n +2 | awk '{print $6}' ); do

    for ExcludeLooper in ${ExcludePaths[*]}; do
        if [[ "${Looper}" == "${ExcludeLooper}" ]]; then
            SkipMount="true"
            break
        fi
    done

    if [[ "${SkipMount}" == "true" ]]; then
        LogWrite -t warning "WARNING - skipping mount:  ${Looper}  (per setting in var:  ExcludePaths)"
        echo
        echo "==================================="
        echo
        SkipMount="false"
        continue
    fi

    FreeMB="$( df -m ${Looper} | tail -n 1 | awk '{print $4}' )"
    LogWrite -t debug "Processing:  ${Looper} , ${FreeMB} Mb free"

    if (( FreeMB < MinFreeMB )); then
        LogWrite -t warning "Not enough free space. Skipping"
        echo
        continue
    fi

    (( FreeMB -= MinUntouchedMb ))

    if (( FreeMB < 1 )); then
        LogWrite warning "Size to write = ${FreeMB} , (MinUntouchedMb = ${MinUntouchedMb} , MinFreeMB = ${MinFreeMB})"
        LogWrite -t warning "Not enough free space to process (negative size). Skipping"
        continue
    fi

    StartTime="$(date +%s)"
    if [[ "${InfoOnly}" == "false" ]]; then
        LogWrite -t info "InfoOnly == ${InfoOnly} - zeroing the empty space..."
        LogWrite -t debug "Writing ${FreeMB} Mb of zeros to ${Looper}/${ZeroFile}"
        if ! dcfldd if=/dev/zero of="${Looper}/${ZeroFile}" bs=1M count="${FreeMB}" status=on statusinterval=8; then
            LogWrite error "Error in dcfldd"
        fi
    else
        LogWrite -t info "InfoOnly == ${InfoOnly} - NOT zeroing the empty space (only displaying info) ..."
    fi

    # ^^^ Alternative way to collect output from dcfldd (better for automation) is:
    # ErrorMessage="$( dd if=/dev/zero of="${Looper}/${ZeroFile}" bs=1M count="${FreeMB}" 2>&1 || echo "...FAILED..." )"
    # [[ "${ErrorMessage}" == *"...FAILED..."* ]] && \
    #   {
    #   echo "${ErrorMessage}"
    #   LogWrite error "Error in dd. Message: ${ErrorMessage}. Continuing with next file system..."
    #   } || {
    #   echo "${ErrorMessage}"
    #   LogWrite debug "dd message: ${ErrorMessage}"
    #   }


    sync
    EndTime="$(date +%s)"
    (( ZeroTime=EndTime-StartTime )) || :
    LogWrite info "Completed processing ${Looper} in ${ZeroTime} seconds"

    if [[ -f "${Looper}/${ZeroFile}" ]]; then
        if rm -f "${Looper}/${ZeroFile}"; then
            LogWrite -t info "Successfully deleted: ${Looper}/${ZeroFile}"
        else
            LogWrite -t error "Error in rm ${Looper}/${ZeroFile}"
        fi
    fi

    sync
    echo
    echo "==================================="
    echo

done
echo
DfOut="$( df -lh )"
LogWrite debug "Output of:  df  after processing:\n${DfOut}"
echo "'df' AFTER processing:"
echo "${DfOut}"
echo
echo "Complete"
echo
LogWrite debug "Function RunZeroDisk ended"
}


# Script
CheckUser

if renice "${ProcessPriority}" -p "${ProcID}" &>/dev/null; then
    LogWrite debug "Nice value of PID ${ProcID} set to ${ProcessPriority}" || \
    LogWrite error "Error setting Nice value of PID ${ProcID} to ${ProcessPriority}"
fi

CheckArgsCount $*
RunZeroDisk

ExitScript info 0 "Script completed successfully"


