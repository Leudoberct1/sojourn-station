/mob/living/carbon/superior_animal/xenomorph/Life()
	. = ..()

/mob/living/carbon/superior_animal/xenomorph/handle_breath(datum/gas_mixture/breath) //we dont care about the air
	return

/mob/living/carbon/superior_animal/xenomorph/handle_environment(var/datum/gas_mixture/environment) //were space proof
	return

/mob/living/carbon/superior_animal/xenomorph/handle_cheap_breath(datum/gas_mixture/breath as anything)
	return

/mob/living/carbon/superior_animal/xenomorph/handle_cheap_environment(datum/gas_mixture/environment as anything)
	return
