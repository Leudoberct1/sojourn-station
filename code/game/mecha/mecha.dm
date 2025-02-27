#define MECHA_INT_FIRE 1
#define MECHA_INT_TEMP_CONTROL 2
#define MECHA_INT_SHORT_CIRCUIT 4
#define MECHA_INT_TANK_BREACH 8
#define MECHA_INT_CONTROL_LOST 16

#define MECHA_MELEE 1
#define MECHA_RANGED 2

#define MOVEMODE_STEP 1
#define MOVEMODE_THRUST 2

#define MECHA_ARMOR_LIGHT 1
#define MECHA_ARMOR_SCOUT 2
#define MECHA_ARMOR_MEDIUM 3
#define MECHA_ARMOR_HEAVY 4
#define MECHA_ARMOR_SUPERHEAVY 5

/obj/mecha
	name = "Mecha"
	desc = "Exosuit"
	icon = 'icons/mecha/mecha.dmi'
	density = 1 //Dense. To raise the heat.
	opacity = 1 ///opaque. Menacing.
	anchored = 1 //no pulling around.
	unacidable = 1 //and no deleting hoomans inside
	layer = BELOW_MOB_LAYER//icon draw layer
	infra_luminosity = 15 //byond implementation is bugged.
	var/initial_icon = null //Mech type for resetting icon. Only used for reskinning kits (see custom items)
	var/can_move = 1
	var/mob/living/carbon/occupant = null
	var/list/dropped_items = list()

	health = 300 //health is health
	var/deflect_chance = 10 //chance to deflect incoming projectiles, hits, or lesser the effect of ex_act.
	var/r_deflect_coeff = 1
	var/m_deflect_coeff = 1
	//ranged and melee damage multipliers
	var/r_damage_coeff = 1
	var/m_damage_coeff = 1
	var/rhit_power_use = 0
	var/mhit_power_use = 0

	//Movement
	var/step_in = 10 //make a step in step_in/10 sec.
	var/dir_in = 2//What direction will the mech face when entered/powered on? Defaults to South.
	var/step_energy_drain = 10
	var/obj/item/mecha_parts/mecha_equipment/thruster/thruster = null

	//the values in this list show how much damage will pass through, not how much will be absorbed.
	var/list/damage_absorption = list("brute"=0.8,"fire"=1.2,"bullet"=0.9,"energy"=1,"bomb"=1)
	// This armor level indicates how fortified the mech's armor is.
	var/armor_level = MECHA_ARMOR_LIGHT
	var/obj/item/cell/large/cell
	var/state = 0
	var/list/log = new
	var/last_message = 0
	var/add_req_access = 1
	var/maint_access = 1
	var/dna	//dna-locking the mech
	var/datum/effect/effect/system/spark_spread/spark_system = new
	var/lights = 0
	var/lights_power = 6
	var/force = 0

	//inner atmos
	var/use_internal_tank = 0
	var/internal_tank_valve = ONE_ATMOSPHERE
	var/obj/machinery/portable_atmospherics/canister/internal_tank
	var/datum/gas_mixture/cabin_air
	var/obj/machinery/atmospherics/portables_connector/connected_port = null

	var/obj/item/device/radio/radio = null

	var/max_temperature = 25000
	var/internal_damage_threshold = 50 //health percentage below which internal damage is possible
	var/internal_damage = 0 //contains bitflags

	var/list/operation_req_access = list()//required access level for mecha operation
	var/list/internals_req_access = list()//required access level to open cell compartment
	var/list/dna_req_access = list(access_heads)

	var/datum/global_iterator/pr_int_temp_processor //normalizes internal air mixture temperature
	var/datum/global_iterator/pr_inertial_movement //controls intertial movement in spesss
	var/datum/global_iterator/pr_give_air //moves air from tank to cabin
	var/datum/global_iterator/pr_internal_damage //processes internal damage


	var/wreckage
	var/noexplode = 0 // Used for cases where an exosuit is spawned and turned into wreckage

	var/list/equipment = new
	var/obj/item/mecha_parts/mecha_equipment/selected
	var/max_equip = 4
	var/datum/events/events

	//Sounds
	var/step_sound = 'sound/mecha/Mech_Step.ogg'
	var/step_turn_sound = 'sound/mecha/Mech_Rotation.ogg'

	var/list/obj/item/mech_ammo_box/ammo[3] // List to hold the mech's internal ammo.

	var/obj/item/clothing/glasses/hud/hud

/obj/mecha/can_prevent_fall()
	return TRUE

/obj/mecha/get_fall_damage()
	return FALL_GIB_DAMAGE

/obj/mecha/drain_power(var/drain_check)

	if(drain_check)
		return 1

	if(!cell)
		return 0

	return cell.drain_power(drain_check)

/obj/mecha/New()
	..()
	events = new

	update_icon()
	add_radio()
	add_cabin()
	add_airtank() //All mecha currently have airtanks. No need to check unless changes are made.
	spark_system.set_up(2, 0, src)
	spark_system.attach(src)
	add_cell()
	add_iterators()
	removeVerb(/obj/mecha/verb/disconnect_from_port)
	log_message("[src.name] created.")
	loc.Entered(src)
	GLOB.mechas_list += src //global mech list
	add_hearing()
	return

/obj/mecha/Destroy()
	src.go_out()
	for(var/mob/M in src) //Let's just be ultra sure
		M.Move(loc)

	if(loc)
		loc.Exited(src)

	if(prob(30) && !noexplode)
		explosion(get_turf(loc), 0, 0, 1, 3)

	if(wreckage)
		var/obj/effect/decal/mecha_wreckage/WR = new wreckage(loc)
		for(var/obj/item/mecha_parts/mecha_equipment/E in equipment)
			if(E.salvageable && prob(30))
				WR.crowbar_salvage += E
				E.forceMove(WR)
				E.equip_ready = 1
			else
				E.forceMove(loc)
				E.destroy()
		if(cell)
			WR.crowbar_salvage += cell
			cell.forceMove(WR)
			cell.charge = rand(0, cell.charge)
			cell = null

		if(internal_tank)
			WR.crowbar_salvage += internal_tank
			internal_tank.forceMove(WR)
			internal_tank = null
	else
		for(var/obj/item/mecha_parts/mecha_equipment/E in equipment)
			E.detach(loc)
			E.destroy()

		QDEL_NULL(cell)
		QDEL_NULL(internal_tank)

	equipment.Cut()

	QDEL_NULL(pr_int_temp_processor)
	QDEL_NULL(pr_inertial_movement)
	QDEL_NULL(pr_give_air)
	QDEL_NULL(pr_internal_damage)
	QDEL_NULL(spark_system)

	GLOB.mechas_list -= src //global mech list
	remove_hearing()
	. = ..()

/obj/mecha/lost_in_space()
	return occupant.lost_in_space()

/obj/mecha/handle_atom_del(atom/A)
	..()
	if(A == cell)
		cell = null

/obj/mecha/get_cell()
	return cell

/obj/mecha/update_icon()
	if (initial_icon)
		icon_state = initial_icon
	else
		icon_state = initial(icon_state)

	if(!occupant)
		icon_state += "-open"


/obj/mecha/proc/reload_gun()
	var/obj/item/mech_ammo_box/MAB
	if(!istype(selected, /obj/item/mecha_parts/mecha_equipment/ranged_weapon/ballistic)) // Does it use bullets?
		return FALSE
	var/obj/item/mecha_parts/mecha_equipment/ranged_weapon/ballistic/gun = selected
	for(var/obj/item/mech_ammo_box/M in ammo) // Run through the boxes
		if(M.ammo_type == gun.ammo_type) // Is it the right ammo?
			MAB = M
	if(MAB) // Only proceed if MAB isn't null, AKA we got a valid box to draw from
		while(gun.max_ammo > gun.projectiles) // Keep loading until we're full or the box's empty
			if(MAB.ammo_amount_left < MAB.amount_per_click) // Check if there's enough ammo left
				MAB.forceMove(src.loc) // Drop the empty ammo box
				for(var/i = ammo.len to 1 step -1) // Check each spot in the ammobox list
					if(ammo[i] == MAB) // Is it the same box?
						ammo[i] = null // It is no longer there
						MAB = null
				return FALSE
			MAB.ammo_amount_left -= MAB.amount_per_click // Remove the ammo from the box
			gun.projectiles += MAB.amount_per_click // Put the ammo in the box
		return TRUE

////////////////////////
////// Helpers /////////
////////////////////////

/obj/mecha/proc/removeVerb(verb_path)
	verbs -= verb_path

/obj/mecha/proc/addVerb(verb_path)
	verbs += verb_path

/obj/mecha/proc/add_airtank()
	internal_tank = new /obj/machinery/portable_atmospherics/canister/air(src)
	return internal_tank

/obj/mecha/proc/add_cell()
	cell = new /obj/item/cell/large/super(src)

/obj/mecha/proc/add_cabin()
	cabin_air = new
	cabin_air.temperature = T20C
	cabin_air.volume = 200
	cabin_air.adjust_multi(
		"oxygen",   O2STANDARD*cabin_air.volume/(R_IDEAL_GAS_EQUATION*cabin_air.temperature),
		"nitrogen", N2STANDARD*cabin_air.volume/(R_IDEAL_GAS_EQUATION*cabin_air.temperature)
	)
	return cabin_air

/obj/mecha/proc/add_radio()
	radio = new(src)
	radio.name = "[src] radio"
	radio.icon = icon
	radio.icon_state = icon_state
	radio.subspace_transmission = 1

/obj/mecha/proc/add_iterators()
	pr_int_temp_processor = new /datum/global_iterator/mecha_preserve_temp(list(src))
	pr_inertial_movement = new /datum/global_iterator/mecha_inertial_movement(null,0)
	pr_give_air = new /datum/global_iterator/mecha_tank_give_air(list(src))
	pr_internal_damage = new /datum/global_iterator/mecha_internal_damage(list(src),0)

/obj/mecha/proc/do_after_mech(delay as num)
	sleep(delay)
	if(src)
		return 1
	return 0

/obj/mecha/proc/enter_after(delay as num, var/mob/user as mob, var/numticks = 5)
	var/turf/T = user.loc

	var/datum/progressbar/progbar = new(user, delay, user)
	var/starttime = world.time

	for(var/i = 0, i < delay, i++)
		sleep(1)
		progbar.update(world.time - starttime)
		if(i % numticks == 0)
			if(!src || !user || !user.canmove || !(user.loc == T))
				qdel(progbar)
				return 0

	qdel(progbar)
	return 1


//Called each step by mechas, and periodically when drifting through space
/obj/mecha/proc/check_for_support()
	var/turf/T = get_turf(src)
	//If we're standing on solid ground, we are fine, even in space.
	//We'll assume mechas have magnetic feet and don't slip
	if (!T.is_hole)
		return TRUE


	//Ok we're floating and there's no gravity
	else
		for (var/a in T)

			if (a == src)
				continue

			var/atom/A = a
			if (A.can_prevent_fall())
				return TRUE
		return FALSE

/obj/mecha/examine(mob/user)
	..(user)
	var/integrity = health/initial(health)*100
	switch(integrity)
		if(85 to 100)
			to_chat(user, "It's fully intact.")
		if(65 to 85)
			to_chat(user, "It's slightly damaged.")
		if(45 to 65)
			to_chat(user, "It's badly damaged.")
		if(25 to 45)
			to_chat(user, "It's heavily damaged.")
		else
			to_chat(user, "It's falling apart.")
	if(equipment && equipment.len)
		to_chat(user, "It's equipped with:")
		for(var/obj/item/mecha_parts/mecha_equipment/ME in equipment)
			to_chat(user, "\icon[ME] [ME]")


