# Terraform Best Practices Guide for AI Agents

This guide outlines industry standard practices for writing high-quality Terraform code.

## Naming Conventions

Consistent naming improves readability and maintainability.

- Use `snake_case` for resource names, variable names, and output names
- Use descriptive names that indicate purpose and context
- Prefix resources with their type (e.g., 'vpc_' for VPC resources)
- For modules, name should reflect functionality provided (e.g., 'network', 'database')

**Good Example:**
```hcl
resource "aws_vpc" "main_vpc" {
  cidr_block = var.vpc_cidr
}
```

## Code Organization

Organize code logically and consistently.

- Group related resources together
- Use separate files for variables, outputs, providers, and main resources
- Use modules for reusable components
- Keep root module simple, delegate complexity to child modules
- Follow standard file structure: main.tf, variables.tf, outputs.tf, providers.tf, versions.tf

## Documentation

Document code thoroughly for future reference and collaboration.

- Include description for all variables, including type, default, and purpose
- Document all outputs with descriptions
- Include README.md for each module explaining purpose, usage, inputs, and outputs
- Add comments for complex logic or non-obvious decisions

**Good Example:**
```hcl
variable "vpc_cidr" {
  description = "CIDR block for the main VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "Must be a valid CIDR block."
  }
}
```

## Versioning

Use explicit versioning for stability and predictability.

- Pin provider versions to specific releases
- Use version constraints in the terraform block
- Specify module versions when using remote modules
- Use `~>` for minor version updates, `>=` for minimum versions

## Formatting

Maintain consistent formatting for readability.

- Run `terraform fmt` before committing changes
- Use 2-space indentation
- Align equals signs for readability
- Sort resource arguments alphabetically where possible
- Use newlines to separate logical blocks of configuration

## Validation

Implement validation for variables and resources.

- Use validation blocks for variables to enforce constraints
- Apply clear type constraints to all variables
- Use lifecycle blocks appropriately for resource management
- Implement precondition and postcondition checks where applicable

## Security

Follow security best practices to protect infrastructure.

- Never hardcode credentials or sensitive data
- Use variables for sensitive values and mark them as sensitive
- Implement least privilege principle for IAM roles and policies
- Enable encryption for data at rest
- Use security groups with minimal necessary access
- Implement proper network segmentation

## State Management

Handle state properly to enable collaboration and reduce risk.

- Use remote state with locking
- Employ state workspaces for environment isolation
- Separate state by component or service
- Implement proper backend configuration with encrypted storage

## Resource Dependencies

Handle resource dependencies explicitly.

- Use `depends_on` where implicit dependencies aren't clear
- Prefer data sources over hardcoded values for resource references
- Use count or for_each instead of standalone duplicate resources
- Consider creation/destruction order for dependent resources

## Module Usage

Use modules effectively for code reuse and abstraction.

**Good Example:**
```hcl
module "network" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.14.0"

  name = "${var.project}-${var.environment}"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  tags = local.common_tags
}
```

## Testing

Implement testing practices for code quality and reliability.

- Write terratest modules for testing infrastructure
- Use `terraform validate` before applying changes
- Implement plan verification in CI/CD pipelines
- Use terraform-docs to generate documentation

## Linting

Use linting tools to catch issues early.

- Run tflint to catch potential errors and best practice violations
- Use checkov or tfsec for security scanning
- Implement pre-commit hooks for automated formatting and validation
- Configure and use .tflint.hcl for project-specific rules

## Tagging

Implement consistent tagging strategy for resource management.

- Apply tags to all resources for cost tracking, ownership, and environment
- Use a standardized tagging module or locals for consistency
- Include mandatory tags: Environment, Owner, Project, ManagedBy
- Consider automated tag enforcement with policy-as-code tools

## Conditional Logic

Use conditional creation and configuration wisely.

- Prefer `for_each` over `count` for complex conditional creation
- Use locals for computed values used in multiple places
- Consider ternary operations for simple conditionals
- Use dynamic blocks for repeated nested blocks with variations

## Recommended Tools

| Tool | Description |
|------|-------------|
| terraform fmt | Built-in formatting tool to ensure consistent style |
| tflint | Linter for detecting errors and enforcing best practices |
| terraform-docs | Documentation generator for Terraform modules |
| checkov | Static code analysis for security and compliance best practices |
| tfsec | Security scanner for Terraform code |
| infracost | Cloud cost estimates for Terraform |
