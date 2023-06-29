#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>
#include <dhooks_gameconf_shim>

#define COLLISION_NORMAL 5
#define COLLISION_PASS 2

#define ITEM_QUALITY_UNUSUAL 5
#define ITEM_QUALITY_STRANGE 11

int g_iSentries[MAXPLAYERS + 1] = { -1, ... };
char g_szOrgName[MAXPLAYERS + 1][64];
ConVar g_CVarRename;
ConVar g_CVarHealth;
ConVar g_CVarHealth1;
ConVar g_CVarHealth2;
ConVar g_CVarHealth3;

public Plugin myinfo =
{
	name = "Playable Sentry",
	author = "Bloomstorm",
	description = "Allow admins to play as Sentry",
	version = "1.0",
	url = "https://idle.msk.ru/"
};

public void OnPluginStart()
{
	Handle hGameConf = LoadGameConfigFile("bm.playable_sentry");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata playable_sentry");
	} else if (!ReadDHooksDefinitions("bm.playable_sentry")) {
		SetFailState("Failed to read DHooks playable_sentry");
	}
	
	// using SentryThink to hide laser and shield
	Handle dtSentryFire = GetDHooksDefinition(hGameConf, "CObjectSentrygun::SentryThink()");
	DHookEnableDetour(dtSentryFire, false, OnSentryGunThinkPre);
	DHookEnableDetour(dtSentryFire, true, OnSentryGunThinkPost);
	
	// TODO: combine in one command
	RegAdminCmd("sm_playable_sentry", Cmd_PlayAsSentry, ADMFLAG_BAN);
	RegAdminCmd("sm_playable_sentry_target", Cmd_PlayAsSentry2, ADMFLAG_CHEATS);
	
	g_CVarRename = CreateConVar("sm_playable_sentry_rename", "0", "Should rename player to mimi-sentry?", _, true, 0.0, true, 1.0);
	g_CVarHealth = CreateConVar("sm_playable_sentry_health", "100", "Mini-sentry health", _, true, 100.0, true, 10000.0);
	g_CVarHealth1 = CreateConVar("sm_playable_sentry_health_lvl1", "150", "Sentry level 1 health", _, true, 100.0, true, 10000.0);
	g_CVarHealth2 = CreateConVar("sm_playable_sentry_health_lvl2", "180", "Sentry level 2 health", _, true, 100.0, true, 10000.0);
	g_CVarHealth3 = CreateConVar("sm_playable_sentry_health_lvl3", "216", "Sentry level 3 health", _, true, 100.0, true, 10000.0);
	
	HookEvent("post_inventory_application", Hook_PostInventoryApplication);
	HookEvent("object_destroyed", Hook_ObjectDestroyed, EventHookMode_Pre);
	HookEvent("object_removed", Hook_ObjectDestroyed, EventHookMode_Pre);
	HookEvent("player_death", Hook_PlayerDeath, EventHookMode_Post);
	
	for (int i = 0; i < MaxClients; i++)
		g_szOrgName[i][0] = '\0';
}

MRESReturn OnSentryGunThinkPre(int sentry) {
	
	//int iOwner = GetEntPropEnt(sentry, Prop_Send, "m_hBuilder");
	return MRES_Ignored;
}

// using SentryThink post to 100% hide laser (m_bPlayerControlled) and shield (m_nShieldLevel)
// there is OnLaserDotTransmit for just-in-case
// ---------------------------------
// используем SentryThink чтобы 100% спрятать лазер (m_bPlayerControlled) и щит (m_nShieldLevel)
// еще есть OnLaserDotTransmit навсякий случай
MRESReturn OnSentryGunThinkPost(int sentry) {
	int iOwner = GetEntPropEnt(sentry, Prop_Send, "m_hBuilder");
	//int iTest = GetEntProp(sentry, Prop_Send, "m_bPlayerControlled");
	//int iTest2 = GetEntProp(sentry, Prop_Send, "m_nShieldLevel");
	//PrintToChatAll("OnSentryGunThinkPost owner %i %i %i", iOwner, iTest, iTest2);
	if (iOwner > 0 && iOwner <= MaxClients)
	{
		if (EntRefToEntIndex(g_iSentries[iOwner]) == sentry)
		{
			SetEntProp(sentry, Prop_Send, "m_bPlayerControlled", 0);
			SetEntProp(sentry, Prop_Send, "m_nShieldLevel", 0);
		}
	}
	return MRES_Ignored;
}

