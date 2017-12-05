#ifndef TCP_H
#define TCP_H

#include "packet.h"

enum{

    BUFFERSIZE = 16,
    SERVERPORT = 255,
    LISTENING = 700,
    LISTENING_SERVER = 689,
    AVAILABLE = 701,
    SYN_SENT = 702,
    SYN_RCVD = 703,
    ESTABLISHED = 704,
    AWAITING = 705,
    FIN_WAIT_1 = 706,
    FIN_WAIT_2 = 719,
    CLOSED = 707,
    BUFFER = PACKET_MAX_PAYLOAD_SIZE - 8,
    sendServerData = 888,
    clientSentData = 999,
    HELLO = 223,
    getUSERNAME = 220,


    //Flags
    URG = 100,
    ACK = 200,
    PSH = 300,
    SYN_CLIENT = 400,
    SYN_SERVER = 401, //differentiate b/w server and client SYN in 3 way handshake
    FIN = 500,
    RST = 600,
    SYN = 777,

};


typedef nx_struct TCP{
        nx_uint8_t srcPort;
        nx_uint8_t destPort;
        nx_uint16_t seqNum;
        nx_uint8_t ACK;
        nx_uint16_t flag;
        nx_uint8_t AdWindow;
        nx_uint8_t dataLength;
        nx_uint16_t data[PACKET_MAX_PAYLOAD_SIZE -8];
        nx_uint8_t doneSending;
        nx_uint8_t payload[PACKET_MAX_PAYLOAD_SIZE];
        

}TCP;




typedef struct socket_t{
        uint8_t srcPort;
        char sentData[128]; //buffer size = 128
        
        uint8_t srcAddr;
        char recievedData[128];
        uint8_t destPort;
        uint8_t destAddr;
        uint8_t connectionState; //state

        
        
        


}socket_t;

typedef struct socket_addr_t{
        uint8_t srcPort;
        char sentData[128]; //buffer size = 128
        
        uint8_t srcAddr;
        char recievedData[128];
        uint8_t destPort;
        uint8_t destAddr;
        uint8_t connectionState; //state

        
        
        


}socket_addr_t;

typedef struct Port{
        bool open;
        uint8_t destAddr;
        int destPort;
        int portNumber;
        uint16_t lastSeq;
        uint16_t nextSeq;
        int srcPort;
        uint16_t state;
        char recievedData[128];
        char sentData[128];
        uint16_t sizeofPayload;
        uint8_t username[PACKET_MAX_PAYLOAD_SIZE];

}Port;










#endif
