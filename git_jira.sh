#!/bin/bash

get_config() {
    echo $(git config --global --get $1)
}

set_config() {
    echo $(git config --global $1 $2)
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
        read -e -p "Jira cli jar:" ans
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
            GIT_JIRA_PASSWORD2=$ans
            if [ "$GIT_JIRA_PASSWORD" != "$GIT_JIRA_PASSWORD2" ]; then
                printf "\nPasswords don't match, try again.\n"
            else
                set_config jira.password "[$GIT_JIRA_PASSWORD]"
                break
            fi
            echo stty $old_tty
            stty $old_tty
        done
    fi
done

# Create "connection string" for Jira server
server="--server $GIT_JIRA_SERVER"
user="--user $GIT_JIRA_USER"
password="--password $GIT_JIRA_PASSWORD"
conn="$server $user $password"

usage() {
    printf "Usage: ${0##*/} <open|close|describe> [-a|--assignee <assignee>]\n"
    printf "open options:\n"
    printf "\t[-c|--component] <component> [-p|--project <project>]\n"
    printf "\t[-x|--suffix <suffix>] [-t|--issue_type <issue_type>]\n"
    printf "\t-s|--summary <summary>\n"
    printf "close options:\n"
    printf "\t-i|--issue <issue>\n"
    printf "describe options (defaults to describing issue of current branch):\n"
    printf "\t[-i|--issue <issue OR issue branch name>]\n"
    exit 0
}

# Process command line options
TEMP=$(getopt -o 'a:c:i:p:s:t:x:' --long assignee:,component:,issue:,project:,summary:,issue_type:,suffix: -n 'git_jira' -- "$@")

[ $? != 0 ] && usage

eval set -- "$TEMP"

component=$(get_config jira.component)
project=$(get_config jira.project)
issue_type=$(get_config jira.issuetype)
issue_type=${issue_type:-Bug}
assignee=$GIT_JIRA_USER
summary=
suffix=

while true; do
    case "$1" in
        -a|--assignee) assignee=$2; shift 2 ;;
        -c|--component) component=$2; shift 2 ;;
        -i|--issue) issue=$2; shift 2 ;;
        -p|--project) project=$2; shift 2 ;;
        -s|--summary) summary=$2; shift 2 ;;
        -t|--issue_type) issue_type=$2; shift 2 ;;
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

        jissue=$(java -jar $JIRA_JAR $conn $action --components "$component" --summary "$summary" | gawk '{ print $2}')

        if [ $? -ne 0 ]; then
            printf "Creation failed\n"
            exit 0
        fi

        issue=$jissue
        if [ -n "$suffix" ]; then
            issue="${issue}_${suffix}"
        fi

        git fetch || { printf "Git fetch failed\n"; exit 1; }
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
        java -jar $JIRA_JAR $conn $action --step "Resolve Issue" --resolution "Fixed"
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
        java -jar $JIRA_JAR $conn $action
        action="--action getComments --issue $issue"
        java -jar $JIRA_JAR $conn $action
    ;;

    *) printf "Invalid action\n"; usage ;;
esac
