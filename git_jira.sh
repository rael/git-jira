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
    printf "Some config values need to be set.  Enter them and I'll store\n"
    printf "them in $HOME/.gitconfig for you.\n"

    if [ -z "$JIRA_JAR" ]; then
        printf "\nThe Jira CLI Jar file should be installed in the\n"
        printf "release directory where you unpacked Jira CLI\n"
        printf "e.g., /opt/jira-cli-1.5.0/release/jira-cli-1.5.0.jar\n\n"
        printf "Jira cli jar: "
        read ans
        JIRA_JAR=$ans
        set_config jira.jar $JIRA_JAR
    fi

    if [ -z "$GIT_JIRA_SERVER" ]; then
        printf "Jira server (e.g., http://localhost:8080): "
        read ans
        GIT_JIRA_SERVER=$ans
        set_config jira.server $GIT_JIRA_SERVER
    fi

    if [ -z "$GIT_JIRA_USER" ]; then
        printf "Jira user: "
        read ans
        GIT_JIRA_USER=$ans
        set_config jira.user $GIT_JIRA_USER
    fi

    if [ -z "$GIT_JIRA_PASSWORD" ]; then
        printf "Jira password: "
        read ans
        GIT_JIRA_PASSWORD=$ans
        set_config jira.password $GIT_JIRA_PASSWORD
    fi
done

# Create "connection string" for Jira server
server="--server $GIT_JIRA_SERVER"
user="--user $GIT_JIRA_USER"
password="--password $GIT_JIRA_PASSWORD"
conn="$server $user $password"

usage() {
    echo "Usage: ${0##*/} <open|close|describe> [-a|--assignee <assignee>]"
    echo -e "open options:"
    echo -e "\t[-c|--component] <component> [-p|--project <project>]"
    echo -e "\t[-x|--suffix <suffix>] [-t|--issue_type <issue_type>]"
    echo -e "\t-s|--summary <summary>"
    echo -e "close options:"
    echo -e "\t-i|--issue <issue>"
    echo -e "describe options (defaults to describing issue of current branch):"
    echo -e "\t[-i|--issue <issue OR issue branch name>]"
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
        *) echo "[$1] Internal getopt error!" ; exit 1 ;;
    esac
done

for arg; do
    case "$arg" in
        open) action=open ;;
        close) action=close ;;
        describe) action=describe ;;
        *) echo "Invalid or extraneous action \"$arg\""; usage ;;
    esac
done

if [ -z "$action" ]; then
    echo "You must provide an action (open|close|describe)"
    usage
fi

#if [ "$action" != "open" -a "$action" != "close" \
#     "$action" != "describe" ]; then
#    echo "action must be one of (open|close|describe)"
#    usage
#fi

case "$action" in
    open)
        if [ -z "$summary" ]; then
            echo "You must provide a summary"
            usage
        fi

        if [ -z "$project" ]; then
            echo "You must provide a project, either on command line or in git config file"
            usage
        fi

        if [ -z "$component" ]; then
            echo "You must provide a component, either on command line or in git config file"
            usage
        fi

        # create issue
        assignee="--assignee $assignee"
        project="--project $project"
        issue_type="--type $issue_type"
        action="--action createIssue $project $assignee $issue_type"

        jissue=$(java -jar $JIRA_JAR $conn $action --components "$component" --summary "$summary" | gawk '{ print $2}')

        if [ $? -ne 0 ]; then
            echo "Creation failed"
            exit 0
        fi

        issue=$jissue
        if [ -n "$suffix" ]; then
            issue="${issue}_${suffix}"
        fi

        git fetch || { echo "Git fetch failed"; exit 1; }
        r=$(git branch ${issue} origin/master 2>&1)
        if [ $? -ne 0 ]; then
            echo "Git branch creation failed:"
            echo $r
            exit 1
        fi
        echo "git branch ${issue} created"
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
                echo "You need to supply an issue if you are not on an issue branch."
                usage
                exit 1
            fi
            issue=$(echo $branch | sed 's/_.*//')
        else
            issue=$(echo $issue | sed 's/_.*//')
        fi
        action="--action getIssue --issue $issue"
        java -jar $JIRA_JAR $conn $action
    ;;

    *) echo "Invalid action"; usage ;;
esac
