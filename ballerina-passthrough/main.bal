import ballerina/http;
import ballerina/log;

configurable string epKeyPath = "../resources/ballerinaKeystore.p12";
configurable string epTrustStorePath = "../resources/ballerinaTruststore.p12";
configurable string epKeyPassword = "ballerina";

configurable boolean clientSsl = true;
configurable boolean serverSsl = true;
configurable int serverPort = 9091;

listener http:Listener securedEP = new (serverPort,
    httpVersion = http:HTTP_1_1,
    secureSocket = serverSsl ? {
            key: {
                path: epKeyPath,
                password: epKeyPassword
            }
        } : ()
);

final http:Client nettyEP = check new (clientSsl ? "https://localhost:8689" : "http://localhost:8688",
    httpVersion = http:HTTP_1_1,
    secureSocket = clientSsl ? {
        cert: {
            path: epTrustStorePath,
            password: epKeyPassword
        },
        verifyHostName: false
    } : ()
);

public function main() {
    log:printInfo("service started", port = serverPort, backend = clientSsl ? "h1" : "h1c", passthrough = serverSsl ? "h1" : "h1c");
}

service /passthrough on securedEP {
    isolated resource function post .(http:Request clientRequest) returns http:Response {
        http:Response|http:ClientError response = nettyEP->forward("/service/EchoService", clientRequest);
        if response is http:Response {
            return response;
        } else {
            log:printError("Error at h1_h1_passthrough", 'error = response);
            http:Response res = new;
            res.statusCode = 500;
            res.setPayload(response.message());
            return res;
        }
    }
}