public Action Hook_ObjectDestroyed(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client)
	{
		int iSentry = EntRefToEntIndex(g_iSentries[client]);
		if (iSentry != -1)
		{
			ForcePlayerSuicide(client);
		}
	}
	return Plugin_Continue;
}

public Action Hook_PostInventoryApplication(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int iSentry = EntRefToEntIndex(g_iSentries[client]);
	if (iSentry > 0)
	{
		// first we create 'explode' effect, if sentry's health > 99999 then we kill it without 'explode' effect
		// ------------------
		// сначало мы создаем эффект взрыва, если хп турели больше 99999, то мы убиваем ее без эффекта взрыва
		SetVariantInt(99999);
		AcceptEntityInput(iSentry, "RemoveHealth");
		AcceptEntityInput(iSentry, "Kill");
		g_iSentries[client] = -1;
		
		int iFlags = GetEntityFlags(client)&~FL_NOTARGET;
		SetEntityFlags(client, iFlags);
		SetEntityRenderMode(client, RENDER_NORMAL);
		SetEntProp(client, Prop_Send, "m_CollisionGroup", COLLISION_NORMAL);
		
		// doesnt unhook for some reason, so we unhook it in Hook_PlayerDeath to 100% make sure it's gone, added just-in-case
		// ------------------
		// почему то не отвязывается, поэтому отвязываем в Hook_PlayerDeath, добавлено навсякий случай
		SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
		
		RestoreHats(client);
		
		if (g_CVarRename.BoolValue && g_szOrgName[client][0] != '\0')
		{
			char szName[64];
			GetClientName(client, szName, sizeof(szName));
			SilentChangeName(client, g_szOrgName[client]);
			g_szOrgName[client][0] = '\0';
		}
	}
	return Plugin_Continue;
}

public Action Hook_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (IsValidEntity(client) && EntRefToEntIndex(g_iSentries[client]) > 0)
	{
		SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
		CreateTimer(0.1, Timer_KillRagdoll, event.GetInt("userid"), TIMER_FLAG_NO_MAPCHANGE);
	}
	return Plugin_Continue;
}

public Action Timer_KillRagdoll(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (client > 0)
	{
		int iRagdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if (iRagdoll > 0)
		{
			AcceptEntityInput(iRagdoll, "Kill");
		}
	}
	return Plugin_Stop;
}

public Action Cmd_PlayAsSentry(int client, int args)
{
	int iGunslinger = GetPlayerWeaponSlot(client, 2);
	if (iGunslinger != -1)
	{
		int iGunslingerId = GetEntProp(iGunslinger, Prop_Send, "m_iItemDefinitionIndex");
		if (iGunslingerId == 142)
		{
			ReplyToCommand(client, "Unequip gunslinger");
			return Plugin_Handled;
		}
	}
	if (!IsPlayerAlive(client))
	{
		ReplyToCommand(client, "Only alive");
		return Plugin_Handled;
	}
	if (GetClientTeam(client) != 3 && GetClientTeam(client) != 2)
	{
		ReplyToCommand(client, "Spectator cant do it");
		return Plugin_Handled;
	}
	if (EntRefToEntIndex(g_iSentries[client]) != -1)
	{
		ReplyToCommand(client, "Only 1 playable sentry");
		return Plugin_Handled;
	}
	char szArg[32];
	if (args < 1)
	{
		szArg = "0";
	}
	else
	{
		GetCmdArg(1, szArg, sizeof(szArg));
	}
	int iLevel = StringToInt(szArg);
	if (iLevel < 0)
		iLevel = 0;
	if (iLevel > 3)
		iLevel = 3;
	
	int iRagdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
	if (iRagdoll > MaxClients && IsValidEntity(iRagdoll))
	{
		AcceptEntityInput(iRagdoll, "Kill");
	}
	
	SetEntityMoveType(client, MOVETYPE_NONE);
	
	SetEntProp(client, Prop_Send, "m_CollisionGroup", COLLISION_PASS);
	int iFlags = GetEntityFlags(client)|FL_NOTARGET;
	SetEntityFlags(client, iFlags);
	
	SetEntityRenderMode(client, RENDER_TRANSCOLOR);    
	SetEntityRenderColor(client, 255, 255, 255, 0);
	
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	
	g_iSentries[client] = EntIndexToEntRef(CreateSentry(client, iLevel));
	
	if (g_CVarRename.BoolValue && iLevel == 0)
	{
		char szName[64];
		GetClientName(client, szName, sizeof(szName));
		g_szOrgName[client] = szName;
		SilentChangeName(client, "mimi sentry");
	}
	return Plugin_Handled;
}

