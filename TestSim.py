#ANDES Lab - University of California, Merced
#Author: UCM ANDES Lab
#$Author: abeltran2 $
#$LastChangedDate: 2014-08-31 16:06:26 -0700 (Sun, 31 Aug 2014) $
#! /usr/bin/python
import sys
from TOSSIM import *
from CommandMsg import *

class TestSim:
    # COMMAND TYPES
    CMD_PING = 0
    CMD_NEIGHBOR_DUMP = 1
    CMD_ROUTE_DUMP=3
    CMD_TEST_CLIENT = 4
    CMD_TEST_SERVER = 5
    CMD_CLIENT_CLOSE = 10
    CMD_HELLO_SERVER = 11
    CMD_BROADCAST = 12
    CMD_WHISPER = 7
    CMD_PRINT_USERS = 13
    # CHANNELS - see includes/channels.h
    COMMAND_CHANNEL="command";
    GENERAL_CHANNEL="general";

    # Project 1
    NEIGHBOR_CHANNEL="neighbor";
    FLOODING_CHANNEL="flooding";

    # Project 2
    ROUTING_CHANNEL="routing";

    # Project 3
    TRANSPORT_CHANNEL="transport";

    # Personal Debuggin Channels for some of the additional models implemented.
    HASHMAP_CHANNEL="hashmap";

    # Initialize Vars
    numMote=0

    def __init__(self):
        self.t = Tossim([])
        self.r = self.t.radio()

        #Create a Command Packet
        self.msg = CommandMsg()
        self.pkt = self.t.newPacket()
        self.pkt.setType(self.msg.get_amType())

    # Load a topo file and use it.
    def loadTopo(self, topoFile):
        print 'Creating Topo!'
        # Read topology file.
        topoFile = 'topo/'+topoFile
        f = open(topoFile, "r")
        self.numMote = int(f.readline());
        print 'Number of Motes', self.numMote
        for line in f:
            s = line.split()
            if s:
                print " ", s[0], " ", s[1], " ", s[2];
                self.r.add(int(s[0]), int(s[1]), float(s[2]))

    # Load a noise file and apply it.
    def loadNoise(self, noiseFile):
        if self.numMote == 0:
            print "Create a topo first"
            return;

        # Get and Create a Noise Model
        noiseFile = 'noise/'+noiseFile;
        noise = open(noiseFile, "r")
        for line in noise:
            str1 = line.strip()
            if str1:
                val = int(str1)
            for i in range(1, self.numMote+1):
                self.t.getNode(i).addNoiseTraceReading(val)

        for i in range(1, self.numMote+1):
            print "Creating noise model for ",i;
            self.t.getNode(i).createNoiseModel()

    def bootNode(self, nodeID):
        if self.numMote == 0:
            print "Create a topo first"
            return;
        self.t.getNode(nodeID).bootAtTime(1333*nodeID);

    def bootAll(self):
        i=0;
        for i in range(1, self.numMote+1):
            self.bootNode(i);

    def moteOff(self, nodeID):
        self.t.getNode(nodeID).turnOff();

    def moteOn(self, nodeID):
        self.t.getNode(nodeID).turnOn();

    def run(self, ticks):
        for i in range(ticks):
            self.t.runNextEvent()

    # Rough run time. tickPerSecond does not work.
    def runTime(self, amount):
        self.run(amount*1000)

    # Generic Command
    def sendCMD(self, ID, dest, payloadStr):
        self.msg.set_dest(dest);
        self.msg.set_id(ID);
        self.msg.setString_payload(payloadStr)
        

        self.pkt.setData(self.msg.data)
        self.pkt.setDestination(dest)
        self.pkt.deliver(dest, self.t.time()+5)
       

    def ping(self, source, dest, msg):
        self.sendCMD(self.CMD_PING, source, "{0}{1}".format(chr(dest),msg));

    def neighborDMP(self, destination):
        self.sendCMD(self.CMD_NEIGHBOR_DUMP, destination, "neighbor command");

    def routeDMP(self, destination):
        self.sendCMD(self.CMD_ROUTE_DUMP, destination, "routing command");

    def addChannel(self, channelName, out=sys.stdout):
        print 'Adding Channel', channelName;
        self.t.addChannel(channelName, out);

    def testServer(self, sourceNode):
        self.sendCMD(self.CMD_TEST_SERVER,sourceNode, "server command");
    
    def testClient(self, client, server, msg):
        self.sendCMD(self.CMD_TEST_CLIENT,client, "{0}{1}".format(chr(server),msg));
    def closeClient(self, client, server, msg):
        self.sendCMD(self.CMD_CLIENT_CLOSE, client,"{0}{1}".format(chr(server),msg))
    
    def helloServer(self, server, client, msg):
        self.sendCMD(self.CMD_HELLO_SERVER, server, "{0}{1}".format(chr(client),msg));
    def broadCast(self, client, server, msg):
        self.sendCMD(self.CMD_BROADCAST, client,  "{0}{1}".format(chr(server),msg));
    
    def whisper(self, server, username, msg):
        self.sendCMD(self.CMD_WHISPER, server, "{0}{1}".format(username,msg));
    
    def listusr(self, client, server, msg):
        self.sendCMD(self.CMD_PRINT_USERS, client, "{0}{1}".format(chr(server),msg))
    
