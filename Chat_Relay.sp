#pragma semicolon 1

#define PLUGIN_AUTHOR "Fishy"
#define PLUGIN_VERSION "0.0.2"

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
	
	CreateConVar("sm_chat_relay_version", PLUGIN_VERSION, "Chat Relay Version", FCVAR_REPLICATED | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);
	
	cHost = CreateConVar("cr_host", "127.0.0.1", "Relay Server Host", FCVAR_NONE);
	cHost.GetString(Host, sizeof Host);
	
	cPort = CreateConVar("cr_port", "8080", "Relay Server Port", FCVAR_NONE);
	Port = cPort.IntValue;
	
	cToken = CreateConVar("cr_token", "fishy", "Relay Server Token", FCVAR_PROTECTED);
	cToken.GetString(Token, sizeof Token);
	
	cChannel = CreateConVar("cr_channel", "1", "Channel to send the message on", FCVAR_NONE);
	Channel = cChannel.IntValue;
	
	cBindings = CreateConVar("cr_bindings", "", "Channel(s) to listen for messages on", FCVAR_NONE); //Empty = All Channels
	cBindings.GetString(sBindings, sizeof sBindings);
	Total_Bindings = ExplodeString(sBindings, ",", pBindings, sizeof pBindings, sizeof pBindings[]);
	for (int i = 0; i < Total_Bindings; i++)
		Bindings[i] = StringToInt(pBindings[i]);
	
	AutoExecConfig(true, "Chat_Relay");
	
	Socket = SocketCreate(SOCKET_TCP, OnSocketError);
	SocketSetOption(Socket, SocketReuseAddr, 1);
	SocketSetOption(Socket, SocketKeepAlive, 1);
	ConnectRelay();
}

void ConnectRelay()
{
	if (!SocketIsConnected(Socket))
		SocketConnect(Socket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, Host, Port);
	else
		PrintToServer("Socket is already connected?");
}

public Action Timer_Reconnect(Handle timer)
{
	ConnectRelay();
}

void ResetSocketData()
{
	Authenticated = false;
	Binded = false;
}

void StartReconnectTimer()
{
	SocketDisconnect(Socket);
	CreateTimer(10.0, Timer_Reconnect);
}

public int OnSocketDisconnected(Handle socket, any arg)
{	
	StartReconnectTimer();
	
	PrintToServer("Socket disconnected");
}

public int OnSocketError(Handle socket, int errorType, int errorNum, any ary)
{
	StartReconnectTimer();
	
	LogError("Socket error %i (errno %i)", errorType, errorNum);
}

public int OnSocketConnected(Handle socket, any arg)
{
	PrintToServer("Successfully Connected");
	ResetSocketData();
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
	
	char Type[64];
			
	//True or false literal
	bool Success = json_object_get_bool(dJson, "success");
	
	json_object_get_string(dJson, "type", Type, sizeof Type);
	
	if (strcmp(Type, "authentication") == 0 && !Authenticated)
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
		
		Handle hErrObj = json_object_get(dJson, "response");
		
		json_object_get_string(hErrObj, "error", sError, sizeof sError);
		PrintToServer("Failed to authenticate: %s", sError);
		
		//Stringify_json_type(json_typeof(hErrStr), keyChar, sizeof keyChar);
		
		return;
	}
	
	if (strcmp(Type, "bindings") == 0 && !Binded)
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
	
	if (strcmp(Type, "message") == 0 && Success)
	{
		char Origin[128], Origin_Type[64], Author[64], Author_ID[64], Message[256];
	
		Handle mObj = json_object_get(dJson, "response");
		
		//int MSG_Channel = json_object_get_int(dJson, "channel");
		json_object_get_string(mObj, "origin", Origin, sizeof Origin);
		json_object_get_string(mObj, "origin_type", Origin_Type, sizeof Origin_Type);
		json_object_get_string(mObj, "author", Author, sizeof Author);
		json_object_get_string(mObj, "author_id", Author_ID, sizeof Author_ID);
		json_object_get_string(mObj, "message", Message, sizeof Message);
	
		CPrintToChatAll("{lightseagreen}[{navy}%s{lightseagreen}] {peru}%s {white}: {orchid}%s", Origin_Type, Author, Message);
		//PrintToServer("%s : %s : %s : %s", Origin, Origin_Type, Author, Message);
	}
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if (!Authenticated || !Client_IsValid(client))
		return;
		
	Handle mJson = json_object();
	Handle mdJson = json_object();
	
	char Client_Name[64], Client_SteamID64[64], Json_Buffer[1024];
	
	GetClientName(client, Client_Name, sizeof Client_Name);
	GetClientAuthId(client, AuthId_SteamID64, Client_SteamID64, sizeof Client_SteamID64);
	
	json_object_set_new(mJson, "type", json_string("message"));
	
	json_object_set_new(mdJson, "channel", json_integer(Channel));
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
	if (!SocketIsConnected(Socket))
		return;
	
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
	if (!SocketIsConnected(Socket))
		return;
		
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

stock bool Client_IsValid(int iClient, bool bAlive = false)
{
	if (iClient >= 1 &&
	iClient <= MaxClients &&
	IsClientConnected(iClient) &&
	IsClientInGame(iClient) &&
	!IsFakeClient(iClient) &&
	(bAlive == false || IsPlayerAlive(iClient)))
	{
		return true;
	}

	return false;
}