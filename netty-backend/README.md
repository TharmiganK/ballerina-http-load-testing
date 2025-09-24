# Netty HTTP Transport Sample

This repository holds samples of HTTP transport implemented using [Netty](https://github.com/netty/netty).

## Prerequisites

- Maven
- Java 21

## Steps to run the application

1. Build the project using the following command:

   ```shell
   mvn clean install
   ```

2. Run the application using the following command:

   ```shell
   java -jar target/netty-http-echo-service.jar --ssl true --http2 false --key-store-file keystore.p12 --key-store-password ballerina
   ```

   > **Note:** The `--ssl` flag is used to enable SSL, the `--http2` flag is used to enable HTTP/2, the `--key-store-file` flag is used to specify the keystore file, and the `--key-store-password` flag is used to specify the keystore password.

3. The application will start on port 8688. Test it using the following command:

   ```shell
   curl -kv https://localhost:8688 -d "Hello Netty"
   ```
