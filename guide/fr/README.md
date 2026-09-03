# Créer des menus et un HUD natifs in-game dans Street Fighter 6 avec REFramework

> **TL;DR** -- Vous pouvez injecter des fenêtres de réglages entièrement natives, des lignes et
> onglets dans le menu pause, du texte dans le panneau HUD, et des popups à l'écran dans le mode
> Entraînement de SF6, en utilisant uniquement du Lua REFramework -- aucun patch de DLL, aucun
> rendu personnalisé, aucun ImGui. Le jeu construit les lignes, gère le focus/la navigation, et
> dessine le tout avec ses propres polices, sprites et cadres nine-slice. Ce guide documente
> chaque technique que nous avons livrée, chaque crash qui nous a appris une règle, et le
> processus de sondage qui a permis de trouver les points d'entrée.

| | |
|---|---|
| **Temps de lecture** | ~45 minutes (intégral) ; ~15 minutes (techniques 1-2 seulement) |
| **Niveau requis** | Lua REFramework intermédiaire (vous maîtrisez `sdk.hook`, `sdk.find_type_definition`, `sdk.get_managed_singleton`) |
| **Version du jeu** | Street Fighter 6, RE Engine (testé avec le build REFramework-Websockets LL5271 ; REFramework standard fonctionne pour toutes les techniques de menus) |
| **Dernière mise à jour** | 2026-09-03 |

[![Native window over the fight](img/native_window_hitconfirm.png)](img/native_window_hitconfirm.png)
*La fenêtre de réglages « Hit Confirm », entièrement construite à partir de l'interface du dialogue Options du jeu, affichée par-dessus le combat en direct, le combat étant en pause.*

---

## Table des matières

