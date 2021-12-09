/*
* +RLBlocker
* by: DENFER © 2021
*
* This program is free software; you can redistribute it and/or modify it under
* the terms of the GNU General Public License, version 3.0, as published by the
* Free Software Foundation.
* 
* This program is distributed in the hope that it will be useful, but WITHOUT
* ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
* FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
* details.
*
* You should have received a copy of the GNU General Public License along with
* this program. If not, see <http://www.gnu.org/licenses/>.
*/

// Main Include
#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>

// Сustom Include
#include <colors>           
#include <autoexecconfig>   

// Plugin Define
#define PLUGIN_VERSION              "1.0 Beta"
#define PLUGIN_AUTHOR 	            "DENFER"

#define MAX_ATTEMPTS                5
#define MAX_ANGLES                  120.0
#define RL_TIME                     0.8

// Compilation options 
#pragma newdecls required
#pragma semicolon 1

// Handles 
Handle  g_hTimerAFK,
        g_hTimerRL[MAXPLAYERS + 1],
        g_hTimerTest[2]; // два таймера, которые никак не влиют на игровой процес, нужны только для дебага и сборы информации.

// ConVars
ConVar  gc_sPrefix,
        gc_flCheckIntervalAFK,
        gc_iTypeOfPunishment,
        gc_iBanTime,
        gc_bWarmupPeriod;

// Strings
char g_sPrefix[64];

// Floats
float   g_fPreviousEyeAngles[MAXPLAYERS + 1][3],
        g_fCurrentEyeAngles[MAXPLAYERS + 1][3],
        g_fDifferenceEyeAngles[MAXPLAYERS + 1][3],
        g_fPreviousCoordinates[MAXPLAYERS + 1][3],
        g_fCurrentCoordinates[MAXPLAYERS + 1][3];

// Integers 
int     g_iAttempts[MAXPLAYERS + 1]; 

// Booleans
// TODO: Удалить тестовую переменную g_bIsTest после официального релиза
bool    g_bIsTest[MAXPLAYERS + 1]; // переменная для теста


// Informations
public Plugin myinfo = {
	name = "+RLBlocker",
	author = "DENFER (for all questions - https://vk.com/fedorinovea)",
	description = "Dealing with +right and +left it just got easier ;)",
	version = PLUGIN_VERSION,
};

public void OnPluginStart() {	
	// Translation 
    LoadTranslations("RLBlocker.phrases");

    // AutoExecConfig
    AutoExecConfig_SetCreateFile(true);
    AutoExecConfig_SetFile("RLBlock", PLUGIN_AUTHOR);

    // Console Commands
    RegAdminCmd("sm_rl", CallBack_RLCreateLogs, ADMFLAG_ROOT);

    // ConVars
    gc_sPrefix =            AutoExecConfig_CreateConVar("sm_rl_prefix", "[SM]", "Префикс перед сообщениями плагина.");
    gc_flCheckIntervalAFK = AutoExecConfig_CreateConVar("sm_rl_check_interval", "5.0", "Интервал между проверками на АФК и соответственно на то, что крутится игрок или нет (указывать в секундах).", 0, true, 0.1, false);
    gc_iTypeOfPunishment =  AutoExecConfig_CreateConVar("sm_rl_type_of_punushment", "1", "Тип наказания за багаюзерство (Багаюз - использование ошибок игры) (1 - убивать игрока, 2 - переводить игрока в спектаторы, 3 - кикать с сервера, 4 - банить игрока на определенный промежуток времени, можно будет указать в sm_rl_ban_time).", 0, true, 1.0, true, 4.0);
    gc_iBanTime =          AutoExecConfig_CreateConVar("sm_rl_ban_time", "300", "Время бана в секундах, при условие, что sm_rl_type_of_punushment = 4.", 0, true, 0.0, false);
    gc_bWarmupPeriod =      AutoExecConfig_CreateConVar("sm_rl_warmup_period", "0", "Проверять игроков во время разминки? (0 - нет, 1 - да)", 0, true, 0.0, true, 1.0);

    // Hooks
    HookEvent("round_start", Event_OnRoundStart);
    HookEvent("player_spawn", Event_OnPlayerSpawn);

    // AutoExecConfig
    AutoExecConfig_ExecuteFile();
    AutoExecConfig_CleanFile();
}