public Action Cmd_PlayAsSentry2(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "sm_playable_sentry_target <target> <level>");
		return Plugin_Handled;
	}
	char szArg1[32];
	char szArg2[32];
	char szTargetName[64];
	int iTargetList[MAXPLAYERS];
	int iTargetCount;
	bool bTnIsMl;
	
	GetCmdArg(1, szArg1, sizeof(szArg1));
	GetCmdArg(2, szArg2, sizeof(szArg2));
	
	int iLevel = StringToInt(szArg2);
	if (iLevel < 0)
		iLevel = 0;
	if (iLevel > 3)
		iLevel = 3;
	
	if ((iTargetCount = ProcessTargetString(szArg1, client, iTargetList, MAXPLAYERS, COMMAND_FILTER_ALIVE|(args < 1 ? COMMAND_FILTER_NO_IMMUNITY : 0),
	szTargetName,
	sizeof(szTargetName),
	bTnIsMl)) <= 0)
	{
		ReplyToCommand(client, "[SM] Invalid");
		return Plugin_Handled;
	}
	for (int i = 0; i < iTargetCount; i++)
	{
		if (EntRefToEntIndex(g_iSentries[iTargetList[i]] <= 0))
		{
			int iGunslinger = GetPlayerWeaponSlot(client, 2);
			if (iGunslinger != -1)
			{
				int iGunslingerId = GetEntProp(iGunslinger, Prop_Send, "m_iItemDefinitionIndex");
				if (iGunslingerId == 142)
				{
					continue;
				}
			}
			int iRagdoll = GetEntPropEnt(iTargetList[i], Prop_Send, "m_hRagdoll");
			if (iRagdoll > MaxClients && IsValidEntity(iRagdoll))
			{
				AcceptEntityInput(iRagdoll, "Kill");
			}
			
			SetEntityMoveType(iTargetList[i], MOVETYPE_NONE);
			
			SetEntProp(iTargetList[i], Prop_Send, "m_CollisionGroup", COLLISION_PASS);
			int iFlags = GetEntityFlags(iTargetList[i])|FL_NOTARGET;
			SetEntityFlags(iTargetList[i], iFlags);
			
			SetEntityRenderMode(iTargetList[i], RENDER_TRANSCOLOR);    
			SetEntityRenderColor(iTargetList[i], 255, 255, 255, 0);
			
			SDKHook(iTargetList[i], SDKHook_OnTakeDamage, OnTakeDamage);
			
			g_iSentries[iTargetList[i]] = EntIndexToEntRef(CreateSentry(iTargetList[i], iLevel));
			
			if (g_CVarRename.BoolValue && iLevel == 0)
			{
				//char szName[64];
				//GetClientName(iTargetList[i], szName, sizeof(szName));
				//g_szOrgName[client] = szName;
				//SilentChangeName(client, "mimi sentry");
			}
		}
	}
	ReplyToCommand(client, "Made %s sentry", szTargetName);
	return Plugin_Handled;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "env_laserdot"))
		SDKHook(entity, SDKHook_SpawnPost, LaserSpawnPost);
}

