#!/bin/bash

# ******************************************************************************
#		W A N P I N G
#			inspiriert von A
build=1002
#
#	Sendet zyklisch Pings an einen festgelegten Zielhost
#
#	Läuft ohne ausgabe, ausser es trott ein Fehler auf. Falls die
#	Standardausgabe nicht verfügbar ist, wird ein Fehlercode ungleich 0 erzeug,
#	falls etwas schiefgeht.
#	Wird unterbrochen mit ctrl-c.
#	Kann im Hintergrund gestartet werden mit 'wanping start'.
#	Zum beenden 'wanping stop'
#
# ******************************************************************************

# colors
reset=$(tput sgr0)
red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
magenta=$(tput setaf 5)
cyan=$(tput setaf 6)

# vars
settings=/var/opt/wanping/wanping.config
overrideverbose=0
running=/var/opt/wanping/.wanpingrunning

# main
main() {
	# read settings file
	get_settings

	# look for instance
	if [ -f $running ]; then
		interruption_command=$(cat $running)
		echo "Eine andere Instanz von wanping läuft bereits."
		service_control
	else
		touch $running
		echo "running" > $running
	fi
	catchfile="$(mktemp)"


	# greets you if verbose=1
	if [ $verbose -eq 1 ] || [ $overrideverbose -eq 1 ]; then
		echo "wanping build $build läuft..."
	fi

	# prepare logfile
	prepare_logfiles

	while true; do
	# capture time and date
	timestamp=$(date)

	# fire up some pings
	ping -q -w $count $target > $catchfile # and capture the output in a file

	# process captured ping output line by line
	while read p; do
		# look if settings have changed
		get_settings

		# look for interruption commands
		interruption_command=$(cat $running)
		case "$interruption_command" in
			stop) ctrl_c;;
			pause)	pause_wanping;;
		esac

		IFS=' ' read -r -a output <<< $p
		if [ -z ${output[0]} ]; then continue; fi
		if [ ${output[0]} = "PING" ]; then continue; fi
		if [ ${output[0]} = "-" ]; then continue; fi


		if [[ ${output[0]} =~ ^[0-9] ]]; then
			transmitted=${output[0]}
			received=${output[3]}
			if [ ${output[6]} = "errors," ]; then
				packetloss_perc=${output[7]}
			else
				packetloss_perc=${output[5]}
			fi
		fi

		if [ ! -z $received ] && [ $received -eq 0 ]; then
			min=0
			avg=0
			max=0
		fi

		if [ ${output[0]} == "rtt" ]; then
			IFS='/' read -r -a minavgmax <<< ${output[3]}
			min=${minavgmax[0]}
			avg=${minavgmax[1]}
			max=${minavgmax[2]}
		fi

	done < $catchfile

	generate_output

	# unset processing vars
	transmitted=
	received=
	packetloss_perc=
	min=
	avg=
	max=

	# emptying catchfile
	echo > $catchfile
	done
}

pause_wanping(){
	if [ $verbose -eq 1 ] || [ $overrideverbose -eq 1 ]; then
		echo "wanping angehalten..."
	fi
	while true; do
		sleep 0.5
		interruption_command=$(cat $running)
		case "$interruption_command" in
			stop) ctrl_c;;
			continue)	break;;
		esac
	done
	echo "running" > $running
	if [ $verbose -eq 1 ] || [ $overrideverbose -eq 1 ]; then
		echo "wanping wird fortgesetzt..."
	fi
}