void Event_OnRoundStart(Event event, const char[] name, bool dontBroadcast) {

    // Если не стоит првоерять на багаюз во время разминки
    if (!gc_bWarmupPeriod.BoolValue && GameRules_GetProp ("m_bWarmupPeriod")) {
        return;
    }

    if (g_hTimerAFK != null) {
        KillTimer(g_hTimerAFK);
        g_hTimerAFK = null;
    }

    g_hTimerAFK = CreateTimer(gc_flCheckIntervalAFK.FloatValue, Timer_CheckAFK, _, TIMER_REPEAT);
}

void Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast) { 
    int client = GetClientOfUserId(GetEventInt(event, "userid"));

    if (IsValidClient(client)) {
        UpdateData(client);
    }
}

public void OnConfigsExecuted() {
    gc_sPrefix.GetString(g_sPrefix, sizeof(g_sPrefix));
}

public Action Timer_CheckAFK(Handle timer) {

    for (int i = 0; i <= MaxClients; ++i) {
        if (IsValidClient(i) && IsPlayerAlive(i) && !g_bIsTest[i]) {
            // Учитыывая, что текущие координаты присваиваются при возрождение игрока, это наилучшее место для присваивания предыдущих координат
            g_fPreviousCoordinates[i] = g_fCurrentCoordinates[i];
            GetClientAbsOrigin(i, g_fCurrentCoordinates[i]);

            // Высчитываем разницу между двумя координатами игрока (новые - старые), тем самым определяем, что игрок away from keyboard
            if (!IsDifferenceBetweenCoordinates(g_fCurrentCoordinates[i], g_fPreviousCoordinates[i])) {
                // По идеи это может закрыть уже работающий таймер, но это не важно, так как сразу же будет запущен новый с сохраненными данными с прошлого
                if (g_hTimerRL[i] != null) {
                    KillTimer(g_hTimerRL[i]);
                    g_hTimerRL[i] = null;
                }

                g_hTimerRL[i] = CreateTimer(RL_TIME, Timer_CheckRL, GetClientUserId(i), TIMER_REPEAT);
            }
        }
    }

    return Plugin_Continue;
}

public Action Timer_CheckRL(Handle timer, int userid) {

    int client = GetClientOfUserId(userid);

    if (IsValidClient(client) && IsPlayerAlive(client) && !g_bIsTest[client]) {
        GetClientEyeAngles(client, g_fCurrentEyeAngles[client]);
        GetClientAbsOrigin(client, g_fCurrentCoordinates[client]);
        
        // Проверяем есть ли изменение по оси X, если изменений нет, то значит игрок либо крутится, либо не вертит камерой вовсе
        // Проверяем есть ли изменения по оси Y, если угол меняется исключительно по ней, то вероятней всего игрок крутится 
        if (IsDifferenceBetweenAngles(g_fPreviousEyeAngles[client][0], g_fCurrentEyeAngles[client][0]) || !IsDifferenceBetweenAngles(g_fPreviousEyeAngles[client][1], g_fCurrentEyeAngles[client][1]) 
        || IsDifferenceBetweenCoordinates(g_fCurrentCoordinates[client], g_fPreviousCoordinates[client])) {
            // Запоминаем текущие координаты
            for (int i = 0; i < 2; ++i) {
                g_fPreviousEyeAngles[client][i] = g_fCurrentEyeAngles[client][i];
            }

            ClearAttempts(client);
            g_hTimerRL[client] = null;
            return Plugin_Stop;
        }

        // Высчитываем разницу между двумя проверками по осям Y 
        g_fDifferenceEyeAngles[client][1] = float(RoundToNearest(g_fPreviousEyeAngles[client][1] - g_fCurrentEyeAngles[client][1])); // Y 

        if (g_fDifferenceEyeAngles[client][1] >= MAX_ANGLES && IsDeferenceSigns(client)) {
            ++g_iAttempts[client]; // условно, попытка исправиться игроку, с каждой проверкой она будет увеличиваться до MAX_ATTEMPTS, как только значение превзойдет - игроку будет выдано наказание.

            if (g_iAttempts[client] > MAX_ATTEMPTS) {
                ClearAttempts(client);
                PunishPlayer(client);
            } 
        }

        // Запоминаем текущие координаты
        for (int i = 0; i < 2; ++i) {
            g_fPreviousEyeAngles[client][i] = g_fCurrentEyeAngles[client][i];
        }

        return Plugin_Continue;
    } 

    ClearAttempts(client);
    g_hTimerRL[client] = null;
    return Plugin_Stop;
}

