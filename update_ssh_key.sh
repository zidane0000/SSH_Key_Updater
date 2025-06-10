#!/usr/bin/env bash
KEY_PATH=~/.ssh/id_ed25519
TODAY=$(date +"%y%m%d%H%M%S")

# Associative array: remote hostname => email/account
# Example: declare -A REMOTES=( [xxx.github.com]=user1@domain.com [aaa.github.com]=user2@domain.com )
declare -A REMOTES
REMOTES=( 
    [fake1.github.com]="user1@example.com"
    [fake2.github.com]="user2@example.com"
    [fake3.github.com]="user3@example.com"
    )

default_check () {
    case "$(uname)" in
        Linux|Darwin)
            if [ "$EUID" -ne 0 ]; then
                echo "Please run as root"
                exit
            fi
            ;;
        MINGW*|CYGWIN*|MSYS*|MSYS_NT*)
            if ! net session > /dev/null 2>&1; then
                echo "Please run as administrator"
                exit
            fi
            ;;
        *)
            echo "Unsupported OS"
            exit
            ;;
    esac

    if ! command -v ssh-keygen &> /dev/null; then
        echo "ssh-keygen could not be found"
        exit
    fi

    if ! command -v gh &> /dev/null; then
        echo "gh could not be found"
        exit
    fi

    # Check if we can authenticate to at least one host in REMOTES
    local authenticated=false
    for remote in "${!REMOTES[@]}"; do
        if gh auth status --hostname "$remote" &>/dev/null; then
            authenticated=true
            break
        fi
    done
    
    if [ "$authenticated" = false ]; then
        echo "You are not logged into any of the configured GitHub hosts."
        echo "Please run one of these commands to login:"
        echo ""
        for remote in "${!REMOTES[@]}"; do
            echo "  gh auth login --hostname $remote --scopes \"admin:public_key,admin:ssh_signing_key,gist,read:org,repo,workflow\""
        done
        echo ""
        echo "After login, run this script again."
        exit 1
    fi
}

switch_gh_account() {
    local remote="$1"
    # Check if already authenticated to this host
    if ! gh auth status --hostname "$remote" &>/dev/null; then
        echo "Warning: Not logged into $remote. Skipping operations for this host."
        echo "To enable operations for $remote, run:"
        echo "  gh auth login --hostname $remote --scopes \"admin:public_key,admin:ssh_signing_key,gist,read:org,repo,workflow\""
        return 1
    fi
    return 0
}

get_gh_token() {
    local remote="$1"
    # Extract token from gh config for the given hostname
    gh auth token --hostname "$remote" 2>/dev/null || {
        echo "Error: Cannot get token for $remote. Please run: gh auth login --hostname $remote" >&2
        return 1
    }
}

get_api_url() {
    local remote="$1"
    if [ "$remote" = "github.com" ]; then
        echo "https://api.github.com"
    else
        echo "https://$remote/api/v3"
    fi
}

create_ssh_key_pair() {
    local email="$1"
    local delete_if_exists="$2"  # true/false
    
    if [ -f "$KEY_PATH" ]; then
        if [ "$delete_if_exists" = "true" ]; then
            echo "SSH key already exists. Deleting it."
            rm $KEY_PATH $KEY_PATH.pub 2>/dev/null
        else
            echo "Error: SSH key already exists at $KEY_PATH"
            return 1
        fi
    fi
    
    ssh-keygen -t ed25519 -f $KEY_PATH -C "$email" -N "" -q
    echo "SSH key pair generated: $KEY_PATH"
}

upload_ssh_key_to_remote() {
    local remote="$1"
    local title="$2"
    
    if ! switch_gh_account "$remote"; then
        return 1
    fi
    
    local token=$(get_gh_token "$remote")
    if [ $? -ne 0 ]; then
        echo "Failed to get token for $remote"
        return 1
    fi
    
    local api_url=$(get_api_url "$remote")
    local key_content=$(cat $KEY_PATH.pub)
    
    curl -s -X POST \
        -H "Authorization: token $token" \
        -H "Content-Type: application/json" \
        -d "{\"title\":\"$title\",\"key\":\"$key_content\"}" \
        "$api_url/user/keys" > /dev/null
    
    if [ $? -eq 0 ]; then
        echo "Successfully added SSH key with title \"$title\" to $remote"
        return 0
    else
        echo "Failed to add key to $remote"
        return 1
    fi
}

generate_new_key() {
    local remote="$1"
    local email="$2"
    
    echo "Generating new SSH key for $remote ($email)"
    
    # Create SSH key pair (delete if exists)
    if ! create_ssh_key_pair "$email" "true"; then
        return 1
    fi
    
    # Upload to remote
    upload_ssh_key_to_remote "$remote" "$TODAY"
}