// only way to damage player is damaging sentry, so spys and snipers cant takedown the owner
// --------------
// чтобы навредить игроку, надо стрелять в турель, таким образом шпионы и снайперы не убьют овнера
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if (victim == attacker)
	{
		damage = 0.0;
		return Plugin_Changed;
	}
	if (!IsValidClient(victim))
		return Plugin_Continue;
	int iSentry = EntRefToEntIndex(g_iSentries[victim]);
	if (iSentry > 0)
	{
		damage = 0.0;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public Action LaserSpawnPost(int entity)
{
	RequestFrame(LaserSpawnPostPost, entity);
	return Plugin_Continue;
}

public void LaserSpawnPostPost(int entity)
{
	if (IsValidEntity(entity))
	{
		int client = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		if (client > 0 && client <= MaxClients && IsClientInGame(client))
		{
			SDKHook(entity, SDKHook_SetTransmit, OnLaserDotTransmit);
		}
	}
}

// for some reason, on specific clients it doesnt hide laser and shield, so we use SentryThink to 100% hide it, OnLaserDotTransmit for just-in-case
// --------------
// по каким то причинам, на некоторых клиентах это не прячет лазер и щит, поэтому используем SentryThink чтобы 100% убедиться что оно скрыто, добавил OnLaserDotTransmit навсякий случай
public Action OnLaserDotTransmit(int entity, int client)
{
	int iSentry = EntRefToEntIndex(g_iSentries[client]);
	if (iSentry != -1)
	{
		SetEntProp(iSentry, Prop_Send, "m_nShieldLevel", 0);
		SetEntProp(iSentry, Prop_Send, "m_bPlayerControlled", 0);
	}
	return Plugin_Continue;
}

int CreateSentry(int client, int level = 0)
{
	float vecClientPos[3], vecClientPosEdit[3], vecClientAngles[3];
	GetClientAbsOrigin(client, vecClientPos);
	GetClientEyeAngles(client, vecClientAngles);
	
	vecClientAngles[0] = 0.0;
	vecClientAngles[2] = 0.0;
	
	vecClientPosEdit = vecClientPos;
	vecClientPosEdit[2] += 30.0;
	
	TeleportEntity(client, vecClientPosEdit, NULL_VECTOR, NULL_VECTOR);
	
	int iMiniSentry = CreateEntityByName("obj_sentrygun");
	AcceptEntityInput(iMiniSentry, "SetBuilder", client);
	DispatchKeyValueVector(iMiniSentry, "origin", vecClientPos);
	DispatchKeyValueVector(iMiniSentry, "angles", vecClientAngles);
	
	// We need to hide the shadows because of big radius sphere
	// ------------
	// Нам нужно скрыть тени из за модели большого шара, обозначающее радиус
	DispatchKeyValue(iMiniSentry, "shadowcastdist", "0");
	DispatchKeyValue(iMiniSentry, "disablereceiveshadows", "1");
	DispatchKeyValue(iMiniSentry, "disableshadows", "1");
	DispatchKeyValue(iMiniSentry, "disableshadowdepth", "1");
	DispatchKeyValue(iMiniSentry, "disableselfshadowing", "1"); 
	
	if (level == 0)
	{
		SetEntProp(iMiniSentry, Prop_Send, "m_bMiniBuilding", 1);
		SetEntProp(iMiniSentry, Prop_Send, "m_iUpgradeLevel", 1);
		SetEntProp(iMiniSentry, Prop_Send, "m_iHighestUpgradeLevel", 1);
	}
	else
	{
		SetEntProp(iMiniSentry, Prop_Send, "m_iUpgradeLevel", level);
		SetEntProp(iMiniSentry, Prop_Send, "m_iHighestUpgradeLevel", level);
	}
	SetEntProp(iMiniSentry, Prop_Data, "m_spawnflags", 4);
	SetEntProp(iMiniSentry, Prop_Send, "m_bBuilding", 1);
	SetEntProp(iMiniSentry, Prop_Send, "m_nSkin", level == 0 ? GetClientTeam(client) : GetClientTeam(client) - 2);
	DispatchSpawn(iMiniSentry);
	
	switch (level)
	{
		case 0:
		{
			SetVariantInt(g_CVarHealth.IntValue);
			AcceptEntityInput(iMiniSentry, "SetHealth");
		}
		case 1:
		{
			SetVariantInt(g_CVarHealth1.IntValue);
			AcceptEntityInput(iMiniSentry, "SetHealth");
		}
		case 2:
		{
			SetVariantInt(g_CVarHealth2.IntValue);
			AcceptEntityInput(iMiniSentry, "SetHealth");
		}
		case 3:
		{
			SetVariantInt(g_CVarHealth3.IntValue);
			AcceptEntityInput(iMiniSentry, "SetHealth");
		}
	}
	
	if (level == 0)
		SetEntPropFloat(iMiniSentry, Prop_Send, "m_flModelScale", 0.75);
	
	for (int i = 0; i < 4; i++)
	{
		TF2_RemoveWeaponSlot(client, i);
	}
	int iWeapon = CreateWeaponItem(client, 30668, 1, "tf_weapon_laser_pointer");
	SetEntityRenderMode(iWeapon, RENDER_TRANSCOLOR);
	SetEntityRenderColor(iWeapon, 255, 255, 255, 0);
	HideWearables(client);
	return iMiniSentry;
}

public int CreateWeaponItem(int client, int itemindex, int weaponSlot, const char[] className) 
{ 
    int iNewEnt = CreateEntityByName(className); 
    if (!IsValidEntity(iNewEnt)) 
        return -1; 
     
    char szNetClass[64]; 
    GetEntityNetClass(iNewEnt, szNetClass, sizeof(szNetClass)); 
    SetEntData(iNewEnt, FindSendPropInfo(szNetClass, "m_iItemDefinitionIndex"), itemindex); 
    SetEntData(iNewEnt, FindSendPropInfo(szNetClass, "m_bInitialized"), 1); 
    SetEntData(iNewEnt, FindSendPropInfo(szNetClass, "m_iEntityLevel"), 1); 
    SetEntData(iNewEnt, FindSendPropInfo(szNetClass, "m_iEntityQuality"), 5); 
    SetEntProp(iNewEnt, Prop_Send, "m_bValidatedAttachedEntity", 1); 
    SetEntProp(iNewEnt, Prop_Send, "m_iAccountID", GetSteamAccountID(client)); 
    SetEntPropEnt(iNewEnt, Prop_Send, "m_hOwnerEntity", client); 
    DispatchSpawn(iNewEnt); 
    TF2_RemoveWeaponSlot(client, weaponSlot); 
    EquipPlayerWeapon(client, iNewEnt); 
    return iNewEnt; 
}

void HideWearables(int client)
{
	int iEnt = -1;
	while ((iEnt = FindEntityByClassname(iEnt, "tf_wearable")) != INVALID_ENT_REFERENCE)
	{
		if (GetEntPropEnt(iEnt, Prop_Send, "m_hOwnerEntity") == client)
		{
			int iQuality = GetEntProp(iEnt, Prop_Send, "m_iEntityQuality");
			// if hat is strange, let players gain 'kill' points, otherwise kill it
			// если шапка стренжовая, то даем игрокам возможность набивать очки, если нет то убиваем
			if (iQuality == ITEM_QUALITY_STRANGE)
			{
				SetEntityRenderMode(iEnt, RENDER_TRANSCOLOR);
				SetEntityRenderColor(iEnt, 255, 255, 255, 0);
			}
			else
			{
				AcceptEntityInput(iEnt, "Kill");
			}
		}
	}
}

void RestoreHats(int client)
{
	int iEnt = -1;
	while ((iEnt = FindEntityByClassname(iEnt, "tf_wearable")) != INVALID_ENT_REFERENCE)
	{
		if (GetEntPropEnt(iEnt, Prop_Send, "m_hOwnerEntity") == client)
		{
			// restore wearables with strange quality
			// восстанавливаем шляпы со стренжом
			SetEntityRenderMode(iEnt, RENDER_TRANSCOLOR);
			SetEntityRenderColor(iEnt, 255, 255, 255, 255);
		}
	}
}

bool IsValidClient(int client)
{
	if (client <= 0 || client > 32)
		return false;
	return IsClientInGame(client);
}

void SilentChangeName(int client, const char[] name)
{
	SetClientInfo(client, "name", name);
	SetEntPropString(client, Prop_Data, "m_szNetname", name);
}