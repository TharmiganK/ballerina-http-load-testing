import ballerina/http;
import ballerina/log;

configurable string epKeyPath = "../resources/ballerinaKeystore.p12";
configurable string epTrustStorePath = "../resources/ballerinaTruststore.p12";
configurable string epKeyPassword = "ballerina";

configurable boolean clientSsl = true;
configurable boolean serverSsl = true;
configurable boolean clientHttp2 = false;
configurable boolean serverHttp2 = false;
configurable int serverPort = 9091;
configurable int backendPort = 8688;
configurable string backendHost = "localhost";

listener http:Listener securedEP = new (serverPort,
    httpVersion = serverHttp2 ? http:HTTP_2_0 : http:HTTP_1_1,
    secureSocket = serverSsl ? {
            key: {
                path: epKeyPath,
                password: epKeyPassword
            }
        } : ()
);

final http:Client nettyEP = check new (clientSsl ? "https://" + backendHost + ":" + backendPort.toString() : "http://" + backendHost + ":" + backendPort.toString(),
    httpVersion = clientHttp2 ? http:HTTP_2_0 : http:HTTP_1_1,
    secureSocket = clientSsl ? {
            cert: {
                path: epTrustStorePath,
                password: epKeyPassword
            },
            verifyHostName: false
        } : ()
);

public function main() {
    string clientProtocol = clientHttp2 ? "h2" : "h1";
    if (!clientSsl) {
        clientProtocol = clientProtocol + "c";
    }
    string serverProtocol = serverHttp2 ? "h2" : "h1";
    if (!serverSsl) {
        serverProtocol = serverProtocol + "c";
    }
    log:printInfo("service started", port = serverPort, backend = clientProtocol, passthrough = serverProtocol);
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
