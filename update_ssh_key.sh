KEY_PATH=~/.ssh/id_ed25519
your_email="your_email@example.com"
TODAY=$(date +"%y%m%d%H%M")

default_check () {
    if [ "$EUID" -ne 0 ]
    then
        echo "Please run as root"
        exit
    fi

    if ! command -v ssh-keygen &> /dev/null
    then
        echo "ssh-keygen could not be found"
        exit
    fi

    if ! command -v gh &> /dev/null
    then
        echo "gh could not be found"
        exit
    fi

    if ! gh auth status
    then
        exit
    fi
}

generate_new_key() {
    echo "Generating new SSH key for GitHub"

    if [ -f "$KEY_PATH" ]; then
        echo "SSH key already exists. Deleting it."
        rm $KEY_PATH
    fi

    ssh-keygen -t ed25519 -f $KEY_PATH -C $your_email -N "" -q

    gh ssh-key add $KEY_PATH.pub --title "$TODAY"
    # echo add pub with title
    echo "add $KEY_PATH.pub with title \"$TODAY\" to GitHub"
}

list_remote_keys() {
    # Split the output into lines
    IFS=$'\n'
    lines=$(gh ssh-key list)
    for line in "${lines[@]}"; do
        TITLE=$(echo $line | awk '{print $1}')
        TYPE=$(echo $line | awk '{print $2}')
        KEY=$(echo $line | awk '{print $3}')
        DATE=$(echo $line | awk '{print $4}')
        ID=$(echo $line | awk '{print $5}')

        echo ""
        echo "Title: $TITLE"
        echo "Type: $TYPE"
        echo "Key: $KEY"
        echo "Date: $DATE"
        echo "ID: $ID"
    done
}

delete_old_remote_keys() {
    IFS=$'\n'
    lines=$(gh ssh-key list)
    for line in "${lines[@]}"; do
        TITLE=$(echo $line | awk '{print $1}')
        TYPE=$(echo $line | awk '{print $2}')
        KEY=$(echo $line | awk '{print $3}')
        DATE=$(echo $line | awk '{print $4}')
        ID=$(echo $line | awk '{print $5}')

        # Convert the title and today's date to seconds since the Unix epoch
        TITLE_REFORMATTED=$(echo $TITLE | sed 's/\(.\{2\}\)\(.\{2\}\)\(.\{2\}\)\(.\{2\}\)\(.\{2\}\)/20\1-\2-\3 \4:\5/')
        TODAY_REFORMATTED=$(echo $TODAY | sed 's/\(.\{2\}\)\(.\{2\}\)\(.\{2\}\)\(.\{2\}\)\(.\{2\}\)/20\1-\2-\3 \4:\5/')

        # Convert the reformatted title and today's date to seconds since the Unix epoch
        TITLE_SECONDS=$(date -d"$TITLE_REFORMATTED" +%s)
        TODAY_SECONDS=$(date -d"$TODAY_REFORMATTED" +%s)

        # Compare the seconds
        if [[ $TITLE_SECONDS -lt $TODAY_SECONDS ]]; then
            echo "Deleting key \"$TITLE\""
            gh ssh-key delete $ID -y
        else
            echo "Skipping key \"$TITLE\""
        fi
    done
}

display_help() {
    echo "Usage: $0 [--generate] [--list] [--delete]"
    echo "Options:"
    echo "  --generate: Generate a new SSH key"
    echo "  --list: List all remote SSH keys"
    echo "  --delete: Delete old remote SSH keys"
    echo "  --help: Display this help message"
}

main() {
    if [ $# -eq 0 ] || [ "$1" == "--help" ]; then
        display_help
        return
    fi

    default_check
    for arg in "$@"
    do
        case $arg in
            --generate)
            generate_new_key
            shift
            ;;
            --list)
            list_remote_keys
            shift
            ;;
            --delete)
            delete_old_remote_keys
            shift
            ;;
            *)            
            ;;
        esac
        shift
    done
}

main "$@"