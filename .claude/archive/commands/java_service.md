In a new directory called 'lambda', create a Java 21 lambda function. It should: 
- Use the AWS SDK for Java 2.x
- Use Gradle as the build tool
- Uses the JSON Schema in the schema directory to validate input and save/update it into a DynamoDB table (whose name is passed as an environment variable)
- Support all standard HTTP methods and follow standard REST best practices for requests and responses, including a health endpoint. Responses should return the full unit object for successful operations, and return detailed error messages showing which fields failed validation with a standard error response format. 
- Respond to events from API Gateway v2
- Create make sure an openapi spec is created for this implementation in a directory in the root called ‘openapi’. Use version 3.1.0
- Implement soft deletes using the ‘deletedAt’ field. All deleted items should be filtered out of responses, and the deletedAt field should be set to the current timestamp when an item is deleted.
- make sure you implement dynamo cursor based pagination with a limit of 100 items per page and a default of 20 items per page
- PUT requests should suport partial updates
- Do not use Quarkus or Spring Boot, but use the AWS Lambda Java runtime API directly.

The groupId should be com.steverhoton.next, and the artifactId should be $ARGUMENTS. Follow all Java rules in your memory for this. Make sure all your code is properly formatted and includes necessary dependencies. It should lint correctly. Write tests for all the code you write, and ensure that the tests are comprehensive with at least 80% coverage. Make sure the code builds and all tests pass. Ultrathink, and let me know what questions you have before you start coding.