/obj/mecha/proc/drop_item()//Derpfix, but may be useful in future for engineering exosuits.
	return

/obj/mecha/hear_talk(mob/M as mob, text, verb, datum/language/speaking, speech_volume)
	if(M==occupant && radio.broadcasting)
		radio.talk_into(M, text, speech_volume = speech_volume)

////////////////////////////
///// Action processing ////
////////////////////////////
/*
/atom/DblClick(object,location,control,params)
	var/mob/M = src.mob
	if(M && M.in_contents_of(/obj/mecha))

		if(mech_click == world.time) return
		mech_click = world.time

		if(!istype(object, /atom)) return
		if(istype(object, /obj/screen))
			var/obj/screen/using = object
			if(using.screen_loc == ui_acti || using.screen_loc == ui_iarrowleft || using.screen_loc == ui_iarrowright)//ignore all HUD objects save 'intent' and its arrows
				return ..()
			else
				return
		var/obj/mecha/Mech = M.loc
		spawn() //this helps prevent clickspam fest.
			if (Mech)
				Mech.click_action(object,M)
//	else
//		return ..()
*/

/obj/mecha/proc/click_action(atom/target,mob/user)
	if(!src.occupant || src.occupant != user ) return
	if(user.stat) return
	if(state)
		occupant_message("<font color='red'>Maintenance protocols in effect.</font>")
		return
	if(!get_charge()) return
	if(src == target) return
	var/dir_to_target = get_dir(src,target)
	if(dir_to_target && !(dir_to_target & src.dir))
		return
	if(hasInternalDamage(MECHA_INT_CONTROL_LOST))
		target = safepick(view(3,target))
		if(!target)
			return
	if(istype(target, /obj/machinery))
		if (src.interface_action(target))
			return
	if(!target.Adjacent(src))
		if(selected && selected.is_ranged())
			selected.action(target)
	else if(selected)
		if(selected.is_melee())
			selected.action(target)
		else
			occupant_message("<font color='red'>You cannot fire this weapon in close quarters!</font>")
	else
		src.melee_action(target)
	return

/obj/mecha/proc/interface_action(obj/machinery/target)
	if(istype(target, /obj/machinery/access_button))
		src.occupant_message(SPAN_NOTICE("Interfacing with [target]."))
		src.log_message("Interfaced with [target].")
		target.attack_hand(src.occupant)
		return 1
	if(istype(target, /obj/machinery/embedded_controller))
		target.nano_ui_interact(src.occupant)
		return 1
	return 0

/obj/mecha/contents_nano_distance(var/src_object, var/mob/living/user)
	. = user.shared_living_nano_distance(src_object) //allow them to interact with anything they can interact with normally.
	if(. != STATUS_INTERACTIVE)
		//Allow interaction with the mecha or anything that is part of the mecha
		if(src_object == src || (src_object in src))
			return STATUS_INTERACTIVE
		if(src.Adjacent(src_object))
			src.occupant_message(SPAN_NOTICE("Interfacing with [src_object]..."))
			src.log_message("Interfaced with [src_object].")
			return STATUS_INTERACTIVE
		if(src_object in view(2, src))
			return STATUS_UPDATE //if they're close enough, allow the occupant to see the screen through the viewport or whatever.

/obj/mecha/proc/melee_action(atom/target)
	return

/obj/mecha/proc/range_action(atom/target)
	return


//////////////////////////////////
////////  Movement procs  ////////
//////////////////////////////////

/obj/mecha/Move(NewLoc, Dir = 0, step_x = 0, step_y = 0, var/glide_size_override = 0)
	. = ..()
	if(.)
		events.fireEvent("onMove",get_turf(src))

/obj/mecha/relaymove(mob/user,direction)
	if(user != src.occupant) //While not "realistic", this piece is player friendly.
		user.forceMove(get_turf(src))
		to_chat(user, "You climb out from [src]")
		return 0
	if(connected_port)
		if(world.time - last_message > 20)
			src.occupant_message("Unable to move while connected to the air system port.")
			last_message = world.time
		return 0
	if(state)
		occupant_message("<font color='red'>Maintenance protocols in effect.</font>")
		return
	return do_move(direction)

//This uses a goddamn do_after for movement, this is very bad. Todo: Redesign this in future
/obj/mecha/proc/do_move(direction)


	//If false, it's just moved, or locked down, or disabled or something
	if(!can_move)
		return 0

	//Currently drifting through space. The iterator that controls this will cancel it if the mech finds
	// things to grip or enables thrusters
	if(src.pr_inertial_movement.active())
		return 0


	if(!has_charge(step_energy_drain))
		return 0

	var/turn = FALSE //If true, we are turning in place instead of moving
	if(src.dir!=direction)
		turn = TRUE

	var/move_result = 0
	var/movemode = MOVEMODE_STEP

	//Alright lets check if we can move
	//If there's no support then we will use the thruster
	if(!check_for_support())
		//Check if the thruster exists, and is able to work. The do_move proc will handle paying gas costs
		if (thruster && thruster.do_move(direction, turn))
			//We pass this into the move procs, prevents stomping sounds
			movemode = MOVEMODE_THRUST


			//The thruster uses power, but far less than moving the legs
			if (!use_power(step_energy_drain*0.1))
				//No movement if power is dead
				return FALSE
		else
			src.pr_inertial_movement.start(list(src,direction))
			src.log_message("Movement control lost. Inertial movement started.")
			return FALSE
	//There is support, normal movement, normal energy cost
	else
		if (!use_power(step_energy_drain))
			//No movement if power is dead
			return FALSE

	//If we make it to here then we can definitely make a movement

	anchored = FALSE //Unanchor in order to move
	// TODO: Glide size handling in here is fucked,
	// because the timing system uses sleep instead of world.time comparisons/delay controllers
	// At least that's my theory I can't be bothered to investigate fully.
	if(turn)
		move_result = mechturn(direction, movemode)
		//We don't set l_move_time for turning on the spot. it doesnt count as movement
	else if(hasInternalDamage(MECHA_INT_CONTROL_LOST))
		set_glide_size(DELAY2GLIDESIZE(step_in))
		move_result = mechsteprand(movemode)
		if (occupant)
			occupant.l_move_time = world.time

	else
		set_glide_size(DELAY2GLIDESIZE(step_in))
		move_result = mechstep(direction, movemode)
		if (occupant)
			occupant.l_move_time = world.time

	anchored = TRUE //Reanchor after moving
	if(move_result)
		can_move = 0



		if(do_after_mech(step_in))
			can_move = 1
		return 1
	return 0

/obj/mecha/proc/mechturn(direction, var/movemode = MOVEMODE_STEP)
	//When turning in 0g with a thruster, we do a little airburst to rotate us
	//The thrust happens in the direction we're already facing, to turn us away from that and to a different direction
	if (movemode == MOVEMODE_THRUST)
		thruster.thrust.trail.do_effect(get_step(loc, dir), dir)

	set_dir(direction)

	if (movemode == MOVEMODE_STEP)
		playsound(src,step_turn_sound,40,1)

	return 1

/obj/mecha/proc/mechstep(direction, var/movemode = MOVEMODE_STEP)
	var/result = Move(get_step(src, direction),direction)
	if(result)
		if (movemode == MOVEMODE_STEP)
			playsound(src,step_sound,100,1)
	return result


/obj/mecha/proc/mechsteprand(var/movemode = MOVEMODE_STEP)
	var/result = step_rand(src)
	if(result)
		if (movemode == MOVEMODE_STEP)
			playsound(src,step_sound,100,1)
	return result

//Used for jetpacks
/obj/mecha/total_movement_delay()
	return step_in

/obj/mecha/Bump(var/atom/obstacle)
//	src.inertia_dir = null
	if(isobj(obstacle))
		var/obj/O = obstacle
		if(istype(O, /obj/effect/portal)) //derpfix
			src.anchored = 0
			O.Crossed(src)
			spawn(0)//countering portal teleport spawn(0), hurr
				src.anchored = 1
		else if(!O.anchored)
			step(obstacle,src.dir)
		else //I have no idea why I disabled this
			obstacle.Bumped(src)
	else if(ismob(obstacle))
		step(obstacle,src.dir)
	else
		obstacle.Bumped(src)
	return

/obj/mecha/get_jetpack()
	if (thruster)
		return thruster.thrust

	return null

//Here we hook in any modules that would prevent the mech from falling
//Return false to float in the air, return true to fall
/obj/mecha/can_fall()
	if (thruster)
		if (thruster.thrust.check_thrust() && thruster.thrust.stabilization_on)
			return FALSE
	.=..()



/*Falling mechas have a similar effect to falling robots. Major devastation to the area and death to
anything directly under them. However, since they are walking vehicles, with legs - and more importantly, knees-
they can absorb most of the shock that would hit themselves, and thusly only take light damage from falling.
This damage is 8% of their max health.
It's still not healthy or recommended in most circumstances, but stomping someone in a mech would be an excellent
assassination method if you time it right*/
/obj/mecha/fall_impact(var/turf/from, var/turf/dest)
	anchored = TRUE //We may have set this temporarily false so we could fall
	take_damage(initial(health)*0.08)

	//Wreck the contents of the tile
	for (var/atom/movable/AM in dest)
		if (AM != src)
			AM.ex_act(3)

	//Damage the tile itself
	dest.ex_act(2)

	//Damage surrounding tiles
	for (var/turf/T in range(1, src))
		if (T == dest)
			continue

		T.ex_act(3)

	//And do some screenshake for everyone in the vicinity
	for (var/mob/M in range(20, src))
		var/dist = get_dist(M, src)
		dist *= 0.5
		if (dist <= 1)
			dist = 1 //Prevent runtime errors

		shake_camera(M, 10/dist, 2.5/dist, 0.12)

	playsound(src, 'sound/weapons/heavysmash.ogg', 100, 1, 20,20)
	spawn(1)
		playsound(src, 'sound/weapons/heavysmash.ogg', 100, 1, 20,20)
	spawn(2)
		playsound(src, 'sound/weapons/heavysmash.ogg', 100, 1, 20,20)

///////////////////////////////////
////////  Internal damage  ////////
///////////////////////////////////

/obj/mecha/proc/check_for_internal_damage(var/list/possible_int_damage,var/ignore_threshold=null)
	if(!islist(possible_int_damage) || isemptylist(possible_int_damage)) return
	if(prob(20))
		if(ignore_threshold || src.health*100/initial(src.health)<src.internal_damage_threshold)
			for(var/T in possible_int_damage)
				if(internal_damage & T)
					possible_int_damage -= T
			var/int_dam_flag = safepick(possible_int_damage)
			if(int_dam_flag)
				setInternalDamage(int_dam_flag)
	if(prob(5))
		if(ignore_threshold || src.health*100/initial(src.health)<src.internal_damage_threshold)
			var/obj/item/mecha_parts/mecha_equipment/destr = safepick(equipment)
			if(destr)
				destr.destroy()
	return

/obj/mecha/proc/hasInternalDamage(int_dam_flag=null)
	return int_dam_flag ? internal_damage&int_dam_flag : internal_damage


/obj/mecha/proc/setInternalDamage(int_dam_flag)
	if(!pr_internal_damage) return

	internal_damage |= int_dam_flag
	pr_internal_damage.start()
	log_append_to_last("Internal damage of type [int_dam_flag].",1)
	occupant << sound('sound/machines/warning-buzzer.ogg',wait=0)
	return

