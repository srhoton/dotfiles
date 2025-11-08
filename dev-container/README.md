# Development Container for GitHub Codespaces

This dev container provides a comprehensive multi-language development environment with the following tools and runtimes.

## Installed Tools

### Language Runtimes
- **Java 21** (Amazon Corretto)
  - JDK with full development tools
  - JAVA_HOME configured

- **Python 3.12**
  - Python virtual environment (venv) support
  - uv package installer (faster alternative to pip)
  - Set as default Python interpreter

- **Go** (Latest stable - 1.22.0)
  - Full Go toolchain
  - GOPATH configured at `~/go`

- **Node.js** (LTS)
  - Latest LTS version
  - npm package manager
  - TypeScript support (installed globally)
  - ts-node for TypeScript execution

### Developer Tools
- **AWS CLI v2** - AWS command-line interface
- **Starship** - Modern, customizable shell prompt
- **Git** - Version control
- **Build tools** - gcc, g++, make

### VS Code Extensions
The container pre-installs the following VS Code extensions:
- Python (ms-python.python)
- Pylance (ms-python.vscode-pylance)
- Go (golang.go)
- Java Extension Pack (vscjava.vscode-java-pack)
- Red Hat Java (redhat.java)
- Docker (ms-azuretools.vscode-docker)
- AWS Toolkit (amazonwebservices.aws-toolkit-vscode)

## Usage

### Using with GitHub Codespaces

1. Push this repository to GitHub
2. Open the repository in GitHub
3. Click "Code" → "Create codespace on main"
4. Wait for the container to build and start

### Using Locally with VS Code

1. Install the "Dev Containers" extension in VS Code
2. Open this folder in VS Code
3. Press F1 and select "Dev Containers: Reopen in Container"
4. Wait for the container to build and start

## Directory Structure

```
dev-container/
├── .devcontainer/
│   ├── devcontainer.json    # Container configuration
│   ├── Dockerfile            # Container image definition
│   └── setup.sh              # Post-creation setup script
└── README.md                 # This file
```

## Configuration Details

### Python with uv
Instead of pip, this container uses `uv`, a fast Python package installer written in Rust. To create a virtual environment and install packages:

```bash
# Create a virtual environment
python -m venv .venv
source .venv/bin/activate

# Install packages with uv
uv pip install package-name
```

### AWS Configuration
Your local AWS credentials (from `~/.aws`) are mounted into the container, so you can use AWS CLI commands immediately.

```bash
# Verify AWS identity
aws sts get-caller-identity
```

### Starship Prompt
The Starship prompt is configured with a custom theme showing:
- Current directory
- Git branch and status
- Active programming language and version
- AWS profile (if configured)

Configuration file: `~/.config/starship.toml`

## Useful Aliases

The container includes several pre-configured aliases:

```bash
# Directory navigation
ll          # List all files with details
la          # List all files including hidden
..          # Go up one directory
...         # Go up two directories

# Python
python      # Points to python3
venv        # Create virtual environment

# Git
gs          # git status
ga          # git add
gc          # git commit
gp          # git push
gl          # git log --oneline --graph --decorate

# AWS
awswhoami   # aws sts get-caller-identity
```

## Version Information

To check installed versions:

```bash
java -version      # Java 21
python --version   # Python 3.12
go version         # Go 1.22.0
node --version     # Node.js LTS
npm --version      # npm
tsc --version      # TypeScript
aws --version      # AWS CLI v2
starship --version # Starship
uv --version       # uv package installer
```

## Customization

### Adding More Tools
Edit the `Dockerfile` to add additional tools or packages.

### Modifying VS Code Settings
Edit `devcontainer.json` to add or modify VS Code extensions and settings.

### Post-Creation Scripts
Modify `setup.sh` to add custom initialization logic that runs after the container is created.

## Troubleshooting

### Container Build Fails
- Check Docker daemon is running
- Ensure you have sufficient disk space
- Review build logs for specific errors

### Tools Not Found
- Rebuild the container: "Dev Containers: Rebuild Container"
- Verify PATH is set correctly: `echo $PATH`

### AWS Credentials Not Working
- Ensure `~/.aws` directory exists locally
- Check file permissions on credentials
- Verify credentials are valid: `aws sts get-caller-identity`

## License

This dev container configuration is provided as-is for development purposes.
