---
description: Create a Java 21 AWS Lambda function with Gradle, DynamoDB, API Gateway v2 support, OpenAPI spec, and comprehensive tests
---

In a new directory called 'lambda', create a Java 21 lambda function. It should:
- Use the AWS SDK for Java 2.x
- Use Gradle as the build tool
- Uses the JSON Schema in the schema directory to validate input and save/update it into a DynamoDB table (whose name is passed as an environment variable)
- Support all standard HTTP methods and follow standard REST best practices for requests and responses, including a health endpoint. Responses should return the full unit object for successful operations, and return detailed error messages showing which fields failed validation with a standard error response format.
- Respond to events from API Gateway v2
- Create an openapi spec in a directory called 'openapi' using version 3.1.0
- Implement soft deletes using the 'deletedAt' field
- Implement DynamoDB cursor based pagination with limit of 100 items per page, default 20
- PUT requests should support partial updates
- Do not use Quarkus or Spring Boot, use AWS Lambda Java runtime API directly

The groupId should be com.steverhoton.next, and the artifactId should be $ARGUMENTS. Follow all Java rules for this. Make sure all code is properly formatted, linted, tested with at least 80% coverage. Ultrathink.