install_programm(){
	if [ -f $running ]; then
		echo "${red}ABBRUCH:${reset} wanping läuft bereits und kann daher nicht installiert werden!"
		exit 2
	fi
	checkifroot
	echo "Installiere wanping build $build"
	echo -n " Verzeichnisse anlegen..."
	 mkdir -p /var/opt/wanping	# For setting
	 mkdir -p /opt/wanping		# For the skript itself
	 mkdir -p /var/log/wanping	# Default directory for logfiles
	echo "${green}OK${reset}"
	echo -n " Programmdaten kopieren..."
	 cp wanping.sh /opt/wanping/wanping.sh
	echo "${green}OK${reset}"
	echo -n " Konfigurationsdatei anlegen..."
	 generate_settings
	echo "${green}OK${reset}"
	echo -n " Rechte festlegen..."
	 chmod -R 667 /var/log/wanping
	 chmod 667 /var/opt/wanping
	 chmod 666 /var/opt/wanping/*
	 chmod -R 755 /opt/wanping
	echo "${green}OK${reset}"
	echo " Softlink setzen"
	 ln -s /opt/wanping/wanping.sh /usr/local/bin/wanping
	echo "Installation abgeschlossen!"
	echo
	exit 0
}

get_settings(){
	if [ ! -f $settings ]; then
		echo "${red}ABBRUCH:${reset} Konfigurationsdatei nicht gefunden!"
		echo "Mit ${cyan}sudo ./wanping.sh -i${reset} wird die installation gestartet und die Konfigurationsdatei angelegt."
		quit 1
	fi
	. $settings
	if [ ! $? -eq 0 ]; then
		echo "${red}ABBRUCH:${reset} Fehler beim lesen der Konfigurationsdatei!"
		quit 1
	fi


}

checkifroot(){
	if [[ $EUID -ne 0 ]]; then
		echo "${red}ABBRUCH:${reset} muss mit root-Rechten gestartet werden!" 2>&1
    	exit 1
	fi
}

generate_settings(){
	if [ -f $settings ]; then
		echo
		echo "${yellow}WARNUNG:${reset} Konfigurationsdatei gefunden! Sicherungskopie wird angelegt."
		mv $settings $settings.backup
	fi
	touch $settings
	if [ ! $? -eq 0 ]; then
		echo "${red}ABBRUCH:${reset} Konfigurationsdatei konnte nicht erstellt werden!"
		echo
		exit 1
	fi
	logdir=/var/log/wanping
	echo "# Dies sind die Einstellungen mit denen wanping arbeitet." >> $settings
	echo "# Sie können nach Belieben geändert werden, sogar wärend wanping läuft. Änderungen werden dann mit dem nächsten Zyklus umgesetzt." >> $settings
	echo >> $settings
	echo "# Dauer eines Ping-Zyklus in Sekunden. Pro Sekunde wird ein Ping auf den Zielhost abgesetzt." >> $settings
	echo "count=60" >> $settings
	echo >> $settings
	echo "# Ping-Zielhost. Googles DNS-Server ist zu empfehlen." >> $settings
	echo "target=\"8.8.8.8\"" >> $settings
	echo >> $settings
	echo "# Namen und Speicherorte der Log-Dateien. Das Standardverzeichnis ist $logdir. Beachten Sie, das der ausführende Benutzer schreibrechte in den Verzeichnissen haben muss." >> $settings
	echo "logfile=$logdir/wanping.log" >> $settings
	echo "faillogfile=$logdir/wanping-fail.log" >> $settings
	echo "csvlogfile=$logdir/wanping.csv" >> $settings
	echo "shortlog=$logdir/wanpingshort.log" >> $settings
	echo >> $settings
	echo "# Zusätzlich zur Log-Datei kann die Zusammenfassung auf der Standardausgabe ausgegeben werden. Voreinstellung ist 0, keine Ausgabe." >> $settings
	echo "verbose=0" >> $settings
	echo >> $settings
	echo "# Log-Datei schreiben." >> $settings
	echo "write_log=1" >> $settings
	echo >> $settings
	echo "# Zusätzliches gekürztes Log schreiben." >> $settings
	echo "# (Wird nur dann geschrieben, wenn ein Standard-Log geschrieben wird.)" >> $settings
	echo "write_shortlog=0" >> $settings
	echo >> $settings
	echo "# Anzahl der Zeilen die vom Standard-Log ins gekürtze Log geschrieben werden sollen (z.B.: 1440 umfassen die letzten 24 Stunden, wenn count auf 60 festgelegt ist.)." >> $settings
	echo "shortlog_lines=1440" >> $settings
	echo >> $settings
	echo "# Seperate .csv-Datei anlegen." >> $settings
	echo "write_csv=0" >> $settings
	echo >> $settings
	echo "# Kopfzeile schreiben, falls .cvs-Datei neu erstellt wird." >> $settings
	echo "write_csv_head=1" >> $settings
	echo >> $settings
	echo "# Fail-Log-Datei schreiben, falls packetloss mehr als 0%." >> $settings
	echo "write_fail_log=0" >> $settings
	echo >> $settings
}

prepare_logfiles() {
	if [ $write_log -eq 1 ] && [ ! -f $logfile ]; then
		touch $logfile
		if [ ! $? -eq 0 ]; then
			echo "${red}ABBRUCH:${reset} Log-Datei kann nicht geschrieben werden!"
			quit 1
		fi
		echo "Standard-Log von wanping" > $logfile
	fi

	if [ $write_fail_log -eq 1 ] && [ ! -f $faillogfile ]; then
		touch $faillogfile
		if [ ! $? -eq 0 ]; then
			echo "${red}ABBRUCH:${reset} Fail-Log-Datei konnte nicht geschrieben werden!"
			quit 1
		fi
		echo "Fail-Log von wanping" > $faillogfile
	fi

	if [ $write_shortlog -eq 1 ] && [ ! -f $shortlog ]; then
		touch $shortlog
		if [ ! $? -eq 0 ]; then
			echo "${red}ABBRUCH:${reset} Short-Log konnte nicht geschrieben werden!"
			quit 1
		fi
		echo "Short-Log von wanping" > $shortlog
	fi

	# csv file preperation to be continued
	if [ $write_csv -eq 1 ] && [ ! -f $csvlogfile ]; then
		touch $csvlogfile
		if [ ! $? -eq 0 ]; then
			echo "${red}ABBRUCH:${reset} .csv-Datei konnte nicht geschrieben werden!"
			quit 1
		fi
		if [ $write_csv_head -eq 1 ]; then
			echo "TIMESTAMP,SEND,RECVD,MIN,AVG,MAX" >> $csvlogfile
		fi
	fi
}

generate_output() {
	# the outputline
	outputline="$timestamp - send:$transmitted recvd:$received lost:$packetloss_perc - timings: min:$min avg:$avg max:$max"

	# echo to stdout if verbose=1
	if [ $verbose -eq 1 ] || [ $overrideverbose -eq 1 ]; then
		echo $outputline
	fi

	# echo'ing to logfile
	if [ $write_log -eq 1 ]; then
		echo $outputline >> $logfile
		if [ ! $? -eq 0 ]; then
			echo "${red}ABBRUCH:${reset}: Log-Datei konnte nicht beschrieben werden!"
			quit 1
		fi
	fi

	# echo to faillogfile if packetloss is more than zero
	if [ $packetloss_perc != "0%" ] && [ $write_fail_log -eq 1 ]; then
		echo $outputline >> $faillogfile
		if [ ! $? -eq 0 ]; then
			echo "${red}ABBRUCH:${reset} Fail-Log-Datei konnte nicht beschrieben werden!"
			quit 1
		fi
	fi

	# echo to csv-file
	if [ $write_csv -eq 1 ]; then write_csv; fi

	# dump short log
	if [ $write_shortlog -eq 1 ] && [ $write_log -eq 1 ]; then
		tac $logfile | head -n $shortlog_lines > $shortlog
		if [ ! $? -eq 0 ]; then
			echo "${red}ABBRUCH:${reset} Short-Log konnte nicht beschrieben werden!"
			quit 1
		fi
	fi
}

ctrl_c() {
	quit 0
}

quit() {
	exitcode=$1
	echo
	rm -f $running
	rm -f $catchfile
	exit $exitcode
}

write_csv() {
	echo "\"$timestamp\",$transmitted,$received,$min,$avg,$max" >> $csvlogfile
	if [ ! $? -eq 0 ]; then
		echo "${red}ABBRUCH:${reset} .csv-Datei konnte nicht beschrieben werden!"
		quit 1
	fi
}

convert_csv() {
	get_settings
	prepare_logfiles

	# capture interrupt
	trap exit INT
	trap exit SIGTERM

	# Set name
	read -p "Möchten Sie eine separate .csv-Datei erstellen? (j/n)" go
	case "$go" in
		j|J|y|Y) convert_csv_seperate_file;;
		*)	targetfile=$csvlogfile;;
	esac

	temp_targetfile=$(mktemp)
	touch $temp_targetfile

	# headline
	if [ $write_csv_head -eq 1 ]; then
		echo "TIMESTAMP,SEND,RECVD,MIN,AVG,MAX" >> $temp_targetfile
	fi

	# read and write
	while read p; do
		#echo "Starting to read a line from $logfile..."
		IFS=' ' read -r -a t <<< $p
		#echo "Line is $p"
		if [ -z ${t[10]} ]; then continue; fi
		timestamp="${t[0]} ${t[1]} ${t[2]} ${t[3]} ${t[4]} ${t[5]}"

		send=$(echo ${t[7]} | grep -oE "[[:digit:]]+")
		received=$(echo ${t[8]} | grep -oE "[[:digit:]]+")
		min=$(echo ${t[12]} | grep -oE "[[:digit:]]+\.[[:digit:]]+")
		avg=$(echo ${t[13]} | grep -oE "[[:digit:]]+\.[[:digit:]]+")
		max=$(echo ${t[14]} | grep -oE "[[:digit:]]+\.[[:digit:]]+")

		#echo "\"$timestamp\",$send,$received,$min,$avg,$max"

		echo "\"$timestamp\",$send,$received,$min,$avg,$max" >> $temp_targetfile

	done < $logfile

	# clean up
	mv $temp_targetfile $targetfile

	# echo done
	echo "Datei erzeugt."
	echo

	exit 0
}

convert_csv_seperate_file() {
	read -p "Namen der Datei eingeben (.csv wird automatisch ergänzt) :" name
	targetfile=$(pwd)/$name.csv
}

show_help(){
	echo "Sendet zyklisch Pings an einen festgelegten Zielhost."
	echo "Aufruf: wanping [start] oder [-Option]"
	echo
	echo "Verfügbare Optionen:"
	echo -e " -v\tAusgabe auf Standardausgabe, egal was in Konfigurationsdatei steht."
	#echo -e " -s\tStart in den Setup-Modus."
	echo -e " -h\tDiese Hilfeseite zeigen."
	echo
	echo "'wanping start' startet wanping im Hintergrund. Alle Ausgaben werden unterdrückt, daher vorher mit 'wanping -v' einen Testlauf machen und sicherzustellen, das alles funktioniert. Die Konfigurationsdatei befindet sich unter ${cyan} /var/opt/wanping${reset}"
	echo
	echo "'wanping csv' erzeugt eine komplette .csv-Datei aus dem aktuellen Log. Dabei kann ausgewählt werden ob eine neue Datei erstellt wird oder die festgelegte Datei neu erstellt wird."
	echo
	quit 0
}

settings(){	# Wird momentan nicht aufgerufen
	get_settings
	echo "Wanping Setup-Modus"
	echo "Speicherort der Konfigurationsdatei:${cyan} /var/opt/wanping${reset}"
	echo
	settings_show
	echo
	read -n 1 -s -p "Möchten Sie etwas ändern? (j/n)" go
	case "$go" in
		j|J|y|Y)	settings_edit;;
		*) echo;;
	esac
	exit 0
}

settings_show(){
	old_count=$count
	old_target=$target
	old_logfile=$logfile
	old_faillogfile=$faillogfile
	old_csvlogfile=$csvlogfile
	old_shortlog=$shortlog
	old_verbose=$verbose
	old_write_log=$write_log
	old_write_shortlog=$write_shortlog
	old_shortlog_lines=$shortlog_lines
	old_write_csv=$write_csv
	old_write_csv_head=$write_csv_head
	old_write_fail_log=$write_fail_log

	echo "Dies sind die aktuellen Einstellungen"
	echo "Dauer des Ping-Zyklus (in Sekunden): ${blue}$old_count${reset}"
	echo "Zielhost: ${blue}$old_target${reset}"
	echo "Log-Datei: ${blue}$old_logfile${reset}"
	echo "Fail-Log-Datei: ${blue}$old_faillogfile${reset}"
	echo "csv-Datei: ${blue}$old_csvlogfile${reset}"
	echo "Short-Log-Datei: ${blue}$old_shortlog${reset}"
	echo "Ausgabe auf Standardausgabe: ${blue}$old_verbose${reset}"
	echo "Log-Datei schreiben: ${blue}$old_write_log${reset}"
	echo "Short-Log-Datei schreiben: ${blue}$old_write_shortlog${reset}"
	echo "Short-Log-Datei länge (in Zeilen): ${blue}$old_shortlog_lines${reset}"
	echo "csv-Datei erstellen: ${blue}$old_write_csv${reset}"
	echo "Kopfzeile der scv-Datei schreiben: ${blue}$old_write_csv_head${reset}"
	echo "Fail-Log-Datei schreiben: ${blue}$old_write_fail_log${reset}"
}

settings_edit(){
	echo
	echo "Legen Sie Schritt für Schritt die Einstellungen fest. Die alten Einstellungen stehen in Klammern und werden übernommen, wenn Sie ohne Eingabe auf Enter drücken. Zum Abbrechen strg-c drücken. Die Einstellungen werden nach Eingabe des letzten Wertes gespeichert."
	echo
}

service_control(){
	echo "Aktueller Zustand von wanping: ${cyan}$interruption_command${reset}. Folgende Befehle stehen zur Auswahl:"
	echo -e " wanping pause \t Hält nach dem letzten Zyklus an, terminiert aber nicht."
	echo -e " wanping stop \t Terminiert wanping nach dem letzten Zyklus."
	echo -e " wanping continue \t Setzt wanping fort, falls angehalten wurde."
	echo
	exit 0
}

set_command() {
	# look for instance
	if [ ! -f $running ]; then
		echo "${red}FEHLER:${reset} wanping läuft nicht!"
		exit 1
	fi
	get_settings
	case "$1" in
		pause) set_command_pause;;
		continue) set_command_continue;;
		stop) set_command_stop;;
	esac
	exit 0
}

set_command_stop() {
	trap "" INT
	echo "Wanping wird angehalten. Bitte warten..."
	echo "ctrl-c kann jetzt nicht benutzt werden!"
	echo "stop" > $running
	while true; do
		sleep 0.25
		if [ ! -f $running ]; then
		echo "Wanping angehalten!"
		exit 0
		fi
	done
}

set_command_continue() {
	echo "Wanping wird fortgesetzt."
	echo "continue" > $running
}

set_command_pause() {
	echo "wanping hält nach dem aktuellen Zyklus an (max $count Sekunden)"
	echo "pause" > $running
}

start_in_background() {
	# look for instance
	if [ -f $running ]; then
		interruption_command=$(cat $running)
		echo "Wanping läuft bereits."
		service_control
	fi
	nohup wanping & > /dev/null 2>&1
	echo "wanping läuft nun im Hintergrund."
	exit 0
}

# Here we go <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< START
trap ctrl_c INT
trap ctrl_c SIGTERM

# Getting options
while [ ! -z $1 ]; do
	case "$1" in
		-h|--help|--hilfe)	show_help;;
		-v)	overrideverbose=1;;
		-s) settings;;
		-i) install_programm;;
		pause) set_command $1;;
		continue) set_command $1;;
		stop) set_command $1;;
		start) start_in_background;;
		csv) convert_csv;;
	esac
	shift
done

main

exit 0	# this line is obsolet