def main():
    s = TestSim();
    s.runTime(10);
    s.loadTopo("long_line.topo");
    s.loadNoise("no_noise.txt");
    s.bootAll();
    s.addChannel(s.COMMAND_CHANNEL);
    s.addChannel(s.GENERAL_CHANNEL);
    s.addChannel(s.NEIGHBOR_CHANNEL);
    s.addChannel(s.FLOODING_CHANNEL);
    s.addChannel(s.ROUTING_CHANNEL);
    s.addChannel(s.TRANSPORT_CHANNEL);

    s.runTime(200);
    
    s.routeDMP(1);
    s.runTime(100);
    s.testServer(1);
    s.runTime(40);
    #s.testServer(1);
    #s.runTime(40);
    s.testClient(2, 1, "TestClient");
    s.runTime(40);
    #s.closeClient(2,1, "closeClient");
    #s.runTime(60);
    s.helloServer(1, 3, "jherrera\r\n");
    s.runTime(80);
    s.helloServer(1, 2, "atrebic\r\n");
    s.runTime(80);
    s.helloServer(1, 4, "kalex\r\n");
    s.runTime(80);
    s.broadCast(3, 1, "Hello World!\r\n");
    s.runTime(80);
    s.whisper(1,"atrebic ", "HELLO!\r\n");
    #s.whisper(1,3, "HI!\r\n");
    s.runTime(80);
    s.listusr(2, 1, "listusr\r\n");
    s.runTime(80);
    #s.testServer(7);
    #s.runTime(20);
    #s.testServer(19);
    #s.runTime(20);
    #for i in range(1, s.numMote+1):
    #        s.neighborDMP(i);
    #        s.runTime(20);
    #        print("\n");
    #s.ping(1, 7, "Hello, World");
    #s.runTime(1000); 
    #s.ping(1,19, "Hi!");
    #s.runTime(600);
    #s.ping(5, 7, "Helloooo!");
    #s.runTime(400);
    #s.ping(9, 2, "WOOOOW!");
    #s.runTime(200);
    #s.moteOff(5);
    #s.runTime(3000);
    #s.ping(15, 7, "HEEEE!");
    #s.runTime(400);
    #s.ping(19, 1, "AAAAAAA!");
    #s.runTime(200);
    #s.ping(2, 3, "GGGGGG!");
    #s.runTime(20);
    #s.ping(5, 9, "SSSSSSS!");
    #s.runTime(20);
    #s.ping(11, 13, "POKEEERR!");
    #s.runTime(20);
    
    i=0;
    
    
    #s.ping(15, 7, "HEEEE!");
    #s.runTime(600);
    #s.moteOn(5);
    #s.runTime(1000);
    #i=0;

    #s.ping(19, 7, "HEEEE!");
    #s.runTime(600);
    #for i in range(1, s.numMote+1):
    #       s.neighborDMP(i);
    #       s.runTime(20);
    #       print("\n");
    #

    
        #j = 0;
    #for j in range(1, s.numMote+1):
            #s.routeDMP(j);
            #s.runTime(100);
            #print("\n")

if __name__ == '__main__':
    main()
