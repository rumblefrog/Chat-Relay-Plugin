#pragma semicolon 1

#define PLUGIN_AUTHOR "Fishy"
#define PLUGIN_VERSION "1.0.1"

#include <sourcemod>
#include <socket>
#include <smjansson>
#include <morecolors>

#pragma newdecls required

Handle Socket;

bool Verbose;

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
	CreateConVar("sm_chat_relay_version", PLUGIN_VERSION, "Chat Relay Version", FCVAR_REPLICATED | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);
	
	cHost = CreateConVar("cr_host", "127.0.0.1", "Relay Server Host", FCVAR_NONE);
	
	cPort = CreateConVar("cr_port", "8080", "Relay Server Port", FCVAR_NONE);
	
	cToken = CreateConVar("cr_token", "fishy", "Relay Server Token", FCVAR_PROTECTED);
	
	cChannel = CreateConVar("cr_channel", "1", "Channel to send the message on", FCVAR_NONE);
	
	cBindings = CreateConVar("cr_bindings", "", "Channel(s) to listen for messages on", FCVAR_NONE); //Empty = None
	
	AutoExecConfig(true, "Chat_Relay");
	
	RegAdminCmd("sm_cr_verbose", CmdVerbose, ADMFLAG_ROOT);
	
	Socket = SocketCreate(SOCKET_TCP, OnSocketError);
	SocketSetOption(Socket, SocketReuseAddr, 1);
	SocketSetOption(Socket, SocketKeepAlive, 1);
	SocketSetOption(Socket, ConcatenateCallbacks, 1);
}

public Action CmdVerbose(int client, int args)
{
	if (Verbose)
		PrintToChat(client, "Disabled Verbose");
	else
		PrintToChat(client, "Enabled Verbose");
		
	Verbose = !Verbose;
	
	return Plugin_Handled;
}

public void OnConfigsExecuted()
{
	GetConVarString(FindConVar("hostname"), Hostname, sizeof Hostname);

	cHost.GetString(Host, sizeof Host);
	
	Port = cPort.IntValue;
	
	cToken.GetString(Token, sizeof Token);
	
	Channel = cChannel.IntValue;
	
	cBindings.GetString(sBindings, sizeof sBindings);
	Total_Bindings = ExplodeString(sBindings, ",", pBindings, sizeof pBindings, sizeof pBindings[]);
	for (int i = 0; i < Total_Bindings; i++)
		Bindings[i] = StringToInt(pBindings[i]);
	
	if (!SocketIsConnected(Socket))
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
}

public int OnSocketReceive(Handle socket, const char[] receiveData, int dataSize, any arg)
{
	if (Verbose)
		PrintToServer("%s", receiveData);
		
	char JSONs[10][512];
	
	int JSON_Count = ExplodeString(receiveData, "\\n", JSONs, sizeof JSONs, sizeof JSONs[]);
	
	for (int i = 0; i < JSON_Count; i++)
	{
		Handle dJson = json_load(JSONs[i]);
	
		if (dJson == INVALID_HANDLE)
		{
			PrintToServer("Failed to parse JSON data");
			return;
		}
	
		char Type[64];
			
		//True or false literal
		bool Success = json_object_get_bool(dJson, "success");
	
		json_object_get_string(dJson, "type", Type, sizeof Type);
	
		if (strcmp(Type, "message") == 0)
		{
			if (!Success) return;
		
			Handle mObj = json_object_get(dJson, "response");
		
			int MSG_Channel = json_object_get_int(mObj, "channel");
		
			if (!IsListening(MSG_Channel))
				return;
		
			char Origin[128], Origin_Type[64], Author[64], Author_ID[64], Message[256];
		
			json_object_get_string(mObj, "origin", Origin, sizeof Origin);
			json_object_get_string(mObj, "origin_type", Origin_Type, sizeof Origin_Type);
			json_object_get_string(mObj, "author", Author, sizeof Author);
			json_object_get_string(mObj, "author_id", Author_ID, sizeof Author_ID);
			json_object_get_string(mObj, "message", Message, sizeof Message);
	
			CPrintToChatAll("{lightseagreen}[{navy}%s{lightseagreen}] {peru}%s {white}: {orchid}%s", Origin_Type, Author, Message);
			//PrintToServer("%s : %s : %s : %s", Origin, Origin_Type, Author, Message);
		}
	}
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if (!Client_IsValid(client))
		return;
		
	if (!SocketIsConnected(Socket))
		return;
		
	Handle mJson = json_object();
	Handle mdJson = json_object();
	
	char Client_Name[64], Client_SteamID64[64], Json_Buffer[1024];
	
	GetClientName(client, Client_Name, sizeof Client_Name);
	GetClientAuthId(client, AuthId_SteamID64, Client_SteamID64, sizeof Client_SteamID64);
	
	json_object_set_new(mJson, "type", json_string("message"));
	json_object_set_new(mJson, "token", json_string(Token));
	
	json_object_set_new(mdJson, "channel", json_integer(Channel));
	json_object_set_new(mdJson, "origin", json_string(Hostname));
	json_object_set_new(mdJson, "origin_type", json_string("game"));
	json_object_set_new(mdJson, "author", json_string(Client_Name));
	json_object_set_new(mdJson, "author_id", json_string(Client_SteamID64));
	json_object_set_new(mdJson, "message", json_string(sArgs));
	
	json_object_set_new(mJson, "data", mdJson);
	
	json_dump(mJson, Json_Buffer, sizeof Json_Buffer, 0);
	
	if (Verbose)
		PrintToServer("%s", Json_Buffer);
	
	SocketSend(Socket, Json_Buffer);
}

bool IsListening(int channel)
{
	for (int i = 0; i < Total_Bindings; i++)
		if (Bindings[i] == channel)
			return true;
			
	return false;
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