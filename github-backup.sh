#!/bin/bash

# Github backup of all repos to S3 script
#
# Requiresments:
#   
#   aws cli
#   uname
#   read
#   jq
#   curl
#   git
#   tar
#   sed
#   pwd
#
# Example usage:
#   $ bash github-backup.sh -h
#   $ bash github-backup.sh -o your-organization -b s3://path-to-your-bucket-folder -u your-user -t github-api-token

set -o errexit 
set -o pipefail

RET_CODE_OK=0
RET_CODE_ERROR=1

PWD=$(pwd)
DATE=$(date '+%Y-%m-%d')

# Help/Usage function
print_help() {
    echo "$0: Usage"
    echo "    [--help|-h]       Print help"
    echo "    [--organization|-o]    (MANDATORY) Organization name"
    echo "    [--bucket|-b]    (MANDATORY) S3 bucket path"
    echo "    [--user|-u]    (MANDATORY) Github user"
    echo "    [--token|-t]    (MANDATORY) Github api token"    
}

# Parse command line arguments
while test -n "$1"; do
    case "$1" in
    --help|-h)
        print_help
        exit $RET_CODE_OK
        ;;
    --organization|-o)
        ORGANIZATION=$2
        shift
        ;;
    --bucket|-b)
        BUCKET=$2
        shift
        ;;
    --user|-u)
        USER=$2
        shift
        ;;
    --token|-t)
        TOKEN=$2
        shift
        ;;
    *)
        echo "$0: Unknown Argument: $1"
        print_help
        exit $RET_CODE_ERROR;
        ;;
    esac

    shift
done

# Check for supported operating system
p_uname=`whereis uname | cut -d' ' -f2`
if [ ! -x "$p_uname" ]; then
    echo "$0: No UNAME available in the system" 
    exit $RET_CODE_ERROR;
fi
OS=`$p_uname`
if [ "$OS" != "Linux" ]; then
    echo "$0: Unsupported OS!" 
    exit $RET_CODE_ERROR;
fi

# Check if AWS cli is available in the system
p_aws=`whereis aws | cut -d' ' -f2`
if [ ! -x "$p_aws" ]; then
    echo "$0: No AWS CLI available in the system!"
    exit $RET_CODE_ERROR;
fi

# Check if sed is available in the system
p_sed=`whereis sed | cut -d' ' -f2`
if [ ! -x "$p_sed" ]; then
    echo "$0: No sed available in the system!"
    exit $RET_CODE_ERROR;
fi

# Check if jq is available in the system
p_jq=`whereis jq | cut -d' ' -f2`
if [ ! -x "$p_jq" ]; then
    echo "$0: No jq available in the system!"
    exit $RET_CODE_ERROR;
fi

# Check if git is available in the system
p_git=`whereis git | cut -d' ' -f2`
if [ ! -x "$p_git" ]; then
    echo "$0: No git available in the system!"
    exit $RET_CODE_ERROR;
fi

# Check if curl is available in the system
p_curl=`whereis curl | cut -d' ' -f2`
if [ ! -x "$p_curl" ]; then
    echo "$0: No curl available in the system!"
    exit $RET_CODE_ERROR;
fi

# Check if curl is available in the system
p_tar=`whereis tar | cut -d' ' -f2`
if [ ! -x "$p_tar" ]; then
    echo "$0: No tar available in the system!"
    exit $RET_CODE_ERROR;
fi

# Check if mandatory argument is present?
if [ -z "$ORGANIZATION" -o -z "$BUCKET" -o -z "$USER" -o -z "$TOKEN" ]; then
    echo "$0: Required argument is missing! Please, consult with the help (-h)!" 
    exit $RET_CODE_ERROR;
fi

echo "$0: Job core execution started at: `date \"+%Y-%m-%d %H:%M:%S\"`"

if [ ! -d "$PWD/repos/" ]; then
    mkdir repos
    echo "Repos directory created."        
fi 

PAGE=0
while true; do
    let "PAGE+=1"
    REPOS_CMD=$("$p_curl" --silent --user "$USER":"$TOKEN" https://api.github.com/orgs/"$ORGANIZATION"/repos?page="$PAGE" | "$p_jq" '.[].ssh_url' | "$p_sed" -e 's/"//g')
    if [ -z "${REPOS_CMD}" ]; then break; fi
    ALL_REPOS_TMP="${ALL_REPOS_TMP}"$'\n'"${REPOS_CMD}"
done

ALL_REPOS=$(echo "$ALL_REPOS_TMP" | "$p_sed" '/^$/d')

if [ -z "${ALL_REPOS}" ]; then 
    echo "Can not get repository links from github." 
fi

while read -r REPO_LINK; do
    echo "Start working on $REPO_LINK"
    REPO_NAME=${REPO_LINK#*/}
    if "$p_git" clone --mirror "$REPO_LINK" "$PWD/repos/$REPO_NAME" > /dev/null; then
        echo "$REPO_NAME repo clone is succesful."
    else
        echo "Can not clone $REPO_NAME."
    fi
    if [ -d "$PWD/repos/$REPO_NAME" ]; then
        if tar -zcvf "$REPO_NAME".tar.gz -C "$PWD/repos/" "$REPO_NAME" > /dev/null; then
            echo "$REPO_NAME archive is ready."
        else 
            echo "Can not archive $REPO_NAME."
        fi
        if "$p_aws" s3 cp "$PWD" "$BUCKET/$DATE/" --recursive --exclude "*" --include "*.gz" > /dev/null; then
            echo "$REPO_NAME is copied to S3."
        else
            echo "Error when coping $REPO_NAME to S3."
        fi
        if rm -rf "$PWD/$REPO_NAME"* "$PWD/repos/$REPO_NAME" > /dev/null; then
            echo "$REPO_NAME is removed from disk."
        else
            echo "Can not remove $REPO_NAME."
        fi
    fi 
done <<< "$ALL_REPOS"

echo "$0: Job core execution ended at: `date \"+%Y-%m-%d %H:%M:%S\"`"

exit $RET_CODE_OK


