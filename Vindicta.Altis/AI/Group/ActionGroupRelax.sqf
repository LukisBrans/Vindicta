#include "common.hpp"

/*
Class: ActionGroup.ActionGroupRelax
*/

#define pr private

CLASS("ActionGroupRelax", "ActionGroup")
	
	// ------------ N E W ------------
	
	METHOD("new") {
		params [P_THISOBJECT, P_OOP_OBJECT("_AI") ];

	} ENDMETHOD;
	
	// logic to run when the goal is activated
	METHOD("activate") {
		params [P_THISOBJECT, P_BOOL("_instant")];

		// Set behaviour
		T_CALLM2("applyGroupBehaviour", "DIAMOND", "SAFE");
		T_CALLM0("clearWaypoints");
		T_CALLM0("regroup");

		pr _AI = T_GETV("AI");
		pr _hG = T_GETV("hG");

		// Find some random position at the location and go there
		pr _group = GETV(T_GETV("AI"), "agent");
		pr _type = CALLM0(_group, "getType");
		pr _gar = CALLM0(_group, "getGarrison");
		pr _loc = CALLM0(_gar, "getLocation");
		pr _useDefaultRandomPos = true;
		pr _pos = [];
		pr _radius = 10;
		if (_type == GROUP_TYPE_VEH) then {
			// Crew of vehicle groups stays aroudn their vehicle
			pr _vehUnits = CALLM0(_group, "getUnits") select {
				CALLM0(_x, "isVehicle")
			};
			if (count _vehUnits > 0) then {
				pr _vehUnit = selectRandom _vehUnits;
				pr _hO = CALLM0(_vehUnit, "getObjectHandle");
				_pos = getPos _hO;
				_radius = 10 + random 10;
				if (! (_pos isEqualTo [0, 0, 0])) then { // Better to be safe here, we don't want to be in the sea
					_useDefaultRandomPos = false;
				};
			};
		};

		// Standard code for default random position
		if (_useDefaultRandomPos) then {
			// Non-vehicle group infantry units just walk around the location randomly
			if (!IS_NULL_OBJECT(_loc)) then {
				_pos = CALLM0(_loc, "getRandomPos");
				_radius = (100 max GETV(_loc, "boundingRadius")) * 1.25
			} else {
				pr _lp = getPos leader _hG;
				_pos = [(_lp select 0) - 30 + random 60, (_lp select 1) - 30 + random 60, 0];
				_radius = 200 + random 150 ;
			};
		};

		pr _activeWP = _hG addWaypoint [ZERO_HEIGHT(_pos), 20, 0];
		_activeWP setWaypointType "MOVE";
		_activeWP setWaypointFormation "DIAMOND";
		_activeWP setWaypointBehaviour "SAFE";

		// Give a goal to units
		pr _units = CALLM0(_group, "getInfantryUnits");
		{
			pr _unitAI = CALLM0(_x, "getAI");
			CALLM4(_unitAI, "addExternalGoal", "GoalUnitDismountCurrentVehicle", 0, [[TAG_INSTANT ARG _instant]], _AI);
		} forEach _units;

		if(_instant) then {
			// Teleport to a random patrol waypoint
			T_CALLM2("teleport", getWPPos _activeWP, _units);
		};

		_hG setCurrentWaypoint _activeWP;

		// Set state
		T_SETV("state", ACTION_STATE_ACTIVE);
		
		// Return ACTIVE state
		ACTION_STATE_ACTIVE
		
	} ENDMETHOD;
	
	// logic to run each update-step
	METHOD("process") {
		params [P_THISOBJECT];
		
		T_CALLM0("failIfEmpty");
		
		T_CALLM0("activateIfInactive");
		
		// Return the current state
		ACTION_STATE_ACTIVE
	} ENDMETHOD;
	
	// logic to run when the action is satisfied
	METHOD("terminate") {
		params [P_THISOBJECT];
		
		// Delete the goal to dismount vehicles
		pr _group = GETV(T_GETV("AI"), "agent");
		pr _units = CALLM0(_group, "getInfantryUnits");
		{
			pr _unitAI = CALLM0(_x, "getAI");
			CALLM2(_unitAI, "deleteExternalGoal", "GoalUnitDismountCurrentVehicle", "");
		} forEach _units;
	} ENDMETHOD;

ENDCLASS;