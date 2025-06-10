# SSH Key Updater

A comprehensive script for managing SSH keys across multiple GitHub hosts. This tool allows you to generate, list, and delete SSH keys for multiple GitHub accounts, including GitHub Enterprise servers.

## Features

- **Multi-Host Support**: Manage SSH keys across multiple GitHub instances (github.com, GitHub Enterprise)
- **Automated Key Generation**: Generate ED25519 SSH keys with timestamp-based titles
- **Key Lifecycle Management**: List and delete old SSH keys automatically
- **Cross-Platform**: Works on Linux, macOS, and Windows (with Git Bash/WSL)
- **Authentication Management**: Handles multiple GitHub account authentication

## Prerequisites

1. **Required Tools**:
   - `ssh-keygen` (usually pre-installed)
   - `gh` (GitHub CLI) - [Installation Guide](https://cli.github.com/)
   - `curl` (for API calls)

2. **Administrative Privileges**:
   - Linux/macOS: Run as root or with sudo
   - Windows: Run as administrator

3. **GitHub Authentication**:
   - Authenticate with each GitHub host using `gh auth login`
   - Required scopes: `admin:public_key`, `admin:ssh_signing_key`, `gist`, `read:org`, `repo`, `workflow`

## Configuration

Edit the `REMOTES` associative array in the script to configure your GitHub hosts:

```bash
declare -A REMOTES
REMOTES=( 
    [fake1.github.com]="user1@example.com"
    [fake2.github.com]="user2@example.com"
    [fake3.github.com]="user3@example.com"
)
```

- **Key**: GitHub hostname (e.g., `github.com`, `your-enterprise.github.com`)
- **Value**: Email address associated with that account

## Usage

```bash
./update_ssh_key.sh [OPTIONS]
```

### Single Host Operations

- `--generate`: Generate and upload SSH key to the first configured host
- `--list`: List all SSH keys for the first configured host
- `--delete`: Delete old SSH keys from the first configured host

### Multi-Host Operations

- `--generate-all`: Generate one SSH key and upload to all configured hosts
- `--list-all`: List SSH keys from all configured hosts
- `--delete-all`: Delete old SSH keys from all configured hosts

### Other Options

- `--help`: Display help message

### Examples

```bash
# Generate SSH key for all GitHub hosts
./update_ssh_key.sh --generate-all

# List keys from all hosts
./update_ssh_key.sh --list-all

# Clean up old keys from all hosts
./update_ssh_key.sh --delete-all

# Generate key for first host only
./update_ssh_key.sh --generate
```

## Authentication Setup

Before using the script, authenticate with each GitHub host:

```bash
# For github.com
gh auth login --hostname github.com --scopes "admin:public_key,admin:ssh_signing_key,gist,read:org,repo,workflow"

# For GitHub Enterprise
gh auth login --hostname your-enterprise.github.com --scopes "admin:public_key,admin:ssh_signing_key,gist,read:org,repo,workflow"
```

## Key Management

### Key Format
- **Type**: ED25519 (modern, secure)
- **Location**: `~/.ssh/id_ed25519`
- **Title Format**: `YYMMDDHHMMSS` (timestamp when created)

### Automatic Cleanup
The `--delete` and `--delete-all` options will remove SSH keys based on their titles:
- Keys with titles in `YYMMDDHHMMSS` or `YYMMDDHHMM` format older than current time
- Keys with non-date titles are preserved
- Current session's key (matching today's timestamp) is preserved

## Script Functions

| Function | Description |
|----------|-------------|
| `default_check()` | Validates prerequisites and authentication |
| `switch_gh_account()` | Switches GitHub CLI context to specified host |
| `get_gh_token()` | Retrieves authentication token for API calls |
| `create_ssh_key_pair()` | Generates ED25519 SSH key pair |
| `upload_ssh_key_to_remote()` | Uploads public key to GitHub host |
| `generate_new_key()` | Complete key generation workflow for single host |
| `generate_new_key_for_all_remotes()` | Generates one key and uploads to all hosts |
| `list_remote_keys()` | Lists SSH keys for specified host |
| `delete_old_remote_keys()` | Removes old SSH keys from specified host |

## Security Considerations

- **Private Key**: Generated at `~/.ssh/id_ed25519` (keep secure)
- **Key Rotation**: Regular key rotation improves security
- **Token Storage**: GitHub CLI stores tokens securely
- **Administrative Access**: Required for SSH key operations

## Troubleshooting

### Common Issues

1. **"Not logged into host"**: Run `gh auth login --hostname <host>`
2. **Permission denied**: Run with administrator/root privileges
3. **ssh-keygen not found**: Install OpenSSH or Git for Windows
4. **API rate limits**: Wait and retry, or check token permissions

### Verification

```bash
# Test SSH connection
ssh -T git@github.com
ssh -T git@your-enterprise.github.com

# Verify GitHub CLI authentication
gh auth status --hostname github.com
```

## License

This project is licensed under the terms specified in the LICENSE file.