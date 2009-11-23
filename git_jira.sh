#!/bin/bash
# Copyright 2009 William S. Lear
# Distributed under terms of the GNU General Public License (see LICENSE file)

get_config() {
    echo $(git config --global --get $1 || exit 1)
}

set_config() {
    git config --global $1 $2 || exit 1
}

JIRA_JAR=$(get_config jira.jar)
GIT_JIRA_SERVER=$(get_config jira.server)
GIT_JIRA_USER=$(get_config jira.user)
GIT_JIRA_PASSWORD=$(get_config jira.password)

while [ -z "$JIRA_JAR" -o -z "$GIT_JIRA_SERVER" -o \
     -z "$GIT_JIRA_USER" -o -z "$GIT_JIRA_PASSWORD" ]; do
    printf "Some config values need to be set.  Enter them (with readline\n"
    printf "editing) and I'll store them in $HOME/.gitconfig for you.\n"

    if [ -z "$JIRA_JAR" ]; then
        printf "\nThe Jira CLI Jar file should be installed in the\n"
        printf "release directory where you unpacked Jira CLI\n"
        printf "e.g., /opt/jira-cli-1.5.0/release/jira-cli-1.5.0.jar\n\n"
        read -e -p "Jira cli jar: " ans
        JIRA_JAR=$ans
        set_config jira.jar $JIRA_JAR
    fi

    if [ -z "$GIT_JIRA_SERVER" ]; then
        read -e -p "Jira server (e.g., http://localhost:8080): " ans
        GIT_JIRA_SERVER=$ans
        set_config jira.server $GIT_JIRA_SERVER
    fi

    if [ -z "$GIT_JIRA_USER" ]; then
        read -e -p "Jira user: " ans
        GIT_JIRA_USER=$ans
        set_config jira.user $GIT_JIRA_USER
    fi

    if [ -z "$GIT_JIRA_PASSWORD" ]; then
        while true; do
            old_tty=$(stty -g)
            trap "stty $old_tty; exit 0" 0 1 2 3 15
            stty -echo
            read -e -p "Jira password: " ans
            GIT_JIRA_PASSWORD=$ans
            printf "\n"
            read -e -p "Confirm jira password: " ans
            printf "\n"
            GIT_JIRA_PASSWORD2=$ans
            if [ "$GIT_JIRA_PASSWORD" != "$GIT_JIRA_PASSWORD2" ]; then
                printf "\nPasswords don't match, try again.\n"
            else
                set_config jira.password "$GIT_JIRA_PASSWORD"
                break
            fi
            stty $old_tty
        done
    fi
done

GIT_JIRA_SETALIAS=$(get_config jira.setalias)

if [ -z "$GIT_JIRA_SETALIAS" ]; then
    GIT_JIRA_ALIAS=$(get_config alias.jira)
    printf "You do not have an alias for git_jira.sh in your gitconfig file.\n"
    read -e -p "Would you like me to add one so you can say 'git jira' instead? ([Y]/N) " ans
    printf "\n"
    ans=$(echo $ans | tr [a-z] [A-Z])
    me=$(readlink -f $0)
    if [ "$ans" == "N" -o "$ans" == "NO" ]; then
        printf "If you'd like to set it in the future, just do:\n"
        printf "%% git config --global alias.jira '!%s'\n\n" $me
    else
        set_config alias.jira "!$me"
        printf "Set alias.jira to !$me\n"
    fi
    set_config jira.setalias "true"
fi

# Create "connection string" for Jira server
server="--server $GIT_JIRA_SERVER"
user="--user $GIT_JIRA_USER"
password="--password $GIT_JIRA_PASSWORD"
conn="$server $user $password"

USAGE="Usage: ${0##*/} <open|close|describe>

open options (-d opens editor):
    [-a|--assignee <assignee>] [-c|--component] <component> [-d|--description]
    [-p|--project <project>] [-x|--suffix <suffix>]
    [-t|--issue_type <issue_type>] -s|--summary <summary>

close options:
    -i|--issue <issue>

describe options (defaults to describing issue of current branch):
    [-i|--issue <issue OR issue branch name>] [-v|--verbose]
"

usage() {
    echo "$USAGE"
    exit 0
}

# Process command line options
TEMP=$(getopt -o 'a:c:di:p:s:t:vx:' --long assignee:,component:,description,issue:,project:,summary:,issue_type:,verbose,suffix: -n 'git_jira' -- "$@")

[ $? != 0 ] && usage

eval set -- "$TEMP"

component=$(get_config jira.component)
description=false
project=$(get_config jira.project)
issue_type=$(get_config jira.issuetype)
issue_type=${issue_type:-Bug}
assignee=$GIT_JIRA_USER
summary=
suffix=
verbose=false

