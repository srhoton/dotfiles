Ok. We need to make some changes to the deployment configuration. These changes likely occuring the terraform files, but may need to be made in the lambda function code as well. Specifically, we need to:
- Change the S3 bucket name to `steve-rhoton-tfstate`
- Make sure the dynamo table name is `{repository-name}-{environment}`
- Make sure the lambda function name is `{repository-name}-{environment}`
- The cognito user pool name on the api gateway authorizer should be us-west-2_Sg0RnpexL (sr-auth-sandbox-sr-user-pool)
- All resources should be created in the `us-west-2` region
- Move the DNS zone to `sb.fullbay.com`
You have access to the aws cli to check the current configuration of the resources. Follow the terraform rules in your memory. All your terraform should format, lint (and conform to tflint-ruleset-aws), and validate. This is building into a dev environment. Ultrathink, and let me know what questions you have.