/obj/mecha/proc/clearInternalDamage(int_dam_flag)
	internal_damage &= ~int_dam_flag
	switch(int_dam_flag)
		if(MECHA_INT_TEMP_CONTROL)
			occupant_message("<font color='blue'><b>Life support system reactivated.</b></font>")
			pr_int_temp_processor.start()
		if(MECHA_INT_FIRE)
			occupant_message("<font color='blue'><b>Internal fire extinquished.</b></font>")
		if(MECHA_INT_TANK_BREACH)
			occupant_message("<font color='blue'><b>Damaged internal tank has been sealed.</b></font>")
	return


////////////////////////////////////////
////////  Health related procs  ////////
////////////////////////////////////////

/obj/mecha/proc/take_damage(amount, type="brute")
	if(amount)
		var/damage = absorb_damage(amount,type)
		health -= damage
		update_health()
		log_append_to_last("Took [damage] points of damage. Damage type: \"[type]\".",1)
	return

/obj/mecha/proc/take_flat_damage(amount, type="brute")
	if(amount)
		health -= amount
		update_health()
		log_append_to_last("Took [amount] points of damage.",1)
	return

/obj/mecha/proc/absorb_damage(damage,damage_type)
	return damage*(listgetindex(damage_absorption,damage_type) || 1)

/obj/mecha/proc/hit_damage(damage, type="brute", is_melee=0)

	var/power_to_use
	var/damage_coeff_to_use

	if(is_melee)
		power_to_use = mhit_power_use
		damage_coeff_to_use = m_damage_coeff
	else
		power_to_use = rhit_power_use
		damage_coeff_to_use = r_damage_coeff

	if(power_to_use && use_power(power_to_use))
		take_damage(round(damage*damage_coeff_to_use), type)
		start_booster_cooldown(is_melee)
		return
	else
		start_booster_cooldown(is_melee)
		take_damage(round(damage*damage_coeff_to_use), type)

	return

/obj/mecha/proc/deflect_hit(is_melee=0)

	var/power_to_use
	var/deflect_coeff_to_use

	if(is_melee)
		power_to_use = mhit_power_use
		deflect_coeff_to_use = m_damage_coeff
	else
		power_to_use = rhit_power_use
		deflect_coeff_to_use = r_damage_coeff

	if(power_to_use)
		if(prob(src.deflect_chance*deflect_coeff_to_use))
			use_power(power_to_use)
			start_booster_cooldown(is_melee)
			return 1
		else
			return 0

	else
		start_booster_cooldown(is_melee)
		if(prob(src.deflect_chance*deflect_coeff_to_use))
			return 1

	return 0

/obj/mecha/proc/start_booster_cooldown(is_melee)

	for(var/obj/item/mecha_parts/mecha_equipment/armor_booster/B in equipment) //Ideally this would be done by the armor booster itself; attempts weren't great for performance.
		if(B.melee == is_melee && B.equip_ready)
			B.set_ready_state(0)
			B.do_after_cooldown()

/obj/mecha/airlock_crush(var/crush_damage)
	..()
	hit_damage(crush_damage, is_melee=1)
	check_for_internal_damage(list(MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))
	return 1

/obj/mecha/proc/update_health()
	if(src.health > 0)
		src.spark_system.start()
	else
		qdel(src)
	return

/obj/mecha/attack_hand(mob/user as mob)
	src.log_message("Attack by hand/paw. Attacker - [user].",1)

	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.species.can_shred(user))
			if(!deflect_hit(is_melee=1))
				src.hit_damage(damage=15, is_melee=1)
				src.check_for_internal_damage(list(MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))
				playsound(src.loc, 'sound/weapons/slash.ogg', 50, 1, -1)
				to_chat(user, SPAN_DANGER("You slash at the armored suit!"))
				visible_message(SPAN_DANGER("\The [user] slashes at [src.name]'s armor!"))
			else
				src.log_append_to_last("Armor saved.")
				playsound(src.loc, 'sound/weapons/slash.ogg', 50, 1, -1)
				to_chat(user, SPAN_DANGER("Your claws had no effect!"))
				src.occupant_message(SPAN_NOTICE("\The [user]'s claws are stopped by the armor."))
				visible_message(SPAN_WARNING("\The [user] rebounds off [src.name]'s armor!"))
		else
			user.visible_message(SPAN_DANGER("\The [user] hits \the [src]. Nothing happens."),SPAN_DANGER("You hit \the [src] with no visible effect."))
			src.log_append_to_last("Armor saved.")
		return
	else if ((HULK in user.mutations) && !deflect_hit(is_melee=1))
		src.hit_damage(damage=15, is_melee=1)
		src.check_for_internal_damage(list(MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))
		user.visible_message("<font color='red'><b>[user] hits [src.name], doing some damage.</b></font>", "<font color='red'><b>You hit [src.name] with all your might. The metal creaks and bends.</b></font>")
	else
		user.visible_message("<font color='red'><b>[user] hits [src.name]. Nothing happens</b></font>","<font color='red'><b>You hit [src.name] with no visible effect.</b></font>")
		src.log_append_to_last("Armor saved.")
	return

/obj/mecha/hitby(atom/movable/A as mob|obj)
	..()
	src.log_message("Hit by [A].",1)
	if(istype(A, /obj/item/mecha_parts/mecha_tracking))
		A.forceMove(src)
		src.visible_message("The [A] fastens firmly to [src].")
		return
	if(deflect_hit(is_melee=0) || ismob(A))
		src.occupant_message(SPAN_NOTICE("\The [A] bounces off the armor."))
		src.visible_message("\The [A] bounces off \the [src] armor.")
		src.log_append_to_last("Armor saved.")
		if(isliving(A))
			var/mob/living/M = A
			M.take_organ_damage(10)
	else if(isobj(A))
		var/obj/O = A
		if(O.throwforce)
			src.hit_damage(O.throwforce, is_melee=0)
			src.check_for_internal_damage(list(MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))
	return

/obj/mecha/bullet_act(var/obj/item/projectile/Proj)
	if(Proj.firer == src.occupant) // Pass the projectile through if we fired it.
		return PROJECTILE_CONTINUE

	src.log_message("Hit by projectile. Type: [Proj.name]([Proj.check_armour]).",1)
	if(deflect_hit(is_melee=0))
		src.occupant_message(SPAN_NOTICE("The armor deflects incoming projectile."))
		src.visible_message("The [src.name] armor deflects the projectile.")
		src.log_append_to_last("Armor saved.")
		return

	if(!(Proj.nodamage))
		var/final_penetration = Proj.penetrating ? Proj.penetrating - src.armor_level : 0
		var/damage_multiplier = final_penetration > 0 ? max(1.5, final_penetration) : 1 // Minimum damage bonus of 50% if you beat the mech's armor
		Proj.penetrating = 0 // Reduce this value to maintain the old penetration loop's behavior
		src.hit_damage(Proj.get_structure_damage() * damage_multiplier, Proj.check_armour, is_melee=0)

		//AP projectiles have a chance to cause additional damage
		if(final_penetration > 0)
			for(var/i in 0 to min(final_penetration, round(Proj.get_total_damage()/15)))
				if(prob(20))
					src.occupant_message(SPAN_WARNING("Your armor was penetrated and a component was damaged!."))
					src.visible_message("Sparks fly from the [src.name] as the projectile strikes a critical component!")
					spark_system.start()
					// check_internal_damage rolls a chance to damage again, so do our own critical damage handling here to guarantee that a component is damaged.
					var/list/possible_int_damage = list(MECHA_INT_FIRE,MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST,MECHA_INT_SHORT_CIRCUIT)
					if(prob(90))
						for(var/T in possible_int_damage)
							if(internal_damage & T)
								possible_int_damage -= T
						var/int_dam_flag = safepick(possible_int_damage)
						if(int_dam_flag)
							setInternalDamage(int_dam_flag)
					else
						var/obj/item/mecha_parts/mecha_equipment/destr = safepick(equipment)
						if(destr)
							destr.destroy()
					break // Only allow one critical hit per penetration

				final_penetration--

				if(prob(15))
					break //give a chance to exit early

	Proj.on_hit(src) //on_hit just returns if it's argument is not a living mob so does this actually do anything?
	..()
	return

/obj/mecha/ex_act(severity)
	src.log_message("Affected by explosion of severity: [severity].",1)
	if(prob(src.deflect_chance))
		severity++
		src.log_append_to_last("Armor saved, changing severity to [severity].")
	// This formula is designed to one-shot anything less armored than a Phazon taking a severity 1 explosion.
	// This formula does the same raw damage (aside from one-shotting) as the previous formula against a Durand, but deals more final damage due to being unmitigated by damage resistance.
	var/damage_proportion = 1 / max(1, (severity + max(0, armor_level - 2)))
	src.take_flat_damage(initial(src.health) * damage_proportion)
	src.check_for_internal_damage(list(MECHA_INT_FIRE,MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST,MECHA_INT_SHORT_CIRCUIT),1)
	return

/*Will fix later -Sieve
/obj/mecha/attack_blob(mob/user as mob)
	src.log_message("Attack by blob. Attacker - [user].",1)
	if(!prob(src.deflect_chance))
		src.take_damage(6)
		src.check_for_internal_damage(list(MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))
		playsound(src.loc, 'sound/effects/blobattack.ogg', 50, 1, -1)
		to_chat(user, SPAN_DANGER("You smash at the armored suit!"))
		for (var/mob/V in viewers(src))
			if(V.client && !(V.blinded))
				V.show_message(SPAN_DANGER("\The [user] smashes against [src.name]'s armor!"), 1)
	else
		src.log_append_to_last("Armor saved.")
		playsound(src.loc, 'sound/effects/blobattack.ogg', 50, 1, -1)
		to_chat(user, SPAN_WARNING("Your attack had no effect!"))
		src.occupant_message(SPAN_WARNING("\The [user]'s attack is stopped by the armor."))
		for (var/mob/V in viewers(src))
			if(V.client && !(V.blinded))
				V.show_message(SPAN_WARNING("\The [user] rebounds off the [src.name] armor!"), 1)
	return
*/

/obj/mecha/emp_act(severity)
	if(use_power((cell.charge/2)/severity))
		take_damage(50 / severity,"energy")
	src.log_message("EMP detected",1)
	check_for_internal_damage(list(MECHA_INT_FIRE,MECHA_INT_TEMP_CONTROL,MECHA_INT_CONTROL_LOST,MECHA_INT_SHORT_CIRCUIT),1)
	return

/obj/mecha/fire_act(datum/gas_mixture/air, exposed_temperature, exposed_volume)
	if(exposed_temperature>src.max_temperature)
		src.log_message("Exposed to dangerous temperature.",1)
		src.take_damage(5,"fire")
		src.check_for_internal_damage(list(MECHA_INT_FIRE, MECHA_INT_TEMP_CONTROL))
	return


//////////////////////
////// AttackBy //////
//////////////////////

