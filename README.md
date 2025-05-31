# dotfiles

A collection of personal configuration files (dotfiles) for various development tools, editors, and environments. This repository contains carefully curated settings for productive development workflows across multiple programming languages and platforms.

## Overview

This repository contains configuration files for:
- Shell environments (Bash)
- Version control (Git)
- Text editors (Vim, Zed)
- Development tools (COC, Microsoft Terminal)
- AI coding assistants (Amazon Q)
- Automation workflows (GitHub Actions)

## Configuration Files

### Shell and System Configuration
- **`.bashrc`** - Bash shell configuration including aliases, environment variables, and prompt customization
- **`.gitconfig`** - Git configuration with user settings, aliases, and behavior preferences

### Editor Configuration
- **`.vimrc`** - Vim editor configuration with plugins, key mappings, and visual settings
- **`coc-settings.json`** - Conquer of Completion (COC) settings for enhanced Vim/Neovim functionality with language server support

### Application Settings
- **`ms_terminal_settings.json`** - Microsoft Terminal configuration including themes, profiles, and key bindings

## Directory Structure

### `.config/zed/` - Zed Editor Configuration
Modern code editor settings and language-specific formatting rules:
- **`settings.json`** - General Zed editor settings and preferences
- **`golang_rules.json`** - Go language formatting and linting rules
- **`java_rules.json`** - Java language formatting and style guidelines
- **`terraform_rules.json`** - Terraform formatting and validation rules

### `.github/workflows/` - GitHub Actions
- **`claude.yml`** - Automated workflow configuration for Claude AI integration

### `.amazonq/rules/` - Amazon Q AI Assistant Rules
Language-specific coding guidelines and rules for Amazon Q:
- **`golang_rules.md`** - Go language best practices and patterns
- **`java_rules.md`** - Java coding standards and conventions
- **`rust_rules.md`** - Rust programming guidelines and idioms
- **`terraform_rules.md`** - Terraform configuration best practices
- **`typescript_rules.md`** - TypeScript development standards and patterns

## Installation

### Prerequisites
- Bash shell
- Git
- Vim/Neovim (for Vim configurations)
- Node.js (for COC functionality)
- Zed editor (for Zed configurations)
- Microsoft Terminal (for Terminal configurations)

### Quick Setup
1. Clone this repository:
   ```bash
   git clone https://github.com/srhoton/dotfiles.git
   cd dotfiles
   ```

2. Create symbolic links for configuration files:
   ```bash
   # Shell configurations
   ln -sf $(pwd)/.bashrc ~/.bashrc
   ln -sf $(pwd)/.gitconfig ~/.gitconfig
   ln -sf $(pwd)/.vimrc ~/.vimrc
   
   # COC settings
   mkdir -p ~/.vim
   ln -sf $(pwd)/coc-settings.json ~/.vim/coc-settings.json
   
   # Zed editor configurations
   mkdir -p ~/.config/zed
   ln -sf $(pwd)/.config/zed/* ~/.config/zed/
   ```

3. For Microsoft Terminal, import the settings manually through the Terminal's settings interface.

### Manual Installation
Alternatively, copy individual configuration files to their respective locations as needed.

## Usage

### Bash Configuration
- Reload configuration: `source ~/.bashrc`
- The `.bashrc` file includes custom aliases and environment variables

### Git Configuration  
- Configuration is automatically applied when using Git commands
- Includes user information, aliases, and merge/diff tools

### Vim Configuration
- Start Vim to use the custom configuration
- COC provides language server integration for enhanced development

### Zed Editor
- Language-specific rules are automatically applied based on file types
- Custom formatting and linting rules enhance code quality

### Amazon Q Integration
- Language-specific rules guide AI-assisted coding
- Rules help maintain consistent code style and best practices

## Customization

Feel free to modify any configuration file to match your preferences:
- Edit shell aliases in `.bashrc`
- Customize Git behavior in `.gitconfig`
- Adjust editor settings in `.vimrc` and Zed configurations
- Modify language rules for different coding standards

## Contributing

This is a personal dotfiles repository, but suggestions and improvements are welcome through issues and pull requests.

## License

These configuration files are provided as-is for personal use. Feel free to adapt them for your own development environment.