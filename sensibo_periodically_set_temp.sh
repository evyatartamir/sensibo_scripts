#!/bin/bash
# Author: Evyatar Tamir 26.9.2020
# Purpose: If AC is on, periodically set the temperature.
# This script is a workaround for a thermostat malfunction, which causes AC to stop working after a few minutes.
# Uses Sensibo API: https://sensibo.github.io/
# Requires command line tool "jq"

# You must set these authentication values, either here or from the environment.
SENSIBO_API_KEY=${SENSIBO_API_KEY:-"1234567890ABCDEFGHIJlmnopqrstu"}
echo "Using API KEY" $SENSIBO_API_KEY

if [ -z $SENSIBO_AC_DEVICE_ID ]; then	
	echo "Device ID not set, getting first device ID from API"
	SENSIBO_AC_DEVICE_ID=$(curl -s -X GET "https://home.sensibo.com/api/v2/users/me/pods?apiKey={$SENSIBO_API_KEY}" | jq -r .result[0].id)
fi

echo "Using AC DEVICE ID" $SENSIBO_AC_DEVICE_ID

SENSIBO_TEMPERATURE_CELSIUS=${SENSIBO_TEMPERATURE_CELSIUS:-"24"}
SENSIBO_TEMP_RESET_SLEEP_PERIOD_SECONDS=${SENSIBO_TEMP_RESET_SLEEP_PERIOD_SECONDS:-"180"}
SENSIBO_ACOFF_SLEEP_PERIOD_SECONDS=${SENSIBO_ACOFF_SLEEP_PERIOD_SECONDS:-"300"}

SENSIBO_TEMPERATURE_RANGE_MIN=${SENSIBO_TEMPERATURE_RANGE_MIN:-"20"}
SENSIBO_TEMPERATURE_RANGE_MAX=${SENSIBO_TEMPERATURE_RANGE_MAX:-"25.5"}

AC_ON_VALUE=1
AC_OFF_VALUE=0

# This function checks if the AC is currently ON
function acIsOn
{
	if [ `curl -s -X GET "https://home.sensibo.com/api/v2/pods/$SENSIBO_AC_DEVICE_ID/acStates?limit=1&apiKey={$SENSIBO_API_KEY}" | jq .result[0].acState.on` = "true" ]; then
		return $AC_ON_VALUE
	else
		return $AC_OFF_VALUE
	fi
}

# This function sets the AC temperature to a given value
function setAcTemp ()
{
	curl -s -o "/dev/null" -X PATCH -H "Content-type: application/json" -d '{"newValue": '$1'}' "https://home.sensibo.com/api/v2/pods/$SENSIBO_AC_DEVICE_ID/acStates/targetTemperature?apiKey={$SENSIBO_API_KEY}"
}

# This function retrieves the last temperature value measured by Sensibo device
function getCurrentTemp
{
	echo `curl -s -X GET "https://home.sensibo.com/api/v2/pods/$SENSIBO_AC_DEVICE_ID?fields=measurements&apiKey={$SENSIBO_API_KEY}" | jq .result.measurements.temperature`
}

# This function checks if a given value is within a certain range
# Parameters: $1 = temp, $2 = min, $3 = max
function isTempInRange ()
{
	# Since Bash can only compare integer expressions, we'll use bc (basic calculator)
	if [[ ($(echo "$1 >= $2" | bc) -eq 1) && ($(echo "$3 >= $1" | bc) -eq 1) ]]; then
		return 1
	else
		return 0
	fi
}

while true; do	
	
	currentTemp=$(getCurrentTemp)
	echo "Temperature measured:" $currentTemp "C"

	isTempInRange $currentTemp $SENSIBO_TEMPERATURE_RANGE_MIN $SENSIBO_TEMPERATURE_RANGE_MAX
	insideRange=$?
	if [ $insideRange -eq 1 ]; then
		echo "Current temperature is within desired range [$SENSIBO_TEMPERATURE_RANGE_MIN,$SENSIBO_TEMPERATURE_RANGE_MAX]"
	else
		echo "Current temperature is outside desired range [$SENSIBO_TEMPERATURE_RANGE_MIN,$SENSIBO_TEMPERATURE_RANGE_MAX]"
	fi

	acIsOn
	acOnValue=$?

	if [ $acOnValue -eq $AC_ON_VALUE ]; then
		echo "Detected AC ON"
		if [ $insideRange -eq 0 ]; then
			echo "Setting temperature:" $SENSIBO_TEMPERATURE_CELSIUS "C"
			setAcTemp $SENSIBO_TEMPERATURE_CELSIUS
		fi
		echo "Sleeping for" $SENSIBO_TEMP_RESET_SLEEP_PERIOD_SECONDS "seconds"
		sleep $SENSIBO_TEMP_RESET_SLEEP_PERIOD_SECONDS
	else
		echo "AC is OFF"
		echo "Sleeping for" $SENSIBO_ACOFF_SLEEP_PERIOD_SECONDS "seconds"
		sleep $SENSIBO_ACOFF_SLEEP_PERIOD_SECONDS
	fi
done
