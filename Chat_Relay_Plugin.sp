#pragma semicolon 1

#define PLUGIN_AUTHOR "Fishy"
#define PLUGIN_VERSION "0.0.1"

#include <sourcemod>
#include <socket>
#include <smjansson>

#pragma newdecls required

#define Host "localhost"
#define Port "8080"

Handle Socket;

public Plugin myinfo = 
{
	name = "Chat Relay Plugin",
	author = PLUGIN_AUTHOR,
	description = "A simple bridge plugin",
	version = PLUGIN_VERSION,
	url = "https://keybase.io/rumblefrog"
};

public void OnPluginStart()
{
	SocketSetOption(INVALID_HANDLE, DebugMode, 1);
	
	Socket = SocketCreate(SOCKET_TCP, OnSocketError);
	
	SocketConnect(socket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, Host, Port);
}

public void OnSocketError(Handle socket, int errorType, int errorNum, any ary)
{
	CloseHandle(socket);
	
	SetFailState("Socket error %i (errno %i)", errorType, errorNum);
}

public void OnSocketConnected(Handle socket, any arg)
{
	//Ignore, continue
}

public void OnSocketReceive(Handle socket, const char[] receiveData, int dataSize, any arg)
{
	//TODO
}

public void OnSocketDisconnected(Handle Socket, any arg)
{
	CloseHandle(Socket);
	
	PrintToServer("Socket disconnected");
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	
}