while true; do
    case "$1" in
        -a|--assignee) assignee=$2; shift 2 ;;
        -c|--component) component=$2; shift 2 ;;
        -d|--description) description=true; shift ;;
        -i|--issue) issue=$2; shift 2 ;;
        -p|--project) project=$2; shift 2 ;;
        -s|--summary) summary=$2; shift 2 ;;
        -t|--issue_type) issue_type=$2; shift 2 ;;
        -v|--verbose) verbose=true; shift ;;
        -x|--suffix) suffix=$2; shift 2 ;;
        --) shift ; break ;;
        *) printf "[$1] Internal getopt error!\n" ; exit 1 ;;
    esac
done

for arg; do
    case "$arg" in
        open) action=open ;;
        close) action=close ;;
        describe) action=describe ;;
        *) printf "Invalid or extraneous action \"$arg\"\n"; usage ;;
    esac
done

if [ -z "$action" ]; then
    printf "You must provide an action (open|close|describe)\n"
    usage
fi

case "$action" in
    open)
        if [ -z "$summary" ]; then
            printf "You must provide a summary\n"
            usage
        fi

        if [ -z "$project" ]; then
            printf "You must provide a project, either on command line or in git config file\n"
            usage
        fi

        if [ -z "$component" ]; then
            printf "You must provide a component, either on command line or in git config file\n"
            usage
        fi

        # create issue
        assignee="--assignee $assignee"
        project="--project $project"
        issue_type="--type $issue_type"
        action="--action createIssue $project $assignee $issue_type"
        if $description; then
            tmpfile=/tmp/$$.git-jira
            trap "rm -f $tmpfile" 0 1 2 3 15

            editor=$GIT_EDITOR
            [ -z "$editor" ] && editor=$VISUAL
            [ -z "$editor" ] && editor=$EDITOR
            [ -z "$editor" ] && editor=vi

            cat << EOF > $tmpfile

# Enter a description above; exit to abort, exit with no changes or delete
# all lines or lines that do not have '#' in front.
EOF

            $editor $tmpfile
            if [ $? -ne 0 ]; then
                echo "Editor session failed, aborting create"
                rm -f $tmpfile
                exit 1
            fi

            dlines=$(grep -v '^ *#' $tmpfile)
            ndlines=$(grep -v '^ *#' $tmpfile | wc -l | gawk '{ print $1; }' )
            if [ $ndlines -gt 0 ]; then
                jissue=$(java -jar $JIRA_JAR $conn $action --components "$component" --description "$dlines" --summary "$summary")
                if [ $? -ne 0 ]; then
                    printf "Issue creation failed.\n"
                    rm -f $tmpfile
                    exit 1
                fi
                jissue=$(echo $jissue | gawk '{ print $2}')
            else
                echo "Issue creation aborted"
                rm -f $tmpfile
                exit 0
            fi
            rm -f $tmpfile
        else
            jissue=$(java -jar $JIRA_JAR $conn $action --components "$component" --summary "$summary")
            if [ $? -ne 0 ]; then
                printf "Issue creation failed.\n"
                exit 1
            fi
            jissue=$(echo $jissue | gawk '{ print $2}')
        fi

        issue=$jissue
        [ -n "$suffix" ] && issue="${issue}_${suffix}"

        if [ -z "$issue" ]; then
            echo "NO ISSUE!"
            exit 1
        fi

        git fetch || { printf "Git fetch failed.\n"; exit 1; }
        r=$(git branch ${issue} origin/master 2>&1)
        if [ $? -ne 0 ]; then
            printf "Git branch creation failed:\n"
            printf "$r\n"
            exit 1
        fi
        printf "git branch ${issue} created\n"
    ;;

    close)
        issue="--issue $issue"
        action="--action progressIssue $issue"
        java -jar $JIRA_JAR $conn $action --step "Resolve Issue" --resolution "Fixed" || exit 1
    ;;

    describe)
        branch=$(git branch | grep '\*' | sed 's/\* //')
        if [ -z "$issue" ]; then
            if [ "$branch" == "master" ]; then
                printf "You need to supply an issue if you are not on an issue branch.\n"
                usage
                exit 1
            fi
            issue=$(echo $branch | sed 's/_.*//')
        else
            issue=$(echo $issue | sed 's/_.*//')
        fi
        action="--action getIssue --issue $issue"
        java -jar $JIRA_JAR $conn $action || exit 1
        if $verbose; then
            action="--action getComments --issue $issue"
            java -jar $JIRA_JAR $conn $action | sed 's/Data for [0-9][0-9]*comments/Comments:/'
        fi
    ;;

    *) printf "Invalid action\n"; usage ;;
esac