generate_new_key_for_all_remotes() {
    # Generate the SSH key once at the beginning
    echo "Generating new SSH key pair..."
    
    # Use the first email for the key comment (or could be made configurable)
    local first_email=""
    for remote in "${!REMOTES[@]}"; do
        first_email="${REMOTES[$remote]}"
        break
    done
    
    if ! create_ssh_key_pair "$first_email" "true"; then
        return 1
    fi
    echo ""
    
    # Now add the same key to all remotes
    local first=true
    for remote in "${!REMOTES[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo ""
            echo "----------------------------------------"
            echo ""
        fi
        
        echo "Adding SSH key to $remote (${REMOTES[$remote]})"
        upload_ssh_key_to_remote "$remote" "$TODAY"
    done
}

list_remote_keys() {
    local remote="$1"
    
    if ! switch_gh_account "$remote"; then
        return 1
    fi
    
    local token=$(get_gh_token "$remote")
    if [ $? -ne 0 ]; then
        echo "Failed to get token for $remote"
        return 1
    fi
    
    local api_url=$(get_api_url "$remote")
    local response=$(curl -s -H "Authorization: token $token" "$api_url/user/keys")
    local curl_exit_code=$?
    
    if [ $curl_exit_code -ne 0 ]; then
        echo "ERROR: Failed to retrieve SSH keys from $remote"
        return 1
    fi
    
    # Parse JSON response and display keys using shell commands only
    if [[ "$response" == "[]" ]]; then
        echo "[$remote] No SSH keys found"
        return 0
    fi
    
    # Check if response contains data
    if [[ "$response" == "["* ]] && [[ "$response" != "[]" ]]; then
        echo "[$remote] SSH Keys:"
        
        # Use awk to parse JSON array and extract key information
        echo "$response" | awk '
        BEGIN { 
            RS = "},"; 
            FS = ",";
            in_array = 0;
        }
        {
            # Skip if this is just array brackets
            if ($0 ~ /^\s*\[\s*$/ || $0 ~ /^\s*\]\s*$/) next;
            
            # Initialize variables for each record
            id = ""; title = ""; key = ""; created_at = ""; key_type = ""; key_short = "";
            
            # Process the entire record to extract fields
            record = $0;
            # Clean up record - remove leading/trailing brackets and braces
            gsub(/^\s*\[?\s*\{?/, "", record);
            gsub(/\}?\s*\]?\s*$/, "", record);
            
            # Extract ID
            if (match(record, /"id"\s*:\s*([0-9]+)/, arr)) {
                id = arr[1];
            }
            
            # Extract title
            if (match(record, /"title"\s*:\s*"([^"]*)"/, arr)) {
                title = arr[1];
            }
            
            # Extract created_at
            if (match(record, /"created_at"\s*:\s*"([^"]*)"/, arr)) {
                created_at = arr[1];
            }
            
            # Extract key (this might span multiple fields due to commas in the key)
            if (match(record, /"key"\s*:\s*"([^"]*)"/, arr)) {
                key = arr[1];
                # Extract key type (first part before space)
                if (match(key, /^([^ ]+)/, type_arr)) {
                    key_type = type_arr[1];
                }
                # Extract key content (second part, truncated)
                if (match(key, /^[^ ]+ ([^ ]+)/, content_arr)) {
                    key_short = substr(content_arr[1], 1, 50);
                }
            }
            
            # Display the key information if we have essential fields
            if (id != "" && title != "") {
                print "";
                print "  Title: " title;
                print "  Type: " key_type;
                print "  Key: " key_short "...";
                print "  Date: " created_at;
                print "  ID: " id;
            }
        }'
    else
        echo "[$remote] No SSH keys found or invalid response"
    fi
}

list_remote_keys_for_all_remotes() {
    local first=true
    for remote in "${!REMOTES[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo ""
            echo "----------------------------------------"
            echo ""
        fi
        list_remote_keys "$remote"
    done
}