/obj/mecha/attackby(obj/item/I, mob/user)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)

	var/list/usable_qualities = list()
	if(state == 1 || state == 2)
		usable_qualities.Add(QUALITY_BOLT_TURNING)
	if(user.a_intent != I_HURT)
		usable_qualities.Add(QUALITY_WELDING)
	if(hasInternalDamage(MECHA_INT_TEMP_CONTROL) || (state==3 && src.cell) || (state==4 && src.cell))
		usable_qualities.Add(QUALITY_SCREW_DRIVING)
	if(state == 2 || state == 3)
		usable_qualities.Add(QUALITY_PRYING)
	if((state >= 3 && src.occupant) || src.dna)
		usable_qualities.Add(QUALITY_PULSING)

	var/tool_type = I.get_tool_type(user, usable_qualities, src)
	switch(tool_type)

		if(QUALITY_BOLT_TURNING)
			if(!user.stat_check(STAT_MEC, STAT_LEVEL_ADEPT))
				to_chat(usr, SPAN_WARNING("You lack the mechanical knowledge to do this!"))
				return
			if(state == 1)
				if(I.use_tool(user, src, WORKTIME_FAST, tool_type, FAILCHANCE_NORMAL, required_stat = STAT_MEC))
					to_chat(user, SPAN_NOTICE("You undo the securing bolts and deploy the rollers."))
					state = 2
					anchored = 0
					return
			if(state == 2)
				if(I.use_tool(user, src, WORKTIME_FAST, tool_type, FAILCHANCE_NORMAL, required_stat = STAT_MEC))
					to_chat(user, SPAN_NOTICE("You tighten the securing bolts and undeploy the rollers."))
					state = 1
					anchored = 1
					return
			return

		if(QUALITY_WELDING)
			if(user.a_intent != I_HURT)
				if(!user.stat_check(STAT_MEC, STAT_LEVEL_ADEPT))
					to_chat(usr, SPAN_WARNING("You lack the mechanical knowledge to do this!"))
					return
				if(src.health >= initial(src.health))
					to_chat(user, SPAN_NOTICE("The [src.name] is at full integrity"))
				if(I.use_tool(user, src, WORKTIME_FAST, tool_type, FAILCHANCE_NORMAL, required_stat = STAT_MEC))
					if (hasInternalDamage(MECHA_INT_TANK_BREACH))
						clearInternalDamage(MECHA_INT_TANK_BREACH)
						to_chat(user, SPAN_NOTICE("You repair the damaged gas tank."))
					if(src.health<initial(src.health))
						var/missing_health = initial(src.health) - src.health
						user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
						var/user_mec = max(0, user.stats.getStat(STAT_MEC))
						if(state == 3)
							to_chat(user, SPAN_NOTICE("You are able to repair more damage to [src.name] from the inside."))
							src.health += min(initial(src.health) * (user_mec / 100), missing_health)
						else
							to_chat(user, SPAN_NOTICE("You repair some damage to [src.name]."))
							src.health += min(user.stats.getStat(STAT_MEC) * 2, missing_health)
					return
			return

		if(QUALITY_PRYING)
			if(!user.stat_check(STAT_MEC, STAT_LEVEL_ADEPT))
				to_chat(usr, SPAN_WARNING("You lack the mechanical knowledge to do this!"))
				return
			if(state == 2)
				if(I.use_tool(user, src, WORKTIME_FAST, tool_type, FAILCHANCE_NORMAL, required_stat = STAT_MEC))
					to_chat(user, SPAN_NOTICE("You open the hatch to the power unit."))
					state = 3
					if(!cell)
						state = 4
					return
			if(state == 3)
				if(I.use_tool(user, src, WORKTIME_FAST, tool_type, FAILCHANCE_NORMAL, required_stat = STAT_MEC))
					to_chat(user, SPAN_NOTICE("You close the hatch to the power unit"))
					state = 2
					return
			return

		if(QUALITY_SCREW_DRIVING)
			if(!user.stat_check(STAT_MEC, STAT_LEVEL_ADEPT))
				to_chat(usr, SPAN_WARNING("You lack the mechanical knowledge to do this!"))
				return
			if(hasInternalDamage(MECHA_INT_TEMP_CONTROL))
				if(I.use_tool(user, src, WORKTIME_FAST, tool_type, FAILCHANCE_NORMAL, required_stat = STAT_MEC))
					to_chat(user, SPAN_NOTICE("You repair the damaged temperature controller."))
					clearInternalDamage(MECHA_INT_TEMP_CONTROL)
					return
			if(state == 3 && src.cell)
				if(I.use_tool(user, src, WORKTIME_FAST, tool_type, FAILCHANCE_NORMAL, required_stat = STAT_MEC))
					to_chat(user, SPAN_NOTICE("You unscrew and pry out the powercell."))
					src.cell.forceMove(src.loc)
					src.cell = null
					state = 4
					src.log_message("Powercell removed.")
			if(state == 4 && src.cell)
				if(I.use_tool(user, src, WORKTIME_FAST, tool_type, FAILCHANCE_NORMAL, required_stat = STAT_MEC))
					to_chat(user, SPAN_NOTICE("You screw the cell in place."))
					state = 3
					return
			return

		if(QUALITY_PULSING)
			if(!user.stat_check(STAT_MEC, STAT_LEVEL_ADEPT))
				to_chat(usr, SPAN_WARNING("You lack the mechanical knowledge to do this!"))
				return
			if(state >= 3 && src.occupant)
				to_chat(user, "You attempt to eject the pilot using the maintenance controls.")
				if(I.use_tool(user, src, WORKTIME_FAST, tool_type, FAILCHANCE_NORMAL, required_stat = STAT_MEC))
					if(src.occupant.stat)
						src.go_out()
						src.log_message("[src.occupant] was ejected using the maintenance controls.")
					else
						to_chat(user, SPAN_WARNING("Your attempt is rejected."))
						src.occupant_message(SPAN_WARNING("An attempt to eject you was made using the maintenance controls."))
						src.log_message("Eject attempt made using maintenance controls - rejected.")
					return
			if(src.dna)
				if(I.use_tool(user, src, WORKTIME_LONG, tool_type, FAILCHANCE_VERY_HARD, required_stat = STAT_MEC))
					src.dna = null
					to_chat(user, SPAN_WARNING("You have reset the mech's DNA lock forcefuly."))
					src.log_message("DNA lock was forcefuly removed.")
				else
					to_chat(user, SPAN_WARNING("You failed to reset the mech's DNA lock."))
					src.log_message("A failed attempt at reseting the DNA lock has been logged.")
			return

		if(ABORT_CHECK)
			return

	if(istype(I, /obj/item/mecha_parts/mecha_equipment))
		if(!user.stat_check(STAT_MEC, STAT_LEVEL_ADEPT))
			to_chat(usr, SPAN_WARNING("You lack the mechanical knowledge to do this!"))
			return

		var/obj/item/mecha_parts/mecha_equipment/E = I
		spawn()
			if(E.can_attach(src))
				user.drop_item()
				E.attach(src)
				user.visible_message("[user] attaches [I] to [src]", "You attach [I] to [src]")
			else
				to_chat(user, "You were unable to attach [I] to [src]")
		return

	var/obj/item/card/id/id_card = I.GetIdCard()
	if(id_card)
		if(add_req_access || maint_access)
			if(internals_access_allowed(usr))
				output_maintenance_dialog(id_card, user)
				return
			else
				to_chat(user, SPAN_WARNING("Invalid ID: Access denied."))
		else
			to_chat(user, SPAN_WARNING("Maintenance protocols disabled by operator."))

	else if(istype(I, /obj/item/stack/cable_coil))
		if(!user.stat_check(STAT_MEC, STAT_LEVEL_ADEPT))
			to_chat(usr, SPAN_WARNING("You lack the mechanical knowledge to do this!"))
			return

		if(state == 3 && hasInternalDamage(MECHA_INT_SHORT_CIRCUIT))
			var/obj/item/stack/cable_coil/CC = I
			if(CC.use(2))
				clearInternalDamage(MECHA_INT_SHORT_CIRCUIT)
				to_chat(user, "You replace the fused wires.")
			else
				to_chat(user, "There's not enough wire to finish the task.")
		return

	else if(istype(I, /obj/item/cell/large))
		if(state == 4 || (state == 3 && !cell))
			if(!src.cell)
				to_chat(user, "You install the powercell")
				user.drop_item()
				I.forceMove(src)
				src.cell = I
				src.log_message("Powercell installed")
				state = 4
			else
				to_chat(user, "There's already a powercell installed.")
		return

	else if(istype(I, /obj/item/mecha_parts/mecha_tracking))
		user.drop_from_inventory(I)
		I.forceMove(src)
		user.visible_message("[user] attaches [I] to [src].", "You attach [I] to [src]")
		return

	else if(istype(I, /obj/item/mech_ammo_box))
		for(var/i = ammo.len to 1 step -1) // Check each spot in the ammobox list
			if(ammo[i] == null) // No box in the way.
				insert_item(I, user)
				ammo[i] = I
				user.visible_message("[user] attaches [I] to [src].", "You attach [I] to [src]")
				src.log_message("Ammobox [I] inserted by [user]")
				return

	else
		src.log_message("Attacked by [I]. Attacker - [user]")

		if(deflect_hit(is_melee=1))
			to_chat(user, SPAN_DANGER("\The [I] bounces off [src.name]."))
			src.log_append_to_last("Armor saved.")
		else
			src.occupant_message("<font color='red'><b>[user] hits [src] with [I].</b></font>")
			user.visible_message("<font color='red'><b>[user] hits [src] with [I].</b></font>", "<font color='red'><b>You hit [src] with [I].</b></font>")
			src.hit_damage(I.force, I.damtype, is_melee=1)
			src.check_for_internal_damage(list(MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))

	return

/*
/obj/mecha/attack_ai(var/mob/living/silicon/ai/user as mob)
	if(!isAI(user))
		return
	var/output = {"<b>Assume direct control over [src]?</b>
						<a href='?src=\ref[src];ai_take_control=\ref[user];duration=3000'>Yes</a><br>
						"}
	user << browse(output, "window=mecha_attack_ai")
	return
*/

/////////////////////////////////////
////////  Atmospheric stuff  ////////
/////////////////////////////////////

/obj/mecha/proc/get_turf_air()
	var/turf/T = get_turf(src)
	if(T)
		. = T.return_air()
	return

/obj/mecha/remove_air(amount)
	if(use_internal_tank)
		return cabin_air.remove(amount)
	else
		var/turf/T = get_turf(src)
		if(T)
			return T.remove_air(amount)
	return

/obj/mecha/return_air()
	if(use_internal_tank)
		return cabin_air
	return get_turf_air()

/obj/mecha/proc/return_pressure()
	. = 0
	if(use_internal_tank)
		. =  cabin_air.return_pressure()
	else
		var/datum/gas_mixture/t_air = get_turf_air()
		if(t_air)
			. = t_air.return_pressure()
	return

//skytodo: //No idea what you want me to do here, mate.
/obj/mecha/proc/return_temperature()
	. = 0
	if(use_internal_tank)
		. = cabin_air.temperature
	else
		var/datum/gas_mixture/t_air = get_turf_air()
		if(t_air)
			. = t_air.temperature
	return

/obj/mecha/proc/connect(obj/machinery/atmospherics/portables_connector/new_port)
	//Make sure not already connected to something else
	if(connected_port || !new_port || new_port.connected_device)
		return 0

	//Make sure are close enough for a valid connection
	if(new_port.loc != src.loc)
		return 0

	//Perform the connection
	connected_port = new_port
	connected_port.connected_device = src

	//Actually enforce the air sharing
	var/datum/pipe_network/network = connected_port.return_network(src)
	if(network && !(internal_tank.return_air() in network.gases))
		network.gases += internal_tank.return_air()
		network.update = 1
	log_message("Connected to gas port.")
	return 1

/obj/mecha/proc/disconnect()
	if(!connected_port)
		return 0

	var/datum/pipe_network/network = connected_port.return_network(src)
	if(network)
		network.gases -= internal_tank.return_air()

	connected_port.connected_device = null
	connected_port = null
	src.log_message("Disconnected from gas port.")
	return 1


/////////////////////////
////////  Verbs  ////////
/////////////////////////