public bool IsDifferenceBetweenCoordinates(float vec1[3], float vec2[3]) {
    // Если зафиксировано изменение координат по ОX
    if (vec1[0] - vec2[0]) { 
        return true;
    }

    // Если зафиксировано изменение координат по ОY
    if (vec1[1] - vec2[1]) { 
        return true;
    }

    // Если зафиксировано изменение координат по ОZ
    if (vec1[2] - vec2[2]) { 
        return true;
    }

    return false;
}

public bool IsDifferenceBetweenAngles(float angles1, float angles2) {
    if (angles1 - angles2) {
        return true;
    }

    return false;
}

public bool IsDeferenceSigns(int client) {
    // -f(x) * -f(x) = f(x) * f(x) - NO OK.
    //  f(x) *  f(x) = f(x) * f(x) - NO OK.
    // -f(x) *  f(x) = - (f(x) * f(x)) - OK. 
    // f(x) *  -f(x) = - (f(x) * f(x)) - OK. 
    // Тем самым мы будем получать углы, которые практически противоположны друг другу. 
    if (g_fCurrentEyeAngles[client][1] * g_fPreviousEyeAngles[client][1] < 0) {
        return true;
    }

    return false;
}

public void PunishPlayer(int client) {
    switch (gc_iTypeOfPunishment.IntValue) {
        // Убить игрока
        case 1: {
            SlapPlayer(client, GetClientHealth(client));
            CPrint(client, "Chat_Slap", "%s %t", g_sPrefix, "Chat_Slap");
        }
        // Перевод в спектаторы
        case 2: {
            ChangeClientTeam(client, CS_TEAM_SPECTATOR);
            CPrint(client, "Chat_Changed_Team", "%s %t", g_sPrefix, "Chat_Changed_Team");
        }
        // Кикнуть с сервера
        case 3: {
            KickClient(client, "%T", "Kick_Info", LANG_SERVER);
        }
        // Забанить
        case 4: {
            char message[256], reason[256];
            // Время бана указано в секундах, для вывода в минуток делим на 60, т.к. бан выдается в минутах.
            FormatEx(message, sizeof(message), "%T", "Ban_Info", LANG_SERVER, gc_iBanTime.IntValue / 60);
            FormatEx(reason, sizeof(reason), "%T", "Ban_Reason", LANG_SERVER);
            BanClient(client, gc_iBanTime.IntValue / 60, BANFLAG_AUTO, reason, message);
        }
    }
}

public void ClearAttempts(int client) {
    g_iAttempts[client] = 0;
}

public void UpdateData(int client) {
    for (int i = 0; i < 3; ++i) {
        g_fPreviousEyeAngles[client][i] = 0.0;
    }

    for (int i = 0; i < 3; ++i) {
        g_fCurrentEyeAngles[client][i] = 0.0;
    }

    for (int i = 0; i < 3; ++i) {
        g_fDifferenceEyeAngles[client][i] = 0.0;
    }

    for (int i = 0; i < 3; ++i) {
        g_fPreviousCoordinates[client][i] = 0.0;
    }

    GetClientAbsOrigin(client, g_fCurrentCoordinates[client]);

    g_iAttempts[client] = 0;

    g_bIsTest[client] = false;
}

public bool IsValidClient(int client) {
    // В рамках данного плагина, боты не играют роли
    if (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client) && !IsClientReplay(client) && !IsClientSourceTV(client)) {
        return true;
    }

    return false;
}

