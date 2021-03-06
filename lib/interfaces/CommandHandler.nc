interface CommandHandler{
   // Events
   event void ping(uint16_t destination, uint8_t *payload);
   event void printNeighbors();
   event void printRouteTable();
   event void printLinkState();
   event void printDistanceVector();
   event void setTestServer();
   event void whisperMessage(uint8_t *username, uint8_t *payload);
   event void setTestClient(int server, uint8_t *payload);
   event void setAppServer();
   event void setAppClient();
   event void clientClose(int server, uint8_t *payload);
   event void helloServer(int client, uint8_t *payload);
   event void broadCastMessage(int server, uint8_t *payload);
   event void listUsers(int server, uint8_t *payload);
   
}