/obj/mecha/verb/connect_to_port()
	set name = "Connect to port"
	set category = "Exosuit Interface"
	set src = usr.loc
	set popup_menu = 0
	if(!src.occupant) return
	if(usr!=src.occupant)
		return
	var/obj/machinery/atmospherics/portables_connector/possible_port = locate(/obj/machinery/atmospherics/portables_connector/) in loc
	if(possible_port)
		if(connect(possible_port))
			src.occupant_message(SPAN_NOTICE("\The [name] connects to the port."))
			src.verbs += /obj/mecha/verb/disconnect_from_port
			src.verbs -= /obj/mecha/verb/connect_to_port
			return
		else
			src.occupant_message(SPAN_DANGER("\The [name] failed to connect to the port."))
			return
	else
		src.occupant_message("Nothing happens")


/obj/mecha/verb/disconnect_from_port()
	set name = "Disconnect from port"
	set category = "Exosuit Interface"
	set src = usr.loc
	set popup_menu = 0
	if(!src.occupant) return
	if(usr!=src.occupant)
		return
	if(disconnect())
		src.occupant_message(SPAN_NOTICE("[name] disconnects from the port."))
		src.verbs -= /obj/mecha/verb/disconnect_from_port
		src.verbs += /obj/mecha/verb/connect_to_port
	else
		src.occupant_message(SPAN_DANGER("[name] is not connected to the port at the moment."))

/obj/mecha/verb/toggle_lights()
	set name = "Toggle Lights"
	set category = "Exosuit Interface"
	set src = usr.loc
	set popup_menu = 0
	if(usr!=occupant)	return
	lights = !lights
	if(lights)	set_light(light_range + lights_power)
	else		set_light(light_range - lights_power)
	src.occupant_message("Toggled lights [lights?"on":"off"].")
	log_message("Toggled lights [lights?"on":"off"].")
	return


/obj/mecha/verb/toggle_internal_tank()
	set name = "Toggle internal airtank usage."
	set category = "Exosuit Interface"
	set src = usr.loc
	set popup_menu = 0
	if(usr!=src.occupant)
		return
	use_internal_tank = !use_internal_tank
	src.occupant_message("Now taking air from [use_internal_tank?"internal airtank":"environment"].")
	src.log_message("Now taking air from [use_internal_tank?"internal airtank":"environment"].")
	return

/obj/mecha/verb/attempt_enter()
	set category = "Object"
	set name = "Enter Exosuit"
	set src in oview(1)

	move_inside(usr)

/obj/mecha/MouseDrop_T(var/mob/target, var/mob/user)
	if(istype(user) && target == user)
		move_inside(user)

/obj/mecha/proc/move_inside(mob/user)

	if (user.stat || !ishuman(user))
		return

	if (user.buckled)
		to_chat(user, SPAN_WARNING("You can't climb into the exosuit while buckled!"))
		return

	if(istype(user.get_equipped_item(slot_back), /obj/item/rig/ameridian_knight))
		to_chat(user, SPAN_WARNING("Your armor is too bulky to fit in the exosuit!"))
		return

	src.log_message("[user] tries to move in.")
	if(iscarbon(user))
		var/mob/living/carbon/C = user
		if(C.handcuffed)
			to_chat(user, SPAN_DANGER("Kinda hard to climb in while handcuffed don't you think?"))
			return
	if (src.occupant)
		user << sound('sound/mecha/UI_SCI-FI_Tone_Deep_Wet_15_stereo_error.ogg',channel = 4, volume = 100)
		to_chat(user, SPAN_DANGER("The [src.name] is already occupied!"))
		src.log_append_to_last("Permission denied.")
		return
/*
	if (usr.abiotic())
		to_chat(user, SPAN_NOTICE("Subject cannot have abiotic items on."))
		return
*/
	var/passed
	if(src.dna)
		if(user.dna.unique_enzymes==src.dna)
			passed = 1
	else if(src.operation_allowed(user))
		passed = 1
	if(!passed)
		user << sound('sound/mecha/UI_SCI-FI_Tone_Deep_Wet_15_stereo_error.ogg',channel = 4, volume = 100)
		to_chat(user, SPAN_WARNING("Access denied"))
		src.log_append_to_last("Permission denied.")
		return
	for(var/mob/living/carbon/slime/M in range(1,user))
		if(M.Victim == user)
			to_chat(user, "You're too busy getting your life sucked out of you.")
			return
//	usr << "You start climbing into [src.name]"

	visible_message(SPAN_NOTICE("\The [user] starts to climb into [src.name]"))

	if(enter_after(40,usr))
		if(!src.occupant)
			moved_inside(user)
		else if(src.occupant!=user)
			to_chat(user, "[src.occupant] was faster. Try better next time, loser.")
	else
		to_chat(user, "You stop entering the exosuit.")
	return

/obj/mecha/proc/moved_inside(var/mob/living/carbon/human/H as mob)
	if(H && H.client && (H in range(1)))
		H.reset_view(src)
		/*
		H.client.perspective = EYE_PERSPECTIVE
		H.client.eye = src
		*/
		H.stop_pulling()
		H.forceMove(src)
		src.occupant = H
		src.add_fingerprint(H)
		src.forceMove(src.loc)
		src.log_append_to_last("[H] moved in as pilot.")
		src.update_icon()
		set_dir(dir_in)
		playsound(src, 'sound/machines/windowdoor.ogg', 50, 1)
		if(!hasInternalDamage())
			src.occupant << sound('sound/mecha/nominal.ogg',volume=50)
		return 1
	else
		return 0

/obj/mecha/verb/view_stats()
	set name = "View Stats"
	set category = "Exosuit Interface"
	set src = usr.loc
	set popup_menu = 0
	if(usr!=src.occupant)
		return
	//pr_update_stats.start()
	src.occupant << browse(src.get_stats_html(), "window=exosuit")
	return

/obj/mecha/verb/reload()
	set name = "Reload Gun"
	set category = "Exosuit Interface"
	set popup_menu = 0
	set src = usr.loc
	if(usr!=src.occupant)
		return
	reload_gun() // Reload the mech's active gun

/*
/obj/mecha/verb/force_eject()
	set category = "Object"
	set name = "Force Eject"
	set src in view(5)
	src.go_out()
	return
*/

/obj/mecha/verb/eject()
	set name = "Eject"
	set category = "Exosuit Interface"
	set src = usr.loc
	set popup_menu = 0
	if(usr!=src.occupant)
		return
	src.go_out()
	add_fingerprint(usr)
	return

/obj/mecha/verb/AIeject()
	set name = "AI Eject"
	set category = "Exosuit Interface"
	set popup_menu = 0

	var/atom/movable/mob_container
	if(ishuman(occupant) || isAI(occupant))
		mob_container = src.occupant

	if(usr!=src.occupant)
		return

	if(isAI(mob_container))
		var/obj/item/mecha_parts/mecha_equipment/tool/ai_holder/AH = locate() in src
		if(AH)
			AH.go_out()

/obj/mecha/proc/go_out()
	if(!src.occupant) return
	var/atom/movable/mob_container
	if(ishuman(occupant) || isAI(occupant))
		mob_container = src.occupant
	else if(isbrain(occupant))
		var/mob/living/carbon/brain/brain = occupant
		mob_container = brain.container
	else
		return
	for(var/item in dropped_items)
		var/atom/movable/I = item
		I.forceMove(loc)
	dropped_items.Cut()

	if(isAI(mob_container))
		AIeject()
		return

	//Eject for AI in mecha
	if(mob_container.forceMove(src.loc))//ejecting mob container

		src.log_message("[mob_container] moved out.")
		occupant.reset_view()
		/*
		if(src.occupant.client)
			src.occupant.client.eye = src.occupant.client.mob
			src.occupant.client.perspective = MOB_PERSPECTIVE
		*/
		src.occupant << browse(null, "window=exosuit")
		if(istype(mob_container, /obj/item/device/mmi))
			var/obj/item/device/mmi/mmi = mob_container
			if(mmi.brainmob)
				occupant.loc = mmi
			mmi.mecha = null
			src.occupant.canmove = 0
			src.verbs += /obj/mecha/verb/eject
		src.occupant = null
		src.update_icon()
		src.set_dir(dir_in)


	if(mob_container.forceMove(src.loc))//ejecting mob container
	/*
		if(ishuman(occupant) && (return_pressure() > HAZARD_HIGH_PRESSURE))
			use_internal_tank = 0
			var/datum/gas_mixture/environment = get_turf_air()
			if(environment)
				var/env_pressure = environment.return_pressure()
				var/pressure_delta = (cabin.return_pressure() - env_pressure)
		//Can not have a pressure delta that would cause environment pressure > tank pressure

				var/transfer_moles = 0
				if(pressure_delta > 0)
					transfer_moles = pressure_delta*environment.volume/(cabin.return_temperature() * R_IDEAL_GAS_EQUATION)

			//Actually transfer the gas
					var/datum/gas_mixture/removed = cabin.air_contents.remove(transfer_moles)
					loc.assume_air(removed)

			occupant.SetStunned(5)
			occupant.SetWeakened(5)
			to_chat(occupant, "You were blown out of the mech!")
	*/
		src.log_message("[mob_container] moved out.")
		occupant.reset_view()
		/*
		if(src.occupant.client)
			src.occupant.client.eye = src.occupant.client.mob
			src.occupant.client.perspective = MOB_PERSPECTIVE
		*/
		src.occupant << browse(null, "window=exosuit")
		if(istype(mob_container, /obj/item/device/mmi))
			var/obj/item/device/mmi/mmi = mob_container
			if(mmi.brainmob)
				occupant.loc = mmi
			mmi.mecha = null
			src.occupant.canmove = 0
			src.verbs += /obj/mecha/verb/eject
		src.occupant = null
		update_icon()
		src.set_dir(dir_in)
	return

/////////////////////////
////// Access stuff /////
/////////////////////////

/obj/mecha/proc/operation_allowed(mob/living/carbon/human/H)
	for(var/ID in list(H.get_active_hand(), H.wear_id, H.belt))
		if(src.check_access(ID, operation_req_access))
			return TRUE
	return FALSE


/obj/mecha/proc/internals_access_allowed(mob/living/carbon/human/H)
	for(var/atom/ID in list(H.get_active_hand(), H.wear_id, H.belt))
		if(src.check_access(ID, internals_req_access))
			return TRUE
	return FALSE

/obj/mecha/proc/dna_reset_allowed(mob/living/carbon/human/H)
	for(var/atom/ID in list(H.get_active_hand(), H.wear_id, H.belt))
		if(src.check_access(ID, dna_req_access))
			return TRUE
	return FALSE


/obj/mecha/check_access(obj/item/card/id/I, list/access_list)
	if(!istype(access_list))
		return TRUE
	if(!access_list.len) //no requirements
		return TRUE

	var/list/user_access = I ? I.GetAccess() : list()

	if(access_list==src.operation_req_access)
		for(var/req in access_list)
			if(!(req in user_access)) //doesn't have this access
				return FALSE
	else if(access_list == src.internals_req_access || access_list == src.dna_req_access)
		for(var/req in access_list)
			if(req in user_access)
				return TRUE
		return FALSE
	return TRUE


////////////////////////////////////
///// Rendering stats window ///////
////////////////////////////////////

