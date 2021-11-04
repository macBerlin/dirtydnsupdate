#!/bin/sh
# Michael Rieder 2021 https://twitter.com/spotmac
# Dynamic DNS Updater for macOS using Kerberos 


REALM="corp.company.net"
LogFile="/private/var/log/DNS.log"
currentuser=`stat -f "%Su" /dev/console`
recordTTL="28800"

writeToLog(){
  NOW=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$0] $NOW  - $1" >> "$LogFile"
  #echo "[$0] $NOW  - $1"

}

## get all DNS Server for Domain
DNS_SERVER=$(dig corp.ad.zalando.net +short)

for dns_ip in ${DNS_SERVER//\\n/
}
do
   	ping -q -t2 -c1 $dns_ip  >>/dev/null 2>&1 
	if [ $? -eq 0 ]; then 
		writeToLog "DNS Server ${dns_ip} is online.."
		ACTIVE_DNS_SERVER=${dns_ip}	
		break	
	fi
done


if [ ! -z "$ACTIVE_DNS_SERVER" ]; then 
	writeToLog "DNSupdate started.."
else
	writeToLog "No company network active exiting."
	exit 0
fi

randomName=$(cat /dev/urandom | env LC_CTYPE=C tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
workfile="/tmp/${randomName}"

if ! klist -s  >>/dev/null 2>&1
then
    writeToLog "Kerberos ticket seems not working. Destroy ticket.."
    kdestroy
fi

sleep 1

if ! klist -s  >>/dev/null 2>&1
then
    writeToLog "Kerberos ticket is not valid. Call Kerberos SSO agent.."
    app-sso --authenticate $REALM   >>/dev/null 2>&1
fi
sleep 2


i=0
until   klist -s  2>&1 
do
    writeToLog "waiting for Kerberos Ticket.."
   app-sso --authenticate $REALM >>/dev/null 2>&1
    sleep 5


    ping -q -t2 -c1 $REALM  >>/dev/null 2>&1 
	if [ $? -eq 0 ]; then 
	writeToLog "waiting for Kerberos Ticket.. $REALM is reachable."
		else
	writeToLog "Network disconnected during DNS Update. exiting!"
	exit 0

	fi




    ((i++))
  	if [[ $i -eq 20 ]]; then
    	break
    	writeToLog "giving up.. user ignore Kerberos SSO login!"
  	fi
done

writeToLog "Kerberos Ticket is valid."

getInterfaces=$(netstat -f inet -rn |  cut -c52-56 | grep -v "Netif" | sort -u | grep -v "lo0" | grep -v -e '^$' | tr -d " ")
countInterfaces=$(echo "$getInterfaces" | wc -l | tr -d " ")

getFirstDNSServer=$(dig $REALM +short | head -n1)




if [ $countInterfaces -gt 0 ]; then 
 
	 	#Set the field separator to new line
		IFS=$'\n'

		#Try to iterate over each line from $getInterfaces
		for Interface in $getInterfaces
		do
		    writeToLog "Check interface: $Interface"
		    ipaddr=`/sbin/ifconfig $Interface | awk '/inet / {print$2}'`

			ping -S $ipaddr -t1 -q -c1 $REALM  >>/dev/null 2>&1		 
			if [ $? -eq 0 ]; then 
		    	writeToLog "company network is reachable. Update DNS on Interface $Interface"
		    	DNSUpdateInterface=$(echo $Interface)
		    fi
		done
fi




computernm=`scutil --get ComputerName`
ipaddr=`/sbin/ifconfig $DNSUpdateInterface | awk '/inet / {print$2}'`
writeToLog "Update DNS with record $computernm.$REALM A $ipaddr "
#In my case the object in AD must be end with a $ sign.
adcomputernm="$computernm$"

# make double sure that temp file isn't there
rm -rfv $workfile > /dev/null	

# compose nsupdate command
# uncomment the first line to specify a DNS server otherwise the machines default will be used. 
#echo server specificDNSserver.ourdomain.net >> $TMPDIR/nsupdate
echo "update delete $computernm.$REALM A" >> ${workfile}
echo "update add $computernm.$REALM $recordTTL A $ipaddr" >> ${workfile}
echo send >> ${workfile}
echo quit >> ${workfile}


nsupdate -g ${workfile}
if [ $? -eq 0 ]; then 
		writeToLog "DNS update succesfully!"
else
		writeToLog "DNS update failed!"

fi
rm ${workfile}
