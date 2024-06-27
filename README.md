# netlib
![netlib - network library](https://github.com/arsscriptum/netlib/blob/master/doc/img/netlib.png "netlib")

Simple, easy to use, network library written in c++ providing
networking functionalities on top of both the tcp and udp protocols.

### What netlib **does**
*   Platform independent non-blocking UDP sockets on Windows, Linux and MacOS.
*   TCP connectivity.
*   Convenient serialization of primitive types with bit packing to reduce bandwidth (a boolean takes up 1 bit)
*   Virtual connection over UDP supporting up to 256 connections per socket.
*   Client/server framework with working LAN lobby out of the box
*   Short circuit delivery of local packets without going over the socket layer

### What netlib **will provide in the future**

*   **SCTP** - The _SCTP_ protocol never caught on, but it seems intriguing, and might be nice to have in the library for experimentation, if not for some internal applications. https://en.wikipedia.org/wiki/Stream_Control_Transmission_Protocol

Repository
----------

https://github.com/arsscriptum/netlib


Build Procedures
----------------

- Windows:
	*  Clone the repository from github
	*  Open the project file netlib.vcxproj using Microsoft Visual Studio 2015
	*  Compile library in as a static package: Debug|Release.
    *  Compile library in as a dynamic dll: DebugDll|ReleaseDll.
	*  Output file in bin folder


Development Notes
-----------------

![Network Structure](https://github.com/arsscriptum/netlib/blob/master/doc/img/netstructure.png)

### Platform Layer

This layer provides a platform independent foundation for networking:

 - NetPlatform
 - NetSocket

### Packet Layer

This layer provides a simple block allocator for packets with bit-packing read/write operations. It also provides an abstract stream interface that unifies packet read/write operations into a single serialize method.

 - NetPacket
 - NetStream

### Abstraction Layer

This layer adds useful abstractions on top of UDP sockets:

 - NetInterface
 - NetBeacon
 - NetPipe

NetInterface represents a network topology neutral concept of slots and virtual connections under UDP. NetBeacon abstracts broadcast sockets into a basic server list. NetPipe provides simulated network conditions (latency/jitter/packetloss etc.) as well as local delivery of packets without going over the socket layer.


## Layers in Detail
This section examines each layer in turn, focusing on key classes in each layer and how they relate to each other.

### Platform Layer
#### NetPlatform
This class wraps up the platform specifics of starting the network layer, connecting the device, and querying network properties such as hostname and mac address that are only available once the network interface is up. In the future we may extend it to provide callbacks notification on connect, disconnect so you dont have to poll it.

On Win32 this interface is basically a wrapper around WSAStartup / WSACleanup, on consoles it is much more complicated. See NetPlatform.cpp for details.

Before using any socket level functionality, you must initialize the net platform and wait until it connects:
```
int main()
{
    printf( "initializing\n" );

    if ( !NetPlatform::Initialize() )
    {
        printf( "failed to initialize network platform\n" );
        return 1;
    }

    printf( "connecting...\n" );

    NetPlatform::Connect();

    while ( !NetPlatform::IsConnected() )
    {
        Sleep( 0 );
    }

    printf( "online.\n" );

    // ....

    printf( "shutting down\n" );

    NetPlatform::Shutdown();

    return 0;
}
```

Of course, you would not normally spinlock until connected like this in your game application, but this is the easiest way to do it when you are writing a simple test application. You get the point.

Once your net platform has connected, you can query the platform for information. The functions below rely on the network platform being connected, they will assert out if its not:

```
    ASSERT( NetPlatform::IsConnected() );

    printf( "hostname: %s\n", NetPlatform::GetHostName() );

    printf( "session id: %d\n", NetPlatform::GenerateSessionId() );

    if ( NetPlatform::CheckCapability( NetPlatform::RECEIVES_OWN_BROADCAST ) )
        printf( "this platform receives its own broadcast packets\n" );
    else
        printf( "this platform does not receive its own broadcast packets\n" );
```


#### NetSocket
Once the network platform has connected, you can initialize the socket layer and create sockets:

Unlike NetPlatform::Initialize/Connect, this layer is very lightweight. It wont block for a long period of time like NetSocket::Initialize can because of WSAStartup on Win32

```
    ASSERT( NetPlatform::IsConnected() );

    NetSocket::Initialize();

    ASSERT( NetSocket::IsInitialized() );

    unsigned short port = 9000;

    NetSocket * socket = NetSocket::Create( port );         // note: you can also pass in a port of zero and the socket layer will find a free port for you

    ASSERT( socket );

    // ...

    NetSocket::Destroy( socket );

    NetSocket::Shutdown();
```

When you shutdown net socket, it checks that all sockets created have been destroyed. It will assert out if you forget to destroy a socket you created.

Under no circumstances are you allowed to delete a socket object directly!

Socket are created as a standard non-blocking UDP socket, with about 64k of send buffer and 64k recv buffer. The amount of buffering you can do before packets get dropped varies depending on platform. Dont rely on it!

By default the socket is of "standard" type, the other option is a "broadcast" socket. You choose the type when you create the socket and you cannot change it afterwards. We do not support multicasting.


Here is how to create a broadcast socket:
```
    ASSERT( NetSocket::IsInitialized() );

    NetSocket * broadcastSocket = NetSocket::Create( port + 1, NetSocket::Broadcast );

    ASSERT( broadcastSocket );

    // ...
```


Once a socket is created, you can query it for useful bits of information:

```
    NetAddress address = socket->GetAddress();
    NetAddress broadcastAddress = broadcastSocket->GetAddress();

    printf( "socket address: %d.%d.%d.%d:%d\n", address.GetA(), address.GetB(), address.GetC(), address.GetD(), address.GetPort() );
    printf( "broadcast address: %d.%d.%d.%d:%d\n", broadcastAddress.GetA(), broadcastAddress.GetB(), broadcastAddress.GetC(), broadcastAddress.GetD(), broadcastAddress.GetPort() );

    ASSERT( socket->GetType() == NetSocket::Standard );
    ASSERT( broadcastSocket->GetType() == NetSocket::Broadcast );
```


You need to create both the send and recv ends of your broadcast socket in broadcast mode for it work across all platforms. Note that some platforms (xenon) do not receive their own broadcast packets locally. You can check this using NetPlatform::CheckCapability( NetPlatform::RECEIVES_OWN_BROADCAST )

Here is how you send data using sockets, remember that all socket operations are non-blocking:

```
    const int bytes = 256;

    unsigned char data[bytes];

    for ( int i = 0; i < bytes; ++i )
        data[i] = (unsigned char) i;

    const int sentBytes = socket->Send( NetAddress( 192,168,0,1, port ), data, bytes );

    ASSERT( sentBytes == bytes );

    const int broadcastBytes = broadcastSocket->Send( NetAddress( 255,255,255,255, port + 1 ), data, bytes );
 
    ASSERT( broadcastBytes == bytes );
```

Socket send will either return zero bytes sent on failure, or the bytes sent identical to the requested bytes to send. It will not return a negative number error code or a partial number of bytes sent like the BSD socket sendto function.

Here is how you receive, its the same for standard and broadcast sockets, so I wont repeat myself:
```
   NetAddress sender;
   unsigned char receivedData[bytes];
   const unsigned int receivedBytes = socket->Receive( sender, receivedData, bytes );

   if ( receivedBytes == bytes )
       printf( "received %d bytes from %d.%d.%d.%d:%d\n", receivedBytes, sender.GetA(), sender.GetB(), sender.GetC(), sender.GetD(), sender.GetPort() ); 
   else
       printf( "failed to receive, or no data available to receive\n" );
```

Since the socket is non-blocking, remember that a return value of zero is not an error condition, it just means that there is nothing available to receive.

Note that we do NOT supply a socket peek function, as it is generally considered bad form (its slow), and is not supported across all platforms.

### Packet Layer
Some of the naming in this layer is confusing because it was not refactored substantially from the original design, and the meaning of some pieces do not necessarily match their functionality in the system.

NetPacket is not really the "packet" that is sent, its actually more like the fixed size block that builds up a real "packet" represented by the NetPacketGroup.

NetPacketGroup is very close to the original battlefront design. It adds a linked-list of NetPacket blocks, and takes care of bit-packing, especially the complicated cases across fixed-size block boundaries.

NetStream is an abstraction I added on top of NetPacketGroup, its sole purpose is to unify read/write operations into a single serialize operation. This makes it possible to write one function that reads and writes the packet data, making it harder to get out of sync (and avoiding cut&paste code maintennance).


#### NetPacket
Whenever you are using NetPacket, NetPacketGroup or NetStream, or any of the layers higher than this one, you must first initialize the packet system.

Once you have initialized NetPacket, you can allocate and free packets, and ask it information like the number of free packets, the total number of packets, and so on:
```
    NetPacket::Initialize();

    ASSERT( NetPacket::IsInitialized() );

    NetPacket * packet = NetPacket::Allocate();

    ASSERT( packet );        // allocate WILL return null if you run out of packets

    const int packetSize = NetPacket::GetSize();
    const int freePackets = NetPacket::GetFreeCount();
    const int allocatedPackets = NetPacket::GetAllocatedCount();
    const int totalPackets = NetPacket::GetTotalCount();

    printf( "packet blocks are %d bytes\n", packetSize );
    printf( "%d packets total, %d are free, %d are allocated\n", totalPackets, freePackets, allocatedPackets );

    NetPacket::Free( packet );

    NetPacket::Shutdown();
```


You typically initialize NetPacket and NetSocket around the same time. I initialize NetPlatform earlier on and wait for it to connect before I initialize these systems. It should not matter what order you initialize/shutdown NetPacket and NetSocket in relative to each other, but make sure you shutdown NetSocket before you shutdown NetPlatform!

You must free all packets before calling NetPacket::Shutdown or it will assert out. You are strictly forbidden from calling delete on a NetPacket* directly, you must use NetPacket::Destroy!

When you have an instance of NetPacket, remember that this instance is really just a "block" in our block allocator, it is not really the whole "packet" that is sent across the network. We will fix this up in the refactor.

Do not use instances of NetPacket directly unless you have no other choice. Use NetStream instead and let it handle the low level NetPacket details for you.

#### NetPacketGroup
This class is a linked list of NetPacket. It has a whole load of linked list operations (GetFront, PopFront, PushFront etc)

The main thing that this class does, aside from acting as a linked list of packets, is that it adds bit-packed read and write operations.

        // input object to serialize (custom)

        NetCustomObject obj;
        obj.AddData(234);
        obj.Compresse();
        
        // serialize write

        NetPacketGroup packetGroup;

        packetGroup.BeginWrite();
        {
            NetStream writeStream( packetGroup, NetStream::Write );
            obj.Serialize( writeStream );
        }

        packetGroup.EndWrite();

        // serialize read

        NetCustomObject serializedObj;
        serializedObj.Defaults();

        packetGroup.BeginRead();
        {
            NetStream readStream( packetGroup, NetStream::Read );
            serializedObj.Serialize( readStream );
        }

        packetGroup.EndRead();

        packetGroup.Free();

        // decompress and check

        serializedObj.Decompress();

#### NetStream
This is the interface you should use when serializing data.

NetStream can be in either read mode, or in write mode.

```
    NetStream stream( ... );

    NetStream::Mode mode = stream.GetMode();

    if ( mode == NetStream::READ )
        printf( "stream is in read mode\n" );
    else if ( mode == NetStream::WRITE )
        printf( "stream is in write mode\n" );
Or you can use these functions:

    if ( stream.IsReading() )
        printf( "stream is reading\n" );

    if ( stream.IsWriting() )
        printf( "stream is writing\n" );
```

Unlike NetPacket and NetPacketGroup, NetStream does not have read and write functions, it has a single set of "Serialize" functions. These functions take the stream mode into consideration and decide whether to read or write data.

### Abstraction Layer

#### NetInterface
The key abstraction of this layer is the NetInterface, it represents a number of virtual connections over a single UDP socket.

The net interface makes no requirements about network topology. You simply have a number of slots (up to 256), that can either be 'open' or 'closed'. Open slots can receive incoming connections, closed slots connect to other net interfaces. Slots are closed by default.

To create client/server topology, you create a net interface with n slots (max connections), and open all the slots. Then you create another net interface with only a single slot, which is closed by default. You 'connect' this slot to the address of the server interface. When the client connects it will be assigned a slot on the server in the range [0,n-1].

![Net Interface](https://github.com/arsscriptum/netlib/blob/master/doc/img/netinterface.png)

Here is some example code to show you some common cases.

Client/server with a single client only:

```
    ASSERT( NetPlatform::IsConnected() );

    ASSERT( NetSocket::IsInitialized() );
    ASSERT( NetPacket::IsInitialized() );

    // start client and server, connect client to server

    NetInterface client, server;

    int port = 9000;
	
    server.Start( port );
    client.Start( port + 1 );

    server.Open();

    client.Connect( server.GetAddress() );

    while ( !client.IsConnected() && !server.IsConnected() )
    {
        server.Update();
        client.Update();
    }

    // we are connected: main update loop

    for ( int i = 0; i < 100; ++i )
    {
        // send packet from client to server

        int number = i;

        NetPacket * clientPacket = NetPacket::Allocate();
        clientPacket->BeginWrite();
        clientPacket->Write( number );
        clientPacket->EndWrite();

        client.Send( clientPacket );         // note: when you send a packet, the interface takes OWNERSHIP of it!

        printf( "client sent packet %d\n", number );

        // receive packets on server

        while ( true )
        {
            NetPacket * packet = server.Receive();

            if ( !packet )
                break;

            unsigned int number = 0;

            packet->BeginRead();
            packet->Read( number );
            packet->EndRead();

            printf( "server received packet %d\n", number );

            NetPacket::Free( packet );           // when you RECEIVE a packet, you take ownership of it!
        }

        // we need to update the interfaces each iteration, otherwise send/recv are not processed

        client.Update();
        server.Update();
    }

    server.Stop();
    client.Stop();
```


Here is a client/server with multiple clients.

Each client is its own net interface which corresponds to a socket, the server has one interface/socket with n slots, one for each client:

```
    ASSERT( NetPlatform::IsConnected() );

    ASSERT( NetSocket::IsInitialized() );
    ASSERT( NetPacket::IsInitialized() );

    // start server with support for 4 players

    const int MaxPlayers = 4;

    NetInterface server;

    int port = 9000;
	
    server.Start( port, MaxPlayers );

    for ( int i = 0; i < MaxPlayers; ++i )
        server.Open( i );

    // connect four clients to the server

    NetInterface client[MaxPlayers];

    for ( int i = 0; i < MaxPlayers; ++i )
    {
        client[i].Start( port + 1 + i );            // note: we can also pass in a port of zero and let the socket layer find a free port for us
        client[i].Connect( server.GetAddress() );
    }

    while ( true )
    {
        server.Update();
        client.Update();

        bool connected = true;

        for ( int i = 0; i < MaxPlayers; ++i )
        {
            if ( !client[i].IsConnected() )         // is client n slot 0 connected?
                connected = false;

            if ( !server.IsConnected( i ) )         // is server slot n connected?
                connected = false;
        } 

        if ( connected )
            break;        
    }

    // we are connected: main update loop

    for ( int i = 0; i < 100; ++i )
    {
        // send packet from client to server

        for ( int j = 0; j < MaxPlayers; ++i )
        {
            int number = j;

            NetPacket * clientPacket = NetPacket::Allocate();
            clientPacket->BeginWrite();
            clientPacket->Write( number );
            clientPacket->EndWrite();

            client[j].Send( clientPacket );         // note: when you send a packet, the interface takes OWNERSHIP of it!

            int clientId = client.GetSlot( j ).GetRemoteSlot();      // note: this is the slot the client is connected to on the server

            printf( "client %d sent packet %d\n", clientId, number );
        }

        // receive packets on server

        while ( true )
        {
            for ( int j = 0; j < MaxPlayers; ++j )
            {
                NetPacket * packet = server.Receive( j );      // note: receive packet from slot number j

                if ( !packet )
                    break;

                unsigned int number = 0;

                packet->BeginRead();
                packet->Read( number );
                packet->EndRead();

                printf( "server received packet %d from client %d\n", number, j );

                NetPacket::Free( packet );           // when you RECEIVE a packet, you take ownership of it!
            }
        }

        // we need to update the interfaces each iteration, otherwise send/recv are not processed

        server.Update();

        for ( int j = 0; j < MaxPlayers; ++j )
            client[j].Update();
    }

    server.Stop();

    for ( int i = 0; i < MaxPlayers; ++i )
        client[i].Stop();

```


By default net interface has timeout disabled.


It is very important that you enable timeout in real world cases, you cant just loop forever and expect to eventually connect! Furthermore, once a client has connected, the only way a client can 100% reliably detect that the client has disconnected is by timeout.

There are also cases where the client cannot connect because there are no free slots, eg. a fifth player trying to connect to a four player game.

You get to decide what unit of time you pass into NetInterface update.

Lets assume that we use units of one second, here is how to implement timeout and handle error cases on connect:

```
    // start client and server, connect client to server with timeout

    NetInterface client, server;

    int port = 9000;
	
    server.Start( port );
    client.Start( port + 1 );

    server.SetTimeOut( 10.0f );       // timeout is 10 seconds
    client.SetTimeOut( 10.0f );

    server.Open();

    client.Connect( server.GetAddress() );

    while ( !client.IsConnected() && client.GetSlot(0).GetConnectionError() == NetInterfaceSlot::ConnectionOK )
    {
        const float deltaTime = 0.1f;

        // note: you have the option to run portions of net interface update independently,
        // eg. you can update sends, update receives, or update its concept of time, this lets you
        // eliminate trivial latencies in your system when sending local packets by updating sends
        // for both client and server, then updating receives for both client/server interfaces. See NetGame.h

        // here we just update everything, because all we want to do is pass in DELTA TIME as the second parameter!

        server.Update( NetInterface::UpdateSend | NetInterface::UpdateReceive | NetInterface::UpdateTime, deltaTime );
        client.Update( NetInterface::UpdateSend | NetInterface::UpdateReceive | NetInterface::UpdateTime, deltaTime );

        Sleep( 100 );     // ~10ms
    }

    switch ( client.GetSlot(0).GetConnectionError() )
    {
        case NetInterfaceSlot::ConnectionOK:      printf( "connection succeeded\n" );       break;
        case NetInterfaceSlot::ConnectionBusy:    printf( "connection failed: busy\n" );    break;
        case NetInterfaceSlot::ConnectionTimeOut: printf( "connection failed: timeout\n" ); break;
    }

    // note: if the connection fails and you want to try again, just call client.Connect again, otherwise no action will be taken past this point
```


You can also implement the net interface listener to receive event callbacks.

Use this to hookup your higher level code to net interface so you can respond to events like client connected, client timed out, incoming packet etc. Its also really useful during debugging your program because you can do printfs to see what is going on:

```
    printf( "test interface listener\n" );

    struct Listener : public NetInterfaceListener
    {
        char name[32];

	protected:

 	   void OnStart( NetInterface & net, int port, unsigned int slots )
	   {
               printf( "%s: started on port %d with %d slot(s)\n", name, port, slots );
	   }

	   void OnStop( NetInterface & net )
	   {
               printf( "%s: stopped\n", name );
	   }

	   void OnUpdate( NetInterface & net, int updateFlags, float deltaTime )
	   {
               printf( "%s: update with delta time %.2f\n", name, deltaTime );
	   }

           void OnSlotConnected( NetInterface & net, unsigned int slot )
	   {
               printf( "%s: slot %d stopped\n", name, slot );
           }

	   void OnSlotConnectionFailed( class NetInterface & net, unsigned int slot, NetInterfaceListener::ConnectionFailedReason reason )
	   {
               switch ( reason )
	       {
		   case Busy: printf( "%s: slot %d connection failed: busy\n", name, slot ); break;
		   case TimeOut: printf( "%s: slot %d connection failed: timeout\n", name, slot ); break;
	       }
	   }

	   void OnSlotTimeOut( NetInterface & net, unsigned int slot )
	   {
	       printf( "%s: slot %d timed out\n", name, slot );
	   }

	   void OnSlotDisconnected( NetInterface & net, unsigned int slot )
	   {
               printf( "%s: slot %d disconnected\n", name, slot );
	   }

           void OnSend( NetInterface & net, NetPacket * packet )
	   {
               printf( "%s: send packet\n", name );
	   }

	   void OnReceive( NetInterface & net, NetPacket * packet )
	   {
	       printf( "%s: receive packet\n", name );
	   }
       };

       Listener clientListener, serverListener;

       strcpy( clientListener.name, "client" );
       strcpy( serverListener.name, "server" );

       NetInterface client, server;

       client.SetListener( &client );
       server.SetListener( &server );

       int port = 9000;

       server.Start( port );
       client.Start( port + 1 );

       server.Open();

       client.Connect( server.GetAddress() );

       // etc...

```

Just like timeouts, setting a listener persists across calls to start/stop. If you want to remove the listener, just call SetListener( NULL )


### NetBeacon
This class abstracts broadcast sockets into a functional LAN lobby.

Beacons can be run in "broadcast" or "receive" mode. Broadcast beacons represent servers broadcasting their existence, while receiver beacons represent the LAN lobby searching for servers on the LAN.

In the broadcast mode, you can set the server payload data that is broadcast any time you want. You can also control the frequency of packets being broadcast. In my experience broadcasting once every 10th of a second is easily fast enough - remember that these packets never go outside the LAN!

On the receiver side, net beacon handles adding, updating and removing servers for you as broadcast packets are recieved. Sequence numbers are used internally to ensure that the server list contains only the latest data.

Here is a quick example showing how to setup a broadcast and receive beacon, then loop and print the list of servers found:

```
struct ServerData
{
    ServerData()
    {
        memset( serverName, 0, sizeof(serverName) );
        memset( levelName, 0, sizeof(levelName) );
        playerCount = 0;
        maximumPlayerCount = 0;
    }

    bool Serialize( NetStream & stream )
    {
        stream.SerializeString( serverName, sizeof(serverName) );
        stream.SerializeString( levelName, sizeof(levelName) );
        stream.SerializeByte( playerCount );
        stream.SerializeByte( maximumPlayerCount );
        return true;
    }

    // note: you need to implement the == and != operators so the net beacon
    // can detect when an entry in the server list has changed

    bool operator == ( const ServerData & other ) const
    {
	return strcmp( serverName, other.serverName ) == 0 &&
	       strcmp( levelName, other.levelName ) == 0 &&
	       playerCount == other.playerCount && 
	       maximumPlayerCount == other.maximumPlayerCount;
    }

    bool operator != ( const ServerData & other ) const
    {
        return !( *this == other );
    }

    char serverName[64];
    char serverName[64];
    unsigned char playerCount;
    unsigned char maximumPlayerCount;
};

int main( int argc, char * argv[] )
{
    NetPlatform::Initialize();

    // not shown: connect platform, wait until connected

    NetSocket::Initialize();
    NetPacket::Initialize();

    typedef NetBeacon<ServerData> ServerBeacon;

    ServerBeacon broadcastBeacon, receiveBeacon;

    const int id = 0x12345;       // note: this hash identifies our network game, this stops Mercs2 lobby seeing LOTR games in its lobby etc...
    const int port = 9000;

    if ( !broadcastBeacon.Start( port, id, ServerBeacon::Broadcast ) )
    {
        printf( "failed to start broadcast beacon!\n" );
        return 1;
    }

    if ( !receiveBeacon.Start( port, id, ServerBeacon::Receive ) )
    {
	printf( "failed to start receive beacon!\n" );
	return 1;
    }

    ServerData data;
    strncpy( data.serverName, NetPlatform::GetHostName(), sizeof( data.serverName ) ); 
    broadcastBeacon.SetOutgoing( data );

    receiveBeacon.SetTimeOut( 5.0f );

    while ( !kbhit() )
    {
        float deltaTime = 1.0f;

        broadcastBeacon.Update( deltaTime );
        receiveBeacon.Update( deltaTime );

        printf( "------------------------------\n" );

        for ( unsigned int i = 0; i < receiveBeacon.GetMaximum(); ++i )
        {
            NetAddress address;

            ServerData * serverData = receiveBeacon.GetIncoming( i, address );

            if ( serverData )
            {
                printf( "%s (%d.%d.%d.%d)\n", 
                        serverData->serverName, address.GetA(), address.GetB(), address.GetC(), address.GetD() );
            }
        }

        printf( "------------------------------\n" );

        Sleep( 1000 );         // 1 second
    }

    broadcastBeacon.Stop();
    receiveBeacon.Stop();

    NetPacket::Shutdown();
    NetSocket::Shutdown();

    NetPlatform::Shutdown();

    return 0;
}
```

#### NetPipe
NetPipe started as our mechanism for simulating network conditions such as latency, jitter and packet loss.

We currently support the following simulated network conditions:

 - Latency
 - Packet Loss
 - Jitter (random +/- delivery time)
 - Out of order packets
 - Duplicate packets
 - Limited bandwidth


Each NetInterface has its own internal NetPipe. You can get this pipe and set the network conditions on it and all communications across the NetInterface will be affected:
```
    NetInterface server;

    server.GetPipe().SetDuplicate( 10.0f );         // 10% of packets are duplicated
    server.GetPipe().SetOutOfOrder( 5.0f );         // 5% of packets are out of order
    server.GetPipe().SetJitter( 1.0f );             // +/- 1 seconds of jitter
    server.GetPipe().SetLatency( 10.0f );           // 10 seconds latency
    server.GetPipe().SetPacketLoss( 90.0f );        // 90% packets lost
    server.GetPipe().SetBandwidth( 100 );           // 100 bits per second

    while ( !quit )
    {
        float deltaTime = 0.01f;      // 1/100th of a second

        server.Update( NetInterface::UpdateSend | NetInterface::UpdateReceive | NetInterface::UpdateTime, deltaTime );

        // ...
    }
```


The other major feature of NetPipe is local packet delivery. This is accomplished by adding a "IsLocal" flag to NetAddress and explicitly linking one NetPipe to another NetPipe. All addresses with the local flag set are routed directly between the two NetPipes without going over the socket layer.

Here is how you accomplish this at the NetPipe level:

```
    // setup client and server

    const int port = 9000;

    NetSocket * server = NetSocket::Create( port );
    NetSocket * client = NetSocket::Create( port + 1 );

    ASSERT( server );
    ASSERT( client );

    // setup pipes

    NetPipe serverPipe( server );         // note: currently they need the socket just for the "address", but we're not actually using the sockets to send/recv data
    NetPipe clientPipe( client );

    serverPipe.SetLocalPipe( &clientPipe );
    clientPipe.SetLocalPipe( &serverPipe );

    // send and receive packets (server to client)

    unsigned char buffer[PacketSize];

    for ( int i = 0; i < PacketSize; ++i )
	buffer[i] = (unsigned char) ( i & 0xFF );

    unsigned int iterations = 100;

    for ( unsigned int i = 0; i < iterations; ++i )
    {
        NetPacket * packet = NetPacket::Allocate();

        packet->BeginWrite();
        packet->Write( buffer, PacketSize );
        packet->EndWrite();

        serverPipe.Send( packet, NetAddress::Local( client->GetAddress() ) );

        float deltaTime = 0.01f;

        serverPipe.Update( deltaTime );
        clientPipe.Update( deltaTime );

        NetAddress sender;
        NetPacket * receivePacket = clientPipe.Receive( sender );

        ASSERT( packet == receivePacket );		// it should be the exact same packet!
        ASSERT( sender == NetAddress::Local( server->GetAddress() ) );

        unsigned char data[PacketSize];

        packet->BeginRead();
        packet->Read( data, PacketSize );
        packet->EndRead();

        ASSERT( memcmp( data, buffer, PacketSize ) == 0 );

        NetPacket::Free( receivePacket );

        Sleep( 10 );     // ~ 1/100th of a second
    }
```

Note that NetAddress::Local is just a convenience function that takes an existing address object, and returns a copy of it with the local flag set.

Here is how you do the same thing at the NetInterface level:
```
    NetSocket::Disable();			// note: block packets going through socket layer, we use this to guarantee to you that packets are not going over sockets

    NetInterface client, server;

    client.SetLocalConnection( &server );
    server.SetLocalConnection( &client );

    int port = 9000;

    server.Start( port );
    client.Start( port + 1 );

    server.Open();

    client.Connect( NetAddress::Local( server.GetAddress() ) );

    while ( !client.IsConnected() || !server.IsConnected() )
    {
        client.Update();
        server.Update();
    }

    // ...

```
Note that simulated network conditions are always ignored for local packets; they are always delivered promptly with no latency or packet loss.





Known Issues
-----------------

 - None so far... 



Coding Standards
-----------------
In terms of code standards, I mainly use the Google style guides (C++, JavaScript, Objective-C, and Python) for my personal projets so this is the coding style I adopted for this project.
Consistency is most important to strive for, the header of the provided library is formated differently from the rest of the projet, but that's about it.

https://github.com/google/styleguide
