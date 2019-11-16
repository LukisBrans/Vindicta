
#define OOP_INFO
#define OOP_WARNING
#define OOP_ERROR
#define OFSTREAM_FILE "buildUI.rpt"
#include "..\..\OOP_Light\OOP_Light.h"
#include "BuildUI_Macros.h"
#include "..\..\GlobalAssert.hpp"
#include "..\defineddikcodes.inc"

#define TIME_FADE_TT 0.84

/*
Class: BuildUI
Initializes the build menu UI, handles opening and closing, and handles the building itself

sound place: 
playSound ["3DEN_notificationDefault", false];

Author: Marvis
*/

#define pr private

g_BuildUI = nil;

#define __RESOURCE_SOURCE_LOCATION 0
#define __RESOURCE_SOURCE_INVENTORY 1

CLASS("BuildUI", "")

	VARIABLE("activeBuildMenus");
	VARIABLE("EHKeyDown");

	VARIABLE("isMenuOpen");					// is the menu itself open?
	VARIABLE("currentCatID");				// currently selected category index
	VARIABLE("currentItemID");				// currently selected item index
	VARIABLE("UICatTexts");					// array of strings for category names
	VARIABLE("UIItemTexts");				// array of strings for item names in current category
	VARIABLE("TimeFadeIn");					// fade in time for category change UI effect
	VARIABLE("TimeFadeInTT");				// fade in time for tool tip text
	VARIABLE("ItemCatOpen");				// true if item list should be shown
	VARIABLE("playerEvents");				// handles to player event handlers when ui is open

	// object variables
	VARIABLE("activeObject");				// Object currently highlighted
	VARIABLE("selectedObjects");			// Objects that will be part of move actions
	VARIABLE("movingObjectGhosts");			// Objects currently being moved (includes selected and active when move starts)
	VARIABLE("isMovingObjects");			// Are objects being moved at the moment?

	// carousel
	VARIABLE("previousItemID");				// Previous item selected so we can animate things 
	VARIABLE("animStartTime");				// Animation start time, used to animated carousel
	VARIABLE("animCompleteTime");			// Time animation will complete (could be in the past, meaning the animation is complete)
	VARIABLE("carouselObjects");			// Objects in the carousel (vehicles)

	VARIABLE("rotation");					// Rotational offset in build and carousel
	VARIABLE("targetRotation");				// Target rotational offset for smooth animation
	VARIABLE("lastFrameTime");				// Time of last frame

	// Source of resources: unit's inventory or location's resources
	VARIABLE("resourceSource");

	METHOD("new") {
		params [P_THISOBJECT];
		OOP_INFO_0("'new' method called. ====================================");

		if(!(isNil("g_BuildUI"))) exitWith {
			OOP_ERROR_0("BuildUI already initialized! Make sure to delete it before trying to initialize it again!");
		};

		g_BuildUI = _thisObject;
		T_SETV("currentCatID", 0);  			// index in Categories class
		T_SETV("currentItemID", 0);  			// index in the current Category class
		T_SETV("TimeFadeIn", 0);
		T_SETV("TimeFadeInTT", 0);
		T_SETV("UICatTexts", []);

		pr _args = ["", "", "", "", ""];
		T_SETV("UIItemTexts", _args);

		T_SETV("ItemCatOpen", false);			// true if item list submenu is open
		T_SETV("playerEvents", []);			// true if item list submenu is open

		T_SETV("activeBuildMenus", []);
		T_SETV("EHKeyDown", nil);

		T_SETV("isMenuOpen", false);
		T_SETV("activeObject", []);
		T_SETV("selectedObjects", []);
		T_SETV("movingObjectGhosts", []);
		T_SETV("isMovingObjects", false);

		T_SETV("previousItemID", 0);
		T_SETV("animStartTime", 0);
		T_SETV("animCompleteTime", 0);
		T_SETV("carouselObjects", []);

		T_SETV("rotation", 0);
		T_SETV("targetRotation", 0);
		T_SETV("lastFrameTime", time);

		T_CALLM("makeCatTexts", [0]); 			// initialize UI category strings

		T_SETV("resourceSource", __RESOURCE_SOURCE_LOCATION);

	} ENDMETHOD;

	METHOD("delete") {
		params [P_THISOBJECT];

		T_CALLM0("closeUI");

		OOP_INFO_1("Player %1 build UI destroyed.", name player);

		if !(isNil "g_rscLayerBuildUI") then {
			g_rscLayerBuildUI = nil;
		};

		g_BuildUI = nil;
	} ENDMETHOD;

	METHOD("addOpenBuildMenuAction") {
		params [P_THISOBJECT, "_object"];

		OOP_INFO_1("Adding Open Build Menu action to %1.", _object);

		pr _id = _object addaction [format ["<img size='1.5' image='\A3\ui_f\data\GUI\Rsc\RscDisplayMain\menu_options_ca.paa' />  %1", "Open Build Menu"], {  
			params ["_target", "_caller", "_actionId", "_arguments"];
			_arguments params [P_THISOBJECT];
			T_CALLM0("openUI");
		}, [_thisObject]];

		T_GETV("activeBuildMenus") pushBack [_object, _id];
	} ENDMETHOD;

	METHOD("removeAllActions") {
		params [P_THISOBJECT];

		OOP_INFO_0("Removing all active Open Build Menu actions.");

		{
			_x params ["_object", "_id"];
			_object removeAction _id;
		} forEach T_GETV("activeBuildMenus");
	} ENDMETHOD;

	// _source: 0 - building from location, 1 - building from our inventory, -1 - don't care and keep building from anywhere
	METHOD("openUI") {
		params [P_THISOBJECT, ["_source", -1]];

		OOP_INFO_0("'openUI' method called.");

		T_SETV("resourceSource", _source);

		if(T_GETV("isMenuOpen")) exitWith {};
		T_SETV("isMenuOpen", true);

		// update UI text and categories, this is a separate function due to https://feedback.bistudio.com/T123355
		["BuildUIUpdate", "onEachFrame", { 
			CALLM0(g_BuildUI, "UIFrameUpdate");
		}] call BIS_fnc_addStackedEventHandler;

		T_CALLM0("enterMoveMode");

		if(isNil "g_rscLayerBuildUI") then {
			g_rscLayerBuildUI = ["rscLayerBuildUI"] call BIS_fnc_rscLayer;	// register build UI layer
		};

		g_rscLayerBuildUI cutRsc ["BuildUI", "PLAIN", -1, false]; // blend in UI

		pr _EHKeyDown = (findDisplay 46) displayAddEventHandler ["KeyDown", {
			params ["_control", "_dikCode", "_shiftState", "_ctrlState", "_altState"];
			if(isNil "g_BuildUI") exitWith {
				_EHKeyDown = (findDisplay 46) displayRemoveEventHandler ["KeyDown", _this select 0];
			};
			CALLM4(g_BuildUI, "onKeyHandler", _dikCode, _shiftState, _ctrlState, _altState);
		}];

		OOP_INFO_1(" Saved key down EH ID: %1", _EHKeyDown);
		T_SETV("EHKeyDown", _EHKeyDown);

		pr _playerEvents = [
			player addEventHandler ["Dammaged", { CALLM0(g_BuildUI, "closeUI"); }],
			player addEventHandler ["GetInMan", { CALLM0(g_BuildUI, "closeUI"); }],
			player addEventHandler ["Killed", { CALLM0(g_BuildUI, "closeUI"); }],
			player addEventHandler ["InventoryOpened", { CALLM0(g_BuildUI, "closeUI"); }]
		];

		T_SETV("playerEvents", _playerEvents);
		
		// Put away weapon
		player action ["SWITCHWEAPON", player, player, -1];

		// TODO: Add player on death event to hide UI and drop held items etc.
		// Also for when they leave camp area.
	} ENDMETHOD;

	STATIC_METHOD("getInstanceOpenUI") {
		params [P_THISOBJECT, P_NUMBER("_source")];
		pr _thisObject = g_BuildUI;
		if (isNil "_thisObject") exitWith {};
		CALLM1(_thisObject, "openUI", _source);
	} ENDMETHOD;

	METHOD("UIFrameUpdate") {
		params [P_THISOBJECT];

		// Bail if we can't build any more here
		if ((!CALLSM1("PlayerMonitor", "canUnitBuildAtLocation", player)) && (T_GETV("resourceSource") != -1)) exitWith {
			T_CALLM0("closeUI");
		};

		pr _UICatTexts = GETV(g_BuildUI, "UICatTexts");
		pr _UIItemTexts = GETV(g_BuildUI, "UIItemTexts");
		pr _TimeFadeIn = GETV(g_BuildUI, "TimeFadeIn");
		pr _TimeFadeInTT = GETV(g_BuildUI, "TimeFadeInTT");
		pr _ItemCatOpen = GETV(g_BuildUI, "ItemCatOpen");
		pr _color = [1, 1, 1, 1] call BIS_fnc_colorRGBAtoHTML;
		pr _isMovingObj = GETV(g_BuildUI, "isMovingObjects");

		pr _display = uinamespace getVariable "buildUI_display";

		if (displayNull != _display) then {

			if (_TimeFadeInTT > time) then {
				pr _alpha = (-1 * ((_TimeFadeInTT) - (time + TIME_FADE_TT))) + 0.02;
				_color = [1, 1, 1, _alpha] call BIS_fnc_colorRGBAtoHTML;

			}; 

			// item menu
			if (_ItemCatOpen) then { 

				// tooltips
				(_display displayCtrl IDC_TOOLTIP1) ctrlsetStructuredText parseText format ["<t color='%1' align='center' valign='bottom'>TAB:</t> <t color='%1' align='center' valign='bottom' font='RobotoCondensedLight'> BUILD/PICK UP/DROP OBJECTS</t>", _color];
				(_display displayCtrl IDC_TOOLTIP2) ctrlsetStructuredText parseText format ["<t color='%1' align='center' valign='bottom'>Q/E:</t> <t color='%1' align='center' valign='bottom' font='RobotoCondensedLight'> ROTATE OBJECT</t>", _color];

				(_display displayCtrl IDC_ITEXTBG) ctrlSetBackgroundColor [0,0,0,0.6];
				(_display displayCtrl IDC_ITEXTL2) ctrlSetText format ["%1", (_UIItemTexts select 0)];
				(_display displayCtrl IDC_ITEXTL1) ctrlSetText format ["%1", (_UIItemTexts select 1)];
				(_display displayCtrl IDC_ITEXTC) ctrlSetText format ["%1", (_UIItemTexts select 2)];
				(_display displayCtrl IDC_ITEXTR1) ctrlSetText format ["%1", (_UIItemTexts select 3)];
				(_display displayCtrl IDC_ITEXTR2) ctrlSetText format ["%1", (_UIItemTexts select 4)];

				{
					(_display displayCtrl _x) ctrlShow true;
					(_display displayCtrl _x) ctrlCommit 0;
				} forEach [IDC_ITEXTR2, IDC_ITEXTR1, IDC_ITEXTC, IDC_ITEXTL1, IDC_ITEXTL2, IDC_ITEXTBG];

			} else { 
				// tooltips
				(_display displayCtrl IDC_TOOLTIP1) ctrlsetStructuredText parseText format ["<t color='%1' align='center' valign='bottom'>TAB:</t> <t color='%1' align='center' valign='bottom' font='RobotoCondensedLight'> BUILD/PICK UP/DROP OBJECTS</t>", _color];
				(_display displayCtrl IDC_TOOLTIP2) ctrlsetStructuredText parseText format ["<t color='%1' align='center' valign='bottom'>BACKSPACE: </t> <t color='%1' align='center' valign='bottom' font='RobotoCondensedLight'> CLOSE MENU</t> <t color='%1' align='center' valign='bottom'>  |  ARROW KEYS: </t> <t color='%1' align='center' valign='bottom' font='RobotoCondensedLight'> NAVIGATE MENU</t>", _color];

				(_display displayCtrl IDC_ITEXTBG) ctrlSetBackgroundColor [0,0,0,0];
				{
					(_display displayCtrl _x) ctrlShow false;
					(_display displayCtrl _x) ctrlCommit 0;
				} forEach [IDC_ITEXTR2, IDC_ITEXTR1, IDC_ITEXTC, IDC_ITEXTL1, IDC_ITEXTL2, IDC_ITEXTBG];
			};

			if (_isMovingObj) then { 
				(_display displayCtrl IDC_TOOLTIP1) ctrlsetStructuredText parseText format ["<t color='%1' align='center' valign='bottom'>TAB:</t> <t color='%1' align='center' valign='bottom' font='RobotoCondensedLight'> BUILD/PICK UP/DROP OBJECTS</t>", _color];
				(_display displayCtrl IDC_TOOLTIP2) ctrlsetStructuredText parseText format ["<t color='%1' align='center' valign='bottom'>Q/E:</t> <t color='%1' align='center' valign='bottom' font='RobotoCondensedLight'> ROTATE OBJECT</t>", _color];
			};

			// cat menu
			(_display displayCtrl IDC_TEXTL2) ctrlSetText format ["%1", (_UICatTexts select 0)];
			(_display displayCtrl IDC_TEXTL1) ctrlSetText format ["%1", (_UICatTexts select 1)];
			(_display displayCtrl IDC_TEXTC) ctrlSetText format ["%1", (_UICatTexts select 2)];

			// button highlight effect
			if (_TimeFadeIn > time) then { 
				(_display displayCtrl IDC_TEXTC) ctrlSetBackgroundColor [1, 1, 1, (_TimeFadeIn - time)];
			} else { (_display displayCtrl IDC_TEXTC) ctrlSetBackgroundColor [1, 1, 1, 0]; };

			(_display displayCtrl IDC_TEXTR1) ctrlSetText format ["%1", (_UICatTexts select 3)];
			(_display displayCtrl IDC_TEXTR2) ctrlSetText format ["%1", (_UICatTexts select 4)];

			{
				(_display displayCtrl _x) ctrlCommit 0;
			} forEach [IDC_TEXTL2, IDC_TEXTL1, IDC_TEXTC, IDC_TEXTR1, IDC_TEXTR2];

			T_CALLM0("updateCarouselOffsets");
		};

		T_PRVAR(lastFrameTime);
		T_PRVAR(rotation);
		T_PRVAR(targetRotation);

		pr _rotationVec = [1, _rotation, 0] call CBA_fnc_polar2vect;
		pr _targetRotationVec = [1, _targetRotation, 0] call CBA_fnc_polar2vect;
		pr _rate = sqrt (_rotationVec distance _targetRotationVec) * 0.25;
		pr _finalVec = [];

		for "_i" from 0 to 2 do 
		{
			_finalVec pushBack ([_rotationVec select _i, _targetRotationVec select _i, _rate, time - _lastFrameTime] call BIS_fnc_lerp);
		};
		T_SETV("rotation", (_finalVec call CBA_fnc_vect2Polar) select 1);

		// pr _newRotation = _rotation + _rate;
	} ENDMETHOD;

	METHOD("onKeyHandler") {
		params [P_THISOBJECT, "_dikCode", "_shiftState", "_ctrlState", "_altState"];

		switch (_dikCode) do { // keyname _dikCode is language dependent!!
			default { false; };

			case DIK_TAB: { 
				// TODO: Currently we don't handle key up so holding down Tab will directly go from 
				// select to place to actually dropping the object if you hold it down too long.
				// Handle KeyUp as well to emulate KeyPress like behaviour for Tab and Backspace.
				playSound ["clicksoft", false];
				T_CALLM0("handleActionKey");
				true; // disables default control 
			};

			case DIK_Q: { 
				playSound ["clicksoft", false];
				pr _rot = if(_shiftState) then { 90 } else { 15 };
				T_CALLM1("rotate", _rot);
				// TODO: rotate object counter-clockwise
				true; // disables default control 
			};

			case DIK_E: { 
				playSound ["clicksoft", false];
				pr _rot = if(_shiftState) then { -90 } else { -15 };
				T_CALLM1("rotate", _rot);
				// TODO: rotate object clockwise
				true; // disables default control 
			};

			case DIK_UP: { 
				if !(T_GETV("isMovingObjects")) then {
					playSound ["clicksoft", false];
					T_CALLM0("openItems"); true; 
				};
			};

			case DIK_DOWN: { 
				playSound ["clicksoft", false];
				T_CALLM0("closeItems"); true; 
			};

			case DIK_LEFT: { 
				playSound ["clicksoft", false];
				T_CALLM1("navLR", -1); 
				true; 
			};

			case DIK_RIGHT: { 
				playSound ["clicksoft", false];
				T_CALLM1("navLR", 1);
				true; 
			};

			// close build menu
			case DIK_BACKSPACE: {
				playSound ["clicksoft", false];
				if(T_GETV("isMovingObjects")) then {
					T_CALLM0("cancelMovingObjects");
				} else {
					T_CALLM0("closeUI"); 
				};
				true; 
			};

			case DIK_DELETE: { 

				CALLSM0("BuildUI", "delActiveObject");
				true; // disables default control 
			};
		};
	} ENDMETHOD;

	METHOD("closeUI") {
		params [P_THISOBJECT];

		OOP_INFO_0("'closeUI' method called. ====================================");
		
		if !(T_GETV("isMenuOpen")) exitWith {};

		// Reset everything that might be active
		T_CALLM0("cancelMovingObjects");
		T_CALLM0("clearCarousel");
		T_CALLM0("exitMoveMode");

		g_rscLayerBuildUI cutRsc ["Default", "PLAIN", -1, false]; // hide UI

		pr _EHKeyDown = T_GETV("EHKeyDown");
		OOP_INFO_1(" Recovered keyDown EH ID: %1", _EHKeyDown);
		(findDisplay 46) displayRemoveEventHandler ["KeyDown", _EHKeyDown];

		T_SETV("EHKeyDown", nil);

		// close item category and reset selected item ID to avoid problems
		T_SETV("currentItemID", 0);
		T_SETV("ItemCatOpen", false);

		["BuildUIUpdate", "onEachFrame"] call BIS_fnc_removeStackedEventHandler;
		OOP_INFO_0("Removed display event handler!");

		T_SETV("isMenuOpen", false);
		T_PRVAR(playerEvents);

		player removeEventHandler["Dammaged", _playerEvents select 0];
		player removeEventHandler["GetInMan", _playerEvents select 1];
		player removeEventHandler["Killed", _playerEvents select 2];
		player removeEventHandler["InventoryOpened", _playerEvents select 3];

		T_SETV("playerEvents", []);
	} ENDMETHOD;

	METHOD("handleActionKey") {
		params [P_THISOBJECT];
		OOP_INFO_0("'handleActionKey' method called");

		T_PRVAR(ItemCatOpen);
		OOP_INFO_1("'handleActionKey' %1", _ItemCatOpen);
		if (_ItemCatOpen) then {
			pr _currentClassName = T_CALLM0("currentClassname");
			OOP_INFO_1("'handleActionKey' creating new %1", _currentClassName);
			T_CALLM0("closeItems");
			T_CALLM1("createNewObject", _currentClassName);
		} else {
			if (T_GETV("isMovingObjects")) then {
				T_CALLM0("dropHere");
			} else {
				T_SETV("rotation", 0);
				T_SETV("targetRotation", 0);
				T_CALLM0("moveSelectedObjects");
			};
		};
	} ENDMETHOD;

	METHOD("rotate") {
		params [P_THISOBJECT, "_amount"];
		OOP_INFO_1("'rotate' method called _amount = %1", _amount);
		T_PRVAR(targetRotation);
		T_SETV("targetRotation", _targetRotation + _amount);
	} ENDMETHOD;

	// opens item list UI element
	METHOD("openItems") {
		params [P_THISOBJECT];
		OOP_INFO_0("'openItems' method called");
		T_SETV("ItemCatOpen", true);
		T_SETV("currentItemID", 0);
		T_SETV("TimeFadeInTT", (time+TIME_FADE_TT));
		T_SETV("rotation", 0);
		T_SETV("targetRotation", 0);

		T_CALLM("makeItemTexts", [0]); // create item list display texts

		T_CALLM0("createCarousel");
		T_CALLM0("exitMoveMode");
	} ENDMETHOD;

	// closes item list UI element
	METHOD("closeItems") {
		params [P_THISOBJECT];
		OOP_INFO_0("'closeItems' method called");
		T_SETV("ItemCatOpen", false);
		//T_SETV("currentItemID", 0);
		T_SETV("TimeFadeInTT", (time+TIME_FADE_TT));
		T_CALLM0("clearCarousel");
		T_CALLM0("enterMoveMode");
	} ENDMETHOD;

	/* Description: Navigate left or right in either category or item list on the UI

		Parameter: Number
		(+)1: array index plus 1 (right)
		-1: array index minus 1 (left)

		current category index + _num = new index
	*/
	METHOD("navLR") {
		params [P_THISOBJECT, "_num"];

		OOP_INFO_1("'navLR' method called: %1", _num);
		pr _itemCatOpen = GETV(g_BuildUI, "ItemCatOpen");
		pr _currentCatID = T_GETV("currentCatID"); // currently selected category

		if (_itemCatOpen) then { 
			pr _currentItemID = T_GETV("currentItemID");
			T_SETV("previousItemID", _currentItemID); 
			T_SETV("animStartTime", time); 
			T_SETV("animCompleteTime", time + 0.2); 
			// How many items in the currently selected category
			pr _itemIndexSize = count ( "true" configClasses ( ( "true" configClasses (missionConfigFile >> "BuildObjects" >> "Categories") ) select _currentCatID) );

			// Update the index and modulus to make it loop back around in both directions. https://stackoverflow.com/a/24093024
			pr _newItemID = (_currentItemID + _num + _itemIndexSize) mod _itemIndexSize;

			T_SETV("currentItemID", _newItemID); 
			T_CALLM("makeItemTexts", [_newItemID]);
		} else {
			T_SETV("TimeFadeIn", (time+(0.4)));
			pr _newCatID = _currentCatID + (_num);
			// How many categories
			pr _categoryIndexSize = count ("true" configClasses (missionConfigFile >> "BuildObjects" >> "Categories"));
			// Update the index and modulus to make it loop back around in both directions. https://stackoverflow.com/a/24093024
			pr _newCatID = (_currentCatID + _num + _categoryIndexSize) mod _categoryIndexSize;

			T_SETV("currentCatID", _newCatID); 
			T_CALLM("makeCatTexts", [_newCatID]);
		};

	} ENDMETHOD;

	// generates an array of display strings for each category on the UI
	// format: [Left text 2, Left text 1, Center text, Right text 1, Right text 2]
	METHOD("makeCatTexts") {
		params [P_THISOBJECT, "_currentCatID"];
		OOP_INFO_0("'makeCatTexts' method called");

		pr _UIarray = [_currentCatID-2, _currentCatID-1, _currentCatID, _currentCatID+1, _currentCatID+2]; 
		pr _return = [];

		pr _categoryClasses = "true" configClasses (missionConfigFile >> "BuildObjects" >> "Categories");
		pr _numCategories = count _categoryClasses;
		{ 
			if ((_x < 0) OR (_x > (_numCategories - 1))) then { 
				_return pushBack ""; 
			} else {
				_return pushBack (toUpper ( getText ( (_categoryClasses select _x) >> "displayName") ) );
			};
		} forEach _UIarray; 

		SETV(_thisObject, "UICatTexts", _return);

	} ENDMETHOD;

	// generates an array of display strings for the item list on the UI
	// format: [Left text 2, Left text 1, Center text, Right text 1, Right text 2]
	METHOD("makeItemTexts") {
		params [P_THISOBJECT, "_ItemID"];
		OOP_INFO_0("'makeItemTexts' method called");
		pr _currentCatID = T_GETV("currentCatID");
		pr _categoryClasses = "true" configClasses (missionConfigFile >> "BuildObjects" >> "Categories");
		pr _itemCatClass = _categoryClasses select _currentCatID; // Class of current category
		pr _objClasses = "true" configClasses _itemCatClass; // Array with object classes
		pr _itemCatIndexSize = (count _objClasses) -1;
		pr _UIarray = [_ItemID-2, _ItemID-1, _ItemID, _ItemID+1, _ItemID+2]; 
		pr _return = [];

		{ 
			if ((_x < 0) OR (_x > _itemCatIndexSize)) then { 
				_return pushBack ""; 
			} else {
				pr _objClass = _objClasses select _x;
				pr _objClassName = getText ( _objClass >> "className");
				pr _objDisplayName = getText (_objClass >> "displayName");
				// If display name is specified in our config, use it, otherwise take it from cfgVehicles
				pr _itemName = if (_objDisplayName != "") then {
					_objDisplayName
				} else {
					getText (configfile >> "CfgVehicles" >> _objClassName >> "displayName");
				};
				pr _itemCost = getNumber (_objClass >> "buildResource");
				pr _str = format ["%1 [%2]", _itemName, _itemCost];
				_return pushBack _str;
			};
		} forEach _UIarray; 

		T_SETV("UIItemTexts", _return);

	} ENDMETHOD;

	/* 
		Returns the classname of the currently selected menu item, if the menu is open.
		Returns "" if the menu is closed.

		Example:
		private classname = T_CALLM0("currentClassname");

	*/
	METHOD("currentClassname") {
		params [P_THISOBJECT];

		T_PRVAR(ItemCatOpen);
		pr _return = "";
		OOP_INFO_1("'currentClassname' %1", _ItemCatOpen);
		if (_ItemCatOpen) then {
			T_PRVAR(currentCatID);
			T_PRVAR(currentItemID);
			pr _catClass = ("true" configClasses (missionConfigFile >> "BuildObjects" >> "Categories")) select _currentCatID;
			pr _objClasses = "true" configClasses _catClass;
			_return = getText ((_objClasses select _currentItemID) >> "className");
			OOP_INFO_4("'currentClassname' %1 %2 %3 %4", _currentCatID, _currentItemID, _itemCat, _return);
		};

		_return
	} ENDMETHOD;

	METHOD("clearCarousel") {
		params [P_THISOBJECT];
		OOP_INFO_0("'clearCarousel' method called");

		T_PRVAR(carouselObjects);
		{
			detach _x;
			deleteVehicle _x;
		} forEach _carouselObjects;

		T_SETV("carouselObjects", []);
	} ENDMETHOD;

	METHOD("getCarouselOffsets") {
		params [P_THISOBJECT];

		T_PRVAR(currentCatID);
		T_PRVAR(currentItemID);

		// How many items in the currently selected category
		pr _catClass = ("true" configClasses (missionConfigFile >> "BuildObjects" >> "Categories")) select _currentCatID;
		pr _objClasses = "true" configClasses _catClass;
		pr _itemIndexSize = (count _objClasses) - 1;

		pr _offsets = [];

		T_PRVAR(animStartTime);
		T_PRVAR(animCompleteTime);
		T_PRVAR(previousItemID);

		pr _xtotal = 0;
		pr _prevx = 0;
		pr _currx = 0;

		// Work out carousel x offsets based on object sizes.
		for "_i" from 0 to _itemIndexSize do {
			pr _itemClassName = getText ((_objClasses select _i) >> "className" );
			pr _size = sizeOf _itemClassName;
			_xtotal = _xtotal + _size + 1;
			pr _xpos = _xtotal - (_size + 1) * 0.5;
			if (_i == _previousItemID) then { _prevx = _xpos; };
			if (_i == _currentItemID) then { _currx = _xpos; };

			pr _offsIdx = _i - _currentItemID;
			pr _offs = [_xpos, 5 + _size * 0.5, 2];
			_offsets pushBack _offs;
		};

		// Animate our actual x offset over time for nice transitions.
		pr _actualXOffs = linearConversion [_animStartTime, _animCompleteTime, time, _prevx, _currx, true];

		// Apply the offsets to the carousel objects.
		for "_i" from 0 to _itemIndexSize do {
			pr _offs = (_offsets select _i) vectorAdd [-_actualXOffs, 0, 0];
			pr _h = 1 - (1 min (0.5 * abs (_offs select 0)));
			_offs = _offs vectorAdd [0, -_h*2, -_h];
			_offsets set [_i, _offs];
		};

		_offsets
	} ENDMETHOD;

	METHOD("createCarousel") {
		params [P_THISOBJECT];

		OOP_INFO_0("'createCarousel' method called");

		T_CALLM0("clearCarousel");

		T_PRVAR(carouselObjects);
		T_PRVAR(currentCatID);
		T_PRVAR(ItemCatOpen);
		T_PRVAR(rotation);

		// If we aren't looking at items in a category then there is no carousel.
		// TODO: maybe carousel could have the active selected item in each category.
		if (!_ItemCatOpen) exitWith { [] };

		// How many items in the currently selected category?
		pr _catClass = ("true" configClasses (missionConfigFile >> "BuildObjects" >> "Categories")) select _currentCatID;
		pr _objClasses = "true" configClasses _catClass;
		pr _itemIndexSize = (count _objClasses) - 1;
		pr _offsets = T_CALLM0("getCarouselOffsets");

		// Create the objects local to the player with the correct offsets.
		for "_i" from 0 to _itemIndexSize do {
			pr _type = getText ((_objClasses select _i) >> "className");
			OOP_INFO_1("Creating carousel item %1", _type);
			pr _offs = _offsets select _i;
			pr _newObj = _type createVehicleLocal (player modelToWorld _offs);
			_newObj attachTo [player, _offs]; 
			_newObj setDir _rotation;
			_carouselObjects pushBack _newObj;
		};
	} ENDMETHOD;

	METHOD("updateCarouselOffsets") {
		params [P_THISOBJECT];

		T_PRVAR(carouselObjects);
		T_PRVAR(currentCatID);
		T_PRVAR(ItemCatOpen);
		T_PRVAR(rotation);

		if (!_ItemCatOpen) exitWith { [] };

		// How many items in the currently selected category
		pr _catClass = ("true" configClasses (missionConfigFile >> "BuildObjects" >> "Categories")) select _currentCatID;
		pr _objClasses = "true" configClasses _catClass;
		pr _itemIndexSize = count _objClasses - 1;
		pr _offsets = T_CALLM0("getCarouselOffsets");
		for "_i" from 0 to _itemIndexSize do {
			pr _offs = _offsets select _i;
			pr _veh = _carouselObjects select _i;
			_veh attachTo [player, _offs];
			_veh setDir _rotation;
		};

		_offsets
	} ENDMETHOD;

	METHOD("createNewObject") {
		params [P_THISCLASS, "_type", ["_offs", []]];
		OOP_INFO_2("'createNewObject' method called, _type = %1, _offs = %2", _type, _offs);

		if(count _offs == 0) then {
			_offs = [0, sizeOf _type * 2, 0];
		};
		// Exit move mode to remove the highlight event handler etc.
		T_CALLM0("exitMoveMode");

		pr _pos = player modelToWorld _offs;
		pr _newObj = _type createVehicleLocal _pos;
		CALL_STATIC_METHOD_2("BuildUI", "setObjectMovable", _newObj, true);
		_newObj setVariable ["build_ui_newObject", true];

		// Why is this necessary? I don't know but it is!
		_newObj setDir -90;
		pr _activeObject = [_newObj, _pos, vectorDir _newObj, vectorUp _newObj];
		T_SETV("activeObject", _activeObject);
		T_CALLM0("moveSelectedObjects");
	} ENDMETHOD;

	multiply_Vec = {
		params ["_a", "_b"];
		private _r = [];
		for "_i" from 0 to (count _a) - 1 do {
			_r pushBack ((_a select _i) * (_b select _i));
		};
		_r
	};

	METHOD("highlightObjectOnEachFrame") {
		params [P_THISOBJECT];

		if(T_GETV("isMovingObjects")) exitWith {};

		T_PRVAR(activeObject);

		if(count _activeObject == 0 or {cursorObject != _activeObject select 0}) then {

			if(count _activeObject > 0) then {
				//CALL_STATIC_METHOD_1("BuildUI", "restoreSelectionObject", _activeObject);
				_activeObject = [];
				T_SETV("activeObject", _activeObject);
			};

			if(CALL_STATIC_METHOD_1("BuildUI", "isObjectMovable", cursorObject)) then {
				_activeObject = CALL_STATIC_METHOD_1("BuildUI", "createSelectionObject", cursorObject);
				_activeObject params ["_obj", "_pos", "_dir", "_up"];
				T_SETV("activeObject", _activeObject);
				//cursorObject setPosWorld [_pos select 0, _pos select 1, (_pos select 2) + 0.02 + 0.02 * cos(time * 720)];
			};

		} else {

			if(count _activeObject != 0) then {
				_activeObject params ["_obj", "_pos", "_dir", "_up"];
				private _bb = boundingBoxReal _obj;
				_bb params ["_min", "_max"];

				// Vert positions where vert is max dot x + min dot ([1, 1, 1]-x)
				private _verts = [
					[0, 0, 0], // lnb
					[1, 0, 0], // rnb
					[1, 0, 1], // rnt
					[0, 0, 1], // lnt
					[0, 1, 0], // lfb
					[1, 1, 0], // rfb
					[1, 1, 1], // rft
					[0, 1, 1]  // lft
				] apply { 
					(([_max, _x] call multiply_Vec) vectorAdd ([_min, [1, 1, 1] vectorDiff _x] call multiply_Vec))
				};

				// Pairs of verts to form edges of bounding box
				private _edges = [
					[0, 1],
					[1, 2],
					[2, 3],
					[3, 0],
					[4, 5],
					[5, 6],
					[6, 7],
					[7, 4],
					[0, 4],
					[1, 5],
					[2, 6],
					[3, 7]
				];
				// Pairs of verts to form edges of bounding box
				private _baseEdges = [
					[0, 1],
					[4, 5],
					[0, 4],
					[1, 5]
				];

				private _spacing = 0.05;
				private _zhgt = (_min select 2) - (_max select 2);
				private _num = ceil ((abs _zhgt) / _spacing);

				// Rate of t set to 5 unit per second
				private _t = 2 * time / _spacing;
				for "_z" from 0 to _num do
				{
					private _zoffs = [0, 0, _z * _spacing];

					// Work out a rotating offset
					private _coffs = (((_t + _z) mod _num) - (_num * 0.8)) / _num;

					// Apply limit
					_coffs = 0 max (1 min _coffs); //if (_coffs > 0.7) then { 1 } else { 0 };

					private _color = [0, 0.812, 0.4, _coffs];
					{
						_x params ["_v0", "_v1"];
						drawLine3D [_obj modelToWorld ((_verts select _v0) vectorAdd _zoffs), _obj modelToWorld ((_verts select _v1) vectorAdd _zoffs), _color];
					} forEach _baseEdges;
				}
			};
		};
	} ENDMETHOD;

	METHOD("enterMoveMode") {
		params [P_THISOBJECT];
		OOP_INFO_0("'enterMoveMode' method called");

		T_SETV("rotation", 0);
		T_SETV("targetRotation", 0);

		// Updated highlighted object, this is a separate function due to https://feedback.bistudio.com/T123355
		["BuildUIHighlightObject", "onEachFrame", { 
			CALLM0(g_BuildUI, "highlightObjectOnEachFrame");
			call build_ui_highlightObjectOnEachFrame;
		}, []] call BIS_fnc_addStackedEventHandler;

	} ENDMETHOD;

	METHOD("exitMoveMode") {
		params [P_THISOBJECT];
		OOP_INFO_0("'exitMoveMode' method called");

		T_PRVAR(activeObject);
		if(count _activeObject > 0) then {
			CALL_STATIC_METHOD_1("BuildUI", "restoreSelectionObject", _activeObject);
			T_SETV("activeObject", []);
		};

		["BuildUIHighlightObject", "onEachFrame"] call BIS_fnc_removeStackedEventHandler;
	} ENDMETHOD;

	METHOD("moveObjectsOnEachFrame") {
		params [P_THISOBJECT];

		T_PRVAR(movingObjectGhosts);
		T_PRVAR(rotation);
		{
			_x params ["_ghostObject", "_object", "_pos", "_dir", "_up"];
			private _relativePos = _ghostObject getVariable "build_ui_relativePos";
			private _dist = _ghostObject getVariable "build_ui_dist";
			private _ins = lineIntersectsSurfaces [
				AGLToASL positionCameraToWorld [0,0,0],
				AGLToASL positionCameraToWorld [0,0,1000],
				player, _ghostObject
			];

			if(count _ins != 0) then {
				pr _firstIns = ASLToAGL ((_ins select 0) select 0);
				private _size = _ghostObject getVariable "build_ui_size";
				private _maxdist = 10 + _size * 0.5; // Max distance the object can be placed at
				
				_dist = (_size max (_maxdist min (player distance _firstIns)) - (_size * 0.5));
			};

			private _height = _ghostObject getVariable "build_ui_height";
			private _relativeRot = _ghostObject getVariable "build_ui_relativeDir";
			private _worldPos = player modelToWorld [_relativePos select 0, _dist, _relativePos select 2];

			// Put on ground
			_worldPos set [2, _height];
			_ghostObject attachTo [player, player worldToModel _worldPos];
			_ghostObject setDir (_relativeRot + _rotation);
			private _surfaceVectorUp = surfaceNormal _worldPos;
			_ghostObject setVectorUp (player vectorWorldToModel _surfaceVectorUp);
			_ghostObject setVariable ["build_ui_dist", _dist];
		} forEach _movingObjectGhosts;
		
	} ENDMETHOD;

	METHOD("moveSelectedObjects") {
		params [P_THISOBJECT];

		OOP_INFO_0("'moveSelectedObjects' method called");

		// Grab the selected objects
		T_PRVAR(activeObject);
		T_PRVAR(selectedObjects);
		T_PRVAR(rotation);

		// Exit move mode so it doesn't interfere (it will clear activeObject, but we already took a copy above)
		T_CALLM0("exitMoveMode");

		pr _movingObjects = +_selectedObjects;
		if (count _activeObject > 0) then {
			CALL_STATIC_METHOD_2("BuildUI", "addSelection", _movingObjects, _activeObject);
		};
		if (count _movingObjects == 0) exitWith { false };

		T_SETV("isMovingObjects", true);

		private _movingObjectGhosts = [];
		{
			_x params ["_object", "_pos", "_dir", "_up"];

			private _relativePos = player worldToModel (_object modelToWorld [0,0,0.1]);
			private _starting_h = getCameraViewDirection player select 2;
			private _bboxCenter = boundingCenter _object;

			private _originHeight = (getPosATL _object) select 2;
			private _height = (_bboxCenter select 2);
			private _relativeDir = getDir _object - getDir player;

			private _ghost = (typeOf _object) createVehicleLocal (getPos _object);

			// This has local only effect
			_object hideObject true;

			_ghost enableSimulation false;
			_ghost setVariable ["build_ui_beingMoved", true];
			_ghost setVariable ["build_ui_relativePos", _relativePos];
			_ghost setVariable ["build_ui_starting_h", _starting_h];
			_ghost setVariable ["build_ui_relativeDir", _relativeDir];
			_ghost setVariable ["build_ui_height", _height];
			_ghost setVariable ["build_ui_dist", _relativePos select 1];
			_ghost setVariable ["build_ui_size", sizeOf (typeOf _object)];

			_ghost attachTo [player, _relativePos];
			_ghost setDir (_relativeDir + _rotation);

			_movingObjectGhosts pushBack [_ghost, _object, _pos, _dir, _up];
		} forEach _movingObjects;

		T_SETV("movingObjectGhosts", _movingObjectGhosts);

		// Update moving objects on each frame, this is a separate function due to https://feedback.bistudio.com/T123355
		["BuildUIMoveObjectsOnEachFrame", "onEachFrame", {
			CALLM0(g_BuildUI, "moveObjectsOnEachFrame");
		}, []] call BIS_fnc_addStackedEventHandler;
		true
	} ENDMETHOD;

	// STATIC_METHOD("createObject") {
	// 	params [P_THISCLASS];
		
	// } ENDMETHOD;
	
	METHOD("dropHere") {
		params [P_THISOBJECT];
		T_PRVAR(movingObjectGhosts);

		["BuildUIMoveObjectsOnEachFrame", "onEachFrame"] call BIS_fnc_removeStackedEventHandler;

		// Detach objects from player and place them
		{
			_x params ["_ghostObject", "_object", "_pos", "_dir", "_up"];
			detach _ghostObject;
			private _currPos = getPos _ghostObject;

			// If it is a new object then we must create a server version.
			if (_object getVariable ["build_ui_newObject", false]) then {
				// We are creating a new object
				// Ask server to do that

				pr _pos = [_currPos select 0, _currPos select 1, 0];
				pr _dir = getDir _ghostObject;
				// These are template catID and subcatID of the object, not catID of the build menu
				pr _currentCatID = T_GETV("currentCatID");
				pr _catClass = ("true" configClasses (missionConfigFile >> "BuildObjects" >> "Categories")) select _currentCatID;
				pr _catConfigClassNameStr = configName _catClass; // "catTents" and such
				pr _objClasses = "true" configClasses _catClass;
				pr _objClass = _objClasses select T_GETV("currentItemID");
				pr _objConfigClassNameStr = configName _objClass; // "Tent1" and such
				pr _className = getText (_objClass >> "className");
				pr _buildRes = getNumber (_objClass >> "buildResource");
				pr _catID = getNumber (_objClass >> "templateCatID");
				pr _subcatID = getNumber (_objClass >> "templateSubcatID");
				pr _gar = CALLM0(gPlayerMonitor, "getCurrentGarrison");

				if (T_GETV("resourceSource") == __RESOURCE_SOURCE_INVENTORY) then {
					// Check player's resources
					pr _playerBuildRes = CALLSM1("Unit", "getInfantryBuildResources", player);
					if (_playerBuildRes >= _buildRes) then {
						CALLSM2("Unit", "removeInfantryBuildResources", player, _buildRes);
						_buildRes = -1; // buildFromGarrison will bypass the resource check at the target garrison
						pr _args = [clientOwner, _gar, _catConfigClassNameStr, _objConfigClassNameStr, _pos, _dir, false];
						// Send the request to server
						CALLM2(gGarrisonServer, "postMethodAsync", "buildFromGarrison", _args);
					} else {
						// Show error message
						systemChat format ["Not enough build resources in your inventory: %1 (%2 required)", _playerBuildRes, _buildRes];
					};
					
				} else {
					// We are building from the location garrison's resources
					pr _args = [clientOwner, _gar, _catConfigClassNameStr, _objConfigClassNameStr, _pos, _dir, true];

					// Send the request to server
					CALLM2(gGarrisonServer, "postMethodAsync", "buildFromGarrison", _args);
				};

				deleteVehicle _object;
			} else {
				// We are just moving an already existing object
				_object setDir (getDir _ghostObject);
				_object setPos [_currPos select 0, _currPos select 1, 0];
				// _object enableSimulationGlobal true;
				_object hideObject false;
			};

			deleteVehicle _ghostObject;
		} forEach _movingObjectGhosts;

		T_SETV("movingObjectGhosts", []);
		T_SETV("isMovingObjects", false);

		T_CALLM0("enterMoveMode");
	} ENDMETHOD;

	METHOD("cancelMovingObjects") {
		params [P_THISOBJECT];

		if !(T_GETV("isMovingObjects")) exitWith {};

		T_PRVAR(movingObjectGhosts);

		["SetHQObjectHeight", "onEachFrame"] call BIS_fnc_removeStackedEventHandler;

		// Detach objects and put objects back where they started
		{
			_x params ["_ghostObject", "_object", "_pos", "_dir", "_up"];
			detach _ghostObject;
			deleteVehicle _ghostObject;

			// If it is a new object then we delete it, otherwise unhide it locally
			if(_object getVariable ["build_ui_newObject", false]) then {
				deleteVehicle _object;
			} else {
				_object hideObject false;
			};
		} forEach _movingObjectGhosts;

		T_SETV("movingObjectGhosts", []);
		T_SETV("isMovingObjects", false);

		T_CALLM0("enterMoveMode");

	} ENDMETHOD;

	STATIC_METHOD("setObjectMovable") {
		params [P_THISCLASS, P_OBJECT("_obj"), P_BOOL("_set")];
		_obj setVariable ["build_ui_allowMove", _set, true];
	} ENDMETHOD;

	STATIC_METHOD("isObjectMovable") {
		params [P_THISCLASS, P_OBJECT("_obj")];
		_obj getVariable ["build_ui_allowMove", false]
	} ENDMETHOD;

	STATIC_METHOD("addSelection") {
		params [P_THISCLASS, P_ARRAY("_arr"), P_ARRAY("_obj")];
		if((_obj select 0) in (_arr apply { _x select 0 })) exitWith {false};
		_arr pushBack _obj;
		true
	} ENDMETHOD;

	STATIC_METHOD("removeSelection") {
		params [P_THISCLASS, P_ARRAY("_arr"), P_ARRAY("_obj")];
		pr _idx = _arr findIf { (_x select 0) == (_obj select 0) };
		if(_idx == -1) exitWith {false};
		_arr deleteAt _idx;
		true
	} ENDMETHOD;

	STATIC_METHOD("createSelectionObject") {
		params [P_THISCLASS, P_OBJECT("_obj")];
		[_obj, getPosWorld _obj, vectorDir _obj, vectorUp _obj]
	} ENDMETHOD;

	STATIC_METHOD("restoreSelectionObject") {
		params [P_THISCLASS, P_ARRAY("_sobj")];
		_sobj params ["_obj", "_pos", "_dir", "_up"];
		OOP_INFO_4("'exitMoveMode' method called %1/%2/%3/%4", _obj, _pos, _dir, _up);
		_obj setPosWorld _pos;
		_obj setVectorDirAndUp [_dir, _up];
		_obj enableSimulation true;
	} ENDMETHOD;

ENDCLASS;

build_UI_addOpenBuildMenuAction = {
	ASSERT_GLOBAL_OBJECT(g_BuildUI);
	params ["_obj"];
	CALLM1(g_BuildUI, "addOpenBuildMenuAction", _obj);
};

build_UI_setObjectMovable = {
	ASSERT_GLOBAL_OBJECT(g_BuildUI);
	params ["_obj", "_val"];
	OOP_INFO_2("'build_UI_setObjectMovable' method called with %1, %2", _obj, _val);
	CALL_STATIC_METHOD_2("BuildUI", "setObjectMovable", _obj, _val);
};
