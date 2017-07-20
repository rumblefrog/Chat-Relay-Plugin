#pragma semicolon 1

#define PLUGIN_AUTHOR "Fishy"
#define PLUGIN_VERSION "0.0.1"

#include <sourcemod>
#include <socket>
#include <smjansson>
#include <morecolors>

#pragma newdecls required

#define Host "127.0.0.1"
#define Port 8080
#define Token "123456"

Handle Socket;
Handle mJson;

bool Authenticated;
bool Binded;

int Bindings[] = {1, 2};

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
	
	SocketConnect(Socket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, Host, Port);
}

public int OnSocketError(Handle socket, int errorType, int errorNum, any ary)
{
	CloseHandle(socket);
	
	SetFailState("Socket error %i (errno %i)", errorType, errorNum);
}

public int OnSocketConnected(Handle socket, any arg)
{
	PrintToServer("Socket connected");
	SocketAuthenticate();
}

public int OnSocketReceive(Handle socket, const char[] receiveData, int dataSize, any arg)
{
	PrintToServer("%s", receiveData);
	
	mJson = json_load(receiveData);
	
	if (mJson == INVALID_HANDLE)
	{
		PrintToServer("Failed to parse JSON data");
		return;
	}
	
	Handle hKey;
	Handle hValue;
	
	hKey = json_object_iter(mJson);
	hValue = json_object_iter_value(hKey);
		
	bool Success = (json_typeof(hValue) == JSON_TRUE ? true : false);
	
	if (!Authenticated)
	{
		if (Success)
		{
			PrintToServer("Successfully Authenticated");
			Authenticated = true;
			SocketBindings();
			return;
		}
		
		char sError[128];
		
		hKey = json_object_iter(mJson);
		hValue = json_object_iter_value(hKey);
		
		json_string_value(hValue, sError, sizeof sError);
		
		PrintToServer("Failed to authenticate: %s", sError);
		
		return;
	}
	
	if (!Binded)
	{
		if (Success)
		{
			PrintToServer("Successfully Binded");
			Binded = true;
			return;
		}
		
		PrintToServer("Failed to bind channels");
		
		return;
	}
	
	char Origin[128], Origin_Type[64], Author[64], Message[256];
	
	json_string_value(mJson, Origin, sizeof Origin);
	json_string_value(mJson, Origin_Type, sizeof Origin_Type);
	json_string_value(mJson, Author, sizeof Author);
	json_string_value(mJson, Message, sizeof Message);
	
	CPrintToChatAll("%s: %s", Author, Message);
}

public int OnSocketDisconnected(Handle socket, any arg)
{
	CloseHandle(socket);
	
	PrintToServer("Socket disconnected");
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	mJson = json_object();
}

void SocketAuthenticate()
{
	Handle aJson = json_object();
	Handle adJson = json_object();
	char Json_Buffer[512];
	
	json_object_set_new(aJson, "type", json_string("authentication"));
	
	json_object_set_new(adJson, "token", json_string(Token));
	
	json_object_set_new(aJson, "data", adJson);
	
	json_dump(aJson, Json_Buffer, sizeof Json_Buffer, 0);
	
	SocketSend(Socket, Json_Buffer);
}

void SocketBindings()
{
	Handle bJson = json_object();
	Handle bdJson = json_object();
	Handle bdbJson = json_array();
	char Json_Buffer[512];
	
	json_object_set_new(bJson, "type", json_string("bindings"));
	
	for (int i = 0; i < sizeof(Bindings); i++)
		json_array_append(bdbJson, json_integer(Bindings[i]));
		
	json_object_set_new(bdJson, "bindings", bdbJson);
	
	json_object_set_new(bJson, "data", bdJson);
	
	json_dump(bJson, Json_Buffer, sizeof Json_Buffer, 0);
	
	PrintToServer("%s", Json_Buffer);
	
	SocketSend(Socket, Json_Buffer);
}