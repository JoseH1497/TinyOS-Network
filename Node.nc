/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/routingTable.h"
#include "includes/TCP.h"
 typedef nx_struct neighbor {
    nx_uint16_t Node;
    nx_uint8_t Life;
}neighbor;

typedef nx_struct netMap{
    nx_uint8_t cost[20];
}netMap;

int seqNum = 1, updateNum = 1;
int numOfVertices = 20;
module Node{
    uses interface Boot;
    
    uses interface Timer<TMilli> as Timer1; //Interface that was wired above.
    uses interface Timer<TMilli> as lspTimer;
    uses interface SplitControl as AMControl;
    uses interface Receive;
    uses interface List<neighbor> as NeighborList;
    uses interface List<pack> as SeenPackList;
    uses interface List<int> as CheckList;
    uses interface Random as Random;
    uses interface Pool<socket_addr_t> as PortPool; 
    
    
    uses interface Hashmap<int> as Hash;
    
    uses interface SimpleSend as Sender;
    
    uses interface CommandHandler;
}

implementation{
    pack sendPackage;
    //int seqNum = 0;
    bool printNodeNeighbors = FALSE;
    int ACKseq = -1;
    //int SUCCESS = 1, FAIL = 0;
    
    // Prototypes
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, int seq, uint8_t *payload, uint8_t length);
    void printNeighbors();
    void printNeighborList();
    void deleteCheckList();
    void deleteNeighborList();
    void compare();
    void neighborDiscovery();
    bool checkPacket(pack Packet);

    void linkedState();
    void printMap(netMap* map);
    int lspSeqNum = 1;
    uint8_t neighborCost[20] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
    netMap nMAP[20];
    bool update = FALSE;
    void shortPathPrint(int);
    int shortestPath(int, int);
    int minDistance(routingTable distance[], bool visited[]);
    
    
    //Project 3
    Port nodePorts[256]; //65k ports but ima just focus on the first 255 
    socket_t sockets[256]; //sockets for ports
    void TestServer();
    void TestClient(int, uint8_t *);
    void initPorts();
    int getFreePort();
    int freeServerPort();
    int getBufferSpaceAvail(Port nodePorts[], int sourcePort);
    void makeTCPPack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, int seq, TCP* payload, uint8_t length);
    //bool bind()
    socket_t SendBuffer[128];
    char RecieveBuffer[128];

    event void Boot.booted(){
        call AMControl.start();
        initPorts(); //initialize all ports to open for every node
        dbg(GENERAL_CHANNEL, "Booted\n");
    }
   
    event void Timer1.fired()
    {
       neighborDiscovery();
    }
    event void lspTimer.fired(){
       if(update){
            linkedState();
            update = FALSE;
       } 
    }
    
    
    event void AMControl.startDone(error_t err){
        if(err == SUCCESS){
            dbg(GENERAL_CHANNEL, "Radio On\n");
            call Timer1.startPeriodic(5000);
            call lspTimer.startPeriodic(5133);
        }else{
            //Retry until successful
            call AMControl.start();
        }
    }
    
    event void AMControl.stopDone(error_t err){
    }
    
    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
        //dbg(GENERAL_CHANNEL, "Packet Received\n");
         
                int size = call CheckList.size();
                

        if(len==sizeof(pack)){
            pack* myMsg=(pack*) payload;
            //dbg(GENERAL_CHANNEL, "Packet received from %d\n",myMsg->src);
            if(myMsg->protocol == HELLO){
	    	dbg(GENERAL_CHANNEL, "Packet received from %d\n",myMsg->src);
	    }
            //dbg(FLOODING_CHANNEL, "Packet being flooded to %d\n",myMsg->dest);
            
            if (!call Hash.contains(myMsg->src))
                call Hash.insert(myMsg->src,-1);

            if(myMsg->TTL == 0){ //check life of packet
                //dbg(FLOODING_CHANNEL,"TTL=0: Dropping Packet\n");
            }else if(myMsg->protocol == 25){ //made own protocol number for net updates
                makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL, myMsg->protocol, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                if(!checkPacket(sendPackage)){
                    int i;
                    neighbor Neigh;
                
                    makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, myMsg->protocol, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                    call Sender.send(sendPackage, AM_BROADCAST_ADDR);
                    for(i = 0; i < 20; i++){
                        nMAP[TOS_NODE_ID].cost[i] = 0;
                    }

                    if(!call NeighborList.isEmpty()){
                        for(i = 0; i < call NeighborList.size(); i++){
                        Neigh = call NeighborList.get(i);
                        neighborCost[Neigh.Node] = 1; //get cost of neighbor nodes
                        nMAP[TOS_NODE_ID].cost[Neigh.Node] = 1;
                    }

                    makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR,20, PROTOCOL_LINKSTATE,lspSeqNum,(uint8_t*) neighborCost, 20);
                    call Sender.send(sendPackage, AM_BROADCAST_ADDR);
                    lspSeqNum++;
                    }

                }
                

            }else if(myMsg->protocol == HELLO){
                int forw = -1;
		dbg(TRANSPORT_CHANNEL,"HELLO COMMAND FROM SERVER %d\n",myMsg->src);
                if(myMsg->dest == TOS_NODE_ID){
                    
                    dbg(TRANSPORT_CHANNEL,"ATTEMPTING TO ESTABLISH CONNECTION TO SERVER %d\n",myMsg->src);
                    TestClient(myMsg->src, myMsg->payload);

                }else{
			
                    makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL - 1, myMsg->protocol, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                    forw = shortestPath(myMsg->dest, TOS_NODE_ID);
		    //dbg(TRANSPORT_CHANNEL,"FORWARDING TO %d\n",forw);
                    call Sender.send(sendPackage, forw);
                }
                




            }else if(myMsg->protocol == getUSERNAME){
	    	int forwardtoo;
	    	if(myMsg->dest == TOS_NODE_ID){
		dbg(TRANSPORT_CHANNEL, "Hello %s\n", nodePorts[myMsg->seq].username);
		makePack(&sendPackage, myMsg->dest, myMsg->src, MAX_TTL, saveUSERNAME, nodePorts[myMsg->seq].destPort, (uint8_t*)nodePorts[myMsg->seq].username, PACKET_MAX_PAYLOAD_SIZE);
		forwardtoo = shortestPath(myMsg->src, TOS_NODE_ID);
		call Sender.send(sendPackage, forwardtoo);
		}else{
			makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL -1, myMsg->protocol, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
			forwardtoo = shortestPath(myMsg->dest, TOS_NODE_ID);
			call Sender.send(sendPackage, forwardtoo);
		}
	    	
	    
	    }else if(myMsg->protocol == saveUSERNAME){
	    	int forwardtoo;
	    	if(myMsg->dest == TOS_NODE_ID){
			nodePorts[myMsg->seq].hasClient = TRUE;
			nodePorts[myMsg->seq].state = ESTABLISHED;
			
			
			memcpy(nodePorts[myMsg->seq].username, myMsg->payload, sizeof(myMsg->payload));
			//dbg(TRANSPORT_CHANNEL, "PORT %d\n", myMsg->seq);
		 	//dbg(TRANSPORT_CHANNEL, "SAVED USERNAME %s\n", nodePorts[myMsg->seq].username);
		}else{
			makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL -1, myMsg->protocol, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
			forwardtoo = shortestPath(myMsg->dest, TOS_NODE_ID);
			call Sender.send(sendPackage, forwardtoo);
		}
	    	 
	    }else if(myMsg->protocol == SERVER_BROADCAST){
	    	int forwardtoo;
		int i;
	    	if(myMsg->dest == TOS_NODE_ID){
			dbg(TRANSPORT_CHANNEL,"Broadcast MESSAGED RECIEVED FROM CLIENT %d PAYLOAD: %s\n",myMsg->src, myMsg->payload);
			for(i = 0; i < 256; i++){
				if(nodePorts[i].hasClient == TRUE){
					dbg(TRANSPORT_CHANNEL,"SENDING Broadcast MESSAGE TO %d on port %d\n",nodePorts[i].destAddr, nodePorts[i].destPort);
					makePack(&sendPackage, TOS_NODE_ID, nodePorts[i].destAddr, MAX_TTL, serverSentBROADCAST, 55, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
					forwardtoo = shortestPath(nodePorts[i].destAddr, TOS_NODE_ID);
					call Sender.send(sendPackage, forwardtoo);
				}
			}
		}else{
			makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL -1, myMsg->protocol, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
			forwardtoo = shortestPath(myMsg->dest, TOS_NODE_ID);
			call Sender.send(sendPackage, forwardtoo);
		}
	    
	    
	    
	    }else if(myMsg->protocol == serverSentBROADCAST){
	    	int forwardtoo;
	    	if(myMsg->dest == TOS_NODE_ID){
			dbg(TRANSPORT_CHANNEL,"-----------Broadcast MESSAGED RECIEVED FROM Server %d PAYLOAD: %s------------\n",myMsg->src, myMsg->payload);
		}else{
			makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL -1, myMsg->protocol, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
			forwardtoo = shortestPath(myMsg->dest, TOS_NODE_ID);
			call Sender.send(sendPackage, forwardtoo);
		}
		
	    
	    }
            else if (myMsg->protocol == PROTOCOL_PING) //pings
            {
               
                
               dbg(FLOODING_CHANNEL,"Packet Received from %d meant for %d... Rebroadcasting\n",myMsg->src, myMsg->dest);
                
                call Hash.remove(myMsg->src);
                call Hash.insert(myMsg->src,myMsg->seq);
                
                if (myMsg->dest == TOS_NODE_ID)
                {
                    int sendTo = 0;
                    makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL,PROTOCOL_PING,myMsg->seq,myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                    // This is when the flooding of a packet has finally led it to it's final destination
                    if(checkPacket(sendPackage)){
                       dbg(FLOODING_CHANNEL,"Dropping Packet from src: %d to dest: %d with seq num:%d\n", myMsg->src,myMsg->dest,myMsg->seq);
                    }else{
                    
                    dbg(FLOODING_CHANNEL, "Packet has Arrived to destination! %d -> %d seq num: %d\n ", myMsg->src,myMsg->dest, myMsg->seq);
                    dbg(FLOODING_CHANNEL, "Package Payload: %s\n", myMsg->payload);

                   
                    //send ACK
                    sendTo =  shortestPath(myMsg->src, TOS_NODE_ID); 
                    dbg(FLOODING_CHANNEL, "Sending ACK back to %d! with seqNum : %d. Forwarding to %d\n", myMsg->src, ACKseq, sendTo);
                    makePack(&sendPackage, TOS_NODE_ID, myMsg->src, 20,PROTOCOL_PINGREPLY,ACKseq,&myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                    call Sender.send(sendPackage, sendTo);
                    ACKseq--;
                    
                    //dbg(FLOODING_CHANNEL, "SendPackage: %d\n", sendPackage.seq);
                    //dbg(FLOODING_CHANNEL, "seqNum: %d\n", seqNum);
                    }
                }
                else
                {   int nextNode =  0;
                    makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL, myMsg->protocol, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                    if(checkPacket(sendPackage)){//return true meaning packet found in SeenPackList
                        //dbg(FLOODING_CHANNEL,"ALREADY SEEN: Dropping Packet from src: %d to dest: %d with seq num:%d\n", myMsg->src,myMsg->dest,myMsg->seq);
                        //dbg(FLOODING_CHANNEL,"ALREADY SEEN: Dropping Packet from src: %d to dest: %d\n", myMsg->src,myMsg->dest);
                    }else{
                        makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL -1, myMsg->protocol, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                        nextNode = shortestPath(myMsg->dest, TOS_NODE_ID);
                    dbg(ROUTING_CHANNEL,"Packet Recieved from %d meant for %d, Sequence Number %d...Forwarding to %d\n",myMsg->src, myMsg->dest, myMsg->seq, nextNode);
                    //dbg(FLOODING_CHANNEL,"Packet Recieved from %d meant for %d... Rebroadcasting\n",myMsg->src, myMsg->dest);
                    //if(TOS_NODE_ID == 19){
                      //      printMap(nMAP);
                       // }

                    call Sender.send(sendPackage, nextNode);
                    }
                    

                }
            }
            else if (myMsg->dest == AM_BROADCAST_ADDR) //neighbor discovery
            {
                
                if(myMsg->protocol == PROTOCOL_PINGREPLY){
                    neighbor Neighbor;
                    neighbor* neighbor_ptr;
                    int somethingChanged = 0;
                    int i = 0;
                    bool FOUND;
                    //dbg(FLOODING_CHANNEL,"received pingreply from %d\n", myMsg->src);
                
                    //dbg(FLOODING_CHANNEL,"Neighbor: %d and Life %d\n",Neighbor->Node,Neighbor->Life);

                    FOUND = FALSE; //IF FOUND, we switch to TRUE
                    size = call NeighborList.size();
                    if(!call NeighborList.isEmpty()){
                            //increase life of neighbors
                        for(i = 0; i < size; i++) {
				            neighbor_ptr = call NeighborList.getAddress(i);
				            neighbor_ptr->Life++;
                            
                            //dbg(NEIGHBOR_CHANNEL, "Life of neighbor %d increased to %d\n", neighbor_ptr.Node, neighbor_ptr.Life);
			            }
                    }
                    
                    
                    //check if source of ping reply is in our neighbors list, if it is, we reset its life to 0 
                    for(i = 0; i < size; i++){
                        neighbor_ptr = call NeighborList.getAddress(i);
                        if(neighbor_ptr->Node == myMsg->src){
                            //found neighbor in list, reset life
                            //dbg(NEIGHBOR_CHANNEL, "Node %d found in neighbor list\n", myMsg->src);
                            neighbor_ptr->Life = 0;
                               
                            FOUND = TRUE;
                            break;
                        }
                    }

                    //if the neighbor is not found it means it is a new neighbor to the node and thus we must add it onto the list by calling an allocation pool for memory PoolOfNeighbors
                    if(!FOUND){
                        //dbg(NEIGHBOR_CHANNEL, "NEW Neighbor: %d added to neighbor list\n", myMsg->src);
                        //Neighbor = &myMsg->src; //get New Neighbor
                        Neighbor.Node = myMsg->src; //add node source
                        Neighbor.Life = 0; //reset life
                        call NeighborList.pushfront(Neighbor); //put into list 
                        size = call NeighborList.size();
                        somethingChanged++;
                        //dbg(NEIGHBOR_CHANNEL,"Neighbor ADDED %d, and life %d\n", Neighbor->Node, Neighbor->Life);

                    }
                    //Check if neighbors havent been called or seen in a while, if 5 pings occur and neighbor is not heard from, we drop it

			        for(i = 0; i < call NeighborList.size(); i++) {
			        	neighbor_ptr = call NeighborList.getAddress(i);
				        
                        
				        if(neighbor_ptr->Life > 5) {
                            //dbg(NEIGHBOR_CHANNEL, "Node %d life has expired dropping from NODE %d list, Havent seen node since %d pings ago\n", neighbor_ptr->Node, TOS_NODE_ID, neighbor_ptr->Life);
					        call NeighborList.remove(i);
                            somethingChanged++;
                        }
			        }

                    if(somethingChanged > 0){
                        neighbor Neigh;
                        update = TRUE;
                        //dbg(ROUTING_CHANNEL, "SOMETHING CHANGED\n");
                        
                    }
                    somethingChanged = 0;
                }else if(myMsg->protocol == PROTOCOL_LINKSTATE){
                    //check if packet has been seen 

                    int i = 0, t= 0;
                    
                    makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL,myMsg->protocol,myMsg->seq,&myMsg->payload, 20);
                    if(!checkPacket(sendPackage)){ //not seen before
                        //dbg(ROUTING_CHANNEL, "LSP recieved from %d, with seqNUM: %d\n", myMsg->src, myMsg->seq);

                        for(i = 0; i < 20; i++){
                            nMAP[myMsg->src].cost[i] = 0;
                        }
                        for(i = 0; i < 20; i++){
                            nMAP[myMsg->src].cost[i] = myMsg->payload[i];
                        }

                        
                        makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1,myMsg->protocol,myMsg->seq,&myMsg->payload, 20);
                        call Sender.send(sendPackage, AM_BROADCAST_ADDR);
                    }else{
                        //dbg(ROUTING_CHANNEL, "LSP ALREADY SEEN from %d, with seqNUM: %d\n", myMsg->src, myMsg->seq);
                    }
                    //put into table 

                    //forward packet 
                }
                

                
            }else if(myMsg->protocol == PROTOCOL_TCP){
                int forwardPackage;
		int freePort;
                if(myMsg->dest == TOS_NODE_ID){
                    TCP *tcpPack = (TCP*) myMsg->payload;
                    TCP newTCPPackage;
                    dbg(TRANSPORT_CHANNEL,"Recieved TCP Packet: from %d on port %d with TCPseq: %d and flag: %d\n", myMsg->src, tcpPack->srcPort, tcpPack->seqNum, tcpPack->flag);
                    if(tcpPack->flag == SYN_CLIENT){//recieved connection request from client
                        freePort = freeServerPort(); 
                        if(freePort != -1){
                            dbg(TRANSPORT_CHANNEL,"Binding client %d with client port %d to Server port %d\n", myMsg->src, tcpPack->srcPort, freePort);
                            nodePorts[freePort].open = FALSE; //not an open port anymore
                            nodePorts[freePort].destAddr = myMsg->src; //port only accepting connections from this address 
                            nodePorts[freePort].destPort = tcpPack->srcPort; //port only accepts data from destAddr and clients port 
                            nodePorts[freePort].srcPort = freePort; //port used for this connection
				
                            //SERVER sends SYN packet back with ACK = tcpPack->seqNum + 1 => sequence number server expects back and with its own sequence number 
                            newTCPPackage.srcPort = freePort; 
                            newTCPPackage.destPort = tcpPack->srcPort;
                            newTCPPackage.flag = SYN_SERVER; //Denotes SYN from SERVER
                            newTCPPackage.ACK = tcpPack->seqNum + 1; //expect this sequence number back from client
                            newTCPPackage.seqNum = (uint16_t) ((call Random.rand16())%256);
                            nodePorts[freePort].lastSeq = newTCPPackage.seqNum;
                            nodePorts[freePort].nextSeq = newTCPPackage.ACK;
			    memcpy(newTCPPackage.payload, tcpPack->payload, sizeof(tcpPack->payload));
			    memcpy(nodePorts[freePort].username, tcpPack->payload, sizeof(tcpPack->payload));
			    //dbg(TRANSPORT_CHANNEL,"payloadSERVER %s\n",newTCPPackage.payload);
                            //dbg(TRANSPORT_CHANNEL,"Server recieved SYN from client and is now sending SYN back to client\n");
                            //dbg(TRANSPORT_CHANNEL,"Server expects sequence number %d from Client %d on port %d\n", newTCPPackage.ACK, myMsg->src, freePort);
                            makeTCPPack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_TCP, myMsg->seq + 1, &newTCPPackage, sizeof(newTCPPackage));
                            forwardPackage = shortestPath(myMsg->src,TOS_NODE_ID);
                            call Sender.send(sendPackage, forwardPackage);

                        }

                    }else if(tcpPack->flag == SYN_SERVER){
                        
                            //dbg(TRANSPORT_CHANNEL, "Client recieved ACK from SERVER and Server expects packet with sequence number %d on port %d\n",tcpPack->ACK,tcpPack->srcPort);
                            nodePorts[tcpPack->destPort].destAddr = myMsg->src; //reserve port for server address
                            
                            //check if lastSeq +1 is equal to the nextSeq expected by server
                            if((nodePorts[tcpPack->destPort].lastSeq + 1) == tcpPack->ACK){//next sequence number for client matches server's expected sequence number 
                                nodePorts[tcpPack->destPort].state = ESTABLISHED; //connection established on client side
                                nodePorts[tcpPack->destPort].nextSeq = tcpPack->seqNum + 1; //next expected sequence number from server
                                 nodePorts[tcpPack->destPort].destPort =tcpPack->srcPort;
                                 nodePorts[tcpPack->destPort].open = FALSE; //port is now closed and reserved for server address
                                 dbg(TRANSPORT_CHANNEL, "Client has recieved packet from SERVER and is trying to establish connection from client port %d to server port %d\n",tcpPack->destPort,tcpPack->srcPort);
                                newTCPPackage.destPort = tcpPack->srcPort;
                                newTCPPackage.srcPort = tcpPack->destPort;
                                newTCPPackage.ACK = nodePorts[tcpPack->destPort].lastSeq + 1;
				memcpy(newTCPPackage.payload, tcpPack->payload, sizeof(tcpPack->payload));
				//dbg(TRANSPORT_CHANNEL,"payloadSERVER %s\n",newTCPPackage.payload);
                                newTCPPackage.seqNum = nodePorts[tcpPack->destPort].lastSeq + 1;
                                nodePorts[tcpPack->destPort].lastSeq = newTCPPackage.seqNum; //update sequence number
                                newTCPPackage.flag = SYN;
                                makeTCPPack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_TCP, myMsg->seq + 1, &newTCPPackage, sizeof(newTCPPackage));
                                forwardPackage = shortestPath(myMsg->src,TOS_NODE_ID);
                                call Sender.send(sendPackage, forwardPackage);

                            
                            }else{
                                dbg(TRANSPORT_CHANNEL,"Client's next sequence number does not match server's next expected sequence number from Server... connection CANNOT BE ESTABLISHED\n");
                            }

                            


                    }else if(tcpPack->flag == SYN){
                        int bufferSize = 0, forwardPackage;
                        if(tcpPack->ACK == nodePorts[tcpPack->destPort].nextSeq ){
                            //dbg(TRANSPORT_CHANNEL,"Server recieved expected Sequence number: %d from client %d\n",nodePorts[tcpPack->destPort].nextSeq, myMsg->src);
                            dbg(TRANSPORT_CHANNEL,"-------CONNECTION ESTABLISHED, Three-WAY Handshake Complete---------\n");
                            dbg(TRANSPORT_CHANNEL,"Client:%d Port: %d\n", myMsg->src, tcpPack->srcPort);
                            dbg(TRANSPORT_CHANNEL,"Server:%d Port: %d\n", TOS_NODE_ID, tcpPack->destPort);
			    
                            if(tcpPack->payload != "TestClient" || tcpPack->payload != "closeClient"){
			    	nodePorts[tcpPack->destPort].destAddr = myMsg->src;
                            	nodePorts[tcpPack->destPort].destPort =  tcpPack->srcPort;
				nodePorts[tcpPack->destPort].srcPort = tcpPack->destPort;
                            	nodePorts[tcpPack->destPort].state = ESTABLISHED;
				makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, getUSERNAME, tcpPack->srcPort, &myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                                //dbg(TRANSPORT_CHANNEL, "Hello %s\n", nodePorts[tcpPack->destPort].username);
				forwardPackage = shortestPath(myMsg->src,TOS_NODE_ID);
                                call Sender.send(sendPackage, forwardPackage);
				
                            }else{
			     
			     nodePorts[tcpPack->destPort].destAddr = myMsg->src;
                            nodePorts[tcpPack->destPort].destPort =  tcpPack->srcPort;
                            nodePorts[tcpPack->destPort].state = ESTABLISHED;
			    memcpy(newTCPPackage.payload, tcpPack->payload, sizeof(tcpPack->payload));
                            nodePorts[tcpPack->destPort].lastSeq = nodePorts[tcpPack->destPort].lastSeq +1;//keeps track of servers sequencenumber
                            nodePorts[tcpPack->destPort].nextSeq = tcpPack->ACK;//keeps track of expected sequence number from client
                            nodePorts[tcpPack->destPort].open = FALSE;//not open anymore
                            dbg(TRANSPORT_CHANNEL,"-------SERVER CAN NOW ACCEPT BYTE STREAM DATA From Client %d on Server port %d---------\n",myMsg->src,tcpPack->destPort);
                            bufferSize = getBufferSpaceAvail(nodePorts, tcpPack->destPort);
                            dbg(TRANSPORT_CHANNEL,"Server has %d Bytes of available BUFFER SPACE for data\n",bufferSize);
                            newTCPPackage.srcPort = tcpPack->destPort;
                            newTCPPackage.destPort = tcpPack->srcPort;
                            newTCPPackage.AdWindow = bufferSize - 1;
                            newTCPPackage.flag = sendServerData; // flag to tell client to start sending data
                            makeTCPPack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_TCP, myMsg->seq + 1, &newTCPPackage, sizeof(newTCPPackage));
                                forwardPackage = shortestPath(myMsg->src,TOS_NODE_ID);
                                call Sender.send(sendPackage, forwardPackage);
			     
			     }
                            


                        }else{
                            dbg(TRANSPORT_CHANNEL,"Server cannot connect to Client:%d Port: %d\n", myMsg->src, tcpPack->srcPort);
                        }
                    }else if(tcpPack->flag == sendServerData){
                            int forwardPackage;
                            dbg(TRANSPORT_CHANNEL,"Server has %d bytes of buffer space\n",tcpPack->AdWindow);
                            if(tcpPack->AdWindow > nodePorts[tcpPack->destPort].sizeofPayload){
                                dbg(TRANSPORT_CHANNEL,"Byte Advertised Window for server has enough space to handle the rest of remaining bytes of client payload on port %d\n", tcpPack->srcPort);
                                newTCPPackage.srcPort = tcpPack->destPort;
                                newTCPPackage.destPort = tcpPack->srcPort;
				memcpy(newTCPPackage.payload, tcpPack->payload, sizeof(tcpPack->payload));
                                newTCPPackage.doneSending = 1; //tell server we are finishing sending our message_t
                                newTCPPackage.flag = clientSentData;
                                makeTCPPack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_TCP, myMsg->seq + 1, &newTCPPackage, sizeof(newTCPPackage));
                                forwardPackage = shortestPath(myMsg->src,TOS_NODE_ID);
                                call Sender.send(sendPackage, forwardPackage);

                            }else if(tcpPack->AdWindow != 0){
                                int nextData;
                                nextData = tcpPack->AdWindow;
                                nodePorts[tcpPack->destPort].sizeofPayload = nodePorts[tcpPack->destPort].sizeofPayload - tcpPack->AdWindow;
                                dbg(TRANSPORT_CHANNEL, "Sending next %d bytes of data to port %d and server %d\n", nextData, tcpPack->srcPort, myMsg->src);
                                newTCPPackage.srcPort = tcpPack->destPort;
                                newTCPPackage.destPort = tcpPack->srcPort;
                                newTCPPackage.doneSending = 0; //tell server we are not finish sending our message_t
                                newTCPPackage.flag = clientSentData;
				memcpy(newTCPPackage.payload, tcpPack->payload, sizeof(tcpPack->payload));
                                newTCPPackage.seqNum = tcpPack->AdWindow;
                                makeTCPPack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_TCP, myMsg->seq + 1, &newTCPPackage, sizeof(newTCPPackage));
                                forwardPackage = shortestPath(myMsg->src,TOS_NODE_ID);
                                call Sender.send(sendPackage, forwardPackage);
                                

                            }else{
                                dbg(TRANSPORT_CHANNEL, "NO BUFFER SPACE AVAILABLE ON PORT%d\n", tcpPack->srcPort);
                            }





                    }else if(tcpPack->flag == clientSentData){
                            int nextSpot;
                            if(tcpPack->doneSending == 1){
                                dbg(TRANSPORT_CHANNEL, "-------------Recieved all data from client %d with client PORT %d--------------\n", myMsg->src, tcpPack->srcPort);
                                dbg(TRANSPORT_CHANNEL, "FREE BUFFER SPACE ON PORT %d\n", tcpPack->destPort);



                            }else{
                                dbg(TRANSPORT_CHANNEL, "-------------Recieved SOME data from client %d with client PORT %d, EXPECTING NEXT BYTES %d--------------\n", myMsg->src, tcpPack->srcPort,tcpPack->seqNum);
                                newTCPPackage.ACK = tcpPack->seqNum;
                                newTCPPackage.srcPort = tcpPack->destPort;
                                newTCPPackage.destPort = tcpPack->srcPort;
                                newTCPPackage.flag = sendServerData;
				memcpy(newTCPPackage.payload, tcpPack->payload, sizeof(tcpPack->payload));
                                makeTCPPack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_TCP, myMsg->seq + 1, &newTCPPackage, sizeof(newTCPPackage));
                                nextSpot = shortestPath(myMsg->src,TOS_NODE_ID);
                                call Sender.send(sendPackage, nextSpot);
                            }




                    }else if(tcpPack->flag == FIN){
                            //connection termination
                            if(nodePorts[tcpPack->destPort].state == ESTABLISHED){
                                dbg(TRANSPORT_CHANNEL, "%d on port %d attempting to teardown connection with %d on port %d\n",myMsg->src,tcpPack->srcPort,TOS_NODE_ID,tcpPack->destPort);
                                nodePorts[tcpPack->destPort].state = FIN_WAIT_2;//host recieved teardown request from a different node
                                newTCPPackage.ACK = tcpPack->seqNum + 1;
                                newTCPPackage.srcPort = tcpPack->destPort;
                                newTCPPackage.destPort = tcpPack->srcPort;
                                newTCPPackage.flag = FIN;
                                makeTCPPack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_TCP, myMsg->seq + 1, &newTCPPackage, sizeof(newTCPPackage));
                                forwardPackage = shortestPath(myMsg->src,TOS_NODE_ID);
                                call Sender.send(sendPackage, forwardPackage);
                            }else if(nodePorts[tcpPack->destPort].state == FIN_WAIT_1){ //this node is who instigated connection teardown
                                if(nodePorts[tcpPack->destPort].nextSeq == tcpPack->ACK){
                                    dbg(TRANSPORT_CHANNEL,"Recieved Expected ACK For CONNECTION TEARDOWN\n");
                                    dbg(TRANSPORT_CHANNEL,"---------------TEARING DOWN CONNECTION to %d on port %d, FREEING MY PORT %d---------------------\n",myMsg->src, tcpPack->srcPort, tcpPack->destPort);
                                    //reopen port
                                    nodePorts[tcpPack->destPort].state = AVAILABLE;
                                    nodePorts[tcpPack->destPort].open = TRUE;
                                    nodePorts[tcpPack->destPort].destAddr = 0;
                                    nodePorts[tcpPack->destPort].destPort = 0;
                                    newTCPPackage.srcPort = tcpPack->destPort;
                                    newTCPPackage.destPort = tcpPack->srcPort;
                                    newTCPPackage.ACK = nodePorts[tcpPack->destPort].lastSeq + 1;
                                    newTCPPackage.seqNum = nodePorts[tcpPack->destPort].lastSeq + 1;
                                    newTCPPackage.flag = FIN;
                                    dbg(TRANSPORT_CHANNEL,"Acknowledging to %d on port %d, so they can teardown their end of CONNECTION\n",myMsg->src, tcpPack->srcPort);
                                    makeTCPPack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_TCP, myMsg->seq + 1, &newTCPPackage, sizeof(newTCPPackage));
                                    forwardPackage = shortestPath(myMsg->src,TOS_NODE_ID);
                                    call Sender.send(sendPackage, forwardPackage);
                                }
                                
                            }else if(nodePorts[tcpPack->destPort].state == FIN_WAIT_2){
                                    dbg(TRANSPORT_CHANNEL,"---------------Tearing Down connection to %d on port %d, FREEING MY PORT %d------------\n",myMsg->src, tcpPack->srcPort, tcpPack->destPort);
                                    nodePorts[tcpPack->destPort].state = AVAILABLE;
                                    nodePorts[tcpPack->destPort].open = TRUE;
                                    nodePorts[tcpPack->destPort].destAddr = 0;
                                    nodePorts[tcpPack->destPort].destPort = 0;
                            }




                    }else{
                        dbg(TRANSPORT_CHANNEL,"NOTHING HAPPENS\n");
                    }


                }else{
				
		    TCP *tcpPack = (TCP*) myMsg->payload;
		    
                    
			  //dbg(TRANSPORT_CHANNEL,"payloadNotMines %s\n",tcpPack->srcPort);
		    //dbg(TRANSPORT_CHANNEL,"payloadNotMines %s\n",tcpPack->payload);
                    makeTCPPack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL - 1, myMsg->protocol, myMsg->seq, tcpPack, sizeof(myMsg->payload));
                    forwardPackage = shortestPath(myMsg->dest,TOS_NODE_ID);
                    //dbg(TRANSPORT_CHANNEL,"TCP packet meant for %d, forwarding to %d\n",myMsg->dest, forwardPackage);
                    call Sender.send(sendPackage, forwardPackage);
                }






            }else if(myMsg->protocol == PROTOCOL_PINGREPLY){ //ACK
                
                
                if(myMsg->dest == TOS_NODE_ID){
                    makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL,PROTOCOL_PINGREPLY,myMsg->seq,&myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                    if(!checkPacket(sendPackage)){
                          dbg(FLOODING_CHANNEL,"Node %d recieved ACK from %d!! and seqNum: %d\n", TOS_NODE_ID,myMsg->src, myMsg->seq);
                       
                        }
                    

                }else{    
                         int nextPlace = 0;

                          makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL ,PROTOCOL_PINGREPLY,myMsg->seq,&myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                          if(!checkPacket(sendPackage)){
                            //dbg(FLOODING_CHANNEL,"ACK recieved from %d meant for %d seqNum: \n", myMsg->src, myMsg->dest, sendPackage.seq);
                            nextPlace = shortestPath(myMsg->dest, TOS_NODE_ID);
                            makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1 ,PROTOCOL_PINGREPLY,myMsg->seq,&myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                            call Sender.send(sendPackage, nextPlace);
                          }else{
                              //dbg(FLOODING_CHANNEL, "ACK ALREADY SEEN ffrom %d to %d and seq: %d\n", myMsg->src, myMsg->dest, myMsg->seq);
                          }
                          
                       
                        
                    
                }
            }
            
            return msg;
        }
        dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
        return msg;
    }
    
    
    event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
        int nextNode= 0;
        dbg(GENERAL_CHANNEL, "PING EVENT \n");
        
        makePack(&sendPackage, TOS_NODE_ID, destination, 20, PROTOCOL_PING, seqNum, payload, PACKET_MAX_PAYLOAD_SIZE);
        nextNode = shortestPath(destination, TOS_NODE_ID);
        checkPacket(sendPackage);
        dbg(ROUTING_CHANNEL, "Forwarding to %d \n", nextNode);
        call Sender.send(sendPackage, nextNode);
        
        call Hash.insert(TOS_NODE_ID,seqNum);
        //dbg(FLOODING_CHANNEL, "seqNumAfter: %d\n", seqNum);
        seqNum++;
    }
    
    event void CommandHandler.printNeighbors()
    {
        printNeighborList();
    }
    
    event void CommandHandler.printRouteTable(){
        
        shortPathPrint(TOS_NODE_ID);
    }
    
    event void CommandHandler.printLinkState(){}
    
    event void CommandHandler.printDistanceVector(){}
    
    event void CommandHandler.setTestServer(){
    		TestServer(); 
    }
    
    event void CommandHandler.setTestClient(int server, uint8_t *payload){
    		TestClient(server, payload);
    }
    event void CommandHandler.clientClose(int server, uint8_t *payload){
        int i, forwardPackage;
        TCP tcpPack;
        for(i = 0; i < 256; i++){
            if(nodePorts[i].destAddr == server && nodePorts[i].state == ESTABLISHED){//client has a current connection to server that it wants to teardown
                dbg(TRANSPORT_CHANNEL,"Attempting to disconnect from server %d on port %d from Client's port %d\n",server,nodePorts[i].destPort,nodePorts[i].srcPort);
                tcpPack.destPort = nodePorts[i].destPort;
                tcpPack.srcPort = nodePorts[i].srcPort;
                tcpPack.seqNum = nodePorts[i].lastSeq;
                tcpPack.flag = FIN;
                nodePorts[i].nextSeq = nodePorts[i].lastSeq + 1;
                nodePorts[i].state = FIN_WAIT_1;
                 makeTCPPack(&sendPackage, TOS_NODE_ID, server,MAX_TTL, PROTOCOL_TCP, seqNum++, &tcpPack, sizeof(tcpPack));
                    forwardPackage = shortestPath(server,TOS_NODE_ID);
                    //dbg(TRANSPORT_CHANNEL,"TCP packet meant for %d, forwarding to %d\n",myMsg->dest, forwardPackage);
                    call Sender.send(sendPackage, forwardPackage);

            }
        }
    }
    event void CommandHandler.setAppServer(){}
    
    event void CommandHandler.setAppClient(){}
    
    event void CommandHandler.helloServer(int client, uint8_t *payload){
        int forward; 
        nodePorts[41].state = LISTENING_SERVER;
        dbg(TRANSPORT_CHANNEL,"Server listening on port 41\n");
        makePack(&sendPackage, TOS_NODE_ID, client, MAX_TTL, HELLO, 0, payload,PACKET_MAX_PAYLOAD_SIZE);
	
        forward = shortestPath(client, TOS_NODE_ID);
	//dbg(TRANSPORT_CHANNEL,"Server forwarding to %d\n", forward);
	//dbg(GENERAL_CHANNEL, "Packet payload %s\n", sendPackage.payload);
        call Sender.send(sendPackage, forward);


    }
    event void CommandHandler.broadCastMessage(int server, uint8_t *payload){
    	int nextNode= 0;
        dbg(GENERAL_CHANNEL, "----Broadcasting message sending to SERVER----- \n");
        
        makePack(&sendPackage, TOS_NODE_ID, server, MAX_TTL, SERVER_BROADCAST, 2, payload, PACKET_MAX_PAYLOAD_SIZE);
        nextNode = shortestPath(server, TOS_NODE_ID);
        
        
        call Sender.send(sendPackage, nextNode);
    
    }
    event void whisper(uint8_t *username, uint8_t *payload){
    	makePack(&sendPackage, TOS_NODE_ID,0, MAX_TTL, 4, 1, payload, PACKET_MAX_PAYLOAD_SIZE);
    	dbg(TRANSPORT_CHANNEL,"payload : %s\n", sendPackage.payload);
	makePack(&sendPackage, TOS_NODE_ID,0, MAX_TTL, 4, 1, username, PACKET_MAX_PAYLOAD_SIZE);
    	dbg(TRANSPORT_CHANNEL,"USERNAME : %s\n", sendPackage.payload);
	
    }
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, int seq, uint8_t* payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }
    void makeTCPPack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, int seq, TCP* payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }
    bool checkPacket(pack Packet){
            pack PacketMatch;
            //pack* package_PTR = &Packet;
            //pack Packet = Packet;
            if(call SeenPackList.isEmpty()){
            
                call SeenPackList.pushfront(Packet);
                return FALSE;
            }else if(Packet.protocol == PROTOCOL_LINKSTATE){
                int j;
                for(j = 0; j < call SeenPackList.size(); j++){
                    PacketMatch = call SeenPackList.get(j);
                    if((PacketMatch.src == Packet.src) && (PacketMatch.protocol == PROTOCOL_LINKSTATE)){
                        if(Packet.seq > PacketMatch.seq){ //new LSP packet, remove old one 
                            call SeenPackList.remove(j);
                            call SeenPackList.pushfront(Packet);
                            return FALSE; //return false because it is new packet
                        }else{
                            return TRUE; //recieved older seq num LSP packet or same
                        }
                    }
                }
            }else if(Packet.seq < 0){ //CHECK IF SEEN ACK
                int k;
                for(k = 0; k < call SeenPackList.size(); k++){
                    PacketMatch = call SeenPackList.get(k);
                    if(PacketMatch.seq < 0){
                        //dbg(NEIGHBOR_CHANNEL, "SEQUENCE NUMBER PACKETMATC = %d, PACKET = %d", PacketMatch.seq, Packet.seq);
                        if((PacketMatch.src == Packet.src) && (PacketMatch.seq == Packet.seq) && (PacketMatch.dest == Packet.dest)){
                            return TRUE; //found
                            
                        }
                    }
                    
                }

            }else{
                int i;
                int size = call SeenPackList.size();
                for(i = 0; i < size; i++){
                    PacketMatch = call SeenPackList.get(i);
                    if( (PacketMatch.protocol == Packet.protocol)&&(PacketMatch.src == Packet.src) && (PacketMatch.dest == Packet.dest) && (PacketMatch.seq == Packet.seq)){
                        //dbg(FLOODING_CHANNEL,"Packet src %d vs PacketMatch src %d\n", Packet->src,PacketMatch->src);
                        //dbg(FLOODING_CHANNEL,"Packet destination %d vs PacketMatch dest %d\n", Packet->dest,PacketMatch->dest);
                        //dbg(FLOODING_CHANNEL,"Packet seq %d vs PacketMatch seq %d\n", Packet->seq,PacketMatch->seq);
                        //call SeenPackList.remove(i);
                        return TRUE; //packet is found in list and has already been seen by node.

                    }

                }
    
                
            }
            //other wise packet not found and we need to push it into seen pack list
                call SeenPackList.pushfront(Packet);
                return FALSE;
    }
    
    void neighborDiscovery(){
        
    
       char* dummyMsg = "NULL\n";

       //dbg(NEIGHBOR_CHANNEL, "Neighbor Discovery: node %d looking for its neighbors\n", TOS_NODE_ID);
		
			
		
		
        //send with destination broadcast
        makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 20, PROTOCOL_PINGREPLY, -2, dummyMsg, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPackage, AM_BROADCAST_ADDR);
        
        
    }

    void printNeighborList()
    {
        int i = 0;
        neighbor Neigh;
        dbg(NEIGHBOR_CHANNEL,"Neighbors for node %d\n",TOS_NODE_ID);
        
        for(i = 0; i < call NeighborList.size(); i++)
        {   Neigh = call NeighborList.get(i);
            dbg(NEIGHBOR_CHANNEL,"Node: %d with Life: %d\n",Neigh.Node, Neigh.Life);
        }
    }
    
    
    
    
    void linkedState(){
        int i;
        neighbor Neigh;
        for(i = 0; i < 20; i++){
            nMAP[0].cost[i] = 0;
        }
        for(i = 0; i < 20; i++){
            nMAP[TOS_NODE_ID].cost[i] = 0;
        }

        if(!call NeighborList.isEmpty()){
            for(i = 0; i < call NeighborList.size(); i++){
                Neigh = call NeighborList.get(i);
                neighborCost[Neigh.Node] = 1; //get cost of neighbor nodes
                nMAP[TOS_NODE_ID].cost[Neigh.Node] = 1;
            }

            makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR,20, PROTOCOL_LINKSTATE,lspSeqNum,(uint8_t*) neighborCost, 20);
            call Sender.send(sendPackage, AM_BROADCAST_ADDR);
            lspSeqNum++;
        }else{
                dbg(ROUTING_CHANNEL, "No neighbors for Node\n");
        }

        
    }
    
    void printMap(netMap * map){
        bool teel = FALSE;
                        if(teel){

                                makePack(&sendPackage, TOS_NODE_ID,AM_BROADCAST_ADDR, 20, 25,updateNum, "updateNet\n", PACKET_MAX_PAYLOAD_SIZE);
                                call Sender.send(sendPackage, AM_BROADCAST_ADDR);
                                updateNum++;
                                //update = FALSE;
                        }else{
                            int i, t;
                            for(i = 0; i < 20; i++){
                                dbg(ROUTING_CHANNEL, "Neighbors of node %d\n", i);
                                for(t = 0; t < 20; t++){
                                    if(map[i].cost[t] > 0){
                                        dbg(ROUTING_CHANNEL,"Node: %d cost: %d\n", t ,map[i].cost[t]);
                                    }
                                    
                                }
                            }
                        }
                        
                        

    }

    int shortestPath(int dest, int first){
        int nodes[20];
    
    int i,j,k, minDistIndex;
    
    routingTable distance[numOfVertices]; 
    bool visited[numOfVertices];
    int holdPath[numOfVertices];
    
    nodes[0] = 0;
    for(i = 0; i < numOfVertices; i++){
        distance[i].distance = 1000, visited[i] = FALSE;
        distance[i].nextHop = 0;
        nodes[i] = i;
        holdPath[i] = 0;
    }
    
    
    distance[first].distance = 0;
    
    i = 0;
    for(i = 0; i < numOfVertices; i++){
        
        
        //minDistIndex = 0;
        minDistIndex = minDistance(distance, visited);
        
        
        
        visited[minDistIndex] = TRUE;
        
     
        for( j = 0; j < numOfVertices; j++){
            if(!visited[j] && nMAP[minDistIndex].cost[j] > 0 && distance[minDistIndex].distance != 1000 && distance[minDistIndex].distance + nMAP[minDistIndex].cost[j] < distance[j].distance){
                distance[j].distance = distance[minDistIndex].distance + nMAP[minDistIndex].cost[j];
                
                holdPath[j] = minDistIndex;
                
                
            }
        }
        minDistIndex = 0;
    }
    i = 1;
    for(i = 1; i < numOfVertices;i++){
        
        j = i;
        
        
        
        
        j = i;
        
        do{
            if(nodes[j] != 0 && j != 0 && nodes[j]!= first){
                
                distance[i].nextHop = nodes[j];
            }
            
            
            j = holdPath[j];
            
            if(nodes[j] != 0 && j != 0){
                
                
            }
            
            
            
        }while(j != 0);
        
        
        
    }
    return distance[dest].nextHop;

    }
    void shortPathPrint(int first){
    int nodes[20];
    
    int i,j,k, minDistIndex;
    
    routingTable distance[numOfVertices]; //distance holds shortest path from  current node to dest node
    bool visited[numOfVertices];//  true when node is in shortest path from current node to dest node
    int holdPath[numOfVertices];
    
    // Init distances to 'infinity' and next hop to 0 or NULL
    nodes[0] = 0;
    for(i = 0; i < numOfVertices; i++){
        distance[i].distance = 1000, visited[i] = FALSE;
        distance[i].nextHop = 0;
        nodes[i] = i;
        holdPath[i] = 0;
    }
    
    //cost from own node to itself is 0
    distance[first].distance = 0;
    //find path to each node from current node
    i = 0;
    for(i = 0; i < numOfVertices; i++){
        
        //min distance from the set of nodes not yet included in the current path for current node
        //minDistIndex = 0;
        minDistIndex = minDistance(distance, visited);
        
        
        //lets us know node already has been seen
        visited[minDistIndex] = TRUE;
        
        // shorter path is obtainedw if node has not been visited and there is an edge from nodes[minDistIndex] to j where total cost is smaller than current cost 
        for( j = 0; j < numOfVertices; j++){
            if(!visited[j] && nMAP[minDistIndex].cost[j] > 0 && distance[minDistIndex].distance != 1000 && distance[minDistIndex].distance + nMAP[minDistIndex].cost[j] < distance[j].distance){
                distance[j].distance = distance[minDistIndex].distance + nMAP[minDistIndex].cost[j];
                
                holdPath[j] = minDistIndex;
                
                
            }
        }
        minDistIndex = 0;
    }
    i = 1;
    for(i = 1; i < numOfVertices;i++){
        
        j = i;
        printf("cost to %d =  %d ", nodes[i], distance[i].distance); //print routing table for current Node
        
        
        
        
        
        j = i;
        
        do{
            if(nodes[j] != 0 && j != 0 && nodes[j]!= first){
                
                distance[i].nextHop = nodes[j];
            }
            
            //distance[i].nextHop = nodes[j+1];
            j = holdPath[j];
            
            if(nodes[j] != 0 && j != 0){
                //printf(" <- %d", nodes[j]);
                
            }
            
            
            
        }while(j != 0);
        printf(" NextHop: %d", distance[i].nextHop);
        printf("\n");
        
        
    }

    
}
    int minDistance(routingTable distance[], bool visited[]){
    
    //finds node with min cost from unseen nodes not included yet
        int min = 1000;
        int minIndex = 0;
        int i;
        for(i = 0; i < numOfVertices; i++){
            if(!visited[i] && distance[i].distance<= min){
                min = distance[i].distance;
                minIndex = i;
            }
    }   
        return minIndex;
    }

	void TestServer(){
		//get open port and start listening
        //socket_addr_t fd;
	    int openPort;
		
        //find open port
        dbg(TRANSPORT_CHANNEL,"----------Attempting to open Server at %d------------\n", TOS_NODE_ID);
        openPort = getFreePort();
        
        if(openPort != -1){
            dbg(TRANSPORT_CHANNEL,"-------------Server listening on port %d-----------\n", openPort);
            //bind(sockets, fd, openPort); //bind to socket
            nodePorts[openPort].state = LISTENING;

        }else{

            dbg(TRANSPORT_CHANNEL,"ATTEMPT FAILED!... NO PORTS AVAILABLE\n");
        }
	
	
	}
    
    void TestClient(int server, uint8_t * payload){
        TCP tcpPackage;
        int openPort;
        int nextPlace;
        dbg(TRANSPORT_CHANNEL, "-------Attempting to connect to SERVER %d-------\n",server);  
        openPort = getFreePort();
        if(openPort != -1){
            dbg(TRANSPORT_CHANNEL,"Client using port %d for connection\n", openPort);
            //bind(sockets, fd, openPort); //bind to socket
            nodePorts[openPort].state = SYN_SENT; //port knows it sent an SYN and thus knows port is being used as a client 
            nodePorts[openPort].srcPort = openPort;
            tcpPackage.srcPort = openPort;
            memcpy(tcpPackage.payload, payload, sizeof(payload));
	    memcpy(nodePorts[openPort].username, payload, sizeof(payload));
	    //dbg(TRANSPORT_CHANNEL,"Client PAYLOAD %s\n", tcpPackage.payload);
            tcpPackage.seqNum = (uint16_t) ((call Random.rand16())%256);// get random starting sequence number for connection
            tcpPackage.flag = SYN_CLIENT;
            nodePorts[openPort].lastSeq = tcpPackage.seqNum;
            nodePorts[openPort].sizeofPayload = sizeof(payload);
            makeTCPPack(&sendPackage, TOS_NODE_ID, server, MAX_TTL, PROTOCOL_TCP, seqNum, &tcpPackage, sizeof(tcpPackage));
            seqNum++;
            nextPlace = shortestPath(server, TOS_NODE_ID);
            dbg(TRANSPORT_CHANNEL,"------------Sending SYN Packet to Server %d with sequence number %d.. forwarding to %d-----------\n", server, tcpPackage.seqNum,nextPlace);
            call Sender.send(sendPackage, nextPlace);
        }else{

            dbg(TRANSPORT_CHANNEL,"NO PORTS AVAILABLE to use for connection\n");
        }
    }
    	
    void initPorts(){
        int i, j;
        //open all ports
	
        for(i = 0; i < 256; i++){
            nodePorts[i].open = TRUE;
            nodePorts[i].destAddr = 0; //initially
            nodePorts[i].portNumber = i;
            nodePorts[i].state = AVAILABLE;
	    nodePorts[i].hasClient = FALSE;
        }
        for(i = 0; i < 256; i++){
            for(j = 0; j < 128; j++){
                nodePorts[i].recievedData[j] = '-';
                nodePorts[i].sentData[j] = '-';
            }
        }
	
    }
    int getFreePort(){
        int i, port;
        bool found = FALSE;
        for(i = 0; i < 256; i++){
                port =  (uint16_t) ((call Random.rand16())%256);
                    if(nodePorts[port].open == TRUE && nodePorts[port].state == AVAILABLE){
                        found = TRUE;
                        return nodePorts[port].portNumber;
                    }
        }
        
        dbg(TRANSPORT_CHANNEL,"No open ports for %d\n", TOS_NODE_ID);
        return -1;
    }
    int freeServerPort(){
        int i, port;
        bool found = FALSE;
        for(i = 0; i < 256; i++){
                
                    if(nodePorts[i].open == TRUE && nodePorts[i].state == LISTENING){
                        nodePorts[i].state = AWAITING;
                        found = TRUE;
                        return nodePorts[i].portNumber;
                    }
        }
	
                
                    if(nodePorts[41].state == LISTENING_SERVER){
		    	for(i = 0; i < 256; i++){
			if(nodePorts[i].open == TRUE){
			nodePorts[i].state = AWAITING;
                        found = TRUE;
			return nodePorts[i].portNumber;
			}
                        
                        
			}
                    }
        
        
        dbg(TRANSPORT_CHANNEL,"No open listening ports for %d\n", TOS_NODE_ID);
        return -1;
    }
    int getBufferSpaceAvail(Port nodePorts[], int sourcePort){
        int sizeAvail = 0;
        int i =0;
        for(i = 0; i < 128; i++){
            if(nodePorts[sourcePort].recievedData[i] == '-' ){
                sizeAvail++;
            }
        }
        return sizeAvail;
    }

}