/obj/mecha/proc/get_stats_html()
	var/output = {"<html>
						<head><title>[src.name] data</title>
						<style>
						body {color: #00ff00; background: #000000; font-family:"Lucida Console",monospace; font-size: 12px;}
						hr {border: 1px solid #0f0; color: #0f0; background-color: #0f0;}
						a {padding:2px 5px;;color:#0f0;}
						.wr {margin-bottom: 5px;}
						.header {cursor:pointer;}
						.open, .closed {background: #32CD32; color:#000; padding:1px 2px;}
						.links a {margin-bottom: 2px;padding-top:3px;}
						.visible {display: block;}
						.hidden {display: none;}
						</style>
						<script language='javascript' type='text/javascript'>
						[js_byjax]
						[js_dropdowns]
						function ticker() {
						    setInterval(function(){
						        window.location='byond://?src=\ref[src]&update_content=1';
						    }, 1000);
						}

						window.onload = function() {
							dropdowns();
							ticker();
						}
						</script>
						</head>
						<body>
						<div id='content'>
						[src.get_stats_part()]
						</div>
						<div id='eq_list'>
						[src.get_equipment_list()]
						</div>
						<hr>
						<div id='commands'>
						[src.get_commands()]
						</div>
						</body>
						</html>
					 "}
	return output


/obj/mecha/proc/report_internal_damage()
	var/output = null
	var/list/dam_reports = list(
										"[MECHA_INT_FIRE]" = "<font color='red'><b>INTERNAL FIRE</b></font>",
										"[MECHA_INT_TEMP_CONTROL]" = "<font color='red'><b>LIFE SUPPORT SYSTEM MALFUNCTION</b></font>",
										"[MECHA_INT_TANK_BREACH]" = "<font color='red'><b>GAS TANK BREACH</b></font>",
										"[MECHA_INT_CONTROL_LOST]" = "<font color='red'><b>COORDINATION SYSTEM CALIBRATION FAILURE</b></font> - <a href='?src=\ref[src];repair_int_control_lost=1'>Recalibrate</a>",
										"[MECHA_INT_SHORT_CIRCUIT]" = "<font color='red'><b>SHORT CIRCUIT</b></font>"
										)
	for(var/tflag in dam_reports)
		var/intdamflag = text2num(tflag)
		if(hasInternalDamage(intdamflag))
			output += dam_reports[tflag]
			output += "<br />"
	if(return_pressure() > WARNING_HIGH_PRESSURE)
		output += "<font color='red'><b>DANGEROUSLY HIGH CABIN PRESSURE</b></font><br />"
	return output


/obj/mecha/proc/get_stats_part()
	var/integrity = health/initial(health)*100
	var/cell_charge = get_charge()
	var/tank_pressure = internal_tank ? round(internal_tank.return_pressure(),0.01) : "None"
	var/tank_temperature = internal_tank ? "[internal_tank.return_temperature()]K|[internal_tank.return_temperature() - T0C]&deg;C" : "Unknown" //Results in type mismatch if there is no tank.
	var/cabin_pressure = round(return_pressure(),0.01)
	var/output = {"[report_internal_damage()]
						[integrity<30?"<font color='red'><b>DAMAGE LEVEL CRITICAL</b></font><br>":null]
						<b>Integrity: </b> [integrity]%<br>
						<b>Powercell charge: </b>[isnull(cell_charge)?"No powercell installed":"[cell.percent()]%"]<br>
						<b>Air source: </b>[use_internal_tank?"Internal Airtank":"Environment"]<br>
						<b>Airtank pressure: </b>[tank_pressure]kPa<br>
						<b>Airtank temperature: </b>[tank_temperature]<br>
						<b>Cabin pressure: </b>[cabin_pressure>WARNING_HIGH_PRESSURE ? "<font color='red'>[cabin_pressure]</font>": cabin_pressure]kPa<br>
						<b>Cabin temperature: </b> [return_temperature()]K|[return_temperature() - T0C]&deg;C<br>
						<b>Lights: </b>[lights?"on":"off"]<br>
						[src.dna?"<b>DNA-locked:</b><br> <span style='font-size:10px;letter-spacing:-1px;'>[src.dna]</span> \[<a href='?src=\ref[src];reset_dna=1'>Reset</a>\]<br>":null]
					"}
	return output

/obj/mecha/proc/get_commands()
	var/output = {"<div class='wr'>
						<div class='header'>Electronics</div>
						<div class='links'>
						<a href='?src=\ref[src];toggle_lights=1'>Toggle Lights</a><br>
						<b>Radio settings:</b><br>
						Microphone: <a href='?src=\ref[src];rmictoggle=1'><span id="rmicstate">[radio.broadcasting?"Engaged":"Disengaged"]</span></a><br>
						Speaker: <a href='?src=\ref[src];rspktoggle=1'><span id="rspkstate">[radio.listening?"Engaged":"Disengaged"]</span></a><br>
						Frequency:
						<a href='?src=\ref[src];rfreq=-10'>-</a>
						<a href='?src=\ref[src];rfreq=-2'>-</a>
						<span id="rfreq">[format_frequency(radio.frequency)]</span>
						<a href='?src=\ref[src];rfreq=2'>+</a>
						<a href='?src=\ref[src];rfreq=10'>+</a><br>
						</div>
						</div>
						<div class='wr'>
						<div class='header'>Airtank</div>
						<div class='links'>
						<a href='?src=\ref[src];toggle_airtank=1'>Toggle Internal Airtank Usage</a><br>
						[(/obj/mecha/verb/disconnect_from_port in src.verbs)?"<a href='?src=\ref[src];port_disconnect=1'>Disconnect from port</a><br>":null]
						[(/obj/mecha/verb/connect_to_port in src.verbs)?"<a href='?src=\ref[src];port_connect=1'>Connect to port</a><br>":null]
						</div>
						</div>
						<div class='wr'>
						<div class='header'>Permissions & Logging</div>
						<div class='links'>
						<a href='?src=\ref[src];toggle_id_upload=1'><span id='t_id_upload'>[add_req_access?"L":"Unl"]ock ID upload panel</span></a><br>
						<a href='?src=\ref[src];toggle_maint_access=1'><span id='t_maint_access'>[maint_access?"Forbid":"Permit"] maintenance protocols</span></a><br>
						<a href='?src=\ref[src];dna_lock=1'>DNA-Lock</a><br>
						<a href='?src=\ref[src];view_log=1'>View internal log</a><br>
						<a href='?src=\ref[src];change_name=1'>Change exosuit name</a><br>
						</div>
						</div>
						<div id='equipment_menu'>[get_equipment_menu()]</div>
						<hr>
						[(/obj/mecha/verb/eject in src.verbs)?"<a href='?src=\ref[src];eject=1'>Eject</a><br>":null]
						"}
	return output

/obj/mecha/proc/get_equipment_menu() //outputs mecha html equipment menu
	var/output
	if(equipment.len)
		output += {"<div class='wr'>
						<div class='header'>Equipment</div>
						<div class='links'>"}
		for(var/obj/item/mecha_parts/mecha_equipment/W in equipment)
			output += "[W.name] <a href='?src=\ref[W];detach=1'>Detach</a><br>"
		output += "<b>Available equipment slots:</b> [max_equip-equipment.len]"
		output += "</div></div>"
	return output

/obj/mecha/proc/get_equipment_list() //outputs mecha equipment list in html
	if(!equipment.len)
		return
	var/output = "<b>Equipment:</b><div style=\"margin-left: 15px;\">"
	for(var/obj/item/mecha_parts/mecha_equipment/MT in equipment)
		output += "<div id='\ref[MT]'>[MT.get_equip_info()]</div>"
	output += "</div>"
	return output


/obj/mecha/proc/get_log_html()
	var/output = "<html><head><title>[src.name] Log</title></head><body style='font: 13px 'Courier', monospace;'>"
	for(var/list/entry in log)
		output += {"<div style='font-weight: bold;'>[time2text(entry["time"],"DDD MMM DD hh:mm:ss")] [game_year]</div>
						<div style='margin-left:15px; margin-bottom:10px;'>[entry["message"]]</div>
						"}
	output += "</body></html>"
	return output


/obj/mecha/proc/output_access_dialog(obj/item/card/id/id_card, mob/user)
	if(!id_card || !user) return
	var/output = {"<html>
						<head><style>
						h1 {font-size:15px;margin-bottom:4px;}
						body {color: #00ff00; background: #000000; font-family:"Courier New", Courier, monospace; font-size: 12px;}
						a {color:#0f0;}
						</style>
						</head>
						<body>
						<h1>Following keycodes are present in this system:</h1>"}
	for(var/a in operation_req_access)
		output += "[get_access_desc(a)] - <a href='?src=\ref[src];del_req_access=[a];user=\ref[user];id_card=\ref[id_card]'>Delete</a><br>"
	output += "<hr><h1>Following keycodes were detected on portable device:</h1>"
	for(var/a in id_card.access)
		if(a in operation_req_access) continue
		var/a_name = get_access_desc(a)
		if(!a_name) continue //there's some strange access without a name
		output += "[a_name] - <a href='?src=\ref[src];add_req_access=[a];user=\ref[user];id_card=\ref[id_card]'>Add</a><br>"
	output += "<hr><a href='?src=\ref[src];finish_req_access=1;user=\ref[user]'>Finish</a> <font color='red'>(Warning! The ID upload panel will be locked. It can be unlocked only through Exosuit Interface.)</font>"
	output += "</body></html>"
	user << browse(output, "window=exosuit_add_access")
	onclose(user, "exosuit_add_access")
	return

/obj/mecha/proc/output_maintenance_dialog(obj/item/card/id/id_card,mob/user)
	if(!id_card || !user) return

	var/maint_options = "<a href='?src=\ref[src];set_internal_tank_valve=1;user=\ref[user]'>Set Cabin Air Pressure</a>"
	if (locate(/obj/item/mecha_parts/mecha_equipment/tool/passenger) in contents)
		maint_options += "<a href='?src=\ref[src];remove_passenger=1;user=\ref[user]'>Remove Passenger</a>"
	if (src.dna)
		maint_options += "<a href='?src=\ref[src];maint_reset_dna=1;user=\ref[user]'>Revert DNA-Lock</a>"

	var/output = {"<html>
						<head>
						<style>
						body {color: #00ff00; background: #000000; font-family:"Courier New", Courier, monospace; font-size: 12px;}
						a {padding:2px 5px; background:#32CD32;color:#000;display:block;margin:2px;text-align:center;text-decoration:none;}
						</style>
						</head>
						<body>
						[add_req_access?"<a href='?src=\ref[src];req_access=1;id_card=\ref[id_card];user=\ref[user]'>Edit operation keycodes</a>":null]
						[maint_access?"<a href='?src=\ref[src];maint_access=1;id_card=\ref[id_card];user=\ref[user]'>Initiate maintenance protocol</a>":null]
						[(state>0) ? maint_options : ""]
						</body>
						</html>"}
	user << browse(output, "window=exosuit_maint_console")
	onclose(user, "exosuit_maint_console")
	return


////////////////////////////////
/////// Messages and Log ///////
////////////////////////////////

/obj/mecha/proc/occupant_message(message as text)
	if(message)
		if(src.occupant && src.occupant.client)
			to_chat(src.occupant, "\icon[src] [message]")
	return

/obj/mecha/proc/log_message(message as text,red=null)
	log.len++
	log[log.len] = list("time"=world.timeofday,"message"="[red?"<font color='red'>":null][message][red?"</font>":null]")
	return log.len

/obj/mecha/proc/log_append_to_last(message, red=null)
	if(!length(log))
		return

	var/list/last_entry = src.log[src.log.len]
	last_entry["message"] += "<br>[red?"<font color='red'>":null][message][red?"</font>":null]"


/////////////////
///// Topic /////
/////////////////

/obj/mecha/Topic(href, href_list)
	..()
	if(href_list["update_content"])
		if(usr != src.occupant)	return
		send_byjax(src.occupant,"exosuit.browser","content",src.get_stats_part())
		return
	if(href_list["close"])
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.ogg',channel=4, volume=100);
		return
	if(usr.stat > 0)
		return
	var/datum/topic_input/m_filter = new /datum/topic_input(href,href_list)
	if(href_list["select_equip"])
		if(usr != src.occupant)	return
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.ogg',channel=4, volume=100);
		var/obj/item/mecha_parts/mecha_equipment/equip = m_filter.getObj("select_equip")
		if(equip)
			src.selected = equip
			src.occupant_message("You switch to [equip]")
			src.visible_message("[src] raises [equip]")
			send_byjax(src.occupant,"exosuit.browser","eq_list",src.get_equipment_list())
		return
	if(href_list["eject"])
		if(usr != src.occupant)	return
		playsound(src,'sound/mecha/ROBOTIC_Servo_Large_Dual_Servos_Open_mono.ogg',100,1)
		src.eject()
		return
	if(href_list["toggle_lights"])
		if(usr != src.occupant)	return
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.ogg',channel=4, volume=100)
		src.toggle_lights()
		return
	if(href_list["toggle_airtank"])
		if(usr != src.occupant)	return
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.ogg',channel=4, volume=100)
		src.toggle_internal_tank()
		return
	if(href_list["rmictoggle"])
		if(usr != src.occupant)	return
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.ogg',channel=4, volume=100)
		radio.broadcasting = !radio.broadcasting
		send_byjax(src.occupant,"exosuit.browser","rmicstate",(radio.broadcasting?"Engaged":"Disengaged"))
		return
	if(href_list["rspktoggle"])
		if(usr != src.occupant)	return
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.ogg',channel=4, volume=100)
		radio.listening = !radio.listening
		send_byjax(src.occupant,"exosuit.browser","rspkstate",(radio.listening?"Engaged":"Disengaged"))
		return
	if(href_list["rfreq"])
		if(usr != src.occupant)	return
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.ogg',channel=4, volume=100)
		var/new_frequency = (radio.frequency + m_filter.getNum("rfreq"))
		if ((radio.frequency < PUBLIC_LOW_FREQ || radio.frequency > PUBLIC_HIGH_FREQ))
			new_frequency = sanitize_frequency(new_frequency)
		radio.set_frequency(new_frequency)
		send_byjax(src.occupant,"exosuit.browser","rfreq","[format_frequency(radio.frequency)]")
		return
	if(href_list["port_disconnect"])
		if(usr != src.occupant)	return
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.ogg',channel=4, volume=100)
		src.disconnect_from_port()
		return
	if (href_list["port_connect"])
		if(usr != src.occupant)	return
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.ogg',channel=4, volume=100)
		src.connect_to_port()
		return
	if (href_list["view_log"])
		if(usr != src.occupant)	return
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.ogg',channel=4, volume=100)
		src.occupant << browse(src.get_log_html(), "window=exosuit_log")
		onclose(occupant, "exosuit_log")
		return
	if (href_list["change_name"])
		if(usr != src.occupant)	return
		var/newname = sanitizeSafe(input(occupant,"Choose new exosuit name","Rename exosuit",initial(name)) as text, MAX_NAME_LEN)
		if(newname)
			usr << sound('sound/mecha/UI_SCI-FI_Tone_Deep_Wet_22_stereo_complite.ogg',channel=4, volume=100)
			name = newname
		else
			alert(occupant, "nope.avi")
		return
	if (href_list["toggle_id_upload"])
		if(usr != src.occupant)	return
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.ogg',channel=4, volume=100)
		add_req_access = !add_req_access
		send_byjax(src.occupant,"exosuit.browser","t_id_upload","[add_req_access?"L":"Unl"]ock ID upload panel")
		return
	if(href_list["toggle_maint_access"])
		if(usr != src.occupant)	return
		if(state)
			usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.ogg',channel=4, volume=100);
			occupant_message("<font color='red'>Maintenance protocols in effect</font>")
			return
		maint_access = !maint_access
		send_byjax(src.occupant,"exosuit.browser","t_maint_access","[maint_access?"Forbid":"Permit"] maintenance protocols")
		return
	if(href_list["req_access"] && add_req_access)
		if(!in_range(src, usr))	return
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.ogg',channel=4, volume=100)
		output_access_dialog(m_filter.getObj("id_card"),m_filter.getMob("user"))
		return
	if(href_list["maint_access"] && maint_access)
		if(!in_range(src, usr))	return
		var/mob/user = m_filter.getMob("user")
		if(user)
			if(state==0)
				state = 1
				user << sound('sound/mecha/UI_SCI-FI_Tone_Deep_Wet_22_stereo_complite.ogg',channel=4, volume=100)
				to_chat(user, "The securing bolts are now exposed.")
			else if(state==1)
				state = 0
				user << sound('sound/mecha/UI_SCI-FI_Tone_Deep_Wet_22_stereo_complite.ogg',channel=4, volume=100)
				to_chat(user, "The securing bolts are now hidden.")
			output_maintenance_dialog(m_filter.getObj("id_card"),user)
		return
	if(href_list["set_internal_tank_valve"] && state >=1)
		if(!in_range(src, usr))	return
		var/mob/user = m_filter.getMob("user")
		if(user)
			usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.ogg',channel=4, volume=100)
			var/new_pressure = input(user,"Input new output pressure","Pressure setting",internal_tank_valve) as num
			if(new_pressure)
				internal_tank_valve = new_pressure
				to_chat(user, "The internal pressure valve has been set to [internal_tank_valve]kPa.")
	if(href_list["remove_passenger"] && state >= 1)
		var/mob/user = m_filter.getMob("user")
		var/list/passengers = list()
		for (var/obj/item/mecha_parts/mecha_equipment/tool/passenger/P in contents)
			if (P.occupant)
				passengers["[P.occupant]"] = P

		if (!passengers)
			to_chat(user, SPAN_WARNING("There are no passengers to remove."))
			return

		var/pname = input(user, "Choose a passenger to forcibly remove.", "Forcibly Remove Passenger") as null|anything in passengers

		if (!pname)
			return

		var/obj/item/mecha_parts/mecha_equipment/tool/passenger/P = passengers[pname]
		var/mob/occupant = P.occupant

		user.visible_message(SPAN_NOTICE("\The [user] begins opening the hatch on \the [P]..."), SPAN_NOTICE("You begin opening the hatch on \the [P]..."))
		if (!do_after(user, 40, needhand = 0))
			return

		user.visible_message(SPAN_NOTICE("\The [user] opens the hatch on \the [P] and removes [occupant]!"), SPAN_NOTICE("You open the hatch on \the [P] and remove [occupant]!"))
		P.go_out()
		P.log_message("[occupant] was removed.")
		return
	if(href_list["add_req_access"] && add_req_access && m_filter.getObj("id_card"))
		if(!in_range(src, usr))	return
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.ogg',channel=4, volume=100)
		operation_req_access += m_filter.getNum("add_req_access")
		output_access_dialog(m_filter.getObj("id_card"),m_filter.getMob("user"))
		return
	if(href_list["del_req_access"] && add_req_access && m_filter.getObj("id_card"))
		if(!in_range(src, usr))	return
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.ogg',channel=4, volume=100)
		operation_req_access -= m_filter.getNum("del_req_access")
		output_access_dialog(m_filter.getObj("id_card"),m_filter.getMob("user"))
		return
	if(href_list["finish_req_access"])
		if(!in_range(src, usr))	return
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.ogg',channel=4, volume=100)
		add_req_access = 0
		var/mob/user = m_filter.getMob("user")
		user << browse(null,"window=exosuit_add_access")
		return
	if(href_list["dna_lock"])
		if(usr != src.occupant)
			return
		if(isbrain(occupant))
			usr << sound('sound/mecha/UI_SCI-FI_Tone_Deep_Wet_15_stereo_error.ogg',channel=4, volume=100)
			occupant_message("You are a brain. No.")
			return
		if(src.occupant)
			usr << sound('sound/mecha/UI_SCI-FI_Compute_01_Wet_stereo.ogg',channel=4, volume=100)
			src.dna = src.occupant.dna.unique_enzymes
			src.occupant_message("You feel a prick as the needle takes your DNA sample.")
		return
	if(href_list["reset_dna"])
		if(usr != src.occupant)
			return
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.ogg',channel=4, volume=100)
		src.dna = null
		src.occupant_message("DNA-Lock disengaged.")
	if(href_list["maint_reset_dna"])
		if(src.dna_reset_allowed(usr))
			usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.ogg',channel=4, volume=100)
			to_chat(usr, SPAN_NOTICE("DNA-Lock has been reverted."))
			src.dna = null
		else
			usr << sound('sound/mecha/UI_SCI-FI_Tone_Deep_Wet_15_stereo_error.ogg',channel=4, volume=100)
			to_chat(usr, SPAN_WARNING("Invalid ID: Higher clearance is required."))
			return
	if(href_list["repair_int_control_lost"])
		if(usr != src.occupant)
			return
		src.occupant_message("Recalibrating coordination system.")
		src.log_message("Recalibration of coordination system started.")
		usr << sound('sound/mecha/UI_SCI-FI_Compute_01_Wet_stereo.ogg',channel=4, volume=100)
		var/T = src.loc
		if(do_after(usr, 10 SECONDS))
			if(T == src.loc)
				src.clearInternalDamage(MECHA_INT_CONTROL_LOST)
				src.occupant_message("<font color='blue'>Recalibration successful.</font>")
				usr << sound('sound/mecha/UI_SCI-FI_Tone_Deep_Wet_22_stereo_complite.ogg',channel=4, volume=100)
				src.log_message("Recalibration of coordination system finished with 0 errors.")
			else
				usr << sound('sound/mecha/UI_SCI-FI_Tone_Deep_Wet_15_stereo_error.ogg',channel=4, volume=100)
				src.occupant_message("<font color='red'>Recalibration failed.</font>")
				src.log_message("Recalibration of coordination system failed with 1 error.",1)

	//debug
	/*
	if(href_list["debug"])
		if(href_list["set_i_dam"])
			setInternalDamage(filter.getNum("set_i_dam"))
		if(href_list["clear_i_dam"])
			clearInternalDamage(filter.getNum("clear_i_dam"))
		return
	*/



/*

	if (href_list["ai_take_control"])
		var/mob/living/silicon/ai/AI = locate(href_list["ai_take_control"])
		var/duration = text2num(href_list["duration"])
		var/mob/living/silicon/ai/O = new /mob/living/silicon/ai(src)
		var/cur_occupant = src.occupant
		O.invisibility = 0
		O.canmove = 1
		O.name = AI.name
		O.real_name = AI.real_name
		O.anchored = 1
		O.aiRestorePowerRoutine = 0
		O.control_disabled = 1 // Can't control things remotely if you're stuck in a card!
		O.laws = AI.laws
		O.stat = AI.stat
		O.oxyloss = AI.getOxyLoss()
		O.fireloss = AI.getFireLoss()
		O.bruteloss = AI.getBruteLoss()
		O.toxloss = AI.toxloss
		O.updatehealth()
		src.occupant = O
		if(AI.mind)
			AI.mind.transfer_to(O)
		AI.name = "Inactive AI"
		AI.real_name = "Inactive AI"
		AI.icon_state = "ai-empty"
		spawn(duration)
			AI.name = O.name
			AI.real_name = O.real_name
			if(O.mind)
				O.mind.transfer_to(AI)
			AI.control_disabled = 0
			AI.laws = O.laws
			AI.oxyloss = O.getOxyLoss()
			AI.fireloss = O.getFireLoss()
			AI.bruteloss = O.getBruteLoss()
			AI.toxloss = O.toxloss
			AI.updatehealth()
			qdel(O)
			if (!AI.stat)
				AI.icon_state = "ai"
			else
				AI.icon_state = "ai-crash"
			src.occupant = cur_occupant
*/
	return

///////////////////////
///// Power stuff /////
///////////////////////

/obj/mecha/proc/has_charge(amount)
	return (get_charge()>=amount)

/obj/mecha/proc/get_charge()
	if(!src.cell)
		return
	return max(0, src.cell.charge)

//Attempts to use the given amount of power
/obj/mecha/proc/use_power(amount)
	if(get_charge() >= amount)
		cell.use(amount)
		return TRUE
	return FALSE

/obj/mecha/proc/give_power(amount)
	if(!isnull(get_charge()))
		cell.give(amount)
		return TRUE
	return FALSE


/obj/mecha/attack_generic(var/mob/user, var/damage, var/attack_message)

	if(!damage)
		return 0

	src.log_message("Attacked. Attacker - [user].",1)

	user.do_attack_animation(src)
	if(!deflect_hit(is_melee=1))
		src.hit_damage(damage, is_melee=1)
		src.check_for_internal_damage(list(MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))
		visible_message(SPAN_DANGER("[user] [attack_message] [src]!"))
		user.attack_log += text("\[[time_stamp()]\] <font color='red'>attacked [src.name]</font>")
	else
		src.log_append_to_last("Armor saved.")
		playsound(src.loc, 'sound/weapons/slash.ogg', 50, 1, -1)
		src.occupant_message(SPAN_NOTICE("\The [user]'s attack is stopped by the armor."))
		visible_message(SPAN_NOTICE("\The [user] rebounds off [src.name]'s armor!"))
		user.attack_log += text("\[[time_stamp()]\] <font color='red'>attacked [src.name]</font>")
	return 1

/obj/mecha/Entered(var/atom/movable/AM, var/atom/old_loc, var/special_event)
	if(MOVED_DROP == special_event)
		dropped_items |= AM
		return ..(AM, old_loc, 0)
	return ..()

/obj/mecha/Exited(var/atom/movable/AM, var/atom/old_loc, var/special_event)
	dropped_items -= AM
	return ..()

//////////////////////////////////////////
////////  Mecha global iterators  ////////
//////////////////////////////////////////


/datum/global_iterator/mecha_preserve_temp  //normalizing cabin air temperature to 20 degrees celsius
	delay = 20

	Process(var/obj/mecha/mecha)
		if(mecha.cabin_air && mecha.cabin_air.volume > 0)
			var/delta = mecha.cabin_air.temperature - T20C
			mecha.cabin_air.temperature -= max(-10, min(10, round(delta/4,0.1)))
		return

/datum/global_iterator/mecha_tank_give_air
	delay = 15

	Process(var/obj/mecha/mecha)
		if(mecha.internal_tank)
			var/datum/gas_mixture/tank_air = mecha.internal_tank.return_air()
			var/datum/gas_mixture/cabin_air = mecha.cabin_air

			var/release_pressure = mecha.internal_tank_valve
			var/cabin_pressure = cabin_air.return_pressure()
			var/pressure_delta = min(release_pressure - cabin_pressure, (tank_air.return_pressure() - cabin_pressure)/2)
			var/transfer_moles = 0
			if(pressure_delta > 0) //cabin pressure lower than release pressure
				if(tank_air.temperature > 0)
					transfer_moles = pressure_delta*cabin_air.volume/(cabin_air.temperature * R_IDEAL_GAS_EQUATION)
					var/datum/gas_mixture/removed = tank_air.remove(transfer_moles)
					cabin_air.merge(removed)
			else if(pressure_delta < 0) //cabin pressure higher than release pressure
				var/datum/gas_mixture/t_air = mecha.get_turf_air()
				pressure_delta = cabin_pressure - release_pressure
				if(t_air)
					pressure_delta = min(cabin_pressure - t_air.return_pressure(), pressure_delta)
				if(pressure_delta > 0) //if location pressure is lower than cabin pressure
					transfer_moles = pressure_delta*cabin_air.volume/(cabin_air.temperature * R_IDEAL_GAS_EQUATION)
					var/datum/gas_mixture/removed = cabin_air.remove(transfer_moles)
					if(t_air)
						t_air.merge(removed)
					else //just delete the cabin gas, we're in space or some shit
						qdel(removed)
		else
			return stop()
		return

/datum/global_iterator/mecha_inertial_movement //inertial movement in space
	delay = 7

	Process(var/obj/mecha/mecha as obj,direction)
		if(direction)
			mecha.anchored = FALSE //Unanchor while moving, so we can fall if we float over a hole witgh gravity
			if(!step(mecha, direction)||mecha.check_for_support() || (mecha.thruster && mecha.thruster.do_move()))
				mecha.inertia_dir = 0
				src.stop()
			mecha.anchored = TRUE
			mecha.inertia_dir = direction
		else
			src.stop()
		return

/datum/global_iterator/mecha_internal_damage // processing internal damage

	Process(var/obj/mecha/mecha)
		if(!mecha.hasInternalDamage())
			return stop()
		if(mecha.hasInternalDamage(MECHA_INT_FIRE))
			if(!mecha.hasInternalDamage(MECHA_INT_TEMP_CONTROL) && prob(5))
				mecha.clearInternalDamage(MECHA_INT_FIRE)
			if(mecha.internal_tank)
				if(mecha.internal_tank.return_pressure()>mecha.internal_tank.maximum_pressure && !(mecha.hasInternalDamage(MECHA_INT_TANK_BREACH)))
					mecha.setInternalDamage(MECHA_INT_TANK_BREACH)
				var/datum/gas_mixture/int_tank_air = mecha.internal_tank.return_air()
				if(int_tank_air && int_tank_air.volume>0) //heat the air_contents
					int_tank_air.temperature = min(6000+T0C, int_tank_air.temperature+rand(10,15))
			if(mecha.cabin_air && mecha.cabin_air.volume>0)
				mecha.cabin_air.temperature = min(6000+T0C, mecha.cabin_air.temperature+rand(10,15))
				if(mecha.cabin_air.temperature>mecha.max_temperature/2)
					mecha.take_damage(4/round(mecha.max_temperature/mecha.cabin_air.temperature,0.1),"fire")
		if(mecha.hasInternalDamage(MECHA_INT_TEMP_CONTROL)) //stop the mecha_preserve_temp loop datum
			mecha.pr_int_temp_processor.stop()
		if(mecha.hasInternalDamage(MECHA_INT_TANK_BREACH)) //remove some air from internal tank
			if(mecha.internal_tank)
				var/datum/gas_mixture/int_tank_air = mecha.internal_tank.return_air()
				var/datum/gas_mixture/leaked_gas = int_tank_air.remove_ratio(0.10)
				if(mecha.loc && hascall(mecha.loc,"assume_air"))
					mecha.loc.assume_air(leaked_gas)
				else
					qdel(leaked_gas)
		if(mecha.hasInternalDamage(MECHA_INT_SHORT_CIRCUIT))
			if(mecha.get_charge())
				mecha.spark_system.start()
				mecha.cell.charge -= min(20,mecha.cell.charge)
				mecha.cell.maxcharge -= min(20,mecha.cell.maxcharge)
		return


/////////////

//debug
/*
/obj/mecha/verb/test_int_damage()
	set name = "Test internal damage"
	set category = "Exosuit Interface"
	set src in view(0)
	if(!occupant) return
	if(usr!=occupant)
		return
	var/output = {"<html>
						<head>
						</head>
						<body>
						<h3>Set:</h3>
						<a href='?src=\ref[src];debug=1;set_i_dam=[MECHA_INT_FIRE]'>MECHA_INT_FIRE</a><br />
						<a href='?src=\ref[src];debug=1;set_i_dam=[MECHA_INT_TEMP_CONTROL]'>MECHA_INT_TEMP_CONTROL</a><br />
						<a href='?src=\ref[src];debug=1;set_i_dam=[MECHA_INT_SHORT_CIRCUIT]'>MECHA_INT_SHORT_CIRCUIT</a><br />
						<a href='?src=\ref[src];debug=1;set_i_dam=[MECHA_INT_TANK_BREACH]'>MECHA_INT_TANK_BREACH</a><br />
						<a href='?src=\ref[src];debug=1;set_i_dam=[MECHA_INT_CONTROL_LOST]'>MECHA_INT_CONTROL_LOST</a><br />
						<hr />
						<h3>Clear:</h3>
						<a href='?src=\ref[src];debug=1;clear_i_dam=[MECHA_INT_FIRE]'>MECHA_INT_FIRE</a><br />
						<a href='?src=\ref[src];debug=1;clear_i_dam=[MECHA_INT_TEMP_CONTROL]'>MECHA_INT_TEMP_CONTROL</a><br />
						<a href='?src=\ref[src];debug=1;clear_i_dam=[MECHA_INT_SHORT_CIRCUIT]'>MECHA_INT_SHORT_CIRCUIT</a><br />
						<a href='?src=\ref[src];debug=1;clear_i_dam=[MECHA_INT_TANK_BREACH]'>MECHA_INT_TANK_BREACH</a><br />
						<a href='?src=\ref[src];debug=1;clear_i_dam=[MECHA_INT_CONTROL_LOST]'>MECHA_INT_CONTROL_LOST</a><br />
 					   </body>
						</html>"}

	occupant << browse(output, "window=ex_debug")
	//src.health = initial(src.health)/2.2
	//src.check_for_internal_damage(list(MECHA_INT_FIRE,MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))
	return
*/



//Used for generating damaged exosuits.
//This does an individual check for each piece of equipment on the exosuit, and removes it if
//this probability passes a check
/obj/mecha/proc/lose_equipment(var/probability)
	for(var/obj/item/mecha_parts/mecha_equipment/E in equipment)
		if (prob(probability))
			E.detach(loc)
			qdel(E)

//Does a number of checks at probability, and alters some configuration values if succeeded
/obj/mecha/proc/misconfigure_systems(var/probability)
	if (prob(probability))
		internal_tank_valve = rand(0,10000) // Screw up the cabin air pressure.
		//This will probably kill the pilot if they dont check it before climbing in
	if (prob(probability))
		use_internal_tank = !use_internal_tank // Flip internal tank mode on or off
	if (prob(probability))
		toggle_lights() // toggle the lights
	if (prob(probability)) // Some settings to screw up the radio
		radio.broadcasting = !radio.broadcasting
	if (prob(probability))
		radio.listening = !radio.listening
	if (prob(probability))
		radio.set_frequency(rand(PUBLIC_LOW_FREQ,PUBLIC_HIGH_FREQ))
	if (prob(probability))
		maint_access = 0 // Disallow maintenance mode
	else
		maint_access = 1 // Explicitly allow maint_access -> Othwerwise we have a stuck mech, as you cant change the state back, if maint_access is 0
		state = 0 // Enable maintenance mode. It won't move.

//Does a random check for each possible type of internal damage, and adds it if it passes
//The probability should be somewhat low unless you just want to saturate it with damage
//Fire is excepted. We're not going to set the exosuit on fire while its in longterm storage
/obj/mecha/proc/random_internal_damage(var/probability)
	if (prob(probability))
		setInternalDamage(MECHA_INT_TEMP_CONTROL)
	if (prob(probability))
		setInternalDamage(MECHA_INT_SHORT_CIRCUIT)
	if (prob(probability))
		setInternalDamage(MECHA_INT_TANK_BREACH)
	if (prob(probability))
		setInternalDamage(MECHA_INT_CONTROL_LOST)

/obj/mecha/proc/hud_deleted(var/obj/item/clothing/glasses/hud/source, var/obj/item/clothing/glasses/hud/placeholder) //2nd arg exists because our signals are outdated
	SIGNAL_HANDLER

	if (hud == source)
		UnregisterSignal(source, COMSIG_HUD_DELETED)
		hud = null