delete_old_remote_keys() {
    local remote="$1"
    switch_gh_account "$remote"
    
    local token=$(get_gh_token "$remote")
    if [ $? -ne 0 ]; then
        echo "Failed to get token for $remote"
        return 1
    fi
    
    local api_url=$(get_api_url "$remote")
    local response=$(curl -s -H "Authorization: token $token" "$api_url/user/keys")
    
    # Parse JSON and delete old keys using shell commands only
    if [[ "$response" == "[]" ]]; then
        echo "[$remote] No SSH keys found to delete"
        return 0
    fi
    
    # Use awk to parse JSON and identify keys to delete
    echo "$response" | awk -v today="$TODAY" -v api_url="$api_url" -v token="$token" '
    BEGIN { 
        RS = "},"; 
        FS = ",";
        
        # Parse today date: YYMMDDHHMMSS
        today_year = 2000 + substr(today, 1, 2);
        today_month = substr(today, 3, 2);
        today_day = substr(today, 5, 2);
        today_hour = substr(today, 7, 2);
        today_min = substr(today, 9, 2);
        today_sec = substr(today, 11, 2);
        
        # Convert to timestamp for comparison
        today_timestamp = mktime(today_year " " today_month " " today_day " " today_hour " " today_min " " today_sec);
    }
    {
        # Skip if this is just array brackets
        if ($0 ~ /^\s*\[\s*$/ || $0 ~ /^\s*\]\s*$/) next;
        
        # Initialize variables for each record
        id = ""; title = "";
        
        # Process the entire record to extract fields
        record = $0;
        # Clean up record - remove leading/trailing brackets and braces
        gsub(/^\s*\[?\s*\{?/, "", record);
        gsub(/\}?\s*\]?\s*$/, "", record);
        
        # Extract ID
        if (match(record, /"id"\s*:\s*([0-9]+)/, arr)) {
            id = arr[1];
        }
        
        # Extract title
        if (match(record, /"title"\s*:\s*"([^"]*)"/, arr)) {
            title = arr[1];
        }
        
        # Process the key if we have essential fields
        if (id != "" && title != "") {
            # Check if title looks like a date (YYMMDDHHMMSS format - 12 digits)
            if (length(title) == 12 && title ~ /^[0-9]+$/) {
                # Parse title date
                title_year = 2000 + substr(title, 1, 2);
                title_month = substr(title, 3, 2);
                title_day = substr(title, 5, 2);
                title_hour = substr(title, 7, 2);
                title_min = substr(title, 9, 2);
                title_sec = substr(title, 11, 2);
                
                # Convert to timestamp
                title_timestamp = mktime(title_year " " title_month " " title_day " " title_hour " " title_min " " title_sec);
                
                # Compare timestamps
                if (title_timestamp < today_timestamp) {
                    print "DELETE:" id ":" title;
                } else {
                    print "SKIP:" id ":" title;
                }
            } else if (length(title) == 10 && title ~ /^[0-9]+$/) {
                # Handle old 10-digit format (YYMMDDHHMM) - treat as having 00 seconds
                title_year = 2000 + substr(title, 1, 2);
                title_month = substr(title, 3, 2);
                title_day = substr(title, 5, 2);
                title_hour = substr(title, 7, 2);
                title_min = substr(title, 9, 2);
                title_sec = 0;
                
                # Convert to timestamp
                title_timestamp = mktime(title_year " " title_month " " title_day " " title_hour " " title_min " " title_sec);
                
                # Compare timestamps
                if (title_timestamp < today_timestamp) {
                    print "DELETE:" id ":" title;
                } else {
                    print "SKIP:" id ":" title;
                }
            } else {
                # If title doesnt look like a date, skip it
                print "SKIP:" id ":" title;
            }
        }
    }' | while IFS=':' read action key_id title; do
        if [ "$action" = "DELETE" ]; then
            echo "Deleting key \"$title\" (ID: $key_id) from $remote"
            curl -s -X DELETE -H "Authorization: token $token" "$api_url/user/keys/$key_id" > /dev/null
            if [ $? -eq 0 ]; then
                echo "Successfully deleted key $key_id"
            else
                echo "Failed to delete key $key_id"
            fi
        elif [ "$action" = "SKIP" ]; then
            echo "Skipping key \"$title\" from $remote"
        fi
    done
}

delete_old_remote_keys_for_all_remotes() {
    local first=true
    for remote in "${!REMOTES[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo ""
            echo "----------------------------------------"
            echo ""
        fi
        delete_old_remote_keys "$remote"
    done
}

display_help() {
    echo "Usage: $0 [--generate] [--list] [--delete] [--generate-all] [--list-all] [--delete-all]"
    echo "Options:"
    echo "  --generate: Generate a new SSH key for the first remote in REMOTES"
    echo "  --list: List all remote SSH keys for the first remote in REMOTES"
    echo "  --delete: Delete old remote SSH keys for the first remote in REMOTES"
    echo "  --generate-all: Generate a new SSH key for all remotes in REMOTES"
    echo "  --list-all: List all remote SSH keys for all remotes in REMOTES"
    echo "  --delete-all: Delete old remote SSH keys for all remotes in REMOTES"
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
            # Use the first remote in REMOTES
            for remote in "${!REMOTES[@]}"; do
                email="${REMOTES[$remote]}"
                generate_new_key "$remote" "$email"
                break
            done
            ;;
            --list)
            for remote in "${!REMOTES[@]}"; do
                list_remote_keys "$remote"
                break
            done
            ;;
            --delete)
            for remote in "${!REMOTES[@]}"; do
                delete_old_remote_keys "$remote"
                break
            done
            ;;
            --generate-all)
            generate_new_key_for_all_remotes
            ;;
            --list-all)
            list_remote_keys_for_all_remotes
            ;;
            --delete-all)
            delete_old_remote_keys_for_all_remotes
            ;;
            *)
            ;;
        esac
        shift
    done
}

main "$@"