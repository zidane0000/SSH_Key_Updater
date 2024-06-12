# SSH Key Updater

This script provides a simple way to manage your SSH keys on GitHub. It allows you to generate a new SSH key, list all remote SSH keys, and delete old remote SSH keys.

## Prerequisites

- You need to have `ssh-keygen` and `gh` (GitHub CLI) installed on your system.
- Replace `your_email@example.com` and key path with actual in code before running the script

    ```base
    KEY_PATH=~/.ssh/id_ed25519
    your_email="your_email@example.com"
    ```

- The script should be run as root.

## Usage

```bash
./update_ssh_key.sh [--generate] [--list] [--delete] [--help]
```

Options:

- `--generate`: Generate a new SSH key and add it to your GitHub account.
- `--list`: List all remote SSH keys in your GitHub account.
- `--delete`: Delete old remote SSH keys from your GitHub account.
- `--help`: Display the help message.

**Warning: `--delete` will delete all old remote SSH keys without asking for confirmation.**


## Functions
- `default_check`: Checks if the script is run as root and if `ssh-keygen` and `gh` are installed. Also checks if you are authenticated with GitHub.
- `generate_new_key`: Generates a new SSH key and adds it to your GitHub account. If an SSH key already exists at the default path, it will be deleted.
- `list_remote_keys`: Lists all remote SSH keys in your GitHub account.
- `delete_old_remote_keys`: Deletes old remote SSH keys from your GitHub account. The keys are considered old if their title (which should represent the date and time of creation in the format `yyMMddHHmm`) is older than the current date and time.

## Note
The script uses the `gh` command-line tool to interact with GitHub. Make sure you are authenticated with GitHub before running the script. You can authenticate by running `gh auth login`.

The script assumes that the title of each SSH key represents the date and time of creation in the format `yyMMddHHmm`. If the title doesn't represent a date or if there are keys with titles that can't be converted to a date, the `delete_old_remote_keys` function might behave unexpectedly.
- --help: Display the help message.