1.  [À qui s'adresse ce guide](#1-à-qui-sadresse-ce-guide)
2.  [Prérequis](#2-prérequis)
3.  [Comment fonctionne l'interface du jeu](#3-comment-fonctionne-linterface-du-jeu)
4.  [Les règles d'or (éprouvées par les crashs)](#4-les-règles-dor-éprouvées-par-les-crashs)
5.  [Technique 1 -- Lignes du dialogue Options (NativeOptions)](#5-technique-1----lignes-du-dialogue-options-nativeoptions)
6.  [Technique 2 -- Lignes et onglets du menu pause (NativePauseMenu)](#6-technique-2----lignes-et-onglets-du-menu-pause-nativepausemenu)
7.  [Technique 3 -- Piloter le HUD du jeu (NativeHud)](#7-technique-3----piloter-le-hud-du-jeu-nativehud)
8.  [Technique 4 -- Emprunter des éléments GUI (NativePopup)](#8-technique-4----emprunter-des-éléments-gui-nativepopup)
9.  [Technique 5 -- Réutiliser des menus entiers du jeu (NativeShortcuts, NativeDialog)](#9-technique-5----réutiliser-des-menus-entiers-du-jeu-nativeshortcuts-nativedialog)
10. [Étude de cas -- L'éditeur de couleurs](#10-étude-de-cas----léditeur-de-couleurs)
11. [Étude de cas -- Le menu de couleur du Drive Impact](#11-étude-de-cas----le-menu-de-couleur-du-drive-impact)
12. [Disséquer un menu du jeu soi-même](#12-disséquer-un-menu-du-jeu-soi-même)
13. [Dépannage](#13-dépannage)
14. [Annexe -- Référence des types et énumérations](#14-annexe----référence-des-types-et-énumérations)
15. [Crédits](#15-crédits)

---

## 1. À qui s'adresse ce guide

Vous êtes un modder Lua REFramework qui souhaite ajouter des réglages, des overlays ou des
contrôles au mode Entraînement de SF6 **sans** fenêtres ImGui ni overlays D2D. Peut-être voulez-vous
que les réglages de votre mod aient l'air de faire partie du jeu. Peut-être qu'ImGui n'est pas
fiable sur les installations de vos utilisateurs. Peut-être voulez-vous des menus navigables à la
manette.

Ce guide couvre cinq techniques complémentaires, de la plus pratique (lignes du dialogue Options) à
la plus expérimentale (détournement du dialogue à deux colonnes des réglages de contrôles du jeu).
Chaque section est autonome : ne lisez que ce dont vous avez besoin.

**Ce que vous obtenez :**
- Une fenêtre de réglages qui s'ouvre par-dessus le combat, met l'action en pause, et ressemble
  exactement aux propres panneaux Options du jeu (curseurs, interrupteurs, spin-texts, boutons).
- Des lignes et des onglets entiers dans le menu pause d'entraînement (spins, boutons, callbacks
  d'action).
- Le propre panneau Dégâts / Dégâts du combo / Type d'attaque du jeu, ainsi que les chiffres du
  minuteur de round, pilotés par votre script.
- Des cadres de popup et du texte assemblés à partir d'éléments GUI empruntés (le cadre néon
  « Match Found », etc.).
- Un processus pour découvrir de nouveaux menus et contrôles à hooker.

---

## 2. Prérequis

### REFramework

N'importe quel build récent de REFramework pour SF6 convient pour les techniques de menus (1 à 5).
Le [build REFramework-Websockets (LL5271)](https://github.com/praydog/REFramework) ajoute un
serveur websocket Lua sur le port 8080, ce qui permet le sondage à distance via des scripts
(section 10), mais il n'est pas nécessaire pour l'injection d'UI elle-même.

### Bases de Lua

Vous devez être à l'aise avec :
- `sdk.find_type_definition`, `sdk.get_managed_singleton`, `sdk.create_instance`
- `sdk.hook(method, pre_fn, post_fn)` et le pattern `PreHookResult.SKIP_ORIGINAL`
- `re.on_pre_application_entry("LateUpdateBehavior", fn)` (callbacks du thread du jeu)
- `re.on_frame` (thread de rendu) vs. le thread du jeu -- cette distinction est critique (Règle 1)
- `json.load_file` / `json.dump_file` pour la persistance

### Méthode de lecture des crashs

Quand SF6 crashe avec REFramework chargé, vérifiez **deux fichiers** avant de relancer (le log est
écrasé au redémarrage) :
1. `reframework/re2_framework_log.txt` -- faites défiler jusqu'à la section « Exception occurred »
   pour la stack trace et l'adresse fautive.
2. `reframework/reframework_crash.dmp` -- l'horodatage indique de quel crash il s'agit.

---

## 3. Comment fonctionne l'interface du jeu

Une brève cartographie de l'architecture UI du jeu, dans la mesure où elle concerne le modding.
Tout ceci a été découvert par sondage (section 10), et non à partir d'une quelconque
documentation officielle.

### Contrôles et agents

L'interface de SF6 est construite sur l'arbre de contrôles `via.gui` du RE Engine. Les contrôles
(`via.gui.Control` et ses sous-types -- `Rect`, `Text`, `Scale9Grid`, `Panel`) forment une
hiérarchie parent-enfant. Chaque écran de menu possède un **UIAgent** (`app.UIAgent`) propriétaire
d'un arbre de contrôles (accessible via `agent.get_ControlMain()`). Tous les agents actifs sont
listés dans `app.UIAgentManager._Entries`.

Noms d'agents clés en mode Entraînement :
| Nom de l'agent | Ce que c'est |
|---|---|
| `ui11200` | Menu pause d'entraînement (onglets, lignes, gestion du focus) |
| `OptionDialog` | Le dialogue Options / Réglages (apparaît par-dessus le combat ou depuis le menu pause) |
| `KeyConfigBattleMenuFG` | Le dialogue à deux colonnes « Control Settings » |
| `BattleHud_Timer` | Minuteur de round (héberge le contrôle `c_main` sous lequel nous empruntons des éléments) |
| `Resident_Cmn_MatchingStandby` | Popup de matchmaking (source des cadres néon et des textes) |

### UIFlows et Params

Les écrans de menu sont gérés par des **UIFlows** (`app.UIFlowManager`). Un flow est démarré par
un appel statique `Start(...)` qui renvoie un `IUIFlowHandle`. Le flow crée un objet `Param` (son
état opérationnel) et pilote l'écran à travers `Init` -> `ShowedObject` -> interaction utilisateur
-> `OnEnd`. Le `get_IsEnd()` du handle vous indique quand le flow est terminé.

Flows importants :
| Classe de flow | Classe Param | Ce qu'elle pilote |
|---|---|---|
| `app.UIFlowOptionBGDialog` | `app.UIFlowOptionBGDialog.Param` | La fenêtre d'options sombre « BattleHud » (notre véhicule principal) |
| `app.UIFlowKeyConfig.Menu` | `app.UIFlowKeyConfig.Menu.Param` | Le dialogue à deux colonnes des réglages de contrôles |
| `app.UIFlowShortcutSetting` | (géré par `app.ShortcutSetting`) | Le menu des réglages de raccourcis |

### UIParts

Les lignes à l'intérieur des menus sont des objets `UIParts` (`UIPartsSpin`, `UIPartsButton`,
`UIPartsScrollList`, `UIPartsGroupScroll`). Le jeu les instancie depuis un pool et les lie à des
objets de données. Vous créez rarement des UIParts directement ; à la place, vous créez les objets
de données (`OptionSettingUnit`, `TrainingMenuData`) et vous laissez le jeu construire les parts.

### GUID de messages (hMsg)

Chaque texte affiché dans les menus de SF6 provient d'une résolution de GUID :
`app.helper.hMsg.GetMessage(Guid)`. Le jeu stocke ses textes dans des tables de messages indexées
par GUID. Nous ne pouvons pas ajouter d'entrées à ces tables, donc nous hookons `GetMessage` et
interceptons nos propres faux GUID, en renvoyant la chaîne de notre choix. C'est le fondement de
chaque technique de ce guide.

```lua
-- Create a GUID and register its text
local guid_text = {}   -- GUID string -> our text
local function message_guid(str)
    local g = sdk.find_type_definition("System.Guid"):get_field("Empty"):get_data(nil):NewGuid()
    guid_text[g:call("ToString()")] = str
    return g
end

-- Hook the message resolver
sdk.hook(
    sdk.find_type_definition("app.helper.hMsg"):get_method("GetMessage(System.Guid)"),
    function(args)
        local s = guid_text[sdk.to_valuetype(args[2], "System.Guid"):call("ToString()")]
        if s then
            thread.get_hook_storage()[1] = s
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end,
    function(retval)
        local s = thread.get_hook_storage()[1]
        if s then return sdk.to_ptr(sdk.create_managed_string(s)) end
        return retval
    end
)
```

### Écrire des GUID dans des objets

Ce build de REFramework refuse l'assignation directe de champs `ValueType` imbriqués (comme
`obj.GuidField = guid`). Vous devez écrire les 16 octets bruts :

```lua
local function set_guid(obj, field_name, guid)
    local off = obj:get_type_definition():get_field(field_name):get_offset_from_base()
    obj:write_qword(off, guid:read_qword(0))
    obj:write_qword(off + 8, guid:read_qword(8))
end
```

---

## 4. Les règles d'or (éprouvées par les crashs)

Chaque règle ci-dessous a été apprise à la suite d'un crash -- la plupart d'entre elles à partir
de violations d'accès qui ont fait planter le jeu sans erreur récupérable. Elles sont listées par
ordre de gravité.

### Règle 1 : pas de Lua hors du thread principal

**Symptôme :** AV (violation d'accès) intermittente dans des fonctions aléatoires du moteur, 1 à
3 minutes après le chargement. Le fait que le menu REFramework soit ouvert masque le bug (il
sérialise l'exécution Lua).

**Cause :** des callbacks `sdk.hook` sur des méthodes qui s'exécutent sur le thread d'input du
jeu, les threads de jobs UI, ou le thread de rendu. Plus précisément, les hooks sur les setters
`InputState`, `UIWidget_TMAttackInfo.SetXText`, et `UIBattleHud_Timer.UpdateBattleHud` exécutaient
tous du Lua hors du thread principal et provoquaient des crashs non déterministes (bissecté avec
`soak.py` : 0/3 crash sans, 3/3 avec).

**Règle :** chaque écriture GUI et chaque callback Lua non trivial doit se produire sur le thread
principal du jeu : `re.on_pre_application_entry("LateUpdateBehavior", fn)`. Les hooks en lecture
seule sur le thread de rendu (`re.on_frame`) sont acceptables pour la collecte de données, mais
**n'écrivez jamais** dans des objets du jeu depuis ce thread.

### Règle 2 : preuve de vie avant d'écrire dans des objets mis en cache

**Symptôme :** AV dans `set_Message`, `set_Color`, ou `set_Visible` sur un `via.gui.Text` ou un
`via.gui.Control` qui était valide quelques frames plus tôt.

**Cause :** le jeu reconstruit son HUD de combat à chaque changement de
`PauseManager._CurrentPauseTypeBit` (le type de pause 8 de notre fenêtre, le vrai menu pause, les
dialogues d'options...). Tout contrôle mis en cache peut être libéré, et `sdk.is_managed_object`
peut renvoyer `true` sur un chunk **réalloué** (mesuré le 31/08 : crash malgré les garde-fous en
place). Pendant les transitions pause/HUD, les contrôles en cache ne sont pas seulement invalides
-- la mémoire peut être réutilisée pour un objet différent.

**Règle :**
1. Appelez `sdk.is_managed_object(control:get_address())` avant chaque écriture -- mais sachez que
   ce n'est pas infaillible.
2. **Videz tous les caches** (panneau, minuteur, textes) dès que `TrainingGamePaused` ou
   `NativeOptionsWindowOpen` devient vrai. Ne tentez aucune « dernière écriture » -- les contrôles
   sont peut-être déjà libérés.
3. Surveillez `_CurrentPauseTypeBit` : à chaque changement, videz tous les caches et attendez 20
   ticks avant de résoudre de nouveaux contrôles.
4. Enveloppez chaque écriture GUI dans un `pcall`. Une seule AV non protégée est fatale.

### Règle 3 : ne jamais repeupler une page de dialogue ouverte

**Symptôme :** RIP 0 (déréférencement de pointeur de fonction nul) dans le pool de parts UI,
quelques frames après avoir modifié une `ChildUnitList` sur une unité dont la page de dialogue est
actuellement affichée.

**Cause :** `SetupDispUnits` lie des UIParts issues d'un pool à vos données. Si vous changez les
types de données (par exemple en remplaçant un curseur par un bouton) pendant que la page est
active, le pool relie des parts du mauvais type, et le prochain appel de mise en page saute dans
une entrée de vtable nulle.

**Règle :** n'appelez jamais `SetupDispUnits` et ne modifiez jamais `ChildUnitList` tant qu'une
page de dialogue est ouverte. À la place : faites `End()` sur le dialogue, attendez que l'agent
disparaisse, `rebuild()` l'arbre de données, puis `Start()` un nouveau dialogue. Avec
`ImmediateFade = true` (section 5), cette transition est visuellement instantanée même sous une
pause maintenue.

### Règle 4 : ne jamais fabriquer d'objets de données du jeu que le moteur attend entièrement construits

**Symptôme :** `NullReferenceException` dans `SetSettingParams` ou `MakeListIndexToParamIndex`,
suivie d'une `IndexOutOfRangeException` dans `UpdateListSetting`, le jeu meurt quelques frames
plus tard.

**Cause :** créer un `app.UIKeyConfig.SettingParam` via `sdk.create_instance` en ne remplissant
que les champs entiers. Les méthodes du moteur attendent que les propriétés string `Name`, `Icon`,
`Comment` et l'énumération `GamePadButton` soient entièrement initialisées. Des params à moitié
construits font planter la construction de la liste.

**Règle :** quand un type du jeu a une initialisation complexe, **clonez** une instance existante
(`CloneSettingParams`, `MemberwiseClone`) plutôt que d'en fabriquer une. Ne surchargez que les
getters de texte via des hooks. C'est ainsi que fonctionne `NativeDialog` (section 9).

### Règle 5 : pcall(func, args), pas pcall(function() ... end)

**Symptôme :** utilisation mémoire croissant progressivement (1 à 3 Mo/minute), finissant par
provoquer des saccades.

**Cause :** `pcall(function() ... end)` alloue une nouvelle closure à chaque appel. Sur les
chemins chauds (60 appels/seconde), ces closures s'accumulent plus vite que le GC ne les collecte.

**Règle :** utilisez `pcall(func, arg1, arg2)` avec une fonction prédéfinie. 89 appels de closure
sur des chemins chauds ont été corrigés dans la codebase de SF6 Tools en une seule passe.

### Règle 6 : io.open est relatif à reframework/data/, ne jamais utiliser ".."

**Symptôme :** `io.open` échoue silencieusement ou écrit à un emplacement inattendu.

**Cause :** REFramework confine `io.open` à `reframework/data/`. Les chemins contenant `..` sont
rejetés. `io.popen` et `os.execute` sont entièrement bloqués.

**Règle :** utilisez `json.dump_file` pour le JSON (il gère les verrous de fichiers Windows).
N'utilisez `io.open` que pour les fichiers texte, toujours avec des chemins relatifs à
`reframework/data/` (pas de préfixe `data/` dans le chemin).

### Règle 7 : fs.glob est coûteux -- jamais sur un timer

**Symptôme :** pics de frame-time d'environ 260 ms toutes les N secondes.

**Cause :** `fs.glob` parcourt tout l'arbre `reframework/data/` (~2200 fichiers). L'appeler
périodiquement (par exemple pour rafraîchir une liste de fichiers) crée des à-coups réguliers.

**Règle :** n'appelez `fs.glob` que juste avant l'ouverture d'un menu (l'utilisateur s'attend à
une brève pause). Mettez le résultat en cache. Dans `NativeOptions`, la vérification
`lists_changed()` et le `rebuild()` se produisent dans le chemin `open_request`, pas sur un timer.

### Règle 8 : écritures GUI uniquement depuis LateUpdateBehavior

**Symptôme :** AV dans `set_Message` lorsqu'appelé depuis `re.on_frame`.

**Cause :** `re.on_frame` s'exécute sur le **thread de rendu**. Écrire dans
`via.gui.Text.set_Message` depuis ce thread entre en concurrence (race condition) avec la propre
passe de mise en page du jeu sur le thread principal.

**Règle :** `set_Message`, `set_Color`, `set_Visible`, `set_Position`, `set_Size` -- tous doivent
être appelés depuis `re.on_pre_application_entry("LateUpdateBehavior", ...)` ou depuis un callback
`sdk.hook` sur une méthode connue pour s'exécuter sur le thread principal (par exemple
`TrainingManager.OpenMenu`).

### Règle 9 : ne jamais modifier les textes du jeu à la source

**Symptôme :** crash ou corruption permanente de texte après une réinitialisation de
l'entraînement.

**Cause :** écraser le champ `Message` d'un contrôle appartenant au jeu signifie que les propres
mises à jour du jeu relisent votre texte et le traitent comme l'original.

**Règle :** n'écrivez que dans des contrôles que vous avez **revendiqués**, et restaurez
l'original quand vous les relâchez. Stockez les originaux sur disque (ils survivent aux
rechargements de script). Pour le panneau HUD, les textes « latéraux » (`LeftText`, `RightText`)
sont réécrits par le widget à chaque frame -- masquez-les et n'utilisez que le texte central.

---

## 5. Technique 1 -- Lignes du dialogue Options (NativeOptions)

C'est la technique principale : injecter des lignes de réglages dans le propre système Options du
jeu et les ouvrir comme une fenêtre autonome par-dessus le combat en direct. Le jeu construit les
interrupteurs, curseurs, spin-texts et boutons ; gère la navigation au d-pad/stick ; et dessine le
tout avec son propre style.

[![SF6 Tools in the Options menu](img/options_sf6tools_submenu.png)](img/options_sf6tools_submenu.png)
*« SF6 Tools » apparaît en bas de Options > General. En le développant, on voit apparaître des sous-groupes (Hit Confirm, Script Manager), chacun ouvrant une fenêtre de style BattleHud par-dessus le combat.*

[![Options window over the fight](img/native_window_hitconfirm.png)](img/native_window_hitconfirm.png)
*La fenêtre « Hit Confirm » avec un curseur, un interrupteur et un bouton, ouverte par-dessus le combat en pause.*

### Comment ça fonctionne

1. **Créez des entrées `OptionSettingUnit`** et attachez-les à
   `app.OptionManager.UnitLists[General]`. L'écran Options du jeu lit cette liste pour construire
   l'onglet « General ». Une unité avec `EventType.OpenSubMenu` devient un groupe cliquable ; une
   unité avec `EventType.OpenBattleHudSetting` ouvre une fenêtre sombre de style « BattleHud ».
2. **Résolvez les textes via de faux GUID** : chaque `TitleMessage` et `DescriptionMessage` est
   un GUID. Nous générons des GUID aléatoires et hookons `hMsg.GetMessage` pour renvoyer nos
   chaînes.
3. **Contournez le Load/Reset du jeu** : hookez `OptionValueUnit.LoadValueEvent` et `ResetEvent`
   pour ignorer nos TypeId (le jeu ne doit pas essayer de charger ou de réinitialiser des valeurs
   qu'il ne possède pas).
4. **Ouvrez une fenêtre par-dessus le combat** : appelez
   `UIFlowOptionBGDialog.Start(SettingData, false)` depuis `LateUpdateBehavior`. Le
   `SettingData.TopUnit` pointe vers une de nos unités de groupe.
5. **Mettez le combat en pause** : `PauseManager.requestPause(true, 8)` (type 8 =
   `BATTLE_MENU_PAUSE`, le même type que celui utilisé par le vrai menu pause). Relâchez-la quand
   la fenêtre se ferme.

### Pas à pas : ajouter un groupe de réglages

#### Étape 1 : allouer des TypeId

Chaque `OptionSettingUnit` a besoin d'un `TypeId` unique. Le jeu met en cache les types de widgets
par TypeId d'un rechargement de script à l'autre, vous devez donc utiliser des ID neufs à chaque
chargement de votre script :

```lua
local next_id = nil
local function new_id()
    if not next_id then
        -- Find the highest existing TypeId in the game's ValueType enum
        local max = 0
        for _, f in ipairs(sdk.find_type_definition("app.Option.ValueType"):get_fields()) do
            if f:is_static() then
                local ok, v = pcall(f.get_data, f, nil)
                if ok and type(v) == "number" and v > max and v < 2100000000 then max = v end
            end
        end
        next_id = math.ceil((max + 1) / 10) * 10 + 100000
        next_id = next_id + (os.time() % 5000) * 100   -- fresh per load
    end
    next_id = next_id + 1
    return next_id
end
```

#### Étape 2 : construire l'arbre d'unités

```lua
local InputType = enum("app.Option.UnitInputType")     -- SpinText, Slider, Button_Type1, Button_Type2
local EventType = enum("app.Option.DecideEventType")   -- OpenSubMenu, OpenBattleHudSetting, SettingReset, ...
local DataType  = enum("app.Option.SettingDataType")   -- Value
local TabType   = enum("app.Option.TabType")           -- General

local mgr = sdk.get_managed_singleton("app.OptionManager")
local parent_list = mgr.UnitLists:call("get_Item", TabType.General)

-- Get empty typed lists from an existing unit (for MemberwiseClone)
local first_setting = parent_list:call("get_Item", 0):call("get_Setting")
local empty_guids    = first_setting.ValueMessageList:call("GetRange", 0, 0)
local empty_settings = first_setting.ChildUnitList:call("GetRange", 0, 0)
```

#### Étape 3 : créer le groupe racine

```lua
local function new_setting()
    local d = sdk.create_instance("app.Option.OptionSettingUnit")
    d.TypeId = new_id()
    return d
end

local function make_unit(desc, description, value_messages)
    local unit = desc:call("MakeUnitData")
    local s = unit:call("get_Setting")
    set_guid(s, "DescriptionMessage", message_guid(description or ""))
    s.ValueMessageList = empty_guids:call("MemberwiseClone")
    s.ChildUnitList    = empty_settings:call("MemberwiseClone")
    for _, msg in ipairs(value_messages or {}) do
        s.ValueMessageList:call("Add", message_guid(msg))
    end
    return unit
end

-- Root: "My Mod" -> opens a sub-menu
local root_desc = new_setting()
set_guid(root_desc, "TitleMessage", message_guid("My Mod"))
root_desc.InputType = InputType.Button_Type1
root_desc.EventType = EventType.OpenSubMenu
local root_unit = make_unit(root_desc, "Settings for My Mod.")
parent_list:call("Add", root_unit)
```

#### Étape 4 : ajouter un sous-groupe de réglages (ouvre une fenêtre)

```lua
local group_desc = new_setting()
set_guid(group_desc, "TitleMessage", message_guid("My Settings"))
group_desc.InputType = InputType.Button_Type1
group_desc.EventType = EventType.OpenBattleHudSetting   -- opens a window over the fight
local group_unit = make_unit(group_desc, "Adjust my mod's parameters.")

-- Attach to root
local function attach(parent, child)
    parent:call("get_ChildUnits"):call("Add", child)
    parent:call("get_Setting").ChildUnitList:call("Add", child:call("get_Setting"))
end
attach(root_unit, group_unit)
```

#### Étape 5 : ajouter un interrupteur (SpinText Off/On)

```lua
local toggle_desc = new_setting()
set_guid(toggle_desc, "TitleMessage", message_guid("Enable Feature"))
toggle_desc._DataType   = DataType.Value
toggle_desc.InputType   = InputType.SpinText
local toggle_type_id = toggle_desc.TypeId

local toggle_unit = make_unit(toggle_desc, "Turn the feature on or off.", {"Off", "On"})
attach(group_unit, toggle_unit)

-- Value setting (min/max/initial)
local vs = sdk.create_instance("app.Option.OptionValueSetting")
vs.TypeId = toggle_type_id
vs.MinValue = 0; vs.MaxValue = 1; vs.InitValue = 1   -- default "On"
toggle_unit:call("set_PrevValue", 1)
toggle_unit:call("set_ValueSetting", vs)
toggle_unit.ValueData = vs:call("MakeValueData")
```

#### Étape 6 : ajouter un curseur

```lua
local slider_desc = new_setting()
set_guid(slider_desc, "TitleMessage", message_guid("Block Rate"))
slider_desc._DataType = DataType.Value
slider_desc.InputType = InputType.Slider

local slider_unit = make_unit(slider_desc, "Chance (%) that the dummy blocks.")
attach(group_unit, slider_unit)

local svs = sdk.create_instance("app.Option.OptionValueSetting")
svs.TypeId = slider_desc.TypeId
svs.MinValue = 0; svs.MaxValue = 100; svs.InitValue = 50
slider_unit:call("set_PrevValue", 50)
slider_unit:call("set_ValueSetting", svs)
slider_unit.ValueData = svs:call("MakeValueData")
```

#### Étape 7 : ajouter un bouton (pattern de la ligne Restore)

Les boutons utilisent `InputType.Button_Type2` et `EventType.SettingReset` -- exactement le
pattern de la ligne « Restore Default Settings » du jeu. Cela s'affiche comme un bouton centré en
pleine largeur.

```lua
local btn_desc = new_setting()
set_guid(btn_desc, "TitleMessage", message_guid("START SESSION"))
btn_desc.InputType = InputType.Button_Type2
btn_desc.EventType = EventType.SettingReset
local btn_unit = make_unit(btn_desc, "Start the training session.")
attach(group_unit, btn_unit)
```

> **Note :** `Button_Type1` affiche le titre aligné à gauche lorsqu'il est focus (utilisé pour la
> navigation en sous-menu). `Button_Type2` garde le titre centré (utilisé pour les boutons
> d'action). Utilisez toujours `Type2` pour les boutons de votre fenêtre de réglages.

Pour gérer les appuis sur les boutons, hookez `Param.GetFocusDecideEventType` et
`Param.FlowEvent_ResetCurrentUnits` :

```lua
local bg_param_td = sdk.find_type_definition("app.UIFlowOptionBGDialog.Param")

-- Intercept the decide: return Invalid (0) for our buttons so no "Revert?" popup appears
sdk.hook(bg_param_td:get_method("GetFocusDecideEventType"), function(args)
    thread.get_hook_storage()["param"] = args[2]
end, function(rv)
    if (sdk.to_int64(rv) & 0xFF) == 1 then   -- SettingReset
        local param = sdk.to_managed_object(thread.get_hook_storage()["param"])
        local u = param:call("GetFocusUnit")
        local tid = u and u:call("get_Setting").TypeId
        if tid == btn_desc.TypeId then
            -- Queue your callback here
            my_button_callback()
            return sdk.to_ptr(0)   -- DecideEventType.Invalid: no popup
        end
    end
    return rv
end)
```

#### Étape 8 : ignorer Load/Reset pour nos ID

```lua
local known_ids = { [toggle_type_id] = true, [slider_desc.TypeId] = true, [btn_desc.TypeId] = true }

local function skip_ours(args)
    local ok, id = pcall(function()
        return sdk.to_managed_object(args[2]):call("get_Setting").TypeId
    end)
    if ok and known_ids[id] then return sdk.PreHookResult.SKIP_ORIGINAL end
end

local vu = sdk.find_type_definition("app.Option.OptionValueUnit")
sdk.hook(vu:get_method("LoadValueEvent"), skip_ours)
sdk.hook(vu:get_method("ResetEvent"), skip_ours)
```

#### Étape 9 : ouvrir la fenêtre par-dessus le combat

```lua
local dialog_handle = nil

local function open_window()
    -- Close any existing dialog first (they stack)
    if dialog_handle then
        pcall(function()
            if not dialog_handle:call("get_IsEnd") then dialog_handle:call("End") end
        end)
    end

    local sd = sdk.create_instance("app.UIFlowOptionBGDialog.SettingData")
    sd.TopUnit = group_unit
    sd.SupportMode = 32
    sd.UseBattleHudBG = false
    sd.PlayerIndex = 0

    local m = sdk.find_type_definition("app.UIFlowOptionBGDialog")
        :get_method("Start(app.UIFlowOptionBGDialog.SettingData, System.Boolean)")
    dialog_handle = m:call(nil, sd, false)
end
```

Appelez `open_window()` depuis `LateUpdateBehavior` quand votre raccourci est pressé ou que votre
bouton du menu pause est activé. **Jamais depuis `re.on_frame`** (Règle 8).

#### Étape 10 : mettre le combat en pause

```lua
local PAUSE_TYPE = 8   -- BATTLE_MENU_PAUSE
local pause_held = false

local function hold_pause(on)
    if on == pause_held then return end
    local mgr = sdk.get_managed_singleton("app.PauseManager")
    if mgr and pcall(function() mgr:call("requestPause", on, PAUSE_TYPE) end) then
        pause_held = on
    end
end
```

Appelez `hold_pause(true)` juste après `open_window()`. Appelez `hold_pause(false)` quand le
dialogue se ferme (détecté via `dialog_handle:call("get_IsEnd")` ou la disparition de l'agent
`OptionDialog`).

#### Étape 11 : détecter la fermeture

Sondez depuis `LateUpdateBehavior` toutes les ~10 ticks :

```lua
if dialog_handle then
    local ended = pcall(function() return dialog_handle:call("get_IsEnd") end)
        and dialog_handle:call("get_IsEnd")
    if ended then
        dialog_handle = nil
        hold_pause(false)
    end
end
```

#### Étape 12 : sonder les changements de valeur

```lua
-- In LateUpdateBehavior, every ~10 ticks:
local ok, n = pcall(function() return toggle_unit:call("get_Value") end)
if ok and n ~= last_toggle_value then
    last_toggle_value = n
    local is_on = (n ~= 0)
    -- Act on the change
end
```

### Exclusion mutuelle avec le menu pause

Le bouton Échap/Start qui ferme votre fenêtre atteint aussi le menu pause d'entraînement via
`TrainingManager.OpenMenu`. Hookez-le pour l'ignorer tant que votre fenêtre est ouverte (et
pendant ~20 frames après) :

```lua
local tm_td = sdk.find_type_definition("app.training.TrainingManager")
local open_menu = tm_td:get_method("OpenMenu(app.training.TrainingManager.MenuType, app.training.BaseParam)")
sdk.hook(open_menu, function(args)
    if my_window_open or (tick - closed_tick) < 20 then
        return sdk.PreHookResult.SKIP_ORIGINAL
    end
end, function(rv) return rv end)
```

### Ignorer le fondu d'écran (ImmediateFade)

Quand vous fermez et rouvrez le dialogue (par exemple pour rafraîchir le contenu après un
changement de mode), la transition par défaut inclut un fondu d'écran. Sous une pause maintenue,
ce fondu se fige (l'animation de fondu a besoin de frames non mises en pause). Pour l'éviter :

```lua
sdk.hook(bg_param_td:get_method("CreatedObject"), function(args)
    if my_window_open then
        pcall(function()
            local param = sdk.to_managed_object(args[2])
            param:set_field("<ImmediateFade>k__BackingField", true)
        end)
    end
end, function(rv) return rv end)
```

### Masquer la ligne « Restore Default Settings » du jeu

Quand votre fenêtre s'ouvre, le jeu ajoute automatiquement une ligne « Restore Default Settings ».
Sur nos pages (où elle ne réinitialiserait rien), masquez-la :

```lua
sdk.hook(bg_param_td:get_method("SetupDispUnits"), function(args)
    thread.get_hook_storage()["param"] = args[2]
end, function(rv)
    pcall(function()
        local param = sdk.to_managed_object(thread.get_hook_storage()["param"])
        local parts = param:get_field("OptionUnits")
        if not parts then return end
        local ours = false
        local reset_parts = {}
        for i = 0, parts:call("get_Length") - 1 do
            local part = parts:call("GetValue", i)
            local ud = part and part:get_field("UnitData")
            if ud then
                local s = ud:call("get_Setting")
                if known_ids[s.TypeId] then
                    ours = true
                elseif s.EventType == 1 then   -- SettingReset (the game's own)
                    reset_parts[#reset_parts + 1] = part
                end
            end
        end
        if ours then
            for _, part in ipairs(reset_parts) do
                local c = part:call("get_Control")
                if c then c:call("set_ForceInvisible", true) end
                pcall(function() part:call("SetDisable", true) end)
            end
        end
    end)
    return rv
end)
```

### Listes dynamiques et rafraîchissement

Si vos options incluent une liste de fichiers (par exemple des slots d'enregistrement),
ne la relisez que juste avant l'ouverture de la fenêtre -- jamais sur un timer (Règle 7). Le
pattern :

1. Avant l'ouverture, vérifiez si une `options_fn` (une fonction renvoyant une liste) a changé.
2. Si oui, démontez l'arbre d'unités (`parent_list:Remove(root_unit)`) et reconstruisez-le.
3. Ouvrez la nouvelle fenêtre.

### Nettoyage à la réinitialisation du script

```lua
re.on_script_reset(function()
    if root_unit and parent_list then
        pcall(function() parent_list:call("Remove", root_unit) end)
    end
end)
```

### Référence de l'API NativeOptions

Le module `NativeOptions.lua` enveloppe tout ce qui précède dans une API propre :

| Fonction | Description |
|---|---|
| `Opt.group(title, desc, {mode=id, key=key})` | Crée un groupe de réglages nommé. `mode` le lie à un ID de mode d'entraînement. |
| `g:toggle(key, title, desc, default, cb, opts)` | Interrupteur booléen (spin Off/On). `cb(value)` se déclenche au changement. |
| `g:choice(key, title, desc, options, default, cb, opts)` | Spin avec options nommées. `default` et la valeur de `cb` sont en base 1. `options` peut être une fonction. |
| `g:slider(key, title, desc, min, max, default, cb, opts)` | Curseur entier. |
| `g:button(key, title, desc, cb, refresh)` | Bouton d'action. `cb()` peut renvoyer `"close"` pour fermer la fenêtre. `refresh=true` reconstruit la fenêtre après l'appui (pour les titres dynamiques). |
| `g:get(key)` / `g:set(key, v)` | Lit/écrit la valeur d'une entrée par programmation. |
| `Opt.open(title)` | Ouvre la fenêtre du groupe nommé par-dessus le combat (si pas en pause). |
| `Opt.open_after_unpause(title)` | Met en file une ouverture qui attend que le combat soit revenu stable pendant 5 ticks. |
| `Opt.close()` | Ferme la fenêtre actuelle. |
| `Opt.set_mode_selector(names, ids, get, set)` | Installe un spin « Training mode » en haut de la fenêtre composite « SF6 Tools ». |
| `Opt.rebuild()` | Démonte et reconstruit l'arbre d'unités (pour le contenu dynamique). |
| `Opt.message_guid(str)` | Crée un faux GUID résolu vers `str` (réutilisable par d'autres modules). |

Options pour les entrées (table `opts`) :
- `deferred = true` -- le callback ne se déclenche qu'après la fermeture de la fenêtre et la
  reprise du combat (pour les opérations lourdes comme l'import d'enregistrements).
- `getter = function()` -- appelée à l'ouverture de la fenêtre pour rafraîchir la valeur de
  l'entrée depuis un état externe.

---

## 6. Technique 2 -- Lignes et onglets du menu pause (NativePauseMenu)

Injecter des lignes dans l'onglet « Basic Settings » du menu pause d'entraînement, et ajouter des
onglets entièrement nouveaux.

[![Pause menu with injected row](img/pause_menu_injected_row.png)](img/pause_menu_injected_row.png)
*La ligne « SF6 Tools Shortcut Settings » en bas de Basic Settings, avec l'indicateur de défilement. Un point d'onglet supplémentaire est visible en haut (notre onglet « SF6 Tools »).*

### Comment ça fonctionne

Le menu pause d'entraînement est piloté par `TrainingManager._UIData._MenuData`, un tableau
`TrainingMenuData[8]` (un par onglet). Les lignes de chaque onglet se trouvent dans `_ChildData`
(statique) et `DynamicChildData` (dynamique, ajoutée à l'exécution). Le jeu fournit
`AddDynamicMenu(funcType, data, action)` pour ajouter des lignes.

Nos lignes utilisent `FuncType = 345` (la valeur `DYNAMIC` que nous avons choisie ; les propres
onglets du jeu utilisent 1..8). Le jeu appelle des méthodes `TrainingMenuFunc` pour les afficher et
interagir avec elles :

| Méthode | Quand | Ce que nous faisons |
|---|---|---|
| `ViewUpdate(param, data, i)` | Par ligne, à chaque frame | Mémoriser laquelle de nos lignes est en cours de traitement (`current = item`) |
| `GetIsActive(ftype)` | Par ligne | Renvoyer `1` (actif) |
| `GetOptionText(ftype)` | Par ligne de spin | Renvoyer le texte de l'option courante |
| `GetOptionIndex(ftype, wanted, ftype)` | Au changement de spin | Appeler `item.set(wanted)`, renvoyer `wanted` |
| `Function(ftype, param, viewData, value)` | À la confirmation/décision | Pour les boutons : appeler `item.on_decide()`, renvoyer 0 (rester) ou 1 (fermer le menu) |

Les lignes sont identifiées par l'adresse de leur `TrainingMenuData` via le GUID `_MessageID`
(car `AddDynamicMenu` clone les données -- les adresses d'origine sont perdues).

### Ajouter une ligne de spin

```lua
local PM = require("func/NativePauseMenu")

PM.spin(
    "Training mode",                           -- title
    "Which training script drives the dummy.", -- guide text (bottom of screen)
    { "DISABLED", "HIT CONFIRM", "REACTION DRILLS" },  -- options
    function() return current_mode_index end,  -- getter (0-based)
    function(i) set_mode(i) end                -- setter (0-based)
)
```

### Ajouter une ligne de bouton

```lua
PM.button(
    "SF6 Tools Shortcut Settings",
    "Open the shortcut configuration menu.",
    function() NativeShortcuts.open() end,   -- on_decide
    true,   -- keep_open: the pause menu stays up
    true    -- in_tab: also appears in our "SF6 Tools" tab
)
```

### Ajouter un onglet complet (page)

```lua
local pg = PM.page("Distance Viewer", "Distance Viewer settings.")

pg:toggle("Display P1", "Show P1 distance overlay.",
    function() return config.p1_enabled end,
    function(v) config.p1_enabled = v; save() end)

pg:spin("Red Zone", "Attack used for the red zone.",
    function() return get_move_names() end,   -- options (function = dynamic list)
    function() return selected_move_index end,
    function(i) select_move(i) end,
    20)  -- capacity: max option count (row built once, options filled live)

pg:button("TELEPORT", "Move both players to this distance.",
    function() teleport() end,
    false)  -- keep_open = false: closes the pause menu after the action

pg:value("Distance", "Current distance between players.",
    function() return string.format("%.1f", current_distance) end)

pg:label("Press L1+R1 to toggle overlay.", "Keyboard: F5.")
```

### L'installation des onglets

Les onglets sont installés en remplaçant `_MenuData` par un tableau plus long (les 8 du jeu + nos
onglets). Chacun de nos onglets est un `TrainingMenuData` avec `_FuncType = 345` et `_ChildData` =
nos objets de ligne. Le jeu affiche l'onglet dans la bande, montre son point de page, et gère le
focus/la navigation.

L'installation se fait avec le menu **fermé** (Règle 3). `NativePauseMenu` vérifie `tabs_present`
toutes les 60 ticks et réinstalle si le jeu a reconstruit ses données de menu (changement de
personnage, etc.).

### Le bug de défilement à 14 lignes

L'onglet Basic Settings a 13 lignes d'origine. En ajouter une fait 14, ce qui atterrit
**exactement** en bas de la vue de défilement (`_ViewTop 37,5 + _ViewSize.h 805 = 842,5 = bas de
la ligne 13`). Mais le masque visuel se situe 20 px plus haut, donc le jeu ne défile jamais et la
dernière ligne est coupée.

**Correctif :** écrivez `_ViewSize.h = 745` dans `UIPartsGroupScroll` (l'item racine de l'agent
`ui11200`) pendant la pause. Une ligne de moins dans la vue, et le propre `ScrollFocusItem` du jeu
y défile. Un onglet à 13 lignes tient toujours (égalité = visible).

```lua
-- In LateUpdateBehavior, while paused:
local mgr = sdk.get_managed_singleton("app.UIAgentManager")
local list = mgr:get_field("_Entries")
for i = 0, list:call("get_Count") - 1 do
    local agent = list:call("get_Item", i).Agent
    local go = agent and agent:call("get_GameObject")
    if go and tostring(go:call("get_Name")) == "ui11200" then
        local root = agent:get_field("_RootItem")
        if root then
            local off = root:get_type_definition():get_field("_ViewSize"):get_offset_from_base()
            if root:read_float(off + 4) > 745 then
                root:write_float(off + 4, 745)
            end
        end
        break
    end
end
```

### Titres dynamiques

Les titres et les guides donnés sous forme de **fonctions** sont réévalués dans un pre-hook sur
`TrainingManager.OpenMenu` (le point d'entrée unique du menu pause, s'exécutant sur le thread du
jeu). Le hook hMsg résout ensuite les GUID vers les textes à jour.

### Référence de l'API NativePauseMenu

| Fonction | Description |
|---|---|
| `PM.spin(title, guide, options, get, set)` | Ajoute une ligne de spin à Basic Settings. `get`/`set` sont en base 0. |
| `PM.button(title, guide, on_decide, keep_open, in_tab)` | Ajoute une ligne de bouton. `in_tab=true` la duplique dans l'onglet « SF6 Tools ». |
| `PM.page(title, guide, opts)` | Crée une nouvelle page d'onglet. Renvoie un objet `Page`. `opts.tab=false` = conteneur seul, aucun onglet installé. |
| `pg:spin(title, guide, options, get, set, capacity)` | Ligne de spin sur une page. `options` peut être une fonction. |
| `pg:toggle(title, guide, get, set)` | Interrupteur Off/On sur une page. |
| `pg:number(title, guide, min, max, step, get, set, fmt)` | Ligne numérique avec pas discrets. |
| `pg:button(title, guide, on_decide, keep_open)` | Ligne de bouton sur une page. |
| `pg:value(title, guide, fn)` | Ligne en lecture seule dont le texte provient de `fn()`. |
| `pg:label(title, guide)` | Ligne de texte statique. |
| `PM.tab_button(title, guide, on_decide, keep_open)` | Bouton présent uniquement dans l'onglet « SF6 Tools ». |

### Limites

- **Pool de lignes :** le jeu crée ~20 UIParts par onglet. Au-delà de ce que le pool peut gérer,
  les lignes supplémentaires ne s'affichent pas. Limitez les pages à **13 lignes ou moins** (les
  propres onglets du jeu ne dépassent jamais 13).
- **Bande d'onglets :** la bande d'onglets du jeu est visuellement conçue pour 8 onglets. En
  ajouter 1 ou 2 fonctionne proprement (points, focus, navigation, tout marche) ; au-delà d'environ
  3 onglets supplémentaires, la bande peut être surchargée.

---

## 7. Technique 3 -- Piloter le HUD du jeu (NativeHud)

Remplacer le texte du panneau « Damage / Combo Damage / Attack Type » du HUD d'entraînement, ainsi
que les chiffres du minuteur de round, par votre propre contenu, en utilisant les propres polices,
sprites et mise en page du jeu.

[![Native HUD panel](img/native_hud_panel.png)](img/native_hud_panel.png)
*Le HUD d'entraînement avec le panneau de dégâts natif (haut centre) affichant les libellés « Damage », « Combo Damage » et « Attack Type ». Le minuteur de round affiche « 99 » avec des sprites de chiffres natifs.*

### Le panneau de dégâts

Le widget `app.training.UIWidget_TMAttackInfo` (trouvé via `TrainingManager._ViewUIWigetDict`)
possède un tableau `AttackInfos` de 3 lignes. Chaque ligne a `LeftText`, `CenterText`, et
`RightText` (des contrôles `via.gui.Text`).

**Constat clé :** le jeu réécrit les textes **latéraux** (`LeftText`, `RightText`) à chaque frame.
Impossible de lutter contre ça. À la place, **masquez** les textes latéraux (`set_Visible(false)`)
et n'écrivez que le texte **central** -- que le jeu ne touche que lors des événements de hit/garde
(et vous réaffirmez le vôtre au tick suivant).

```lua
local NativeHud = require("func/NativeHud")

-- Take ownership
NativeHud.claim("my_mod")

-- Write three rows (l/c/r parts are joined into the centre text with spacing)
NativeHud.set(0, "l", "SCORE: 3")
NativeHud.set(0, "c", "HIT CONFIRM")
NativeHud.set(0, "r", "TOTAL: 10")
NativeHud.set(0, "c", nil, 0xFF00FF00)   -- green colour (ABGR)

NativeHud.set(1, "l", "HIT: 80%")
NativeHud.set(1, "r", "BLOCK: 20%")

NativeHud.set(2, "c", "WAITING")

-- Give it back when done
NativeHud.release("my_mod")
```

### Le minuteur de round

`app.UIBattleHud_Timer` possède des contrôles de sprites de chiffres (`e_texture_number_001`,
`010`, `100`) pilotés par `set_UVPatternNo(digit)`. Le signe infini est `c_infinite` (masqué via
`set_ForceInvisible` pendant que nous pilotons les chiffres).

```lua
NativeHud.set_timer(29, 0xFF0000FF)   -- show "29" in red
NativeHud.set_timer(nil)               -- give the timer back
```

Pour les nombres >= 100, le module ajuste les positions et l'échelle des sprites (le jeu n'utilise
normalement que deux chiffres).

### Sécurité critique (les quatre règles anti-AV)

Chacune de ces quatre règles correspond à un crash bissecté les 30-31/08/2026 :

1. **Aucune écriture GUI en pause** -- quand `TrainingGamePaused` ou `NativeOptionsWindowOpen`
   devient vrai, videz tous les caches silencieusement. Ne tentez pas d'« écriture d'adieu ».
2. **Ne restaurez les textes qu'au pre-hook `OpenMenu`** -- c'est le seul point où les contrôles
   du HUD sont garantis vivants (avant le démontage qui suit).
3. **Surveillez `_CurrentPauseTypeBit`** -- tout changement déclenche une reconstruction du HUD.
   Videz tous les caches et attendez 20 ticks.
4. **`sdk.is_managed_object` ne suffit pas** -- il laisse passer les chunks mémoire réalloués.
   Enveloppez toujours les écritures GUI dans un `pcall`.

### Référence de l'API NativeHud

| Fonction | Description |
|---|---|
| `NativeHud.claim(name)` | Prend possession du HUD. Un seul propriétaire à la fois. |
| `NativeHud.release(name)` | Rend tout (textes originaux restaurés). |
| `NativeHud.set(row, col, text, color)` | Définit texte/couleur. `row` = 0-2, `col` = "l"/"c"/"r", `color` = ABGR. |
| `NativeHud.clear()` | Efface tout le texte en attente. |
| `NativeHud.set_timer(n, color)` | Pilote les chiffres du minuteur (0-999). `nil` restaure le minuteur du jeu. |
| `NativeHud.request_text_visible(bool)` | Affiche/masque les textes du panneau (pour les modes qui n'utilisent pas le HUD). |
| `NativeHud.available()` | Vrai quand les contrôles du panneau sont résolus. |

---

## 8. Technique 4 -- Emprunter des éléments GUI (NativePopup)

Construire des popups, barres et cadres à l'écran à partir des propres éléments `via.gui` du jeu
-- sans en créer aucun. Cette technique a été utilisée pour la NativeTopBar (boutons de mode en
haut de l'écran), la NativeBottomBar (boutons d'action en bas, désormais désactivée), et la
NativePopup (cadres de notification).

[![Borrowed popup](img/borrowed_popup.png)](img/borrowed_popup.png)
*Une popup assemblée à partir d'éléments GUI empruntés : le cadre néon « Match Found » (Scale9Grid), un corps Rect sombre, et des éléments de texte issus d'agents dormants.*

### Pourquoi ne pas créer d'éléments ?

- `sdk.create_instance("via.gui.Text")` s'affiche correctement sous le bon parent et la bonne
  racine, mais **ne survit pas à une réinitialisation de script** (REFramework libère ses
  instances managées, créant un enfant orphelin qui plante sur `set_Message`).
- `Panel:call("create_instance", ...)` et `control:call("duplicate")` ne s'affichent pas depuis
  Lua (le moteur exige une étape d'enregistrement que nous ne pouvons pas déclencher).
- Seuls les éléments **construits par le moteur lui-même** (à partir de prefabs, pendant
  l'initialisation d'un agent) possèdent l'état interne complet nécessaire à l'affichage.

### La recette

1. **Trouvez des éléments de réserve** que le moteur a construits mais n'affiche jamais dans votre
   mode de jeu. Les agents de matchmaking résidents (`Resident_Cmn_MatchingStandby`,
   `Resident_Cmn_MatchingSelect`, etc.) ont des enfants cachés (skins Battle Hub, skins d'attente
   en ligne) chargés mais invisibles en Fighting Ground.
2. **Copiez l'apparence** depuis une source visible : `source:call("copyProperties", spare)`.
   Cela copie l'atlas nine-slice, le slot de police, les paramètres de glow, et la configuration
   des couleurs.
   > **Attention :** le sens est `SOURCE -> CIBLE` (les propriétés de la source sont copiées
   > **sur** l'élément de réserve). Inverser le sens corrompt silencieusement la source.
3. **Re-parentez sous un hôte vivant** : `host:call("addChild", spare)`. L'hôte doit être visible
   et présent dans l'arbre de rendu. Le `c_main` de `BattleHud_Timer` est un bon choix (il est
   toujours présent en mode Entraînement et dispose du slot de police 8).
4. **Pilotez position, taille, couleur, priorité** depuis `LateUpdateBehavior`.

### Ce qui fonctionne et ce qui ne fonctionne pas

| Opération | Résultat |
|---|---|
| `addChild` d'un Rect d'un agent vers un autre | Fonctionne (s'il n'est pas déjà enfant ailleurs ; `remove()` + `addChild` si nécessaire) |
| `addChild` d'un Text | Fonctionne **une seule fois**. `remove()` sur un Text supprime définitivement son enregistrement de police -- il devient un rectangle vide. Ne déplacez un Text qu'une seule fois. |
| `addChild` d'un Scale9Grid | Fonctionne. `remove()` supprime l'atlas. Ne le déplacez qu'une seule fois. |
| `copyProperties` Scale9Grid -> Scale9Grid | Fonctionne. Copie l'atlas nine-slice, les rects de bordure, et le mode de rendu. |
| `copyProperties` Text -> Text | Fonctionne. Copie le slot de police, le contour, les réglages de glow. |
| Définir `MaskType = 0` | Requis. Un contrôle emprunté peut porter un masque hérité de son parent d'origine, ce qui couperait tout l'hôte. |
| Définir `ControlPoint = 5` | Ancrage centré (positionnement plus simple). |

### L'échec de la barre du bas et les leçons tirées

La NativeBottomBar (boutons d'action en bas de l'écran) a été construite et fonctionnait, mais
elle est **désactivée** (`NativeBottomBar_Experimental = true` pour l'activer). Problèmes :

1. **Pool de textes trop petit.** Seuls ~4 éléments Text parmi tous les agents résidents
   survivent à l'adoption sans planter sur `set_Message`. La barre du bas a besoin d'un texte par
   bouton.
2. **Les textes sont réécrits par leur widget d'origine.** `BattleHud_HitCount/e_txt_score`
   s'affiche correctement après adoption, mais `set_Message` déclenche une AV. Les textes de
   `BattleHud_MatchWonNumber` sont écrasés pendant les combos (contournement : réaffirmer les
   libellés toutes les 60 ticks).
3. **La réinitialisation de script libère les textes créés par sdk.create_instance.** Même avec
   `add_ref()`, le GC du moteur ou le nettoyage de REFramework libère les instances de texte
   créées, laissant des enfants orphelins sous l'hôte.

**Leçon :** les UI à base d'éléments empruntés sont viables pour de petits éléments (une popup de
1 à 3 lignes, une barre du haut avec des libellés fixes) mais ne passent pas à l'échelle pour des
barres dynamiques à plusieurs boutons. Pour une UI de réglages, utilisez plutôt les techniques 1
et 2.

---

## 9. Technique 5 -- Réutiliser des menus entiers du jeu (NativeShortcuts, NativeDialog)

### A. Substitution du menu Shortcut Settings (NativeShortcuts)

Le menu Shortcut Settings du jeu (`app.ShortcutSetting`) affiche les bindings manette/clavier à
partir de deux listes de données : `_SettingUserData.Data` (définitions) et
`SettingSaveData.ItemDataList` (état). En **substituant** ces deux listes par les nôtres pendant
que le menu est ouvert, nous obtenons un menu de configuration de touches pleinement fonctionnel
avec nos lignes.

**Comment ça fonctionne :**
1. Construire des tableaux `ShortcutSettingData` et `ShortcutSettingItemSaveData` pour nos
   actions.
2. Avant `ShortcutSetting.Start(0)`, substituer les listes du moteur par les nôtres.
3. Bloquer `ShortcutSaveData.Save` et `ShortcutSetting.Save` pendant la substitution (le jeu ne
   doit pas persister nos lignes comme de vrais raccourcis).
4. À la fermeture du menu (`get_IsOpening() == false`), restaurer les listes originales et pousser
   les bindings dans notre framework de raccourcis.

### B. Détournement du dialogue à deux colonnes (NativeDialog)

> **Statut :** implémenté et fonctionnel, mais **rejeté par le projet** au profit des fenêtres
> NativeOptions (Technique 1). Documenté ici à titre de référence pour la technique et ses pièges.
> `NativeDialog.lua` reste dans le repo, inutilisé.

Le dialogue « P1 Control Settings » (`app.UIFlowKeyConfig.Menu`) possède un spin de catégories à
gauche et une liste déroulante de lignes à droite. En hookant ses méthodes `Param` pendant que
notre dialogue est actif, nous pouvons lui faire afficher nos catégories et nos lignes.

**Leçon critique -- la Règle 4 en action :** la première version créait des instances
`SettingParam` via `sdk.create_instance` en ne remplissant que les champs entiers. Le
`MakeListIndexToParamIndex` du moteur essayait de lire `Name` (une propriété string), obtenait
null, et levait une `NullReferenceException`. Le correctif : **cloner** le propre tableau du jeu
avec `Param.CloneSettingParams(sourceArray)` et ne surcharger que les getters de texte (`GetName`,
`GetIcon`, `GetInputIcon`, `GetComment`) via des hooks.

**Hooks clés :**
- `GetBattleSettingParams` (post-hook) : capture le tableau du jeu comme source de clonage,
  renvoie notre clone pour la catégorie courante.
- `SpinPresetChanged` (pre-hook, SKIP) : définit notre catégorie, `SetSettingParams(clone)`,
  `UpdateListSetting()`, `UpdateTextSpinPreset()`.
- `SettingParam.GetName/GetIcon/GetInputIcon/GetComment` : renvoie nos textes pour les lignes
  mappées, `""` pour les slots de clone non mappés.
- `UIAgent.InputDecide` : intercepte la confirmation sur la liste de la colonne de droite. Pour
  les items de spin : passer à l'option suivante. Pour les boutons : exécuter l'action.
- Bloquer toute persistance (`SaveSettingParams`, `SaveOther`, `RevertSettings`, etc.) et la
  détection de changement (`CheckChanges` -> 0, `EqualSettings` -> true) pendant que c'est actif.

**Quand préférer cette approche à la Technique 1 :** uniquement si vous avez véritablement besoin
d'une mise en page à deux colonnes (catégories à gauche, items à droite). Pour la plupart des
réglages, la Technique 1 est plus simple et plus fiable.

---

## 10. Étude de cas -- L'éditeur de couleurs

Un exemple concret de la Technique 1 (NativeOptions) poussé jusqu'à une véritable interface de
réglages en pleine profondeur : un éditeur de couleur HSV et de matériaux par emplacement pour les
costumes des personnages, ouvert directement depuis l'écran Modifier le personnage du jeu. Si la
Technique 1 ci-dessus vous a montré la mécanique, cette section montre jusqu'où elle peut monter en
puissance.

### Ouverture

Sur l'écran Modifier le personnage (Réglages du combattant), le guide en bas de la ligne Couleur
affiche une astuce « Edit Color ». Appuyez sur F (clavier) / A (manette), ou cliquez gauche sur la
ligne, pour l'ouvrir. L'éditeur compte sept pages : QUICK EDIT, EDIT COLORS, EDIT MATERIALS, EDIT
SQUARES, SAVE, SAVE AS, et RESET (ou RESET / ERASE quand une couleur « MC » est sélectionnée).
Changez de page avec A / E (L1 / R1), ou cliquez sur les flèches à côté du titre.

### Curseurs et valeurs

Les curseurs sont en HSV, pas en RGB : Teinte, Saturation et Luminosité, chacun sur une échelle de
0 à 255 (la Teinte de 0-255 correspond à 0-360 degrés). Les matériaux utilisent Blend / Rough /
Metal, chacun de 0 à 1000. Retour arrière (R3) réinitialise la ligne sélectionnée à sa valeur
**sauvegardée** -- pas à une valeur par défaut. C / V (Carré / Triangle) copient et collent le
nombre d'une ligne.

### Indicateur d'état non sauvegardé

Un point rouge en haut à gauche d'une ligne signifie que quelque chose en dessous d'elle dans
l'arbre diffère de l'état sauvegardé : d'abord le curseur modifié lui-même, puis son groupe, puis
les lignes racines, afin que vous puissiez toujours voir d'un coup d'œil où se trouve un changement
non sauvegardé. Il disparaît après SAVE, ou dès qu'une valeur est ramenée à sa position sauvegardée.

### Save / Save As / Reset / Erase

SAVE écrit les valeurs actuelles et laisse la fenêtre ouverte, en faisant passer le titre à « SAVE
OK! » comme confirmation. SAVE AS crée un nouvel emplacement « MC n » et rouvre l'éditeur dessus.
RESET revient à l'état d'origine -- les couleurs du jeu lui-même, ou un pack de couleurs installé
-- ou, sur une couleur « MC », à son dernier SAVE. ERASE supprime entièrement un emplacement « MC ».

### Quick Edit

Un curseur de teinte absolue par famille de couleurs. Les groupes de costumes propres au jeu se
rassemblent en sept familles, chacune nommée d'après son plus grand groupe : SKIN, HAIR, FACE, plus
les groupes propres à la tenue. La ligne de guide sous chaque ligne précise exactement quels
groupes elle va déplacer (« Changes: ... »).

### Emplacements de texture

Certains emplacements restent sur leur texture dans la couleur que vous consultez actuellement,
mais le jeu utilise bien une couleur unie pour ce même emplacement dans une autre couleur du
costume. Ceux-ci sont marqués « (texture) » dans la liste des emplacements. Déplacer le curseur
attribue à l'emplacement une couleur qui lui est propre (Retour arrière le ramène à la texture) ;
Generate Random couvre aussi les emplacements en texture.

### Liste des couleurs

Au-delà des couleurs numérotées propres au jeu, la liste peut contenir : **RW n**, des packs de
couleurs que les moddeurs déposent dans `data/SF6_ColorSpinExtra_data/colors/<Fighter>/` ; **MC n**,
vos propres couleurs sauvegardées ; et trois entrées de défilement : **LL1** (vêtements et accessoires défilent au hasard, cheveux /
peau / visage intacts), **LL2** (vêtements, accessoires et cheveux -- sourcils, barbe compris),
**LL3** (tout).

### Caméra de prévisualisation

Pendant que l'éditeur est ouvert, la caméra de prévisualisation est à vous : le glisser-gauche
tourne, le glisser-milieu déplace, et la molette (ou Page Up / Page Down) zoome. À la manette :
le stick droit tourne, L3 + stick droit déplace, R2 / L2 zoome. Des blocs d'astuces Zoom et Move
apparaissent à côté du bloc Rotation propre au jeu afin que le schéma de contrôle soit découvrable
sur place.

### Localisation

Le texte des menus suit le réglage de langue du jeu lui-même -- en, fr, ja, zh-Hans, plus it, de,
es, es-419, ru, pl, pt-BR, ko, zh-Hant, et ar -- et se met à jour en direct dès que vous le changez
depuis l'écran Options du jeu.

### Fichiers sources

| Module | Chemin | Rôle |
|---|---|---|
| SF6_ColorSpinExtra | `autorun/SF6_ColorSpinExtra.lua` | Injection dans la liste des couleurs (entrées RW/MC/LL) et éditeur natif de couleur/matériaux HSV |
| NativeLocale | [`autorun/func/NativeLocale.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/NativeLocale.lua) | Localisation du texte des menus, suit la langue du jeu |

---

## 11. Étude de cas -- Le menu de couleur du Drive Impact

Un second exemple concret de la Technique 1, cette fois réutilisé sur trois écrans différents avec
deux profondeurs de menu différentes.

### Où il s'ouvre

Le guide en bas affiche « X Edit Drive Impact Color » (X au clavier, Carré à la manette) à trois
endroits : l'écran Modifier le personnage, le popup « Character Settings » du menu pause
d'entraînement, et le panneau de couleur de sélection de personnage en VS / entraînement. Les deux
popups reçoivent un menu **simplifié** (Enabled + Preset seulement) ; Modifier le personnage reçoit
le menu complet décrit ci-dessous.

### Lignes

- **Enabled** -- Off / On / Follow. Follow reprend les deux carrés de la couleur que porte
  actuellement le personnage en combat ; rien d'autre n'a besoin d'être configuré. Pour une
  couleur du jeu, la paire est lue dans les données du jeu (`app.helper.hGUI.GetFighterCostumeColorData(fighter,
  costume, couleur)` renvoie un `app.FighterColorData` avec `Color00` / `Color01`, exactement les
  puces que peignent les écrans de sélection) ; pour une couleur sauvegardée, ce sont ses deux
  carrés. Le costume porté vient du chemin du fichier du contrôleur de couleurs
  (`esf027_003_CCVD.user` = Terry, costume 3).
- **Preset** -- un spin listant les préréglages partagés entre tous les personnages, puis les
  couleurs sauvegardées propres à ce personnage (« MC n » avec leurs deux carrés affichés en
  ligne), puis **LL** pour une palette qui défile.
- **Color 1** (la couleur principale -- éclaboussures et traînées d'impact) et **Color 2**
  (l'accent) ouvrent chacune une page HSV avec le même comportement de Retour arrière vers la
  valeur sauvegardée, copier/coller et point rouge que l'éditeur de couleurs (section 10).
- **SAVE** écrase le préréglage sélectionné -- ou, avec une couleur « MC n » sélectionnée à la
  place, écrit Color 1 / Color 2 directement dans les deux carrés de cette couleur. **SAVE AS**
  crée un nouveau préréglage (« DI n »). **RESET** revient aux couleurs de l'élément sélectionné ;
  sur un préréglage sauvegardé, la page propose à la place RESET / DELETE.

### Pas de prévisualisation sur Modifier le personnage

Le Drive Impact lui-même ne peut être déclenché qu'en combat réel, donc les couleurs que vous
choisissez ici ne s'affichent pas sur le modèle de prévisualisation de l'écran Modifier le
personnage -- elles apparaissent en combat. Avec LL sélectionné, la palette continue de défiler
pour le reste du combat.

### Par joueur

Les réglages sont par personnage **et par camp**. Le menu édite le camp depuis lequel il a été
ouvert (le titre l'indique : « LUKE - P2 »), et `<Fighter>.json` contient deux réglages, `p1` et
`p2`. Avec deux personnages différents, chaque camp écrit ses propres providers d'effet, donc
P1 Off / P2 On marche tel quel. En miroir, les deux Drive Impact lisent les **mêmes** providers :
les couleurs sont alors écrites à l'instant où le Drive Impact d'un camp démarre (`act_st` 11 du
joueur), avec le réglage de ce camp -- ses couleurs, ou la palette du jeu s'il est Off.

### Données

`data/SF6_DIRecolor_data/<Fighter>.json` (`{ p1 = ..., p2 = ... }`) et `_presets.json`
contiennent tout ce que ce menu édite ; les mêmes fichiers sont aussi éditables depuis le panneau
ImGui « DI Recolor (P1 / P2) », dont le nœud Debug affiche la paire en cours de choix sur un écran
de sélection (« colour to apply ») à côté de la dernière paire appliquée en combat.

### Fichiers sources

| Module | Chemin | Rôle |
|---|---|---|
| DIColorMenu | `autorun/func/DIColorMenu.lua` | Le menu natif de couleur du Drive Impact décrit dans cette section |
| SF6_DIRecolor | `autorun/SF6_DIRecolor.lua` | Moteur de couleur du Drive Impact et données par personnage ; expose `_G.SF6_DIRecolor` pour que le menu puisse lire et écrire |

---

## 12. Disséquer un menu du jeu soi-même

Les techniques de ce guide ont été trouvées en sondant l'UI du jeu en cours d'exécution avec des
scripts Lua jetables. Voici le processus.

### Outils

- **`sf6.py`** (dans `agent/sf6.py`) : un script Python qui dialogue avec le serveur websocket de
  REFramework. Commandes clés :
  - `sf6.py run agent/tmp/my_probe.lua --wait my_probe` -- déploie un script de sonde et attend
    qu'il écrive `data/my_probe.json`.
  - `sf6.py shot` -- prend une capture d'écran (enregistrée dans `agent/shots/`).
  - `sf6.py reset` -- réinitialise tous les scripts (efface les hooks des sondes).
  - `sf6.py logs` -- lit `re2_framework_log.txt` à la recherche d'erreurs.
  - `sf6.py state` -- affiche l'état actuel du jeu (flow, mode, personnages, positions, HP).
  - `sf6.py tap ESC` / `sf6.py tap E` / `sf6.py tap A` -- envoie des appuis de touche pour naviguer
    dans les menus.
- **Scripts de sonde** (dans `agent/tmp/`) : de courts fichiers Lua qui déversent des données en
  JSON puis se terminent.

### Processus de sondage

1. **Naviguez jusqu'au menu** que vous voulez inspecter : `sf6.py nav training`, puis
   `sf6.py tap ESC` pour ouvrir le menu pause, `sf6.py tap E`/`sf6.py tap A` pour changer d'onglet.

2. **Énumérez les UIAgents** pour trouver qui possède le menu :

```lua
-- agent/tmp/probe_agents.lua
local out = {}
local mgr = sdk.get_managed_singleton("app.UIAgentManager")
local list = mgr:get_field("_Entries")
for i = 0, list:call("get_Count") - 1 do
    local agent = list:call("get_Item", i).Agent
    local go = agent and agent:call("get_GameObject")
    out[#out + 1] = {
        name = go and tostring(go:call("get_Name")) or "?",
        type = agent and agent:get_type_definition():get_full_name() or "?"
    }
end
json.dump_file("__OUT__.json", out)
```

3. **Extrayez un arbre de contrôles** une fois l'agent identifié :

```lua
-- agent/tmp/probe_ctrl_tree.lua
local function dump(ctrl, depth)
    if not ctrl or depth > 20 then return nil end
    local r = {
        name = tostring(ctrl:call("get_Name")),
        type = ctrl:get_type_definition():get_name(),
        visible = ctrl:call("get_Visible"),
        size = { w = ctrl:call("get_Size").w, h = ctrl:call("get_Size").h }
    }
    local children = {}
    local c = ctrl:call("get_Child")
    while c do
        children[#children + 1] = dump(c, depth + 1)
        c = c:call("get_Next")
    end
    if #children > 0 then r.children = children end
    return r
end
-- ... find the agent, get_ControlMain(), dump(main, 0) ...
json.dump_file("__OUT__.json", tree)
```

4. **Extrayez les définitions de types** (champs et méthodes) des objets intéressants :

```lua
local function dump_type(td)
    local fields, methods = {}, {}
    for _, f in ipairs(td:get_fields()) do
        fields[#fields + 1] = { name = f:get_name(), type = f:get_type():get_full_name() }
    end
    for _, m in ipairs(td:get_methods()) do
        local params = {}
        for _, p in ipairs(m:get_param_types()) do params[#params + 1] = p:get_full_name() end
        methods[#methods + 1] = { name = m:get_name(), params = params, ret = m:get_return_type():get_full_name() }
    end
    return { name = td:get_full_name(), fields = fields, methods = methods }
end
```

5. **Tracez un protocole par hooks** pour voir ce que le jeu appelle sur ses flows :

```lua
-- Hook every method of a Param type, log which ones fire
local td = sdk.find_type_definition("app.UIFlowOptionBGDialog.Param")
for _, m in ipairs(td:get_methods()) do
    pcall(function()
        sdk.hook(m, function(args)
            log.info("PARAM CALL: " .. m:get_name())
        end, function(rv) return rv end)
    end)
end
```

> **Attention :** réinitialisez les scripts entre deux sondages par hooks (`sf6.py reset`). Des
> hooks d'une sonde précédente qui ne sont plus répondus peuvent provoquer des lignes vides, des
> callbacks morts, ou des crashs.

### Pièges

- `System.Int32[].GetValue(i)` renvoie `nil` sur certains builds de REFramework (le build
  websocket LL5271). Essayez `get_element(i)`, des lectures mémoire brutes
  (`read_dword(0x20 + 4*i)`), ou l'opérateur d'index `array[i]`.
- Les textes GUID `hMsg` enregistrés par un chargement de script précédent meurent au Reset
  Scripts. Si vous sondez avec de faux GUID, ils seront vides après une réinitialisation jusqu'à
  ce que la sonde les réenregistre.
- Les scripts de sonde vont dans `agent/tmp/`, jamais dans `autorun/`. Les scripts dans
  `autorun/` se chargent automatiquement au démarrage et ne sont pas réinitialisés par
  `sf6.py reset` ; les scripts dans des sous-dossiers d'`autorun/` ne sont jamais rechargés par
  Reset Scripts.

---

## 13. Dépannage

| Symptôme | Cause | Correctif |
|---|---|---|
| **Écran noir** après ouverture/fermeture de la fenêtre | Animation de fondu figée sous une pause maintenue | Définir `<ImmediateFade>k__BackingField = true` sur `CreatedObject` (section 5). Relâcher la pause si le dialogue n'a pas disparu après 30 ticks. |
| **RIP 0** (crash de pointeur nul) après changement du contenu de la fenêtre | Repeuplement d'une page de dialogue ouverte (Règle 3) | Faire `End()` sur le dialogue, attendre que l'agent `OptionDialog` disparaisse, puis `Start()` un nouveau. |
| **AV dans set_Message** | Écriture dans un contrôle `via.gui.Text` libéré | Vider tous les caches à la pause/ouverture de fenêtre (Règle 2). Ne jamais écrire pendant les transitions de pause. |
| Ligne vide avec **icône de cercle barré** | `GetIsActive` non répondu pour notre `FuncType` | Hooker `TrainingMenuFunc.GetIsActive` : renvoyer `1` pour votre FuncType. |
| **Ligne non focalisable** dans le menu pause | `_FuncType` absent de l'énumération attendue par le jeu | Utiliser `345` (DYNAMIC) de façon cohérente. S'assurer que `IsEnabled = true` sur le `TrainingMenuData`. |
| **Texte vide** dans une ligne de menu | GUID non enregistré (premier chargement) ou perdu après Reset Scripts | Réenregistrer les GUID dans `re.on_script_reset` ou au moment de la construction. Vérifier que `message_guid()` a été appelé avant la création de l'unité. |
| **Popup « Restore Default Settings? »** à l'appui sur un bouton | Le bouton utilise `EventType.SettingReset` sans interception de la décision | Hooker `GetFocusDecideEventType` : renvoyer `Invalid (0)` pour les TypeId de vos boutons. |
| **14e ligne coupée** dans Basic Settings | `_ViewSize.h` de la vue de défilement trop grand | Écrire `_ViewSize.h = 745` dans `UIPartsGroupScroll` pendant que le menu est ouvert. |
| **La valeur revient à sa valeur par défaut** à l'ouverture de la fenêtre | Le `LoadValueEvent` du jeu se déclenche pour votre TypeId | Hooker `OptionValueUnit.LoadValueEvent` : ignorer pour vos TypeId. |
| La fenêtre s'ouvre mais **le combat n'est pas en pause** | Mauvais `PauseType` ou pause refusée | Utiliser le type `8` (`BATTLE_MENU_PAUSE`). Vérifier que vous n'êtes pas déjà dans un état de pause différent. |
| **La fenêtre d'options s'ouvre en quittant le menu pause** | `OpenMenu` non bloqué pendant les frames de grâce | Hooker `TrainingManager.OpenMenu` : ignorer pendant ~20 frames après la fermeture de votre fenêtre. |
| **Fuite mémoire** (mémoire Lua croissante) | `pcall(function() ... end)` sur des chemins chauds | Remplacer par `pcall(named_func, args)` (Règle 5). |
| **Pics de frame** toutes les N secondes | `fs.glob` sur un timer | Déplacer les appels `fs.glob` uniquement dans le chemin d'ouverture de fenêtre (Règle 7). |
| Le spin du menu pause affiche une **valeur incorrecte** après un changement de mode | Le getter renvoie un index périmé | Reconstruire et réinstaller les onglets quand le mode change de façon externe. |
| **Mauvaise couleur** du texte NativeHud | Utilisation de RGB au lieu d'ABGR | Toutes les couleurs `via.gui` sont en **ABGR** (alpha dans l'octet de poids fort, puis bleu). `0xFF0000FF` = rouge opaque. |

---

## 14. Annexe -- Référence des types et énumérations

### Énumérations app.Option

| Énumération | Valeurs utilisées |
|---|---|
| `app.Option.UnitInputType` | `SpinText` (spin avec flèches), `Slider` (barre horizontale), `Button_Type1` (sous-menu / aligné à gauche), `Button_Type2` (action / centré), `Button_Type0` (popup radio, ne fonctionne pas pour des ID personnalisés) |
| `app.Option.DecideEventType` | `OpenSubMenu` (entre dans le sous-menu), `OpenBattleHudSetting` (ouvre la fenêtre HUD), `SettingReset` (bouton / restauration), `OpenRadioButton` (liste popup, ne fonctionne pas pour des ID personnalisés), `Invalid` (0, ne fait rien) |
| `app.Option.SettingDataType` | `Value` (possède une valeur numérique avec min/max) |
| `app.Option.TabType` | `General` (l'onglet où réside « SF6 Tools ») |

### Types app.training

| Type | Champs clés |
|---|---|
| `TrainingMenuData` | `_Type` (0=TEXT_ONLY, 1=SPIN), `_FuncType` (1..8 d'origine, 345 le nôtre), `_MessageID` (GUID), `_GuideMessage` (GUID), `_ChildData` (TrainingMenuData[]), `DynamicChildData` (List), `IsEnabled`, `_Interval`, `_GuidIcon`, `VisibleCase` |
| `TrainingMenuFunc` | Méthodes : `ViewUpdate`, `GetIsActive`, `GetOptionText`, `GetOptionText2`, `GetOptionIndex`, `IsValueType`, `GetVisibleCase`, `IsChangedValue`, `Function` |
| `TrainingPauseMenuUserData` | `_MenuData` : `TrainingMenuData[]` (un par onglet) |

### app.UIFlowOptionBGDialog

| Type | Membres clés |
|---|---|
| `SettingData` | `TopUnit`, `SupportMode` (32), `UseBattleHudBG` (false pour nos fenêtres), `PlayerIndex` |
| `Param` | `GetFocusUnit()`, `GetFocusDecideEventType()`, `SetupDispUnits()`, `FlowEvent_ResetCurrentUnits()`, `CreatedObject()`, `OptionUnits` (tableau de parts) |
| Statique | `Start(SettingData, bool)` -> `IUIFlowHandle` |

### PauseManager

| Type de pause | Valeur | Ce que ça fait |
|---|---|---|
| `DIALOG_PAUSE` | 1 | Met en pause uniquement les objets de portée dialogue (pas le combat) |
| `BATTLE_MENU_PAUSE` | 8 | Met le combat en pause (comme le vrai menu pause). Bit = 64 dans `_CurrentPauseTypeBit`. |
| `BATTLE_TRAINING_PAUSE` | 11 | Refusé hors du contexte du menu d'entraînement |

### EConfigInitLayout (position de départ)

| Nom | Valeur |
|---|---|
| `CENTER` | 0 |
| `RIGHT` | 1 |
| `LEFT` | 2 |
| `MANUAL` | 3 |

### Fichiers sources

Tous les modules ci-dessous sont publiés dans [`guide/lua/func/`](https://github.com/Wael3rd/SF6_Tools/tree/main/guide/lua/func). Copiez-les dans `reframework/autorun/func/` ; `NativeOptions.lua` est le module de base (`NativePauseMenu`, `NativeDialog` et `NativeShortcuts` en dépendent).

| Module | Chemin | Rôle |
|---|---|---|
| NativeOptions | [`autorun/func/NativeOptions.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/NativeOptions.lua) | Fenêtre du dialogue Options (Technique 1) |
| NativePauseMenu | [`autorun/func/NativePauseMenu.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/NativePauseMenu.lua) | Lignes et onglets du menu pause (Technique 2) |
| NativeHud | [`autorun/func/NativeHud.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/NativeHud.lua) | Panneau de dégâts et minuteur (Technique 3) |
| NativePopup | [`autorun/func/NativePopup.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/NativePopup.lua) | Popups à éléments empruntés (Technique 4) |
| NativeShortcuts | [`autorun/func/NativeShortcuts.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/NativeShortcuts.lua) | Substitution de Shortcut Settings (Technique 5A) |
| NativeDialog | [`autorun/func/NativeDialog.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/NativeDialog.lua) | Détournement du dialogue KeyConfig (Technique 5B) |
| NativeTopBar | [`autorun/func/NativeTopBar.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/NativeTopBar.lua) | Barre de sélection de mode (éléments empruntés, désactivée) |
| NativeBottomBar | [`autorun/func/NativeBottomBar.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/NativeBottomBar.lua) | Barre de boutons d'action (expérimentale, désactivée) |
| GameState | [`autorun/func/GameState.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/GameState.lua) | Détection de la pause (`GS.in_pause_menu`) |
| Training_ScriptManager | `autorun/Training_ScriptManager.lua` | Orchestrateur (changement de mode, enregistrement) |

---

## 15. Crédits

- **Wael3rd** -- Tous les modules d'UI native (NativeOptions, NativePauseMenu, NativeHud,
  NativePopup, NativeShortcuts, NativeDialog, NativeTopBar, NativeBottomBar), le processus de
  sondage, l'investigation des crashs, et ce guide.
- **mfyk** -- La technique d'injection dans OptionManager (OptionSettingUnit dans UnitLists, hook
  de texte à faux GUID, fenêtre OpenBattleHudSetting). Partagée publiquement en 2026, usage public
  autorisé. Le fondement de la Technique 1.
- **alphaZomega** -- Outillage REFramework et base de connaissances utilisés pendant le
  développement.
- **cdjay** -- Contributions à la codebase de SF6 Tools (catalogues BCM, notation moderne, format
  d'affichage des commandes) référencées dans le Training_ScriptManager.
- **LL5271** -- Le fork REFramework-Websockets (le build `dinput8.dll` utilisé ici) : son serveur websocket
  rend possible le processus de sondage à distance (`sf6.py run / state / shot`) et toutes les dissections
  de ce guide.
- **praydog** -- REFramework lui-même.

---

*Changelog : 2026-09-03 -- Ajout des sections 10-11 (éditeur de couleurs, menu de couleur du Drive
Impact). 2026-08-31 -- Version initiale.*
