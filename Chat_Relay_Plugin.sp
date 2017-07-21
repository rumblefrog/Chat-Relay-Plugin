#pragma semicolon 1

#define PLUGIN_AUTHOR "Fishy"
#define PLUGIN_VERSION "0.0.1"

#include <sourcemod>
#include <socket>
#include <smjansson>
#include <morecolors>

#pragma newdecls required

Handle Socket;

bool Authenticated;
bool Binded;

int Port = 8080;
int Channel = 1;
int Bindings[128];
int Total_Bindings;

char Hostname[64];
char Host[64] = "127.0.0.1";
char Token[64] = "fishy";

char sBindings[64];
char pBindings[128][16];

ConVar cHost;
ConVar cPort;
ConVar cToken;
ConVar cChannel;
ConVar cBindings;

public Plugin myinfo = 
{
	name = "Chat Relay",
	author = PLUGIN_AUTHOR,
	description = "A simple bridge plugin",
	version = PLUGIN_VERSION,
	url = "https://keybase.io/rumblefrog"
};

public void OnPluginStart()
{
	SocketSetOption(INVALID_HANDLE, DebugMode, 1);
	
	GetConVarString(FindConVar("hostname"), Hostname, sizeof Hostname);
	
	cHost = CreateConVar("cr_host", "127.0.0.1", "Relay Server Host");
	cHost.GetString(Host, sizeof Host);
	
	cPort = CreateConVar("cr_port", "8080", "Relay Server Port");
	Port = cPort.IntValue;
	
	cToken = CreateConVar("cr_token", "fishy", "Relay Server Token");
	cToken.GetString(Token, sizeof Token);
	
	cChannel = CreateConVar("cr_channel", "1", "Channel to send the message on");
	Channel = cChannel.IntValue;
	
	cBindings = CreateConVar("cr_bindings", "", "Channel(s) to listen for messages on"); //Empty = All Channels
	cBindings.GetString(sBindings, sizeof sBindings);
	Total_Bindings = ExplodeString(sBindings, ",", pBindings, sizeof pBindings, sizeof pBindings[]);
	for (int i = 0; i < Total_Bindings; i++)
		Bindings[i] = StringToInt(pBindings[i]);
	
	PrintToServer("%s", pBindings[0]);
	
	AutoExecConfig(true, "Chat_Relay");
	
	Socket = SocketCreate(SOCKET_TCP, OnSocketError);
	
	SocketConnect(Socket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, Host, Port);
}

public void OnPluginEnd()
{
	if (Socket != INVALID_HANDLE)
		SocketDisconnect(Socket);
}

public int OnSocketError(Handle socket, int errorType, int errorNum, any ary)
{
	CloseHandle(socket);
	
	SetFailState("Socket error %i (errno %i)", errorType, errorNum);
}

public int OnSocketConnected(Handle socket, any arg)
{
	SocketAuthenticate();
}

public int OnSocketReceive(Handle socket, const char[] receiveData, int dataSize, any arg)
{
	Handle dJson = json_load(receiveData);
	
	if (dJson == INVALID_HANDLE)
	{
		PrintToServer("Failed to parse JSON data");
		return;
	}
	
	Handle hKey;
	Handle hValue;
		
	//Success Object
	hKey = json_object_iter(dJson);
	hValue = json_object_iter_value(hKey);
	
	//True or false literal
	bool Success = (json_is_true(hValue) ? true : false);
	
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
		
		//Response Object
		
		hKey = json_object_iter_next(dJson, hKey);
		hValue = json_object_iter_value(hKey);
			
		Handle hErrObj = json_object_iter(hValue);
		Handle hErrStr = json_object_iter_value(hErrObj);
			
		if (json_typeof(hErrStr) == JSON_STRING)
		{
			json_string_value(hErrStr, sError, sizeof sError);
			PrintToServer("Failed to authenticate: %s", sError);
		}
		
		//Stringify_json_type(json_typeof(hErrStr), keyChar, sizeof keyChar);
		
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
	
	char Origin[128], Origin_Type[64], Author[64], Author_ID[64], Message[256];
	
	json_object_get_string(dJson, "origin", Origin, sizeof Origin);
	json_object_get_string(dJson, "origin_type", Origin_Type, sizeof Origin_Type);
	json_object_get_string(dJson, "author", Author, sizeof Author);
	json_object_get_string(dJson, "author_id", Author_ID, sizeof Author_ID);
	json_object_get_string(dJson, "message", Message, sizeof Message);
	
	CPrintToChatAll("{lightseagreen}[{navy}%s{lightseagreen}] {peru}%s {white}: {orchid}%s", Origin_Type, Author, Message);
	//PrintToServer("%s : %s : %s : %s", Origin, Origin_Type, Author, Message);
}

public int OnSocketDisconnected(Handle socket, any arg)
{
	CloseHandle(socket);
	
	PrintToServer("Socket disconnected");
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if (!Authenticated)
		return;
		
	Handle mJson = json_object();
	Handle mdJson = json_object();
	
	char Client_Name[64], Client_SteamID64[64], Json_Buffer[1024];
	
	GetClientName(client, Client_Name, sizeof Client_Name);
	GetClientAuthId(client, AuthId_SteamID64, Client_SteamID64, sizeof Client_SteamID64);
	
	json_object_set_new(mJson, "type", json_string("message"));
	
	json_object_set_new(mdJson, "origin", json_string(Hostname));
	json_object_set_new(mdJson, "origin_type", json_string("game"));
	json_object_set_new(mdJson, "author", json_string(Client_Name));
	json_object_set_new(mdJson, "author_id", json_string(Client_SteamID64));
	json_object_set_new(mdJson, "message", json_string(sArgs));
	
	json_object_set_new(mJson, "data", mdJson);
	
	json_dump(mJson, Json_Buffer, sizeof Json_Buffer, 0);
	
	SocketSend(Socket, Json_Buffer);
}

void SocketAuthenticate()
{
	Handle aJson = json_object();
	Handle adJson = json_object();
	char Json_Buffer[512];
	
	json_object_set_new(aJson, "type", json_string("authentication"));
	json_object_set_new(aJson, "channel", json_integer(Channel));
	
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
	
	for (int i = 0; i < Total_Bindings; i++)
		json_array_append(bdbJson, json_integer(Bindings[i]));
		
	json_object_set_new(bdJson, "bindings", bdbJson);
	
	json_object_set_new(bJson, "data", bdJson);
	
	json_dump(bJson, Json_Buffer, sizeof Json_Buffer, 0);
		
	SocketSend(Socket, Json_Buffer);
}