/*
/ Дальше идет дебажная информация, она нужна исключительно для меня и людей, 
/ которые готовы помочь в развитие плагина. 
*/
public Action CallBack_RLCreateLogs(int client, int args) {

    g_bIsTest[client] = true;

    // Создаем путь к файлу с логами
    if (!DirExists("addons/sourcemod/logs/DENFER/RLBlocker")) {
        CreateDirectory("addons/sourcemod/logs", 511);
        CreateDirectory("addons/sourcemod/logs/DENFER", 511);
        CreateDirectory("addons/sourcemod/logs/DENFER/RLBlocker", 511);
    }

    char fileName[32], path[PLATFORM_MAX_PATH] = "addons/sourcemod/logs/DENFER/RLBlocker";

    FormatTime(fileName, sizeof(fileName), "%d.%m.%Y"); // 09.12.2021
    FormatEx(path, sizeof(path), "%s/%s.log", path, fileName); // 09.12.2021.log

    File file = OpenFile(path, "w");

    CPrint(client, _, "[DENFER]: Спасибо, что помогаете улучшить плагин - напишите в консоле {green}+right{default} или {green}+left{default}");
    CPrint(client, _, "[DENFER]: Как только проверка закончится продублируйте команды, только уже с минусом {green}-right{default} или {green}-left{default} соответственно, благодарю за помощь!");

    // Определяем игру
    char buffer[128];
    switch (GetEngineVersion()) {
        case Engine_CSGO: {
            FormatEx(buffer, sizeof(buffer), "Counter-Strike: Global Offensive");
        }
        case Engine_CSS: {
            FormatEx(buffer, sizeof(buffer), "Counter-Strike: Source");
        }
        default: {
            FormatEx(buffer, sizeof(buffer), "Other");
        }
    }
    LogToFileEx(path, buffer);
    FormatEx(buffer, sizeof(buffer), "TickRate = %f", 1.0 / GetTickInterval()); // Получаем тикрейт сервера
    LogToFileEx(path, buffer);
    LogToFileEx(path, "--------------- Проверка запущена ---------------");
    
    if (g_hTimerTest[0] != null) {
        KillTimer(g_hTimerTest[0]);
        g_hTimerTest[0] = null;
    }

    g_hTimerTest[0] = CreateTimer(90.0, Timer_Test, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

    if (g_hTimerTest[1] != null) {
        KillTimer(g_hTimerTest[1]);
        g_hTimerTest[1] = null;
    }

    g_hTimerTest[1] = CreateTimer(RL_TIME, Timer_CheckRLTest, GetClientUserId(client), TIMER_REPEAT);

    delete file;
    return Plugin_Handled;
}

public Action Timer_Test(Handle timer, int userid) {
    int client = GetClientOfUserId(userid);

    if (IsValidClient(client)) {
        g_bIsTest[client] = false;
    }

    if (g_hTimerTest[1] != null) {
        KillTimer(g_hTimerTest[1]);
        g_hTimerTest[1] = null;
    }

    char fileName[32], path[PLATFORM_MAX_PATH] = "addons/sourcemod/logs/DENFER/RLBlocker";

    FormatTime(fileName, sizeof(fileName), "%d.%m.%Y"); // 09.12.2021
    FormatEx(path, sizeof(path), "%s/%s.log", path, fileName); // 09.12.2021.log

    LogToFileEx(path, "--------------- Проверка окончена ---------------");
    LogToFileEx(path, "Данный файл содержит информацию по работе плагина на вашем сервере.");
    LogToFileEx(path, "По вашему желанию вы можете отправить файл мне: {green}vk.com/fedorinovea{default} или {green}hlmod.ru/members/denfer.126978{default}");
    CPrint(client, _, "[DENFER]: Проверка успешно закончена, загляните в {green}addons/sourcemod/logs/DENFER/RLBlocker{default} и по возможности отправьте файл мне, спасибо!");

    g_hTimerTest[0] = null;
    return Plugin_Stop;
}

public Action Timer_CheckRLTest(Handle timer, int userid) {

    int client = GetClientOfUserId(userid);

    if (IsValidClient(client) && IsPlayerAlive(client)) {
        GetClientEyeAngles(client, g_fCurrentEyeAngles[client]);
        GetClientAbsOrigin(client, g_fCurrentCoordinates[client]);

        g_fDifferenceEyeAngles[client][1] = float(RoundToNearest(g_fPreviousEyeAngles[client][1] - g_fCurrentEyeAngles[client][1]));

        // Выводим информацию 
        char fileName[32], path[PLATFORM_MAX_PATH] = "addons/sourcemod/logs/DENFER/RLBlocker";

        FormatTime(fileName, sizeof(fileName), "%d.%m.%Y"); // 09.12.2021
        FormatEx(path, sizeof(path), "%s/%s.log", path, fileName); // 09.12.2021.log

        LogToFileEx(path, "Y = %f, Difference Between Angles = %f", g_fCurrentEyeAngles[client][1], FloatAbs(g_fDifferenceEyeAngles[client][1]));

        for (int i = 0; i < 2; ++i) {
            g_fPreviousEyeAngles[client][i] = g_fCurrentEyeAngles[client][i];
        }

        return Plugin_Continue;
    } 

    g_hTimerTest[1] = null;
    return Plugin_Stop;
}